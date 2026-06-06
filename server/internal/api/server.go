package api

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/JackieSung4ev/gdrive/server/internal/auth"
	"github.com/JackieSung4ev/gdrive/server/internal/driveguard"
	"github.com/JackieSung4ev/gdrive/server/internal/jobs"
	"github.com/JackieSung4ev/gdrive/server/internal/model"
	"github.com/JackieSung4ev/gdrive/server/internal/plans"
)

const maxDecryptUploadBytes int64 = 1024 * 1024 * 1024

type Server struct {
	driveguard    *driveguard.Client
	jobs          *jobs.Manager
	plans         *plans.Manager
	auth          *auth.Store
	googleOAuthMu sync.Mutex
	googleOAuth   map[string]googleOAuthState
}

type googleOAuthState struct {
	RemoteName  string
	Scope       string
	RedirectURI string
	ExpiresAt   time.Time
}

type googleOAuthConfig struct {
	ClientID     string
	ClientSecret string
	RemoteName   string
	Scope        string
	PublicURL    string
}

func NewServer(client *driveguard.Client, jobManager *jobs.Manager, planManager *plans.Manager, authStore *auth.Store) *Server {
	return &Server{
		driveguard:  client,
		jobs:        jobManager,
		plans:       planManager,
		auth:        authStore,
		googleOAuth: map[string]googleOAuthState{},
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/health", s.handleHealth)
	mux.HandleFunc("/api/v1/auth/state", s.handleAuthState)
	mux.HandleFunc("/api/v1/auth/bootstrap", s.handleAuthBootstrap)
	mux.HandleFunc("/api/v1/auth/login", s.handleAuthLogin)
	mux.HandleFunc("/api/v1/auth/logout", s.handleAuthLogout)
	mux.HandleFunc("/api/v1/auth/password", s.withAuth(s.handleAuthPassword))
	mux.HandleFunc("/api/v1/auth/totp/setup", s.withAuth(s.handleAuthTOTPSetup))
	mux.HandleFunc("/api/v1/auth/totp/enable", s.withAuth(s.handleAuthTOTPEnable))
	mux.HandleFunc("/api/v1/auth/totp/disable", s.withAuth(s.handleAuthTOTPDisable))
	mux.HandleFunc("/api/v1/security/archive-password", s.withAuth(s.handleArchivePassword))
	mux.HandleFunc("/api/v1/restore/decrypt", s.withAuth(s.handleRestoreDecrypt))
	mux.HandleFunc("/api/v1/status", s.withAuth(s.handleStatus))
	mux.HandleFunc("/api/v1/cloud-providers", s.withAuth(s.handleCloudProviders))
	mux.HandleFunc("/api/v1/cloud/google/auth-url", s.withAuth(s.handleGoogleAuthURL))
	mux.HandleFunc("/api/v1/cloud/google/callback", s.handleGoogleCallback)
	mux.HandleFunc("/api/v1/backup-plans", s.withAuth(s.handleBackupPlans))
	mux.HandleFunc("/api/v1/logs", s.withAuth(s.handleLogs))
	mux.HandleFunc("/api/v1/jobs/backup", s.withAuth(s.handleStartBackup))
	mux.HandleFunc("/api/v1/jobs/", s.withAuth(s.handleJob))
	mux.HandleFunc("/api/v1/jobs", s.withAuth(s.handleJobs))
	return mux
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"service": "driveguardd",
		"time":    time.Now().Format(time.RFC3339),
	})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	status := s.driveguard.Dashboard(r.Context())
	status.Jobs = s.jobs.List()
	if planList := s.plans.List(); len(planList) > 0 {
		status.Plans = planList
	}
	writeJSON(w, http.StatusOK, status)
}

func (s *Server) handleAuthState(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	writeJSON(w, http.StatusOK, s.auth.State(r))
}

func (s *Server) handleAuthBootstrap(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	var request struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	state, err := s.auth.Bootstrap(w, r, request.Username, request.Password)
	if err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, state)
}

