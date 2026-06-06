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
			CronGuard:       c.CronGuardStatus(ctx),
		},
		Metrics: model.Metrics{LastRun: now},
	}

	output, err := c.Run(statusCtx, "status")
	values := parseStatus(output)
	applyStatusValues(&dashboard, values)
	dashboard.Targets = readTargets(values)
	dashboard.Metrics = countTargets(dashboard.Metrics, dashboard.Targets)
	dashboard.LocalBackup = inspectLocalBackup(dashboard.Config.BackupRoot)
	dashboard.Providers = buildProviders(values)
	dashboard.Plans = PlansFromConfig(dashboard.Config, readShellConfigValues(configFileFromStatus(values)))
	dashboard.Checks = buildChecks(scriptPath, values, err)
	dashboard.Logs = c.LogLines(ctx, 20)

	if err != nil {
		dashboard.Service.Mode = "Degraded"
	}

	return dashboard
}

func (c *Client) EnablePlan(ctx context.Context, plan model.BackupPlan) (model.BackupPlan, error) {
	remoteName, err := remoteNameForPlan(plan.ProviderID)
	if err != nil {
		return model.BackupPlan{}, err
	}
	providerID := normalizedProviderID(plan.ProviderID)

	plan.RemotePath = strings.Trim(strings.TrimSpace(plan.RemotePath), "/")
	if plan.RemotePath == "" {
		plan.RemotePath = "driveguard"
	}
	plan.Cron = strings.TrimSpace(plan.Cron)
	if !validCron(plan.Cron) {
		return model.BackupPlan{}, fmt.Errorf("cron expression must contain exactly five fields")
	}
	if plan.RetentionCopies < 1 {
		plan.RetentionCopies = 7
	}
	if strings.ContainsAny(plan.RemotePath, "\x00\r\n") {
		return model.BackupPlan{}, fmt.Errorf("remote directory cannot contain newlines")
	}
	scopeUpdates, err := c.backupScopeUpdates(ctx, plan)
	if err != nil {
		return model.BackupPlan{}, err
	}

	configPath := c.ConfigFile(ctx)
	raw, err := os.ReadFile(configPath)
	if err != nil && !os.IsNotExist(err) {
		return model.BackupPlan{}, err
	}

	updates := map[string]string{
		"RCLONE_REMOTE":      remoteName,
		"RCLONE_REMOTE_PATH": plan.RemotePath,
		"KEEP_COPIES":        strconv.Itoa(plan.RetentionCopies),
		"CRON_EXPR":          plan.Cron,
		"ENABLE_CRON_GUARD":  "1",
		"WEB_PLAN_NAME":      plan.Name,
		"WEB_PLAN_KIND":      string(plan.Kind),
		"WEB_PLAN_TARGET":    plan.Target,
		"WEB_PLAN_PROVIDER":  providerID,
	}
	for key, value := range scopeUpdates {
		updates[key] = value
	}
	for key, value := range updates {
		if strings.ContainsAny(value, "\x00\r\n") {
			return model.BackupPlan{}, fmt.Errorf("%s cannot contain newlines", key)
		}
	}

	if err := os.MkdirAll(filepath.Dir(configPath), 0700); err != nil {
		return model.BackupPlan{}, err
	}
	updated := updateShellConfig(string(raw), updates, planConfigKeyOrder)
	if err := os.WriteFile(configPath, []byte(updated), 0600); err != nil {
		return model.BackupPlan{}, err
	}

	commandCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	if output, err := c.Run(commandCtx, "cron"); err != nil {
		return model.BackupPlan{}, fmt.Errorf("install cron failed: %s", commandError(err, output))
	}
	if output, err := c.Run(commandCtx, "install-guard"); err != nil {
		return model.BackupPlan{}, fmt.Errorf("install cron guard failed: %s", commandError(err, output))
	}

	plan.ProviderID = providerID
	plan.Enabled = true
	plan.State = model.PlanReady
	plan.NextRun = "installed in cron"
	plan.LastRun = ""
	return plan, nil
}

