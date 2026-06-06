import type {
  BackupPlan,
  CloudProvider,
  CreateBackupPlanRequest,
  CreateBackupPlanResponse,
  AuthState,
  CloudAuthUrlResponse,
  DriveGuardStatus,
  LoginResponse,
  StartBackupResponse,
  TotpSetupResponse
} from '../types'

const API_BASE = import.meta.env.VITE_API_BASE_URL || '/api/v1'
const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true'
let csrfToken = ''

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  try {
    const method = init?.method || 'GET'
    const response = await fetch(`${API_BASE}${path}`, {
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
        ...(csrfToken && method !== 'GET' ? { 'X-CSRF-Token': csrfToken } : {})
      },
      ...init
    })

    if (!response.ok) {
      let message = `API returned ${response.status}`
      try {
        const payload = (await response.json()) as { error?: string }
        if (payload.error) {
          message = payload.error
        }
      } catch {
        // Keep the HTTP status fallback when the response is not JSON.
      }
      throw new Error(message)
    }

    return (await response.json()) as T
  } catch (error) {
    if (USE_MOCKS) {
      return mockResponse<T>(path, init)
    }
    throw error
  }
}

function mockResponse<T>(path: string, init?: RequestInit): T {
  if (path === '/auth/state') {
    return {
      configured: true,
      authenticated: true,
      username: 'admin',
      twoFactorEnabled: false,
      csrfToken: 'mock-csrf'
    } as T
  }

  if (path === '/auth/bootstrap') {
    return {
      configured: true,
      authenticated: true,
      username: 'admin',
      twoFactorEnabled: false,
      csrfToken: 'mock-csrf'
    } as T
  }

  if (path === '/auth/login') {
    return {
      requiresTotp: false,
      state: {
        configured: true,
        authenticated: true,
        username: 'admin',
        twoFactorEnabled: false,
        csrfToken: 'mock-csrf'
      }
    } as T
  }

  if (path === '/auth/password' || path === '/auth/totp/enable' || path === '/auth/totp/disable') {
    return {
      configured: true,
      authenticated: true,
      username: 'admin',
      twoFactorEnabled: path === '/auth/totp/enable',
      csrfToken: 'mock-csrf'
    } as T
  }

  if (path === '/auth/totp/setup') {
    return {
      secret: 'JBSWY3DPEHPK3PXP',
      otpauthUrl: 'otpauth://totp/DriveGuard:admin?secret=JBSWY3DPEHPK3PXP&issuer=DriveGuard'
    } as T
  }

  if (path === '/auth/logout') {
    return { status: 'ok' } as T
  }

  if (path === '/security/archive-password') {
    return { status: 'ok', configured: true } as T
  }

  if (path === '/status') {
    return mockStatus as T
  }

  if (path === '/cloud-providers') {
    return { providers: mockStatus.providers } as T
  }

  if (path === '/cloud/google/auth-url') {
    return {
      configured: true,
      authUrl: 'https://accounts.google.com/o/oauth2/v2/auth?client_id=mock&response_type=code',
      redirectUri: 'https://example.com/api/v1/cloud/google/callback',
      remoteName: 'gdrive',
      scope: 'drive.file'
    } as T
  }

  if (path === '/backup-plans' && (!init || init.method === 'GET')) {
    return { plans: mockStatus.plans } as T
  }

  if (path === '/backup-plans' && init?.method === 'POST') {
    const payload = init.body ? JSON.parse(String(init.body)) : {}
    return {
      plan: {
        ...payload,
        id: `mock-plan-${Date.now()}`,
        state: payload.enabled ? 'ready' : 'draft',
        nextRun: payload.enabled ? 'installed in cron' : 'after cron install',
        lastRun: ''
      }
    } as T
  }

  if (path === '/jobs/backup' && init?.method === 'POST') {
    return {
      job: {
        id: `mock-${Date.now()}`,
        type: 'manual-backup',
        state: 'queued',
        startedAt: new Date().toISOString()
      }
    } as T
  }

  throw new Error(`No mock response for ${path}`)
}

