package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/JackieSung4ev/gdrive/server/internal/driveguard"
	"github.com/JackieSung4ev/gdrive/server/internal/jobs"
	"github.com/JackieSung4ev/gdrive/server/internal/model"
)

type Server struct {
	driveguard *driveguard.Client
	jobs       *jobs.Manager
}

func NewServer(client *driveguard.Client, jobManager *jobs.Manager) *Server {
	return &Server{driveguard: client, jobs: jobManager}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/health", s.handleHealth)
	mux.HandleFunc("/api/v1/status", s.handleStatus)
	mux.HandleFunc("/api/v1/logs", s.handleLogs)
	mux.HandleFunc("/api/v1/jobs/backup", s.handleStartBackup)
	mux.HandleFunc("/api/v1/jobs/", s.handleJob)
	mux.HandleFunc("/api/v1/jobs", s.handleJobs)
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
	writeJSON(w, http.StatusOK, status)
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

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