func (s *Server) handleAuthLogin(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	var request struct {
		Username string `json:"username"`
		Password string `json:"password"`
		TOTPCode string `json:"totpCode"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	result, err := s.auth.Login(w, r, request.Username, request.Password, request.TOTPCode)
	if err != nil {
		if errors.Is(err, auth.ErrTotpRequired) {
			writeJSON(w, http.StatusOK, result)
			return
		}
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) handleAuthLogout(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	s.auth.Logout(w, r)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleAuthPassword(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	var request struct {
		CurrentPassword string `json:"currentPassword"`
		NewPassword     string `json:"newPassword"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := s.auth.ChangePassword(r, request.CurrentPassword, request.NewPassword); err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.auth.State(r))
}

func (s *Server) handleAuthTOTPSetup(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	secret, otpauth, err := s.auth.SetupTOTP(r)
	if err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"secret": secret, "otpauthUrl": otpauth})
}

func (s *Server) handleAuthTOTPEnable(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	var request struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := s.auth.EnableTOTP(r, request.Code); err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.auth.State(r))
}

func (s *Server) handleAuthTOTPDisable(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	var request struct {
		Password string `json:"password"`
		Code     string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := s.auth.DisableTOTP(r, request.Password, request.Code); err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.auth.State(r))
}

func (s *Server) handleCloudProviders(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	status := s.driveguard.Dashboard(r.Context())
	writeJSON(w, http.StatusOK, map[string][]model.CloudProvider{
		"providers": status.Providers,
	})
}

func (s *Server) handleGoogleAuthURL(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	config := googleConfig(r)
	redirectURI := googleRedirectURI(r, config)
	if config.ClientID == "" || config.ClientSecret == "" {
		writeJSON(w, http.StatusOK, map[string]any{
			"configured":  false,
			"authUrl":     "",
			"redirectUri": redirectURI,
			"remoteName":  config.RemoteName,
			"scope":       config.Scope,
		})
		return
	}

	state, err := randomState()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "unable to create OAuth state")
		return
	}

	s.googleOAuthMu.Lock()
	s.pruneGoogleOAuthLocked()
	s.googleOAuth[state] = googleOAuthState{
		RemoteName:  config.RemoteName,
		Scope:       config.Scope,
		RedirectURI: redirectURI,
		ExpiresAt:   time.Now().Add(10 * time.Minute),
	}
	s.googleOAuthMu.Unlock()

	authURL, err := googleAuthURL(config.ClientID, redirectURI, googleScopeURL(config.Scope), state)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "unable to create Google authorization URL")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"configured":  true,
		"authUrl":     authURL,
		"redirectUri": redirectURI,
		"remoteName":  config.RemoteName,
		"scope":       config.Scope,
	})
}

func (s *Server) handleGoogleCallback(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	if oauthErr := r.URL.Query().Get("error"); oauthErr != "" {
		writeOAuthHTML(w, false, "Google authorization failed: "+oauthErr)
		return
	}

	stateValue := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	if stateValue == "" || code == "" {
		writeOAuthHTML(w, false, "Google authorization callback is missing state or code.")
		return
	}

	state, ok := s.takeGoogleOAuthState(stateValue)
	if !ok {
		writeOAuthHTML(w, false, "Google authorization state expired or is invalid. Please start again from DriveGuard.")
		return
	}

	config := googleConfig(r)
	if config.ClientID == "" || config.ClientSecret == "" {
		writeOAuthHTML(w, false, "Google OAuth client ID or secret is not configured on this server.")
		return
	}

	token, err := exchangeGoogleToken(r.Context(), config.ClientID, config.ClientSecret, state.RedirectURI, code)
	if err != nil {
		writeOAuthHTML(w, false, err.Error())
		return
	}

	tokenJSON, err := rcloneTokenJSON(token)
	if err != nil {
		writeOAuthHTML(w, false, err.Error())
		return
	}

	configPath, err := s.driveguard.SaveGoogleDriveRemote(r.Context(), state.RemoteName, config.ClientID, config.ClientSecret, state.Scope, tokenJSON)
	if err != nil {
		writeOAuthHTML(w, false, "Unable to save rclone Google Drive remote: "+err.Error())
		return
	}

	writeOAuthHTML(w, true, "Google Drive authorization saved to "+configPath+". You can close this tab and refresh DriveGuard.")
}

