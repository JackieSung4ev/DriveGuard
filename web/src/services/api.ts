import type { DriveGuardStatus, StartBackupResponse } from '../types'

const API_BASE = import.meta.env.VITE_API_BASE_URL || '/api/v1'

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  try {
    const response = await fetch(`${API_BASE}${path}`, {
      headers: { 'Content-Type': 'application/json' },
      ...init
    })

    if (!response.ok) {
      throw new Error(`API returned ${response.status}`)
    }

    return (await response.json()) as T
  } catch (error) {
    if (import.meta.env.DEV) {
      return mockResponse<T>(path, init)
    }
    throw error
  }
}

function mockResponse<T>(path: string, init?: RequestInit): T {
  if (path === '/status') {
    return mockStatus as T
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

export function getStatus(): Promise<DriveGuardStatus> {
  return request<DriveGuardStatus>('/status')
}

export function startBackup(): Promise<StartBackupResponse> {
  return request<StartBackupResponse>('/jobs/backup', { method: 'POST' })
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