func (c *Client) ConfigFile(ctx context.Context) string {
	if configured := strings.TrimSpace(os.Getenv("CONFIG_FILE")); configured != "" {
		return configured
	}

	statusCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	output, _ := c.Run(statusCtx, "status")
	if configFile := parseStatus(output)["config file"]; configFile != "" {
		return configFile
	}
	if runtime.GOOS == "windows" {
		return "driveguard-config.conf"
	}
	return "/etc/driveguard/config.conf"
}

func (c *Client) CronGuardStatus(ctx context.Context) string {
	if runtime.GOOS == "windows" {
		return "unavailable"
	}

	statusCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	output, err := c.runCommand(statusCtx, "systemctl", "is-active", "driveguard-cron-guard.timer")
	state := strings.TrimSpace(output)
	if err == nil && state == "active" {
		return "enabled"
	}
	if state == "inactive" || state == "failed" {
		return state
	}
	if state != "" {
		return "unknown"
	}
	return "unknown"
}

func (c *Client) backupScopeUpdates(ctx context.Context, plan model.BackupPlan) (map[string]string, error) {
	updates := map[string]string{
		"BACKUP_SCOPE_KIND":     "full",
		"BACKUP_SCOPE_NAME":     "",
		"BACKUP_SCOPE_LOCATION": "",
		"BACKUP_SCOPE_EXCLUDES": "",
	}
	if plan.Kind == model.BackupKindFull || strings.TrimSpace(plan.Target) == "" || plan.Target == "all" {
		return updates, nil
	}

	status := c.Dashboard(ctx)
	var selected model.BackupTarget
	found := false
	for _, target := range status.Targets {
		if target.ID == plan.Target {
			selected = target
			found = true
			break
		}
	}
	if !found {
		return nil, fmt.Errorf("selected backup target was not found in the configured target list")
	}

	switch {
	case plan.Kind == model.BackupKindWebsite && selected.Type == model.TargetSite:
		updates["BACKUP_SCOPE_KIND"] = "website"
		updates["BACKUP_SCOPE_NAME"] = selected.Name
		updates["BACKUP_SCOPE_LOCATION"] = selected.Location
	case plan.Kind == model.BackupKindDatabase && selected.Type == model.TargetMySQL:
		updates["BACKUP_SCOPE_KIND"] = "mysql"
		updates["BACKUP_SCOPE_NAME"] = selected.Name
	case plan.Kind == model.BackupKindDatabase && selected.Type == model.TargetPostgreSQL:
		updates["BACKUP_SCOPE_KIND"] = "postgresql"
		updates["BACKUP_SCOPE_NAME"] = selected.Name
	default:
		return nil, fmt.Errorf("selected target does not match the backup content type")
	}
	return updates, nil
}

func PlansFromConfig(config model.RuntimeConfig, metadata map[string]string) []model.BackupPlan {
	cron := strings.TrimSpace(config.Cron)
	if cron == "" || cron == "-" {
		return nil
	}

	remote := strings.TrimSuffix(strings.TrimSpace(config.Remote), ":")
	if remote == "" || remote == "-" {
		remote = "gdrive"
	}
	remotePath := strings.Trim(strings.TrimSpace(config.RemotePath), "/")
	if remotePath == "" || remotePath == "-" {
		remotePath = "driveguard"
	}
	retention := config.RetentionCopies
	if retention < 1 {
		retention = 7
	}
	name := valueOr(metadata["WEB_PLAN_NAME"], "DriveGuard scheduled backup")
	kind := backupKindOrDefault(metadata["WEB_PLAN_KIND"])
	target := valueOr(metadata["WEB_PLAN_TARGET"], "all")
	providerID := valueOr(metadata["WEB_PLAN_PROVIDER"], providerIDForRemote(remote))

	return []model.BackupPlan{
		{
			ID:              "plan-cli-active",
			Name:            name,
			Kind:            kind,
			Target:          target,
			ProviderID:      providerID,
			RemotePath:      remotePath,
			Cron:            cron,
			RetentionCopies: retention,
			Encrypted:       true,
			Enabled:         true,
			State:           model.PlanReady,
			NextRun:         "installed in cron",
			LastRun:         "",
		},
	}
}