func (s *Server) handleArchivePassword(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	var request struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	path, err := s.driveguard.SetArchivePassword(r.Context(), request.Password)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "configured": true, "path": path})
}

func (s *Server) handleBackupPlans(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		status := s.driveguard.Dashboard(r.Context())
		if planList := s.plans.List(); len(planList) > 0 {
			status.Plans = planList
		}
		writeJSON(w, http.StatusOK, map[string][]model.BackupPlan{
			"plans": status.Plans,
		})
	case http.MethodPost:
		var plan model.BackupPlan
		if err := json.NewDecoder(r.Body).Decode(&plan); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}

		prepared, err := plans.Prepare(plan)
		if err != nil {
			status := http.StatusInternalServerError
			if errors.Is(err, plans.ErrInvalidPlan) {
				status = http.StatusBadRequest
			}
			writeError(w, status, err.Error())
			return
		}

		if prepared.Enabled {
			enabled, err := s.driveguard.EnablePlan(r.Context(), prepared)
			if err != nil {
				writeError(w, http.StatusInternalServerError, err.Error())
				return
			}
			s.plans.SetActive(enabled)
			writeJSON(w, http.StatusCreated, map[string]model.BackupPlan{"plan": enabled})
			return
		}

		created, err := s.plans.Add(prepared)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusCreated, map[string]model.BackupPlan{"plan": created})
	default:
		w.Header().Set("Allow", strings.Join([]string{http.MethodGet, http.MethodPost}, ", "))
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func (s *Server) handleRestoreDecrypt(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxDecryptUploadBytes)
	if err := r.ParseMultipartForm(16 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "invalid upload or file is too large")
		return
	}
	if r.MultipartForm != nil {
		defer r.MultipartForm.RemoveAll()
	}

	uploaded, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "encrypted file is required")
		return
	}
	defer uploaded.Close()

	tempDir, err := os.MkdirTemp("", "driveguard-restore-*")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "unable to create temporary workspace")
		return
	}
	defer os.RemoveAll(tempDir)

	sourcePath := filepath.Join(tempDir, "backup.enc")
	source, err := os.OpenFile(sourcePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "unable to prepare encrypted file")
		return
	}
	written, copyErr := io.Copy(source, uploaded)
	closeErr := source.Close()
	if copyErr != nil {
		writeError(w, http.StatusBadRequest, "unable to read encrypted file")
		return
	}
	if closeErr != nil {
		writeError(w, http.StatusInternalServerError, "unable to save encrypted file")
		return
	}
	if written == 0 {
		writeError(w, http.StatusBadRequest, "encrypted file is empty")
		return
	}

	outputPath := filepath.Join(tempDir, "decrypted")
	if err := s.driveguard.DecryptFile(r.Context(), sourcePath, outputPath); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	output, err := os.Open(outputPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "unable to open decrypted file")
		return
	}
	defer output.Close()

	info, err := output.Stat()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "unable to inspect decrypted file")
		return
	}

	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{
		"filename": decryptedDownloadName(header.Filename),
	}))
	w.Header().Set("Content-Length", strconv.FormatInt(info.Size(), 10))
	if _, err := io.Copy(w, output); err != nil {
		return
	}
}

func (s *Server) handleLogs(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	limit := 80
	if raw := r.URL.Query().Get("lines"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			limit = parsed
		}
	}
	if limit < 1 {
		limit = 1
	}
	if limit > 500 {
		limit = 500
	}

	writeJSON(w, http.StatusOK, map[string][]model.LogLine{
		"logs": s.driveguard.LogLines(r.Context(), limit),
	})
}

func (s *Server) handleJobs(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	writeJSON(w, http.StatusOK, map[string][]model.JobSummary{
		"jobs": s.jobs.List(),
	})
}

