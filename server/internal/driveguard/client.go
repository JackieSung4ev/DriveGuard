package driveguard

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/JackieSung4ev/gdrive/server/internal/model"
)

type Client struct {
	scriptPath string
}

func NewClient(scriptPath string) *Client {
	return &Client{scriptPath: scriptPath}
}

func (c *Client) Run(ctx context.Context, args ...string) (string, error) {
	script := c.ScriptPath()
	name := script
	commandArgs := args

	if strings.HasSuffix(script, ".sh") {
		name = "bash"
		commandArgs = append([]string{script}, args...)
	}

	cmd := exec.CommandContext(ctx, name, commandArgs...)
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output

	err := cmd.Run()
	return trimOutput(output.String()), err
}

func (c *Client) ScriptPath() string {
	if c.scriptPath != "" {
		return c.scriptPath
	}

	candidates := []string{
		filepath.Join("..", "driveguard.sh"),
		"driveguard.sh",
		"/usr/local/bin/driveguard",
		"/usr/local/bin/dg",
	}

	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			if abs, err := filepath.Abs(candidate); err == nil {
				return abs
			}
			return candidate
		}
	}

	return "driveguard"
}

func (c *Client) Dashboard(ctx context.Context) model.DriveGuardStatus {
	statusCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	now := time.Now().Format(time.RFC3339)
	scriptPath := c.ScriptPath()
	dashboard := model.DriveGuardStatus{
		Service: model.ServiceInfo{
			Mode:       "Ready",
			API:        "Go service",
			ScriptPath: scriptPath,
			LocalTime:  now,
		},
		Config: model.RuntimeConfig{
			Remote:          "-",
			RemotePath:      "-",
			BackupRoot:      "-",
			RetentionCopies: 0,
			Cron:            "-",
			CronGuard:       "unknown",
		},
		Metrics: model.Metrics{LastRun: now},
	}

	output, err := c.Run(statusCtx, "status")
	values := parseStatus(output)
	applyStatusValues(&dashboard, values)
	dashboard.Targets = readTargets(values)
	dashboard.Metrics = countTargets(dashboard.Metrics, dashboard.Targets)
	dashboard.Providers = buildProviders(values)
	dashboard.Plans = DefaultPlans()
	dashboard.Checks = buildChecks(scriptPath, values, err)
	dashboard.Logs = c.LogLines(ctx, 20)

	if err != nil {
		dashboard.Service.Mode = "Degraded"
	}

	return dashboard
}

func DefaultPlans() []model.BackupPlan {
	return []model.BackupPlan{
		{
			ID:              "plan-default-full",
			Name:            "每日全量备份",
			Kind:            model.BackupKindFull,
			Target:          "all configured websites and databases",
			ProviderID:      "google-drive",
			RemotePath:      "driveguard",
			Cron:            "0 3 * * *",
			RetentionCopies: 7,
			Encrypted:       true,
			Enabled:         true,
			State:           model.PlanReady,
			NextRun:         "03:00 daily",
			LastRun:         "",
		},
	}
}

func (c *Client) LogLines(ctx context.Context, limit int) []model.LogLine {
	if limit <= 0 {
		limit = 80
	}

	logCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	output, err := c.Run(logCtx, "log", strconv.Itoa(limit))
	if err != nil && strings.TrimSpace(output) == "" {
		return []model.LogLine{{
			ID:      "log-error",
			Time:    time.Now().Format("15:04:05"),
			Level:   model.LogWarning,
			Message: err.Error(),
		}}
	}

	return parseLogLines(output)
}

func (c *Client) ArchivePasswordFile(ctx context.Context) string {
	statusCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	output, _ := c.Run(statusCtx, "status")
	if passwordFile := parseStatus(output)["password file"]; passwordFile != "" {
		return passwordFile
	}
	return defaultArchivePasswordFile()
}

func (c *Client) SetArchivePassword(ctx context.Context, password string) (string, error) {
	if len(password) < 12 {
		return "", fmt.Errorf("archive password must be at least 12 characters")
	}
	if strings.ContainsAny(password, "\r\n") {
		return "", fmt.Errorf("archive password cannot contain newlines")
	}

	passwordFile := c.ArchivePasswordFile(ctx)
	if err := os.MkdirAll(filepath.Dir(passwordFile), 0700); err != nil {
		return "", err
	}
	if err := os.WriteFile(passwordFile, []byte(password), 0600); err != nil {
		return "", err
	}
	return passwordFile, nil
}

