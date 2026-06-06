package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base32"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	CookieName     = "driveguard_session"
	csrfHeader     = "X-CSRF-Token"
	passwordIters  = 210000
	sessionHours   = 12
	minPasswordLen = 12
)

var (
	ErrConfigured       = errors.New("account already configured")
	ErrNotConfigured    = errors.New("account is not configured")
	ErrInvalidLogin     = errors.New("invalid username or password")
	ErrTotpRequired     = errors.New("totp code required")
	ErrInvalidTotp      = errors.New("invalid totp code")
	ErrWeakPassword     = errors.New("password must be at least 12 characters")
	ErrInvalidCSRFToken = errors.New("invalid csrf token")
)

type Store struct {
	path string
	mu   sync.Mutex
	data dataFile
}

type dataFile struct {
	Users    map[string]User    `json:"users"`
	Sessions map[string]Session `json:"sessions"`
}

type User struct {
	Username          string `json:"username"`
	PasswordHash      string `json:"passwordHash"`
	TOTPSecret        string `json:"totpSecret,omitempty"`
	TOTPEnabled       bool   `json:"totpEnabled"`
	PasswordChangedAt string `json:"passwordChangedAt"`
}

type Session struct {
	TokenHash string `json:"tokenHash"`
	Username  string `json:"username"`
	CSRFToken string `json:"csrfToken"`
	CreatedAt string `json:"createdAt"`
	ExpiresAt string `json:"expiresAt"`
}

type State struct {
	Configured       bool   `json:"configured"`
	Authenticated    bool   `json:"authenticated"`
	Username         string `json:"username,omitempty"`
	TwoFactorEnabled bool   `json:"twoFactorEnabled"`
	CSRFToken        string `json:"csrfToken,omitempty"`
}

type LoginResult struct {
	RequiresTOTP bool   `json:"requiresTotp"`
	State        State  `json:"state,omitempty"`
	Message      string `json:"message,omitempty"`
}

func NewStore(path string) (*Store, error) {
	if path == "" {
		path = "driveguard-auth.json"
	}

	store := &Store{path: path, data: dataFile{Users: map[string]User{}, Sessions: map[string]Session{}}}
	if err := store.load(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *Store) Configured() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.data.Users) > 0
}

func (s *Store) State(r *http.Request) State {
	s.mu.Lock()
	defer s.mu.Unlock()

	state := State{Configured: len(s.data.Users) > 0}
	session, ok := s.sessionFromRequestLocked(r)
	if !ok {
		return state
	}

	user, ok := s.data.Users[session.Username]
	if !ok {
		return state
	}

	state.Authenticated = true
	state.Username = user.Username
	state.TwoFactorEnabled = user.TOTPEnabled
	state.CSRFToken = session.CSRFToken
	return state
}

func (s *Store) Bootstrap(w http.ResponseWriter, r *http.Request, username, password string) (State, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.data.Users) > 0 {
		return State{}, ErrConfigured
	}
	if len(password) < minPasswordLen {
		return State{}, ErrWeakPassword
	}

	username = strings.TrimSpace(username)
	if username == "" {
		username = "admin"
	}

	hash, err := hashPassword(password)
	if err != nil {
		return State{}, err
	}

	s.data.Users[username] = User{
		Username:          username,
		PasswordHash:      hash,
		PasswordChangedAt: time.Now().Format(time.RFC3339),
	}

	session, token, err := s.createSessionLocked(username)
	if err != nil {
		return State{}, err
	}
	if err := s.saveLocked(); err != nil {
		return State{}, err
	}

	writeSessionCookie(w, r, token, session)
	return State{Configured: true, Authenticated: true, Username: username, CSRFToken: session.CSRFToken}, nil
}

func (s *Store) Login(w http.ResponseWriter, r *http.Request, username, password, code string) (LoginResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.data.Users) == 0 {
		return LoginResult{}, ErrNotConfigured
	}

	user, ok := s.data.Users[strings.TrimSpace(username)]
	if !ok || !verifyPassword(user.PasswordHash, password) {
		return LoginResult{}, ErrInvalidLogin
	}
	if user.TOTPEnabled {
		if strings.TrimSpace(code) == "" {
			return LoginResult{RequiresTOTP: true, Message: ErrTotpRequired.Error()}, ErrTotpRequired
		}
		if !verifyTOTP(user.TOTPSecret, code, time.Now()) {
			return LoginResult{}, ErrInvalidTotp
		}
	}

	session, token, err := s.createSessionLocked(user.Username)
	if err != nil {
		return LoginResult{}, err
	}
	if err := s.saveLocked(); err != nil {
		return LoginResult{}, err
	}

	writeSessionCookie(w, r, token, session)
	state := State{
		Configured:       true,
		Authenticated:    true,
		Username:         user.Username,
		TwoFactorEnabled: user.TOTPEnabled,
		CSRFToken:        session.CSRFToken,
	}
	return LoginResult{State: state}, nil
}