func (s *Server) handleJob(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodGet) {
		return
	}

	id := strings.TrimPrefix(r.URL.Path, "/api/v1/jobs/")
	if id == "" || strings.Contains(id, "/") {
		writeError(w, http.StatusNotFound, "job not found")
		return
	}

	job, ok := s.jobs.Get(id)
	if !ok {
		writeError(w, http.StatusNotFound, "job not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]model.JobSummary{"job": job})
}

func (s *Server) handleStartBackup(w http.ResponseWriter, r *http.Request) {
	if !allowMethod(w, r, http.MethodPost) {
		return
	}

	job, err := s.jobs.StartBackup()
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, jobs.ErrJobRunning) {
			status = http.StatusConflict
		}
		writeError(w, status, err.Error())
		return
	}

	writeJSON(w, http.StatusAccepted, map[string]model.JobSummary{"job": job})
}

func allowMethod(w http.ResponseWriter, r *http.Request, method string) bool {
	if r.Method == method {
		return true
	}
	w.Header().Set("Allow", method)
	writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	return false
}

func (s *Server) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		mutate := r.Method != http.MethodGet && r.Method != http.MethodHead && r.Method != http.MethodOptions
		if _, err := s.auth.Require(r, mutate); err != nil {
			writeAuthError(w, err)
			return
		}
		next(w, r)
	}
}

type googleTokenResponse struct {
	AccessToken      string `json:"access_token"`
	TokenType        string `json:"token_type"`
	RefreshToken     string `json:"refresh_token"`
	ExpiresIn        int    `json:"expires_in"`
	Error            string `json:"error"`
	ErrorDescription string `json:"error_description"`
}

func googleConfig(r *http.Request) googleOAuthConfig {
	return googleOAuthConfig{
		ClientID:     strings.TrimSpace(os.Getenv("DRIVEGUARD_GOOGLE_CLIENT_ID")),
		ClientSecret: strings.TrimSpace(os.Getenv("DRIVEGUARD_GOOGLE_CLIENT_SECRET")),
		RemoteName:   envOr("DRIVEGUARD_GOOGLE_REMOTE", "gdrive"),
		Scope:        rcloneGoogleScope(envOr("DRIVEGUARD_GOOGLE_SCOPE", "drive.file")),
		PublicURL:    strings.TrimRight(strings.TrimSpace(os.Getenv("DRIVEGUARD_PUBLIC_URL")), "/"),
	}
}

func googleRedirectURI(r *http.Request, config googleOAuthConfig) string {
	base := config.PublicURL
	if base == "" {
		scheme := r.Header.Get("X-Forwarded-Proto")
		if scheme == "" {
			if r.TLS != nil {
				scheme = "https"
			} else {
				scheme = "http"
			}
		}
		host := r.Header.Get("X-Forwarded-Host")
		if host == "" {
			host = r.Host
		}
		base = scheme + "://" + host
	}
	return strings.TrimRight(base, "/") + "/api/v1/cloud/google/callback"
}

func googleAuthURL(clientID, redirectURI, scope, state string) (string, error) {
	values := url.Values{}
	values.Set("client_id", clientID)
	values.Set("redirect_uri", redirectURI)
	values.Set("response_type", "code")
	values.Set("scope", scope)
	values.Set("state", state)
	values.Set("access_type", "offline")
	values.Set("prompt", "consent")
	values.Set("include_granted_scopes", "false")

	authURL := url.URL{
		Scheme:   "https",
		Host:     "accounts.google.com",
		Path:     "/o/oauth2/v2/auth",
		RawQuery: values.Encode(),
	}
	return authURL.String(), nil
}

func googleScopeURL(scope string) string {
	switch rcloneGoogleScope(scope) {
	case "drive":
		return "https://www.googleapis.com/auth/drive"
	default:
		return "https://www.googleapis.com/auth/drive.file"
	}
}

func rcloneGoogleScope(scope string) string {
	normalized := strings.TrimSpace(scope)
	switch normalized {
	case "https://www.googleapis.com/auth/drive":
		return "drive"
	case "https://www.googleapis.com/auth/drive.file":
		return "drive.file"
	case "drive":
		return "drive"
	default:
		return "drive.file"
	}
}

