<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Cloud,
  Database,
  Folder,
  HardDrive,
  ListChecks,
  Play,
  RefreshCcw,
  Server,
  ShieldCheck,
  SquareTerminal
} from '@lucide/vue'
import { getStatus, startBackup } from './services/api'
import type { BackupTarget, DriveGuardStatus } from './types'

const status = ref<DriveGuardStatus | null>(null)
const loading = ref(true)
const runningBackup = ref(false)
const error = ref('')

const totalTargets = computed(() => {
  if (!status.value) return 0
  const metrics = status.value.metrics
  return metrics.websites + metrics.mysqlDatabases + metrics.postgresDatabases
})

const readyChecks = computed(() => {
  if (!status.value) return 0
  return status.value.checks.filter((check) => check.state === 'ok').length
})

async function refresh() {
  loading.value = true
  error.value = ''

  try {
    status.value = await getStatus()
  } catch (err) {
    error.value = err instanceof Error ? err.message : 'Unable to load status'
  } finally {
    loading.value = false
  }
}

async function runBackup() {
  runningBackup.value = true
  error.value = ''

  try {
    const response = await startBackup()
    if (status.value) {
      status.value.jobs = [response.job, ...status.value.jobs].slice(0, 5)
    }
  } catch (err) {
    error.value = err instanceof Error ? err.message : 'Unable to start backup'
  } finally {
    runningBackup.value = false
  }
}

function targetIcon(target: BackupTarget) {
  if (target.type === 'site') return Folder
  if (target.type === 'postgresql') return Server
  return Database
}

function formatDate(value: string) {
  if (!value) return '-'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date)
}

onMounted(refresh)
</script>

<template>
  <div class="app-shell">
    <aside class="sidebar">
      <div class="brand">
        <ShieldCheck :size="28" aria-hidden="true" />
        <div>
          <strong>DriveGuard</strong>
          <span>Console</span>
        </div>
      </div>

      <nav class="nav-list" aria-label="Primary">
        <a class="nav-item active" href="#overview">
          <Activity :size="18" aria-hidden="true" />
          Overview
        </a>
        <a class="nav-item" href="#targets">
          <ListChecks :size="18" aria-hidden="true" />
          Targets
        </a>
        <a class="nav-item" href="#logs">
          <SquareTerminal :size="18" aria-hidden="true" />
          Logs
        </a>
      </nav>

      <div class="sidebar-status">
        <span class="status-dot"></span>
        <div>
          <strong>CLI stable</strong>
          <span>{{ status?.service.scriptPath || 'driveguard.sh' }}</span>
        </div>
      </div>
    </aside>

    <main class="workspace">
      <header class="topbar">
        <div>
          <p class="eyebrow">Backup control</p>
          <h1>DriveGuard Console</h1>
        </div>

        <div class="top-actions">
          <button class="icon-button" type="button" aria-label="Refresh status" @click="refresh" :disabled="loading">
            <RefreshCcw :size="18" aria-hidden="true" />
          </button>
          <button class="primary-button" type="button" @click="runBackup" :disabled="runningBackup">
            <Play :size="18" aria-hidden="true" />
            {{ runningBackup ? 'Starting' : 'Run backup' }}
          </button>
        </div>
      </header>

      <div v-if="error" class="alert" role="alert">
        <AlertTriangle :size="18" aria-hidden="true" />
        {{ error }}
      </div>

      <section id="overview" class="metric-grid" aria-label="Overview metrics">
        <article class="metric-panel">
          <span class="metric-icon"><Cloud :size="20" aria-hidden="true" /></span>
          <p>Remote</p>
          <strong>{{ status?.config.remote || '-' }}</strong>
          <small>{{ status?.config.remotePath || '-' }}</small>
        </article>
        <article class="metric-panel">
          <span class="metric-icon"><HardDrive :size="20" aria-hidden="true" /></span>
          <p>Targets</p>
          <strong>{{ totalTargets }}</strong>
          <small>{{ status?.metrics.websites || 0 }} sites, {{ status?.metrics.mysqlDatabases || 0 }} MySQL, {{ status?.metrics.postgresDatabases || 0 }} PostgreSQL</small>
        </article>
        <article class="metric-panel">
          <span class="metric-icon"><Clock :size="20" aria-hidden="true" /></span>
          <p>Schedule</p>
          <strong>{{ status?.config.cron || '-' }}</strong>
          <small>Retention {{ status?.config.retentionCopies || 0 }} copies</small>
        </article>
        <article class="metric-panel">
          <span class="metric-icon"><CheckCircle2 :size="20" aria-hidden="true" /></span>
          <p>Checks</p>
          <strong>{{ readyChecks }}/{{ status?.checks.length || 0 }}</strong>
          <small>{{ status?.config.cronGuard || 'guard unknown' }}</small>
        </article>
      </section>

      <section class="content-grid">
        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Configuration</p>
              <h2>Runtime</h2>
            </div>
          </div>
          <dl class="definition-list">
            <div>
              <dt>API</dt>
              <dd>{{ status?.service.api || '-' }}</dd>
            </div>
            <div>
              <dt>Mode</dt>
              <dd>{{ status?.service.mode || '-' }}</dd>
            </div>
            <div>
              <dt>Backup root</dt>
              <dd>{{ status?.config.backupRoot || '-' }}</dd>
            </div>
            <div>
              <dt>Last run</dt>
              <dd>{{ status?.metrics.lastRun ? formatDate(status.metrics.lastRun) : '-' }}</dd>
            </div>
          </dl>
        </article>

        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Readiness</p>
              <h2>Checks</h2>
            </div>
          </div>
          <ul class="check-list">
            <li v-for="check in status?.checks || []" :key="check.id" :class="`check-${check.state}`">
              <span class="check-state"></span>
              <div>
                <strong>{{ check.label }}</strong>
                <small>{{ check.value }}</small>
              </div>
            </li>
          </ul>
        </article>
      </section>

      <section id="targets" class="panel target-panel">
        <div class="panel-header">
          <div>
            <p class="eyebrow">Inventory</p>
            <h2>Backup Targets</h2>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Type</th>
                <th>Location</th>
                <th>Last backup</th>
                <th>Size</th>
                <th>State</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="target in status?.targets || []" :key="target.id">
                <td>
                  <span class="target-name">
                    <component :is="targetIcon(target)" :size="18" aria-hidden="true" />
                    {{ target.name }}
                  </span>
                </td>
                <td>{{ target.type }}</td>
                <td>{{ target.location }}</td>
                <td>{{ formatDate(target.lastBackup) }}</td>
                <td>{{ target.size }}</td>
                <td>
                  <span :class="['badge', `badge-${target.state}`]">{{ target.state }}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="content-grid">
        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Queue</p>
              <h2>Jobs</h2>
            </div>
          </div>
          <ul class="job-list">
            <li v-for="job in status?.jobs || []" :key="job.id">
              <div>
                <strong>{{ job.type }}</strong>
                <small>{{ formatDate(job.startedAt) }}</small>
              </div>
              <span :class="['badge', `badge-${job.state}`]">{{ job.state }}</span>
            </li>
          </ul>
        </article>

        <article id="logs" class="panel">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Recent</p>
              <h2>Logs</h2>
            </div>
          </div>
          <ul class="log-list">
            <li v-for="line in status?.logs || []" :key="line.id" :class="`log-${line.level}`">
              <time>{{ line.time }}</time>
              <span>{{ line.message }}</span>
            </li>
          </ul>
        </article>
      </section>
    </main>
  </div>
</template>