func (s *Store) Logout(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if cookie, err := r.Cookie(CookieName); err == nil {
		delete(s.data.Sessions, tokenHash(cookie.Value))
		_ = s.saveLocked()
	}

	http.SetCookie(w, &http.Cookie{
		Name:     CookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		Secure:   r.TLS != nil,
	})
}

func (s *Store) Require(r *http.Request, mutate bool) (State, error) {
	state := s.State(r)
	if !state.Configured || !state.Authenticated {
		return state, ErrInvalidLogin
	}
	if mutate && subtle.ConstantTimeCompare([]byte(r.Header.Get(csrfHeader)), []byte(state.CSRFToken)) != 1 {
		return state, ErrInvalidCSRFToken
	}
	return state, nil
}

func (s *Store) ChangePassword(r *http.Request, currentPassword, nextPassword string) error {
	if len(nextPassword) < minPasswordLen {
		return ErrWeakPassword
	}

	state, err := s.Require(r, true)
	if err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	user := s.data.Users[state.Username]
	if !verifyPassword(user.PasswordHash, currentPassword) {
		return ErrInvalidLogin
	}

	hash, err := hashPassword(nextPassword)
	if err != nil {
		return err
	}
	user.PasswordHash = hash
	user.PasswordChangedAt = time.Now().Format(time.RFC3339)
	s.data.Users[state.Username] = user
	return s.saveLocked()
}

func (s *Store) SetupTOTP(r *http.Request) (secret, otpauth string, err error) {
	state, err := s.Require(r, true)
	if err != nil {
		return "", "", err
	}

	secret = newTOTPSecret()

	s.mu.Lock()
	user := s.data.Users[state.Username]
	user.TOTPSecret = secret
	s.data.Users[state.Username] = user
	err = s.saveLocked()
	s.mu.Unlock()
	if err != nil {
		return "", "", err
	}

	otpauth = fmt.Sprintf("otpauth://totp/DriveGuard:%s?secret=%s&issuer=DriveGuard&algorithm=SHA1&digits=6&period=30", state.Username, secret)
	return secret, otpauth, nil
}

func (s *Store) EnableTOTP(r *http.Request, code string) error {
	state, err := s.Require(r, true)
	if err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	user := s.data.Users[state.Username]
	if user.TOTPSecret == "" || !verifyTOTP(user.TOTPSecret, code, time.Now()) {
		return ErrInvalidTotp
	}
	user.TOTPEnabled = true
	s.data.Users[state.Username] = user
	return s.saveLocked()
}

func (s *Store) DisableTOTP(r *http.Request, password, code string) error {
	state, err := s.Require(r, true)
	if err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	user := s.data.Users[state.Username]
	if !verifyPassword(user.PasswordHash, password) {
		return ErrInvalidLogin
	}
	if user.TOTPEnabled && !verifyTOTP(user.TOTPSecret, code, time.Now()) {
		return ErrInvalidTotp
	}
	user.TOTPEnabled = false
	user.TOTPSecret = ""
	s.data.Users[state.Username] = user
	return s.saveLocked()
}

func (s *Store) load() error {
	raw, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}

	if err := json.Unmarshal(raw, &s.data); err != nil {
		return err
	}
	if s.data.Users == nil {
		s.data.Users = map[string]User{}
	}
	if s.data.Sessions == nil {
		s.data.Sessions = map[string]Session{}
	}
	return nil
}

func (s *Store) saveLocked() error {
	raw, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return err
	}
	if dir := filepath.Dir(s.path); dir != "." {
		if err := os.MkdirAll(dir, 0700); err != nil {
			return err
		}
	}
	return os.WriteFile(s.path, raw, 0600)
}

func (s *Store) sessionFromRequestLocked(r *http.Request) (Session, bool) {
	cookie, err := r.Cookie(CookieName)
	if err != nil || cookie.Value == "" {
		return Session{}, false
	}

	session, ok := s.data.Sessions[tokenHash(cookie.Value)]
	if !ok {
		return Session{}, false
	}

	expiresAt, err := time.Parse(time.RFC3339, session.ExpiresAt)
	if err != nil || time.Now().After(expiresAt) {
		delete(s.data.Sessions, session.TokenHash)
		_ = s.saveLocked()
		return Session{}, false
	}

	return session, true
}