export async function getStatus(): Promise<DriveGuardStatus> {
  const status = await request<DriveGuardStatus>('/status')
  return {
    ...status,
    targets: status.targets ?? [],
    providers: status.providers ?? mockStatus.providers,
    plans: status.plans ?? mockStatus.plans,
    checks: status.checks ?? [],
    jobs: status.jobs ?? [],
    logs: status.logs ?? []
  }
}

export async function getAuthState(): Promise<AuthState> {
  const state = await request<AuthState>('/auth/state')
  csrfToken = state.csrfToken || ''
  return state
}

export async function bootstrapAccount(username: string, password: string): Promise<AuthState> {
  const state = await request<AuthState>('/auth/bootstrap', {
    method: 'POST',
    body: JSON.stringify({ username, password })
  })
  csrfToken = state.csrfToken || ''
  return state
}

export async function login(username: string, password: string, totpCode: string): Promise<LoginResponse> {
  const result = await request<LoginResponse>('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username, password, totpCode })
  })
  csrfToken = result.state?.csrfToken || ''
  return result
}

export function logout(): Promise<{ status: string }> {
  csrfToken = ''
  return request<{ status: string }>('/auth/logout', { method: 'POST' })
}

export async function changePassword(currentPassword: string, newPassword: string): Promise<AuthState> {
  const state = await request<AuthState>('/auth/password', {
    method: 'POST',
    body: JSON.stringify({ currentPassword, newPassword })
  })
  csrfToken = state.csrfToken || csrfToken
  return state
}

export function setupTotp(): Promise<TotpSetupResponse> {
  return request<TotpSetupResponse>('/auth/totp/setup', { method: 'POST' })
}

export async function enableTotp(code: string): Promise<AuthState> {
  const state = await request<AuthState>('/auth/totp/enable', {
    method: 'POST',
    body: JSON.stringify({ code })
  })
  csrfToken = state.csrfToken || csrfToken
  return state
}

export async function disableTotp(password: string, code: string): Promise<AuthState> {
  const state = await request<AuthState>('/auth/totp/disable', {
    method: 'POST',
    body: JSON.stringify({ password, code })
  })
  csrfToken = state.csrfToken || csrfToken
  return state
}

export function setArchivePassword(password: string): Promise<{ status: string; configured: boolean }> {
  return request<{ status: string; configured: boolean }>('/security/archive-password', {
    method: 'POST',
    body: JSON.stringify({ password })
  })
}

export async function decryptBackupFile(file: File): Promise<Blob> {
  if (USE_MOCKS) {
    return new Blob([`Mock decrypted content for ${file.name}\n`], { type: 'application/octet-stream' })
  }

  const form = new FormData()
  form.append('file', file)

  const response = await fetch(`${API_BASE}/restore/decrypt`, {
    method: 'POST',
    credentials: 'include',
    headers: {
      ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {})
    },
    body: form
  })

  if (!response.ok) {
    let message = `API returned ${response.status}`
    try {
      const payload = (await response.json()) as { error?: string }
      if (payload.error) {
        message = payload.error
      }
    } catch {
      // Keep the HTTP status fallback when the response is not JSON.
    }
    throw new Error(message)
  }

  return response.blob()
}

export function startBackup(): Promise<StartBackupResponse> {
  return request<StartBackupResponse>('/jobs/backup', { method: 'POST' })
}

export function getCloudProviders(): Promise<{ providers: CloudProvider[] }> {
  return request<{ providers: CloudProvider[] }>('/cloud-providers')
}

export function getGoogleAuthUrl(): Promise<CloudAuthUrlResponse> {
  return request<CloudAuthUrlResponse>('/cloud/google/auth-url')
}

export function getBackupPlans(): Promise<{ plans: BackupPlan[] }> {
  return request<{ plans: BackupPlan[] }>('/backup-plans')
}

export function createBackupPlan(plan: CreateBackupPlanRequest): Promise<CreateBackupPlanResponse> {
  return request<CreateBackupPlanResponse>('/backup-plans', {
    method: 'POST',
    body: JSON.stringify(plan)
  })
}