func inspectLocalBackup(root string) model.LocalBackupInfo {
	root = strings.TrimSpace(root)
	info := model.LocalBackupInfo{Path: root}
	if root == "" || root == "-" {
		return info
	}

	stat, err := os.Stat(root)
	if err != nil || !stat.IsDir() {
		return info
	}
	info.Exists = true

	var latestTime time.Time
	_ = filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil || entry.IsDir() {
			return nil
		}
		if !strings.HasSuffix(strings.ToLower(entry.Name()), ".enc") {
			return nil
		}

		fileInfo, err := entry.Info()
		if err != nil {
			return nil
		}
		info.FileCount++
		if fileInfo.ModTime().After(latestTime) {
			latestTime = fileInfo.ModTime()
			info.LatestFile = path
			info.LatestTime = fileInfo.ModTime().Format(time.RFC3339)
		}
		return nil
	})

	return info
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

func (c *Client) SaveGoogleDriveRemote(ctx context.Context, remoteName, clientID, clientSecret, scope string, tokenJSON []byte) (string, error) {
	remoteName = strings.TrimSuffix(strings.TrimSpace(remoteName), ":")
	if remoteName == "" {
		remoteName = "gdrive"
	}
	if strings.ContainsAny(remoteName, "[]\r\n") {
		return "", fmt.Errorf("invalid rclone remote name")
	}
	if strings.TrimSpace(clientID) == "" || strings.TrimSpace(clientSecret) == "" {
		return "", fmt.Errorf("Google OAuth client ID and secret are required")
	}
	if strings.TrimSpace(scope) == "" {
		scope = "drive.file"
	}
	if len(tokenJSON) == 0 {
		return "", fmt.Errorf("Google OAuth token is empty")
	}

	configPath := c.RcloneConfigFile(ctx)
	if err := os.MkdirAll(filepath.Dir(configPath), 0700); err != nil {
		return "", err
	}

	raw, err := os.ReadFile(configPath)
	if err != nil && !os.IsNotExist(err) {
		return "", err
	}

	section := []string{
		"[" + remoteName + "]",
		"type = drive",
		"client_id = " + strings.TrimSpace(clientID),
		"client_secret = " + strings.TrimSpace(clientSecret),
		"scope = " + strings.TrimSpace(scope),
		"token = " + strings.TrimSpace(string(tokenJSON)),
	}
	updated := replaceConfigSection(string(raw), remoteName, section)
	if err := os.WriteFile(configPath, []byte(updated), 0600); err != nil {
		return "", err
	}
	return configPath, nil
}

func (c *Client) RcloneConfigFile(ctx context.Context) string {
	if configured := strings.TrimSpace(os.Getenv("RCLONE_CONFIG")); configured != "" {
		return configured
	}

	configCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	output, err := c.runCommand(configCtx, "rclone", "config", "file")
	if err == nil {
		scanner := bufio.NewScanner(strings.NewReader(output))
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" || strings.Contains(line, "Configuration file") {
				continue
			}
			if strings.Contains(line, "rclone.conf") {
				return line
			}
		}
	}

	if runtime.GOOS == "windows" {
		if appData := os.Getenv("APPDATA"); appData != "" {
			return filepath.Join(appData, "rclone", "rclone.conf")
		}
		return "rclone.conf"
	}
	if home := os.Getenv("HOME"); home != "" {
		return filepath.Join(home, ".config", "rclone", "rclone.conf")
	}
	return "/root/.config/rclone/rclone.conf"
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

func (c *Client) runCommand(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output

	err := cmd.Run()
	return trimOutput(output.String()), err
}

