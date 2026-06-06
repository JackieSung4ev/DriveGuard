package jobs

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/JackieSung4ev/gdrive/server/internal/model"
)

var ErrJobRunning = errors.New("a backup job is already running")

type Runner interface {
	Run(ctx context.Context, args ...string) (string, error)
}

type Manager struct {
	runner Runner
	mu     sync.Mutex
	jobs   map[string]model.JobSummary
	order  []string
}

func NewManager(runner Runner) *Manager {
	return &Manager{
		runner: runner,
		jobs:   map[string]model.JobSummary{},
		order:  []string{},
	}
}

func (m *Manager) StartBackup() (model.JobSummary, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, job := range m.jobs {
		if job.State == model.JobQueued || job.State == model.JobRunning {
			return model.JobSummary{}, ErrJobRunning
		}
	}

	now := time.Now()
	job := model.JobSummary{
		ID:        fmt.Sprintf("job-%d", now.UnixNano()),
		Type:      "manual-backup",
		State:     model.JobQueued,
		StartedAt: now.Format(time.RFC3339),
	}
	m.jobs[job.ID] = job
	m.order = append([]string{job.ID}, m.order...)
	m.pruneLocked()

	go m.run(job.ID)

	return job, nil
}

func (m *Manager) List() []model.JobSummary {
	m.mu.Lock()
	defer m.mu.Unlock()

	result := make([]model.JobSummary, 0, len(m.order))
	for _, id := range m.order {
		result = append(result, m.jobs[id])
	}
	return result
}

func (m *Manager) Get(id string) (model.JobSummary, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	job, ok := m.jobs[id]
	return job, ok
}

func (m *Manager) run(id string) {
	m.update(id, func(job *model.JobSummary) {
		job.State = model.JobRunning
	})

	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Hour)
	defer cancel()

	output, err := m.runner.Run(ctx, "backup")
	finishedAt := time.Now().Format(time.RFC3339)

	m.update(id, func(job *model.JobSummary) {
		job.FinishedAt = finishedAt
		job.Output = output
		if err != nil {
			job.State = model.JobFailed
			if job.Output == "" {
				job.Output = err.Error()
			}
			return
		}
		job.State = model.JobSuccess
	})
}

func (m *Manager) update(id string, apply func(*model.JobSummary)) {
	m.mu.Lock()
	defer m.mu.Unlock()

	job, ok := m.jobs[id]
	if !ok {
		return
	}
	apply(&job)
	m.jobs[id] = job
}

func (m *Manager) pruneLocked() {
	const maxJobs = 25
	if len(m.order) <= maxJobs {
		return
	}

	for _, id := range m.order[maxJobs:] {
		delete(m.jobs, id)
	}
	m.order = m.order[:maxJobs]
}