const mockStatus: DriveGuardStatus = {
  service: {
    mode: 'Development',
    api: 'Mock data',
    scriptPath: './driveguard.sh',
    localTime: new Date().toISOString()
  },
  config: {
    remote: 'cloud:',
    remotePath: 'driveguard',
    backupRoot: '/var/backups/driveguard',
    retentionCopies: 7,
    cron: '0 3 * * *',
    cronGuard: 'enabled'
  },
  metrics: {
    websites: 3,
    mysqlDatabases: 4,
    postgresDatabases: 1,
    lastRun: '2026-06-06T03:00:00+08:00'
  },
  targets: [
    {
      id: 'site-main',
      name: 'main-site',
      type: 'site',
      location: '/var/www/main',
      state: 'ready',
      lastBackup: '2026-06-06T03:04:00+08:00',
      size: '824 MB'
    },
    {
      id: 'mysql-store',
      name: 'store',
      type: 'mysql',
      location: 'localhost:3306',
      state: 'ready',
      lastBackup: '2026-06-06T03:06:00+08:00',
      size: '112 MB'
    },
    {
      id: 'pg-analytics',
      name: 'analytics',
      type: 'postgresql',
      location: 'localhost:5432',
      state: 'warning',
      lastBackup: '2026-06-05T03:06:00+08:00',
      size: '2.4 GB'
    }
  ],
  providers: [
    {
      id: 'google-drive',
      name: 'Google Drive',
      type: 'drive',
      state: 'connected',
      remoteName: 'gdrive',
      remotePath: 'driveguard',
      description: 'Google Drive rclone remote',
      authCommand: 'sudo dg auth google',
      checkCommand: 'rclone lsd gdrive:'
    },
    {
      id: 'onedrive',
      name: 'Microsoft OneDrive',
      type: 'onedrive',
      state: 'needs_auth',
      remoteName: 'onedrive',
      remotePath: 'driveguard',
      description: 'OneDrive rclone remote',
      authCommand: 'sudo dg auth onedrive',
      checkCommand: 'rclone lsd onedrive:'
    }
  ],
  plans: [
    {
      id: 'plan-default-full',
      name: '每日全量备份',
      kind: 'full',
      target: 'all configured websites and databases',
      providerId: 'google-drive',
      remotePath: 'driveguard',
      cron: '0 3 * * *',
      retentionCopies: 7,
      encrypted: true,
      enabled: true,
      state: 'ready',
      nextRun: '03:00 daily',
      lastRun: '2026-06-06T03:08:24+08:00'
    }
  ],
  checks: [
    { id: 'rclone', label: 'rclone remote', value: 'connected', state: 'ok' },
    { id: 'encryption', label: 'archive password', value: 'configured', state: 'ok' },
    { id: 'cron', label: 'cron schedule', value: 'installed', state: 'ok' },
    { id: 'postgres', label: 'PostgreSQL', value: 'needs password check', state: 'warning' }
  ],
  jobs: [
    {
      id: 'job-2406060300',
      type: 'scheduled backup',
      state: 'success',
      startedAt: '2026-06-06T03:00:00+08:00',
      finishedAt: '2026-06-06T03:08:24+08:00'
    },
    {
      id: 'job-2406050300',
      type: 'scheduled backup',
      state: 'success',
      startedAt: '2026-06-05T03:00:00+08:00',
      finishedAt: '2026-06-05T03:07:51+08:00'
    }
  ],
  logs: [
    {
      id: 'log-1',
      time: '03:08:24',
      level: 'info',
      message: 'Backup finished: websites 3, MySQL/MariaDB databases 4, PostgreSQL databases 1'
    },
    {
      id: 'log-2',
      time: '03:07:15',
      level: 'info',
      message: 'Uploaded database/store.sql.gz.enc to cloud:driveguard/database'
    },
    {
      id: 'log-3',
      time: '03:06:02',
      level: 'warning',
      message: 'PostgreSQL password file should be checked before the next run'
    }
  ]
}
