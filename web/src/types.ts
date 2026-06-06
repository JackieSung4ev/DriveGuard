export type TargetType = 'site' | 'mysql' | 'postgresql'
export type TargetState = 'ready' | 'warning' | 'disabled'
export type CheckState = 'ok' | 'warning' | 'error'
export type JobState = 'queued' | 'running' | 'success' | 'failed'

export interface BackupTarget {
  id: string
  name: string
  type: TargetType
  location: string
  state: TargetState
  lastBackup: string
  size: string
}

export interface StatusCheck {
  id: string
  label: string
  value: string
  state: CheckState
}

export interface JobSummary {
  id: string
  type: string
  state: JobState
  startedAt: string
  finishedAt?: string
  output?: string
}

export interface LogLine {
  id: string
  time: string
  level: 'info' | 'warning' | 'error'
  message: string
}

export interface DriveGuardStatus {
  service: {
    mode: string
    api: string
    scriptPath: string
    localTime: string
  }
  config: {
    remote: string
    remotePath: string
    backupRoot: string
    retentionCopies: number
    cron: string
    cronGuard: string
  }
  metrics: {
    websites: number
    mysqlDatabases: number
    postgresDatabases: number
    lastRun: string
  }
  targets: BackupTarget[]
  checks: StatusCheck[]
  jobs: JobSummary[]
  logs: LogLine[]
}

export interface StartBackupResponse {
  job: JobSummary
}
