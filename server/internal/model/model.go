package model

type TargetType string
type TargetState string
type CheckState string
type JobState string
type LogLevel string

const (
	TargetSite       TargetType = "site"
	TargetMySQL      TargetType = "mysql"
	TargetPostgreSQL TargetType = "postgresql"

	TargetReady    TargetState = "ready"
	TargetWarning  TargetState = "warning"
	TargetDisabled TargetState = "disabled"

	CheckOK      CheckState = "ok"
	CheckWarning CheckState = "warning"
	CheckError   CheckState = "error"

	JobQueued  JobState = "queued"
	JobRunning JobState = "running"
	JobSuccess JobState = "success"
	JobFailed  JobState = "failed"

	LogInfo    LogLevel = "info"
	LogWarning LogLevel = "warning"
	LogError   LogLevel = "error"
)

type DriveGuardStatus struct {
	Service ServiceInfo    `json:"service"`
	Config  RuntimeConfig  `json:"config"`
	Metrics Metrics        `json:"metrics"`
	Targets []BackupTarget `json:"targets"`
	Checks  []StatusCheck  `json:"checks"`
	Jobs    []JobSummary   `json:"jobs"`
	Logs    []LogLine      `json:"logs"`
}

type ServiceInfo struct {
	Mode       string `json:"mode"`
	API        string `json:"api"`
	ScriptPath string `json:"scriptPath"`
	LocalTime  string `json:"localTime"`
}

type RuntimeConfig struct {
	Remote          string `json:"remote"`
	RemotePath      string `json:"remotePath"`
	BackupRoot      string `json:"backupRoot"`
	RetentionCopies int    `json:"retentionCopies"`
	Cron            string `json:"cron"`
	CronGuard       string `json:"cronGuard"`
}

type Metrics struct {
	Websites          int    `json:"websites"`
	MySQLDatabases    int    `json:"mysqlDatabases"`
	PostgresDatabases int    `json:"postgresDatabases"`
	LastRun           string `json:"lastRun"`
}

type BackupTarget struct {
	ID         string      `json:"id"`
	Name       string      `json:"name"`
	Type       TargetType  `json:"type"`
	Location   string      `json:"location"`
	State      TargetState `json:"state"`
	LastBackup string      `json:"lastBackup"`
	Size       string      `json:"size"`
}

type StatusCheck struct {
	ID    string     `json:"id"`
	Label string     `json:"label"`
	Value string     `json:"value"`
	State CheckState `json:"state"`
}

type JobSummary struct {
	ID         string   `json:"id"`
	Type       string   `json:"type"`
	State      JobState `json:"state"`
	StartedAt  string   `json:"startedAt"`
	FinishedAt string   `json:"finishedAt,omitempty"`
	Output     string   `json:"output,omitempty"`
}

type LogLine struct {
	ID      string   `json:"id"`
	Time    string   `json:"time"`
	Level   LogLevel `json:"level"`
	Message string   `json:"message"`
}