func replaceConfigSection(raw, sectionName string, section []string) string {
	lines := strings.Split(strings.ReplaceAll(raw, "\r\n", "\n"), "\n")
	header := "[" + sectionName + "]"
	result := []string{}
	inserted := false

	for i := 0; i < len(lines); {
		line := lines[i]
		if strings.TrimSpace(line) == header {
			if len(result) > 0 && strings.TrimSpace(result[len(result)-1]) != "" {
				result = append(result, "")
			}
			result = append(result, section...)
			inserted = true
			i++
			for i < len(lines) && !isConfigSectionHeader(lines[i]) {
				i++
			}
			continue
		}
		result = append(result, line)
		i++
	}

	for len(result) > 0 && strings.TrimSpace(result[len(result)-1]) == "" {
		result = result[:len(result)-1]
	}
	if !inserted {
		if len(result) > 0 {
			result = append(result, "")
		}
		result = append(result, section...)
	}
	return strings.Join(result, "\n") + "\n"
}

func isConfigSectionHeader(line string) bool {
	trimmed := strings.TrimSpace(line)
	return strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]")
}

func defaultArchivePasswordFile() string {
	if runtime.GOOS == "windows" {
		return "driveguard-archive.pass"
	}
	return "/etc/driveguard/archive.pass"
}

var statusLinePattern = regexp.MustCompile(`^\s*([^:：]+)[:：]\s*(.*)$`)

var statusKeyAliases = map[string]string{
	"配置文件":                "config file",
	"更新仓库":                "update repository",
	"远程目录":                "remote directory",
	"本地目录":                "local directory",
	"保留份数":                "retention copies",
	"自动发现网站":              "auto discover websites",
	"网站根目录":               "website roots",
	"自动发现数据库":             "auto discover databases",
	"postgresql 备份":       "postgresql backup",
	"定时任务":                "cron schedule",
	"网站列表":                "website list",
	"mysql/mariadb 数据库列表": "mysql/mariadb database list",
	"postgresql 数据库列表":    "postgresql database list",
	"密码文件":                "password file",
	"mysql 配置":            "mysql config",
	"postgresql 密码文件":     "postgresql password file",
}

func parseStatus(output string) map[string]string {
	values := map[string]string{}
	scanner := bufio.NewScanner(strings.NewReader(output))

	for scanner.Scan() {
		line := scanner.Text()
		match := statusLinePattern.FindStringSubmatch(line)
		if len(match) != 3 {
			continue
		}

		key := normalizeStatusKey(match[1])
		values[key] = strings.TrimSpace(match[2])
	}

	return values
}

func normalizeStatusKey(key string) string {
	normalized := strings.ToLower(strings.TrimSpace(key))
	if alias, ok := statusKeyAliases[normalized]; ok {
		return alias
	}
	return normalized
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
	targets = append(targets, readLocalDatabaseTargets(values["local directory"], targets)...)
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

func readLocalDatabaseTargets(root string, existing []model.BackupTarget) []model.BackupTarget {
	root = strings.TrimSpace(root)
	if root == "" || root == "-" {
		return nil
	}

	seen := map[string]bool{}
	for _, target := range existing {
		if target.Type == model.TargetMySQL || target.Type == model.TargetPostgreSQL {
			seen[targetKey(target.Type, target.Name)] = true
		}
	}

	databaseRoot := filepath.Join(root, "database")
	targets := []model.BackupTarget{}
	targets = append(targets, readLocalDatabaseBackupTargets(databaseRoot, model.TargetMySQL, seen)...)
	targets = append(targets, readLocalDatabaseBackupTargets(filepath.Join(databaseRoot, "postgresql"), model.TargetPostgreSQL, seen)...)
	return targets
}

func readLocalDatabaseBackupTargets(root string, targetType model.TargetType, seen map[string]bool) []model.BackupTarget {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}

	targets := []model.BackupTarget{}
	for _, entry := range entries {
		if targetType == model.TargetMySQL && entry.IsDir() && strings.EqualFold(entry.Name(), "postgresql") {
			continue
		}

		if entry.IsDir() {
			latestFile, latestTime := latestEncryptedBackup(filepath.Join(root, entry.Name()))
			if latestFile == "" {
				continue
			}
			if target := localDatabaseTarget(targetType, entry.Name(), latestFile, latestTime, seen); target.ID != "" {
				targets = append(targets, target)
			}
			continue
		}

		name := databaseNameFromBackupFile(entry.Name(), targetType)
		if name == "" {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if target := localDatabaseTarget(targetType, name, filepath.Join(root, entry.Name()), info.ModTime(), seen); target.ID != "" {
			targets = append(targets, target)
		}
	}
	return targets
}

func localDatabaseTarget(targetType model.TargetType, name, latestFile string, latestTime time.Time, seen map[string]bool) model.BackupTarget {
	key := targetKey(targetType, name)
	if seen[key] {
		return model.BackupTarget{}
	}
	seen[key] = true

	return model.BackupTarget{
		ID:         fmt.Sprintf("%s-%s", targetType, sanitizeID(name)),
		Name:       name,
		Type:       targetType,
		Location:   "local backup history",
		State:      model.TargetReady,
		LastBackup: latestTime.Format(time.RFC3339),
		Size:       backupFileSize(latestFile),
	}
}

func latestEncryptedBackup(root string) (string, time.Time) {
	var latestFile string
	var latestTime time.Time
	_ = filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil || entry.IsDir() {
			return nil
		}
		if !strings.HasSuffix(strings.ToLower(entry.Name()), ".enc") {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return nil
		}
		if info.ModTime().After(latestTime) {
			latestFile = path
			latestTime = info.ModTime()
		}
		return nil
	})
	return latestFile, latestTime
}