func (s *Store) createSessionLocked(username string) (Session, string, error) {
	token := randomURLToken(32)
	csrf := randomURLToken(24)
	now := time.Now()
	session := Session{
		TokenHash: tokenHash(token),
		Username:  username,
		CSRFToken: csrf,
		CreatedAt: now.Format(time.RFC3339),
		ExpiresAt: now.Add(sessionHours * time.Hour).Format(time.RFC3339),
	}
	s.data.Sessions[session.TokenHash] = session
	return session, token, nil
}

func writeSessionCookie(w http.ResponseWriter, r *http.Request, token string, session Session) {
	expiresAt, _ := time.Parse(time.RFC3339, session.ExpiresAt)
	http.SetCookie(w, &http.Cookie{
		Name:     CookieName,
		Value:    token,
		Path:     "/",
		Expires:  expiresAt,
		MaxAge:   int(time.Until(expiresAt).Seconds()),
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		Secure:   r.TLS != nil,
	})
}

func hashPassword(password string) (string, error) {
	salt := randomBytes(16)
	key := pbkdf2([]byte(password), salt, passwordIters, 32, sha256.New)
	return fmt.Sprintf("pbkdf2_sha256$%d$%s$%s", passwordIters, b64(salt), b64(key)), nil
}

func verifyPassword(encoded, password string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != "pbkdf2_sha256" {
		return false
	}

	iters, err := strconv.Atoi(parts[1])
	if err != nil || iters < 100000 {
		return false
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[2])
	if err != nil {
		return false
	}
	expected, err := base64.RawStdEncoding.DecodeString(parts[3])
	if err != nil {
		return false
	}

	actual := pbkdf2([]byte(password), salt, iters, len(expected), sha256.New)
	return subtle.ConstantTimeCompare(expected, actual) == 1
}

func pbkdf2(password, salt []byte, iter, keyLen int, h func() hash.Hash) []byte {
	prf := hmac.New(h, password)
	hashLen := prf.Size()
	blocks := int(math.Ceil(float64(keyLen) / float64(hashLen)))
	output := make([]byte, 0, blocks*hashLen)
	var counter [4]byte

	for block := 1; block <= blocks; block++ {
		prf.Reset()
		prf.Write(salt)
		binary.BigEndian.PutUint32(counter[:], uint32(block))
		prf.Write(counter[:])
		u := prf.Sum(nil)
		t := append([]byte{}, u...)

		for i := 1; i < iter; i++ {
			prf.Reset()
			prf.Write(u)
			u = prf.Sum(nil)
			for j := range t {
				t[j] ^= u[j]
			}
		}
		output = append(output, t...)
	}

	return output[:keyLen]
}

func newTOTPSecret() string {
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(randomBytes(20))
}

func verifyTOTP(secret, code string, now time.Time) bool {
	code = strings.TrimSpace(code)
	if len(code) != 6 {
		return false
	}

	for offset := int64(-1); offset <= 1; offset++ {
		if subtle.ConstantTimeCompare([]byte(totpCode(secret, now.Add(time.Duration(offset)*30*time.Second))), []byte(code)) == 1 {
			return true
		}
	}
	return false
}

func totpCode(secret string, now time.Time) string {
	key, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(strings.ToUpper(secret))
	if err != nil {
		return "000000"
	}

	counter := uint64(now.Unix() / 30)
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], counter)

	mac := hmac.New(sha1.New, key)
	mac.Write(msg[:])
	sum := mac.Sum(nil)
	offset := sum[len(sum)-1] & 0x0f
	bin := (uint32(sum[offset])&0x7f)<<24 |
		(uint32(sum[offset+1])&0xff)<<16 |
		(uint32(sum[offset+2])&0xff)<<8 |
		(uint32(sum[offset+3]) & 0xff)
	return fmt.Sprintf("%06d", bin%1000000)
}

func randomBytes(size int) []byte {
	value := make([]byte, size)
	if _, err := rand.Read(value); err != nil {
		panic(err)
	}
	return value
}

func randomURLToken(size int) string {
	return base64.RawURLEncoding.EncodeToString(randomBytes(size))
}

func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return b64(sum[:])
}

func b64(value []byte) string {
	return base64.RawStdEncoding.EncodeToString(value)
}
