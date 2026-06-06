package plans

import (
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/JackieSung4ev/gdrive/server/internal/model"
)

var ErrInvalidPlan = errors.New("invalid backup plan")

type Manager struct {
	mu    sync.Mutex
	plans []model.BackupPlan
}

func NewManager(defaults []model.BackupPlan) *Manager {
	return &Manager{plans: append([]model.BackupPlan{}, defaults...)}
}

func (m *Manager) List() []model.BackupPlan {
	m.mu.Lock()
	defer m.mu.Unlock()

	return append([]model.BackupPlan{}, m.plans...)
}

func (m *Manager) Add(plan model.BackupPlan) (model.BackupPlan, error) {
	if strings.TrimSpace(plan.Name) == "" || strings.TrimSpace(plan.ProviderID) == "" {
		return model.BackupPlan{}, ErrInvalidPlan
	}
	if plan.RetentionCopies < 1 {
		plan.RetentionCopies = 7
	}
	if strings.TrimSpace(plan.Cron) == "" {
		plan.Cron = "0 3 * * *"
	}
	if strings.TrimSpace(plan.RemotePath) == "" {
		plan.RemotePath = "driveguard"
	}
	if plan.Kind == "" {
		plan.Kind = model.BackupKindFull
	}

	now := time.Now()
	plan.ID = fmt.Sprintf("plan-%d", now.UnixNano())
	plan.State = model.PlanDraft
	plan.NextRun = "after cron install"
	plan.LastRun = ""

	m.mu.Lock()
	defer m.mu.Unlock()

	m.plans = append([]model.BackupPlan{plan}, m.plans...)
	return plan, nil
}