func databaseNameFromBackupFile(name string, targetType model.TargetType) string {
	var prefix string
	switch targetType {
	case model.TargetPostgreSQL:
		prefix = "Pg_"
	default:
		prefix = "Db_"
	}
	if !strings.HasPrefix(name, prefix) || !strings.HasSuffix(strings.ToLower(name), ".sql.gz.enc") {
		return ""
	}

	trimmed := strings.TrimSuffix(strings.TrimPrefix(name, prefix), ".sql.gz.enc")
	parts := strings.Split(trimmed, "_")
	if len(parts) < 3 {
		return ""
	}
	datePart := parts[len(parts)-2]
	timePart := parts[len(parts)-1]
	if len(datePart) != 8 || len(timePart) != 6 {
		return ""
	}
	return strings.Join(parts[:len(parts)-2], "_")
}

func backupFileSize(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return "-"
	}
	return strconv.FormatInt(info.Size(), 10) + " B"
}

func targetKey(targetType model.TargetType, name string) string {
	return string(targetType) + "\x00" + strings.ToLower(strings.TrimSpace(name))
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

var planConfigKeyOrder = []string{
	"RCLONE_REMOTE",
	"RCLONE_REMOTE_PATH",
	"KEEP_COPIES",
	"CRON_EXPR",
	"ENABLE_CRON_GUARD",
	"BACKUP_SCOPE_KIND",
	"BACKUP_SCOPE_NAME",
	"BACKUP_SCOPE_LOCATION",
	"BACKUP_SCOPE_EXCLUDES",
	"WEB_PLAN_NAME",
	"WEB_PLAN_KIND",
	"WEB_PLAN_TARGET",
	"WEB_PLAN_PROVIDER",
}

func configFileFromStatus(values map[string]string) string {
	if configFile := strings.TrimSpace(values["config file"]); configFile != "" {
		return configFile
	}
	if configured := strings.TrimSpace(os.Getenv("CONFIG_FILE")); configured != "" {
		return configured
	}
	if runtime.GOOS == "windows" {
		return "driveguard-config.conf"
	}
	return "/etc/driveguard/config.conf"
}

func readShellConfigValues(path string) map[string]string {
	values := map[string]string{}
	raw, err := os.ReadFile(path)
	if err != nil {
		return values
	}

	for _, line := range strings.Split(strings.ReplaceAll(string(raw), "\r\n", "\n"), "\n") {
		key, ok := shellAssignmentKey(line)
		if !ok {
			continue
		}
		index := strings.Index(strings.TrimSpace(line), "=")
		if index < 0 {
			continue
		}
		values[key] = shellUnquote(strings.TrimSpace(line)[index+1:])
	}
	return values
}

func updateShellConfig(raw string, updates map[string]string, order []string) string {
	lines := strings.Split(strings.ReplaceAll(raw, "\r\n", "\n"), "\n")
	result := []string{}
	seen := map[string]bool{}

	for _, line := range lines {
		key, ok := shellAssignmentKey(line)
		if !ok {
			result = append(result, line)
			continue
		}

		value, shouldUpdate := updates[key]
		if !shouldUpdate {
			result = append(result, line)
			continue
		}

		result = append(result, key+"="+shellQuote(value))
		seen[key] = true
	}

	for len(result) > 0 && strings.TrimSpace(result[len(result)-1]) == "" {
		result = result[:len(result)-1]
	}
	if len(result) == 0 {
		result = append(result, "# DriveGuard configuration file, updated by web UI")
	}

	for _, key := range order {
		if _, ok := seen[key]; ok {
			continue
		}
		value, ok := updates[key]
		if !ok {
			continue
		}
		result = append(result, key+"="+shellQuote(value))
	}

	return strings.Join(result, "\n") + "\n"
}

func shellAssignmentKey(line string) (string, bool) {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, "#") {
		return "", false
	}

	index := strings.Index(trimmed, "=")
	if index <= 0 {
		return "", false
	}

	key := trimmed[:index]
	for _, char := range key {
		if (char >= 'A' && char <= 'Z') || (char >= '0' && char <= '9') || char == '_' {
			continue
		}
		return "", false
	}
	return key, true
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func shellUnquote(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 2 && strings.HasPrefix(value, "'") && strings.HasSuffix(value, "'") {
		return strings.ReplaceAll(value[1:len(value)-1], "'\"'\"'", "'")
	}
	if len(value) >= 2 && strings.HasPrefix(value, "\"") && strings.HasSuffix(value, "\"") {
		return strings.ReplaceAll(value[1:len(value)-1], `\"`, `"`)
	}
	return value
}

func validCron(expr string) bool {
	if strings.ContainsAny(expr, "\x00\r\n") {
		return false
	}
	return len(strings.Fields(expr)) == 5
}

func remoteNameForPlan(providerID string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(strings.TrimSuffix(providerID, ":")))
	switch normalized {
	case "google", "google-drive", "gdrive", "drive":
		return cleanRemoteName(envOrDefault("DRIVEGUARD_GOOGLE_REMOTE", "gdrive"))
	case "onedrive", "one-drive", "microsoft", "microsoft-onedrive":
		return cleanRemoteName(envOrDefault("DRIVEGUARD_ONEDRIVE_REMOTE", "onedrive"))
	default:
		return cleanRemoteName(normalized)
	}
}