func (c *Client) DecryptFile(ctx context.Context, source, destination string) error {
	if strings.TrimSpace(source) == "" || strings.TrimSpace(destination) == "" {
		return fmt.Errorf("source and destination are required")
	}

	passwordFile := c.ArchivePasswordFile(ctx)
	if _, err := os.Stat(passwordFile); err != nil {
		return fmt.Errorf("archive password file is not configured")
	}

	decryptCtx, cancel := context.WithTimeout(ctx, 45*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(
		decryptCtx,
		"openssl",
		"enc",
		"-d",
		"-aes-256-cbc",
		"-pbkdf2",
		"-iter",
		"200000",
		"-in",
		source,
		"-out",
		destination,
		"-pass",
		"file:"+passwordFile,
	)
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output

	if err := cmd.Run(); err != nil {
		message := strings.TrimSpace(trimOutput(output.String()))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("decrypt failed: %s", message)
	}
	return nil
}

func defaultArchivePasswordFile() string {
	if runtime.GOOS == "windows" {
		return "driveguard-archive.pass"
	}
	return "/etc/driveguard/archive.pass"
}

var statusLinePattern = regexp.MustCompile(`^\s*([^:]+):\s*(.*)$`)

func parseStatus(output string) map[string]string {
	values := map[string]string{}
	scanner := bufio.NewScanner(strings.NewReader(output))

	for scanner.Scan() {
		line := scanner.Text()
		match := statusLinePattern.FindStringSubmatch(line)
		if len(match) != 3 {
			continue
		}

		key := strings.ToLower(strings.TrimSpace(match[1]))
		values[key] = strings.TrimSpace(match[2])
	}

	return values
}

func applyStatusValues(status *model.DriveGuardStatus, values map[string]string) {
	status.Config.Remote = valueOr(values["rclone remote"], status.Config.Remote)
	status.Config.RemotePath = valueOr(values["remote directory"], status.Config.RemotePath)
	status.Config.BackupRoot = valueOr(values["local directory"], status.Config.BackupRoot)
	status.Config.Cron = valueOr(values["cron schedule"], status.Config.Cron)

	if copies, err := strconv.Atoi(values["retention copies"]); err == nil {
		status.Config.RetentionCopies = copies
	}
}

func buildChecks(scriptPath string, values map[string]string, commandErr error) []model.StatusCheck {
	checks := []model.StatusCheck{}

	if _, err := os.Stat(scriptPath); err == nil {
		checks = append(checks, model.StatusCheck{ID: "script", Label: "DriveGuard CLI", Value: "found", State: model.CheckOK})
	} else {
		checks = append(checks, model.StatusCheck{ID: "script", Label: "DriveGuard CLI", Value: "not found", State: model.CheckWarning})
	}

	if commandErr != nil {
		checks = append(checks, model.StatusCheck{ID: "status", Label: "status command", Value: commandErr.Error(), State: model.CheckError})
	}

	if remote := values["rclone remote"]; remote != "" {
		checks = append(checks, model.StatusCheck{ID: "remote", Label: "rclone remote", Value: remote, State: model.CheckOK})
	} else {
		checks = append(checks, model.StatusCheck{ID: "remote", Label: "rclone remote", Value: "not configured", State: model.CheckWarning})
	}

	if cron := values["cron schedule"]; cron != "" {
		checks = append(checks, model.StatusCheck{ID: "cron", Label: "cron schedule", Value: cron, State: model.CheckOK})
	}

	if passwordFile := values["password file"]; passwordFile != "" {
		state := model.CheckWarning
		value := "missing"
		if _, err := os.Stat(passwordFile); err == nil {
			state = model.CheckOK
			value = "configured"
		}
		checks = append(checks, model.StatusCheck{ID: "encryption", Label: "archive password", Value: value, State: state})
	}

	return checks
}

func buildProviders(values map[string]string) []model.CloudProvider {
	remote := strings.TrimSuffix(values["rclone remote"], ":")
	remotePath := valueOr(values["remote directory"], "driveguard")
	googleState := model.ProviderNeedsAuth
	oneDriveState := model.ProviderNeedsAuth

	switch {
	case strings.Contains(strings.ToLower(remote), "google"), strings.Contains(strings.ToLower(remote), "gdrive"), strings.Contains(strings.ToLower(remote), "drive"):
		googleState = model.ProviderConnected
	case strings.Contains(strings.ToLower(remote), "one"):
		oneDriveState = model.ProviderConnected
	}

	return []model.CloudProvider{
		{
			ID:           "google-drive",
			Name:         "Google Drive",
			Type:         "drive",
			State:        googleState,
			RemoteName:   providerRemoteName(remote, "gdrive"),
			RemotePath:   remotePath,
			Description:  "通过 rclone 授权 Google Drive，适合已有 Google 云盘或 Workspace 账号的服务器备份。",
			AuthCommand:  "sudo dg auth google",
			CheckCommand: "rclone lsd gdrive:",
		},
		{
			ID:           "onedrive",
			Name:         "Microsoft OneDrive",
			Type:         "onedrive",
			State:        oneDriveState,
			RemoteName:   providerRemoteName(remote, "onedrive"),
			RemotePath:   remotePath,
			Description:  "通过 rclone 授权 OneDrive，适合 Microsoft 365 或个人 OneDrive 备份空间。",
			AuthCommand:  "sudo dg auth onedrive",
			CheckCommand: "rclone lsd onedrive:",
		},
	}
}

func readTargets(values map[string]string) []model.BackupTarget {
	targets := []model.BackupTarget{}
	targets = append(targets, readSiteTargets(values["website list"])...)
	targets = append(targets, readDatabaseTargets(values["mysql/mariadb database list"], model.TargetMySQL)...)
	targets = append(targets, readDatabaseTargets(values["postgresql database list"], model.TargetPostgreSQL)...)
	return targets
}

func readSiteTargets(path string) []model.BackupTarget {
	if path == "" {
		return nil
	}

	file, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer file.Close()

	targets := []model.BackupTarget{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.Split(line, "|")
		if len(parts) < 2 {
			continue
		}

		name := strings.TrimSpace(parts[0])
		location := strings.TrimSpace(parts[1])
		targets = append(targets, model.BackupTarget{
			ID:         "site-" + sanitizeID(name),
			Name:       name,
			Type:       model.TargetSite,
			Location:   location,
			State:      pathState(location),
			LastBackup: "",
			Size:       "-",
		})
	}

	return targets
}

func readDatabaseTargets(path string, targetType model.TargetType) []model.BackupTarget {
	if path == "" {
		return nil
	}

	file, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer file.Close()

	targets := []model.BackupTarget{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		name := strings.TrimSpace(scanner.Text())
		if name == "" || strings.HasPrefix(name, "#") {
			continue
		}

		targets = append(targets, model.BackupTarget{
			ID:         fmt.Sprintf("%s-%s", targetType, sanitizeID(name)),
			Name:       name,
			Type:       targetType,
			Location:   "configured",
			State:      model.TargetReady,
			LastBackup: "",
			Size:       "-",
		})
	}

	return targets
}

func countTargets(metrics model.Metrics, targets []model.BackupTarget) model.Metrics {
	metrics.Websites = 0
	metrics.MySQLDatabases = 0
	metrics.PostgresDatabases = 0

	for _, target := range targets {
		switch target.Type {
		case model.TargetSite:
			metrics.Websites++
		case model.TargetMySQL:
			metrics.MySQLDatabases++
		case model.TargetPostgreSQL:
			metrics.PostgresDatabases++
		}
	}

	return metrics
}

func parseLogLines(output string) []model.LogLine {
	lines := []model.LogLine{}
	scanner := bufio.NewScanner(strings.NewReader(output))
	index := 0

	for scanner.Scan() {
		raw := strings.TrimSpace(scanner.Text())
		if raw == "" {
			continue
		}

		index++
		level := model.LogInfo
		lower := strings.ToLower(raw)
		if strings.Contains(lower, "error") || strings.Contains(lower, "failed") {
			level = model.LogError
		} else if strings.Contains(lower, "warning") || strings.Contains(lower, "skipping") {
			level = model.LogWarning
		}

		lines = append(lines, model.LogLine{
			ID:      fmt.Sprintf("log-%d", index),
			Time:    extractLogTime(raw),
			Level:   level,
			Message: raw,
		})
	}

	return lines
}

func extractLogTime(line string) string {
	if strings.HasPrefix(line, "[") {
		if end := strings.Index(line, "]"); end > 0 {
			value := strings.TrimPrefix(line[:end], "[")
			if len(value) >= 19 {
				return value[11:19]
			}
			return value
		}
	}
	return time.Now().Format("15:04:05")
}

func pathState(path string) model.TargetState {
	if _, err := os.Stat(path); err == nil {
		return model.TargetReady
	}
	return model.TargetWarning
}

func valueOr(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func providerRemoteName(remote, fallback string) string {
	if remote == "" {
		return fallback
	}
	return remote
}

func sanitizeID(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	var builder strings.Builder
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.' {
			builder.WriteRune(r)
			continue
		}
		builder.WriteByte('-')
	}
	result := strings.Trim(builder.String(), "-")
	if result == "" {
		return "target"
	}
	return result
}

func trimOutput(output string) string {
	const maxOutput = 20000
	if len(output) <= maxOutput {
		return output
	}
	return output[len(output)-maxOutput:]
}
