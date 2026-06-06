package api

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/JackieSung4ev/gdrive/server/internal/auth"
	"github.com/JackieSung4ev/gdrive/server/internal/driveguard"
	"github.com/JackieSung4ev/gdrive/server/internal/jobs"
	"github.com/JackieSung4ev/gdrive/server/internal/model"
	"github.com/JackieSung4ev/gdrive/server/internal/plans"
)

const maxDecryptUploadBytes int64 = 1024 * 1024 * 1024

type Server struct {
	driveguard *driveguard.Client
	jobs       *jobs.Manager
	plans      *plans.Manager
	auth       *auth.Store
}

func NewServer(client *driveguard.Client, jobManager *jobs.Manager, planManager *plans.Manager, authStore *auth.Store) *Server {
	return &Server{driveguard: client, jobs: jobManager, plans: planManager, auth: authStore}
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
	status.Plans = s.plans.List()
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
		writeJSON(w, http.StatusOK, map[string][]model.BackupPlan{
			"plans": s.plans.List(),
		})
	case http.MethodPost:
		var plan model.BackupPlan
		if err := json.NewDecoder(r.Body).Decode(&plan); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}

		created, err := s.plans.Add(plan)
		if err != nil {
			status := http.StatusInternalServerError
			if errors.Is(err, plans.ErrInvalidPlan) {
				status = http.StatusBadRequest
			}
			writeError(w, status, err.Error())
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