func cleanRemoteName(remoteName string) (string, error) {
	remoteName = strings.TrimSpace(strings.TrimSuffix(remoteName, ":"))
	if remoteName == "" {
		return "", fmt.Errorf("rclone remote name is required")
	}
	if strings.ContainsAny(remoteName, "[]:/\\\x00\r\n") {
		return "", fmt.Errorf("invalid rclone remote name")
	}
	return remoteName, nil
}

func providerIDForRemote(remote string) string {
	normalized := strings.ToLower(strings.TrimSuffix(strings.TrimSpace(remote), ":"))
	switch {
	case strings.Contains(normalized, "one"):
		return "onedrive"
	case strings.Contains(normalized, "google"), strings.Contains(normalized, "gdrive"), strings.Contains(normalized, "drive"):
		return "google-drive"
	default:
		return "google-drive"
	}
}

func normalizedProviderID(providerID string) string {
	normalized := strings.ToLower(strings.TrimSpace(providerID))
	switch normalized {
	case "onedrive", "one-drive", "microsoft", "microsoft-onedrive":
		return "onedrive"
	default:
		return "google-drive"
	}
}

func backupKindOrDefault(value string) model.BackupKind {
	switch model.BackupKind(strings.TrimSpace(value)) {
	case model.BackupKindWebsite:
		return model.BackupKindWebsite
	case model.BackupKindDatabase:
		return model.BackupKindDatabase
	default:
		return model.BackupKindFull
	}
}

func envOrDefault(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func commandError(err error, output string) string {
	message := strings.TrimSpace(trimOutput(output))
	if message == "" {
		return err.Error()
	}
	return message
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