func exchangeGoogleToken(ctx context.Context, clientID, clientSecret, redirectURI, code string) (googleTokenResponse, error) {
	values := url.Values{}
	values.Set("client_id", clientID)
	values.Set("client_secret", clientSecret)
	values.Set("redirect_uri", redirectURI)
	values.Set("code", code)
	values.Set("grant_type", "authorization_code")

	request, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://oauth2.googleapis.com/token", strings.NewReader(values.Encode()))
	if err != nil {
		return googleTokenResponse{}, err
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return googleTokenResponse{}, fmt.Errorf("Google token exchange failed: %w", err)
	}
	defer response.Body.Close()

	var token googleTokenResponse
	if err := json.NewDecoder(response.Body).Decode(&token); err != nil {
		return googleTokenResponse{}, fmt.Errorf("Google token response is invalid")
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 || token.Error != "" {
		message := token.Error
		if token.ErrorDescription != "" {
			message = token.ErrorDescription
		}
		if message == "" {
			message = "Google token exchange failed"
		}
		return googleTokenResponse{}, fmt.Errorf(message)
	}
	if token.AccessToken == "" || token.RefreshToken == "" {
		return googleTokenResponse{}, fmt.Errorf("Google did not return a refresh token. Revoke the old grant for this OAuth client and try again.")
	}
	if token.TokenType == "" {
		token.TokenType = "Bearer"
	}
	if token.ExpiresIn <= 0 {
		token.ExpiresIn = 3600
	}
	return token, nil
}

func rcloneTokenJSON(token googleTokenResponse) ([]byte, error) {
	return json.Marshal(map[string]string{
		"access_token":  token.AccessToken,
		"token_type":    token.TokenType,
		"refresh_token": token.RefreshToken,
		"expiry":        time.Now().Add(time.Duration(token.ExpiresIn) * time.Second).Format(time.RFC3339Nano),
	})
}

func randomState() (string, error) {
	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func (s *Server) pruneGoogleOAuthLocked() {
	now := time.Now()
	for state, entry := range s.googleOAuth {
		if now.After(entry.ExpiresAt) {
			delete(s.googleOAuth, state)
		}
	}
}

func (s *Server) takeGoogleOAuthState(value string) (googleOAuthState, bool) {
	s.googleOAuthMu.Lock()
	defer s.googleOAuthMu.Unlock()

	s.pruneGoogleOAuthLocked()
	state, ok := s.googleOAuth[value]
	if !ok {
		return googleOAuthState{}, false
	}
	delete(s.googleOAuth, value)
	if time.Now().After(state.ExpiresAt) {
		return googleOAuthState{}, false
	}
	return state, true
}

func writeOAuthHTML(w http.ResponseWriter, success bool, message string) {
	status := http.StatusOK
	title := "DriveGuard authorization complete"
	if !success {
		status = http.StatusBadRequest
		title = "DriveGuard authorization failed"
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	_, _ = fmt.Fprintf(w, `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s</title>
  <style>
    body{font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;background:#f6fbff;color:#172033}
    main{width:min(560px,calc(100%% - 32px));padding:24px;border:1px solid #dbe8f4;border-radius:8px;background:#fff;box-shadow:0 14px 36px rgba(18,104,216,.08)}
    h1{margin:0 0 12px;font-size:1.35rem}
    p{margin:0 0 18px;color:#667085}
    a{color:#1268d8;font-weight:700}
  </style>
</head>
<body>
  <main>
    <h1>%s</h1>
    <p>%s</p>
    <a href="/">Back to DriveGuard</a>
  </main>
</body>
</html>`, html.EscapeString(title), html.EscapeString(title), html.EscapeString(message))
}

func envOr(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func decryptedDownloadName(name string) string {
	base := filepath.Base(strings.ReplaceAll(strings.TrimSpace(name), "\\", "/"))
	if base == "." || base == "/" || base == "" {
		return "driveguard-restored"
	}
	if strings.HasSuffix(strings.ToLower(base), ".enc") {
		base = base[:len(base)-4]
	}
	base = strings.Trim(base, ". ")
	if base == "" {
		return "driveguard-restored"
	}
	return base
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func writeAuthError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrConfigured):
		writeError(w, http.StatusConflict, err.Error())
	case errors.Is(err, auth.ErrWeakPassword):
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, auth.ErrInvalidCSRFToken):
		writeError(w, http.StatusForbidden, err.Error())
	default:
		writeError(w, http.StatusUnauthorized, err.Error())
	}
}
