export type TargetType = 'site' | 'mysql' | 'postgresql'
export type TargetState = 'ready' | 'warning' | 'disabled'
export type CheckState = 'ok' | 'warning' | 'error'
export type JobState = 'queued' | 'running' | 'success' | 'failed'
export type ProviderState = 'connected' | 'needs_auth' | 'disabled'
export type BackupKind = 'website' | 'database' | 'full'
export type PlanState = 'ready' | 'draft' | 'disabled'

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

export interface CloudProvider {
  id: string
  name: string
  type: string
  state: ProviderState
  remoteName: string
  remotePath: string
  description: string
  authCommand: string
  checkCommand: string
}

export interface BackupPlan {
  id: string
  name: string
  kind: BackupKind
  target: string
  providerId: string
  remotePath: string
  cron: string
  retentionCopies: number
  encrypted: boolean
  enabled: boolean
  state: PlanState
  nextRun: string
  lastRun: string
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
  localBackup: {
    path: string
    exists: boolean
    fileCount: number
    latestFile: string
    latestTime: string
  }
  targets: BackupTarget[]
  providers: CloudProvider[]
  plans: BackupPlan[]
  checks: StatusCheck[]
  jobs: JobSummary[]
  logs: LogLine[]
}

export interface StartBackupResponse {
  job: JobSummary
}

export type CreateBackupPlanRequest = Omit<BackupPlan, 'id' | 'state' | 'nextRun' | 'lastRun'>

export interface CreateBackupPlanResponse {
  plan: BackupPlan
}

export interface AuthState {
  configured: boolean
  authenticated: boolean
  username?: string
  twoFactorEnabled: boolean
  csrfToken?: string
}

export interface LoginResponse {
  requiresTotp: boolean
  state?: AuthState
  message?: string
}

export interface TotpSetupResponse {
  secret: string
  otpauthUrl: string
}

export interface CloudAuthUrlResponse {
  configured: boolean
  authUrl: string
  redirectUri: string
  remoteName: string
  scope: string
}
