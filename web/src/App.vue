<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'
import {
  AlertTriangle,
  CalendarClock,
  CheckCircle2,
  ChevronDown,
  Cloud,
  Copy,
  Database,
  Download,
  FileDown,
  Folder,
  HardDrive,
  Home,
  KeyRound,
  Languages,
  ListChecks,
  LockKeyhole,
  LogOut,
  Menu,
  Monitor,
  Moon,
  PanelLeftClose,
  PanelLeftOpen,
  Play,
  Plus,
  RefreshCcw,
  Save,
  Server,
  ShieldCheck,
  Smartphone,
  SquareTerminal,
  Sun,
  UploadCloud,
  UserRound,
  X
} from '@lucide/vue'
import {
  bootstrapAccount,
  changePassword,
  createBackupPlan,
  decryptBackupFile,
  disableTotp,
  enableTotp,
  getAuthState,
  getStatus,
  login,
  logout,
  setArchivePassword,
  setupTotp,
  startBackup
} from './services/api'
import { detectLocale, formatMessage, messages, type I18nKey, type Locale } from './i18n'
import { createQrSvg } from './qr'
import type { AuthState, BackupKind, BackupTarget, CloudProvider, DriveGuardStatus, TotpSetupResponse } from './types'

type Page = 'home' | 'cloud' | 'plans' | 'restore' | 'logs' | 'account'
type CycleType = 'daily' | 'weekly' | 'monthly' | 'interval' | 'custom'
type ThemeMode = 'light' | 'dark' | 'auto'

const locale = ref<Locale>(detectLocale())
const activePage = ref<Page>('home')
const sidebarCollapsed = ref(false)
const mobileNavOpen = ref(false)
const themeMode = ref<ThemeMode>(detectThemeMode())
const status = ref<DriveGuardStatus | null>(null)
const authState = ref<AuthState | null>(null)
const loading = ref(true)
const runningBackup = ref(false)
const savingPlan = ref(false)
const decryptingRestore = ref(false)
const error = ref('')
const notice = ref('')
const authProvider = ref<CloudProvider | null>(null)
const verificationUrl = ref('')
const totpSetup = ref<TotpSetupResponse | null>(null)
const restoreFile = ref<File | null>(null)
const accountMenuRef = ref<HTMLDetailsElement | null>(null)
const languageSelectRef = ref<HTMLSelectElement | null>(null)
let noticeTimer: number | undefined
let themeMediaQuery: MediaQueryList | undefined
let removeThemeListener: (() => void) | undefined

function t(key: I18nKey, values?: Record<string, string | number>) {
  return formatMessage(messages[locale.value][key], values)
}

function detectThemeMode(): ThemeMode {
  const stored = window.localStorage.getItem('driveguard-theme')
  if (stored === 'dark' || stored === 'auto') return stored
  return 'light'
}

const loginForm = reactive({
  username: 'admin',
  password: '',
  totpCode: '',
  requiresTotp: false
})

const accountForm = reactive({
  username: 'admin',
  password: '',
  currentPassword: '',
  newPassword: '',
  totpCode: '',
  disablePassword: '',
  disableCode: ''
})

const planForm = reactive({
  name: t('defaultPlanName'),
  kind: 'full' as BackupKind,
  target: 'all',
  providerId: 'google-drive',
  remotePath: 'driveguard',
  retentionCopies: 7,
  encrypted: true,
  encryptionPassword: '',
  encryptionPasswordConfirm: ''
})

const scheduleForm = reactive({
  type: 'daily' as CycleType,
  time: '03:00',
  weekday: '1',
  monthDay: 1,
  intervalHours: 12,
  customCron: '0 3 * * *'
})

const providers = computed(() => status.value?.providers ?? [])
const plans = computed(() => status.value?.plans ?? [])
const targets = computed(() => status.value?.targets ?? [])
const logs = computed(() => status.value?.logs ?? [])
const jobs = computed(() => status.value?.jobs ?? [])

const totalTargets = computed(() => {
  if (!status.value) return 0
  const metrics = status.value.metrics
  return metrics.websites + metrics.mysqlDatabases + metrics.postgresDatabases
})

const readyProviders = computed(() => providers.value.filter((provider) => provider.state === 'connected').length)
const selectedProvider = computed(() => providers.value.find((provider) => provider.id === planForm.providerId))
const authValue = computed(() => (authProvider.value ? providerAuthCommand(authProvider.value) : ''))
const archivePasswordConfigured = computed(() =>
  status.value?.checks.some((check) => check.id === 'encryption' && check.state === 'ok') ?? false
)
const totpQrSvg = computed(() => {
  if (!totpSetup.value) return ''
  try {
    return createQrSvg(totpSetup.value.otpauthUrl)
  } catch {
    return ''
  }
})
const pageTitle = computed(() => {
  const titles: Record<Page, I18nKey> = {
    home: 'titleHome',
    cloud: 'titleCloud',
    plans: 'titlePlans',
    restore: 'titleRestore',
    logs: 'titleLogs',
    account: 'titleAccount'
  }
  return t(titles[activePage.value])
})

const targetOptions = computed(() => {
  if (planForm.kind === 'full') {
    return [{ value: 'all', label: t('allTargets') }]
  }

  return targets.value
    .filter((target) => {
      if (planForm.kind === 'website') return target.type === 'site'
      return target.type === 'mysql' || target.type === 'postgresql'
    })
    .map((target) => ({ value: target.id, label: `${target.name} · ${target.location}` }))
})

watch(locale, (value, oldValue) => {
  window.localStorage.setItem('driveguard-locale', value)
  if (planForm.name === messages[oldValue].defaultPlanName) {
    planForm.name = t('defaultPlanName')
  }
})

watch(
  () => planForm.kind,
  () => {
    planForm.target = targetOptions.value[0]?.value || 'all'
  }
)

watch(notice, (value) => {
  if (noticeTimer) {
    window.clearTimeout(noticeTimer)
    noticeTimer = undefined
  }
  if (!value) return

  noticeTimer = window.setTimeout(() => {
    if (notice.value === value) {
      notice.value = ''
    }
  }, 4000)
})

watch(activePage, () => {
  notice.value = ''
  error.value = ''
  mobileNavOpen.value = false
})

watch(themeMode, (value) => {
  window.localStorage.setItem('driveguard-theme', value)
  applyThemeMode(value)
})

function applyThemeMode(value = themeMode.value) {
  const prefersDark = themeMediaQuery?.matches ?? window.matchMedia('(prefers-color-scheme: dark)').matches
  const resolved = value === 'auto' ? (prefersDark ? 'dark' : 'light') : value
  document.documentElement.dataset.theme = resolved
  document.documentElement.dataset.themeMode = value
}

function setupThemeListener() {
  themeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
  const listener = () => {
    if (themeMode.value === 'auto') {
      applyThemeMode('auto')
    }
  }

  themeMediaQuery.addEventListener('change', listener)
  removeThemeListener = () => themeMediaQuery?.removeEventListener('change', listener)
}

function goPage(page: Page) {
  activePage.value = page
  mobileNavOpen.value = false
}

function closeFloatingControls() {
  if (accountMenuRef.value) {
    accountMenuRef.value.open = false
  }
  languageSelectRef.value?.blur()
}

function handleDocumentPointerDown(event: PointerEvent) {
  const target = event.target
  if (!(target instanceof Node)) return

  if (accountMenuRef.value && !accountMenuRef.value.contains(target)) {
    accountMenuRef.value.open = false
  }
  if (languageSelectRef.value && !languageSelectRef.value.contains(target)) {
    languageSelectRef.value.blur()
  }
}

function handleDocumentKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    closeFloatingControls()
  }
}

async function initialize() {
  loading.value = true
  error.value = ''

  try {
    authState.value = await getAuthState()
    if (authState.value.authenticated) {
      await refreshStatus()
    }
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('authFailed')
  } finally {
    loading.value = false
  }
}

async function refreshStatus() {
  status.value = await getStatus()
  if (status.value.providers[0] && !status.value.providers.some((provider) => provider.id === planForm.providerId)) {
    planForm.providerId = status.value.providers[0].id
  }
}

async function refresh() {
  error.value = ''
  notice.value = ''
  try {
    await refreshStatus()
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('loadStatusFailed')
  }
}

async function submitBootstrap() {
  error.value = ''
  notice.value = ''
  try {
    authState.value = await bootstrapAccount(accountForm.username, accountForm.password)
    accountForm.password = ''
    await refreshStatus()
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('authFailed')
  }
}

async function submitLogin() {
  error.value = ''
  notice.value = ''
  try {
    const response = await login(loginForm.username, loginForm.password, loginForm.totpCode)
    if (response.requiresTotp) {
      loginForm.requiresTotp = true
      notice.value = t('requiresTotp')
      return
    }
    if (response.state) {
      authState.value = response.state
      loginForm.password = ''
      loginForm.totpCode = ''
      await refreshStatus()
    }
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('authFailed')
  }
}

async function submitLogout() {
  error.value = ''
  notice.value = ''
  try {
    await logout()
    authState.value = await getAuthState()
  } catch (err) {
    authState.value = { configured: true, authenticated: false, twoFactorEnabled: false }
    error.value = err instanceof Error ? err.message : t('authFailed')
  } finally {
    loginForm.password = ''
    loginForm.totpCode = ''
    loginForm.requiresTotp = false
    status.value = null
    mobileNavOpen.value = false
    activePage.value = 'home'
  }
}

async function runBackup() {
  runningBackup.value = true
  error.value = ''
  notice.value = ''

  try {
    const response = await startBackup()
    if (status.value) {
      status.value.jobs = [response.job, ...status.value.jobs].slice(0, 5)
    }
    notice.value = t('backupQueued')
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('startBackupFailed')
  } finally {
    runningBackup.value = false
  }
}

function selectRestoreFile(event: Event) {
  const input = event.target as HTMLInputElement
  restoreFile.value = input.files?.[0] ?? null
}

async function decryptRestoreFile() {
  error.value = ''
  notice.value = ''
  if (!restoreFile.value) {
    error.value = t('restoreFileRequired')
    return
  }

  decryptingRestore.value = true
  try {
    const file = restoreFile.value
    const decrypted = await decryptBackupFile(file)
    downloadBlob(decrypted, restoreDownloadName(file.name))
    notice.value = t('restoreDownloaded')
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('restoreFailed')
  } finally {
    decryptingRestore.value = false
  }
}

function downloadBlob(blob: Blob, filename: string) {
  const url = window.URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  window.URL.revokeObjectURL(url)
}

function restoreDownloadName(filename: string) {
  const trimmed = filename.trim()
  if (!trimmed) return 'driveguard-restored'
  const withoutEnc = trimmed.toLowerCase().endsWith('.enc') ? trimmed.slice(0, -4) : trimmed
  return withoutEnc || 'driveguard-restored'
}

async function savePlan() {
  savingPlan.value = true
  error.value = ''
  notice.value = ''

  try {
    if (planForm.encrypted) {
      const password = planForm.encryptionPassword
      if (password || planForm.encryptionPasswordConfirm) {
        if (password !== planForm.encryptionPasswordConfirm) {
          error.value = t('encryptionPasswordMismatch')
          return
        }
        await setArchivePassword(password)
        planForm.encryptionPassword = ''
        planForm.encryptionPasswordConfirm = ''
        await refreshStatus()
      } else if (!archivePasswordConfigured.value) {
        error.value = t('encryptionPasswordRequired')
        return
      }
    }

    const response = await createBackupPlan({
      name: planForm.name,
      kind: planForm.kind,
      target: planForm.target,
      providerId: planForm.providerId,
      remotePath: planForm.remotePath,
      cron: buildCron(),
      retentionCopies: planForm.retentionCopies,
      encrypted: planForm.encrypted,
      enabled: true
    })

    if (status.value) {
      status.value.plans = [response.plan, ...status.value.plans]
    }
    notice.value = t('planSaved')
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('savePlanFailed')
  } finally {
    savingPlan.value = false
  }
}

async function submitPasswordChange() {
  error.value = ''
  notice.value = ''
  try {
    authState.value = await changePassword(accountForm.currentPassword, accountForm.newPassword)
    accountForm.currentPassword = ''
    accountForm.newPassword = ''
    notice.value = t('passwordChanged')
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('authFailed')
  }
}

async function startTotpSetup() {
  error.value = ''
  notice.value = ''
  try {
    totpSetup.value = await setupTotp()
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('authFailed')
  }
}

async function submitTotpEnable() {
  error.value = ''
  notice.value = ''
  try {
    authState.value = await enableTotp(accountForm.totpCode)
    accountForm.totpCode = ''
    totpSetup.value = null
    notice.value = t('totpEnabled')
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('authFailed')
  }
}

async function submitTotpDisable() {
  error.value = ''
  notice.value = ''
  try {
    authState.value = await disableTotp(accountForm.disablePassword, accountForm.disableCode)
    accountForm.disablePassword = ''
    accountForm.disableCode = ''
    notice.value = t('totpDisabled')
  } catch (err) {
    error.value = err instanceof Error ? err.message : t('authFailed')
  }
}

function openAuth(provider: CloudProvider) {
  authProvider.value = provider
  verificationUrl.value = ''
}

function providerAuthCommand(provider: CloudProvider) {
  if (provider.id === 'onedrive') return 'sudo dg auth onedrive'
  if (provider.id === 'google-drive') return 'sudo dg auth google'
  return provider.authCommand || 'sudo dg auth'
}

function closeAuth() {
  authProvider.value = null
  verificationUrl.value = ''
}

function confirmAuth() {
  if (!verificationUrl.value.trim()) {
    error.value = t('verificationUrl')
    return
  }
  notice.value = t('authPending')
  closeAuth()
}

async function copyText(value: string) {
  error.value = ''
  notice.value = ''
  try {
    await navigator.clipboard.writeText(value)
    notice.value = t('copied')
  } catch {
    notice.value = value
  }
}

function buildCron() {
  const [hour, minute] = scheduleForm.time.split(':').map(Number)
  switch (scheduleForm.type) {
    case 'weekly':
      return `${minute} ${hour} * * ${scheduleForm.weekday}`
    case 'monthly':
      return `${minute} ${hour} ${scheduleForm.monthDay} * *`
    case 'interval':
      return `0 */${scheduleForm.intervalHours} * * *`
    case 'custom':
      return scheduleForm.customCron
    default:
      return `${minute} ${hour} * * *`
  }
}

function readableSchedule(cron: string) {
  const parts = cron.trim().split(/\s+/)
  if (parts.length !== 5) return cron

  const [minute, hour, day, month, weekday] = parts
  if (minute === '0' && hour.startsWith('*/') && day === '*' && month === '*' && weekday === '*') {
    return `${t('every')} ${hour.replace('*/', '')} ${t('hours')}`
  }
  if (day === '*' && month === '*' && weekday === '*') return `${t('daily')} ${timeLabel(hour, minute)}`
  if (day === '*' && month === '*') return `${t('weekly')} ${weekdayLabel(weekday)} ${timeLabel(hour, minute)}`
  if (month === '*' && weekday === '*') return `${t('monthly')} ${day}${t('dayOfMonth')} ${timeLabel(hour, minute)}`
  return cron
}

function timeLabel(hour: string, minute: string) {
  return `${hour.padStart(2, '0')}:${minute.padStart(2, '0')}`
}

function weekdayLabel(value: string) {
  const labels: Record<string, I18nKey> = {
    '1': 'monday',
    '2': 'tuesday',
    '3': 'wednesday',
    '4': 'thursday',
    '5': 'friday',
    '6': 'saturday',
    '0': 'sunday'
  }
  return t(labels[value] || 'monday')
}

function targetIcon(target: BackupTarget) {
  if (target.type === 'site') return Folder
  if (target.type === 'postgresql') return Server
  return Database
}

function planKindLabel(kind: BackupKind) {
  if (kind === 'website') return t('website')
  if (kind === 'database') return t('database')
  return t('full')
}

function providerName(providerId: string) {
  return providers.value.find((provider) => provider.id === providerId)?.name ?? providerId
}

function providerStateLabel(provider: CloudProvider) {
  return provider.state === 'connected' ? t('connected') : t('needsAuth')
}

function formatDate(value: string) {
  if (!value) return '-'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value

  return new Intl.DateTimeFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', {
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date)
}

onMounted(() => {
  setupThemeListener()
  applyThemeMode()
  document.addEventListener('pointerdown', handleDocumentPointerDown, true)
  document.addEventListener('keydown', handleDocumentKeydown)
  initialize()
})
onUnmounted(() => {
  if (noticeTimer) {
    window.clearTimeout(noticeTimer)
  }
  document.removeEventListener('pointerdown', handleDocumentPointerDown, true)
  document.removeEventListener('keydown', handleDocumentKeydown)
  removeThemeListener?.()
})
</script>

<template>
  <div v-if="!authState?.configured || !authState.authenticated" class="auth-screen">
    <section class="auth-panel">
      <div class="brand auth-brand">
        <ShieldCheck :size="30" aria-hidden="true" />
        <div>
          <strong>DriveGuard</strong>
          <span>{{ t('appLabel') }}</span>
        </div>
      </div>

      <div class="auth-language">
        <label class="language-control">
          <Languages :size="18" aria-hidden="true" />
          <select ref="languageSelectRef" v-model="locale" :aria-label="t('language')">
            <option value="en">English</option>
            <option value="zh">中文</option>
          </select>
        </label>
      </div>

      <div v-if="error" class="alert alert-error" role="alert">
        <AlertTriangle :size="18" aria-hidden="true" />
        {{ error }}
      </div>
      <div v-if="notice" class="alert alert-info" role="status">
        <CheckCircle2 :size="18" aria-hidden="true" />
        {{ notice }}
      </div>

      <form v-if="authState && !authState.configured" class="auth-form" @submit.prevent="submitBootstrap">
        <h1>{{ t('setupAccount') }}</h1>
        <p>{{ t('notConfiguredHint') }}</p>
        <label>
          <span>{{ t('username') }}</span>
          <input v-model="accountForm.username" autocomplete="username" required />
        </label>
        <label>
          <span>{{ t('password') }}</span>
          <input v-model="accountForm.password" type="password" autocomplete="new-password" required minlength="12" />
        </label>
        <button class="primary-button" type="submit">{{ t('createAccount') }}</button>
      </form>

      <form v-else class="auth-form" @submit.prevent="submitLogin">
        <h1>{{ t('signInTitle') }}</h1>
        <p>{{ t('securityHint') }}</p>
        <label>
          <span>{{ t('username') }}</span>
          <input v-model="loginForm.username" autocomplete="username" required />
        </label>
        <label>
          <span>{{ t('password') }}</span>
          <input v-model="loginForm.password" type="password" autocomplete="current-password" required />
        </label>
        <label v-if="loginForm.requiresTotp">
          <span>{{ t('totpCode') }}</span>
          <input v-model="loginForm.totpCode" inputmode="numeric" autocomplete="one-time-code" />
        </label>
        <button class="primary-button" type="submit">{{ t('signIn') }}</button>
      </form>
    </section>
  </div>

  <div v-else :class="['app-shell', { 'sidebar-collapsed': sidebarCollapsed }]">
    <aside
      id="app-navigation"
      :class="['sidebar', { 'sidebar-collapsed': sidebarCollapsed, 'mobile-open': mobileNavOpen }]"
    >
      <div class="brand">
        <ShieldCheck :size="28" aria-hidden="true" />
        <div class="brand-copy">
          <strong>DriveGuard</strong>
          <span>{{ authState.username }}</span>
        </div>
      </div>

      <nav class="nav-list" :aria-label="t('appLabel')">
        <button :class="['nav-item', { active: activePage === 'home' }]" type="button" @click="goPage('home')">
          <Home :size="18" aria-hidden="true" />
          <span class="nav-label">{{ t('home') }}</span>
        </button>
        <button :class="['nav-item', { active: activePage === 'cloud' }]" type="button" @click="goPage('cloud')">
          <KeyRound :size="18" aria-hidden="true" />
          <span class="nav-label">{{ t('cloudAuth') }}</span>
        </button>
        <button :class="['nav-item', { active: activePage === 'plans' }]" type="button" @click="goPage('plans')">
          <CalendarClock :size="18" aria-hidden="true" />
          <span class="nav-label">{{ t('backupPlans') }}</span>
        </button>
        <button :class="['nav-item', { active: activePage === 'restore' }]" type="button" @click="goPage('restore')">
          <FileDown :size="18" aria-hidden="true" />
          <span class="nav-label">{{ t('restoreDecrypt') }}</span>
        </button>
        <button :class="['nav-item', { active: activePage === 'logs' }]" type="button" @click="goPage('logs')">
          <SquareTerminal :size="18" aria-hidden="true" />
          <span class="nav-label">{{ t('runLogs') }}</span>
        </button>
        <button :class="['nav-item', { active: activePage === 'account' }]" type="button" @click="goPage('account')">
          <UserRound :size="18" aria-hidden="true" />
          <span class="nav-label">{{ t('accountSecurity') }}</span>
        </button>
      </nav>

      <button
        class="sidebar-toggle"
        type="button"
        :aria-label="sidebarCollapsed ? t('expandSidebar') : t('collapseSidebar')"
        :title="sidebarCollapsed ? t('expandSidebar') : t('collapseSidebar')"
        @click="sidebarCollapsed = !sidebarCollapsed"
      >
        <PanelLeftOpen v-if="sidebarCollapsed" :size="18" aria-hidden="true" />
        <PanelLeftClose v-else :size="18" aria-hidden="true" />
        <span class="nav-label">{{ sidebarCollapsed ? t('expandSidebar') : t('collapseSidebar') }}</span>
      </button>
    </aside>
    <button
      v-if="mobileNavOpen"
      class="mobile-nav-backdrop"
      type="button"
      :aria-label="t('closeSidebar')"
      @click="mobileNavOpen = false"
    ></button>

    <main class="workspace">
      <header class="topbar">
        <div>
          <p class="eyebrow">{{ t('appLabel') }}</p>
          <h1>{{ pageTitle }}</h1>
        </div>

        <div class="top-actions">
          <label class="language-control">
            <Languages :size="18" aria-hidden="true" />
            <select ref="languageSelectRef" v-model="locale" :aria-label="t('language')">
              <option value="en">English</option>
              <option value="zh">中文</option>
            </select>
          </label>
          <div class="theme-control" role="group" :aria-label="t('themeMode')">
            <button
              :class="['theme-option', { active: themeMode === 'light' }]"
              type="button"
              :aria-label="t('normalMode')"
              :title="t('normalMode')"
              @click="themeMode = 'light'"
            >
              <Sun :size="17" aria-hidden="true" />
            </button>
            <button
              :class="['theme-option', { active: themeMode === 'dark' }]"
              type="button"
              :aria-label="t('darkMode')"
              :title="t('darkMode')"
              @click="themeMode = 'dark'"
            >
              <Moon :size="17" aria-hidden="true" />
            </button>
            <button
              :class="['theme-option', { active: themeMode === 'auto' }]"
              type="button"
              :aria-label="t('autoMode')"
              :title="t('autoMode')"
              @click="themeMode = 'auto'"
            >
              <Monitor :size="17" aria-hidden="true" />
            </button>
          </div>
          <details ref="accountMenuRef" class="account-menu">
            <summary class="account-summary" :aria-label="t('accountMenu')">
              <UserRound :size="18" aria-hidden="true" />
              <span>{{ authState.username || 'admin' }}</span>
              <ChevronDown :size="16" aria-hidden="true" />
            </summary>
            <div class="account-popover">
              <button class="account-menu-item" type="button" @click="goPage('account')">
                <UserRound :size="17" aria-hidden="true" />
                {{ t('accountSettings') }}
              </button>
              <button class="account-menu-item danger" type="button" @click="submitLogout">
                <LogOut :size="17" aria-hidden="true" />
                {{ t('logout') }}
              </button>
            </div>
          </details>
          <button
            class="icon-button mobile-nav-button"
            type="button"
            :aria-label="t('openSidebar')"
            :aria-controls="'app-navigation'"
            :aria-expanded="mobileNavOpen"
            @click="mobileNavOpen = true"
          >
            <Menu :size="18" aria-hidden="true" />
          </button>
        </div>
      </header>

      <div v-if="error" class="alert alert-error" role="alert">
        <AlertTriangle :size="18" aria-hidden="true" />
        {{ error }}
      </div>
      <div v-if="notice" class="alert alert-info" role="status">
        <CheckCircle2 :size="18" aria-hidden="true" />
        {{ notice }}
      </div>

      <section v-if="activePage === 'home'" class="page-stack">
        <div class="dashboard-actions">
          <button class="secondary-button" type="button" :aria-label="t('refreshStatus')" @click="refresh">
            <RefreshCcw :size="18" aria-hidden="true" />
            {{ t('refreshStatus') }}
          </button>
          <button class="primary-button" type="button" @click="runBackup" :disabled="runningBackup">
            <Play :size="18" aria-hidden="true" />
            {{ runningBackup ? t('starting') : t('runNow') }}
          </button>
        </div>

        <div class="metric-grid">
          <article class="metric-panel">
            <span class="metric-icon"><Cloud :size="20" aria-hidden="true" /></span>
            <p>{{ t('clouds') }}</p>
            <strong>{{ providers.length }}</strong>
            <small>{{ t('providerReady') }}: {{ readyProviders }}</small>
          </article>
          <article class="metric-panel">
            <span class="metric-icon"><CalendarClock :size="20" aria-hidden="true" /></span>
            <p>{{ t('plans') }}</p>
            <strong>{{ plans.length }}</strong>
            <small>{{ plans[0] ? readableSchedule(plans[0].cron) : '-' }}</small>
          </article>
          <article class="metric-panel">
            <span class="metric-icon"><HardDrive :size="20" aria-hidden="true" /></span>
            <p>{{ t('targets') }}</p>
            <strong>{{ totalTargets }}</strong>
            <small>{{ status?.metrics.websites || 0 }} {{ t('website') }}, {{ status?.metrics.mysqlDatabases || 0 }} MySQL</small>
          </article>
          <article class="metric-panel">
            <span class="metric-icon"><ListChecks :size="20" aria-hidden="true" /></span>
            <p>{{ t('lastRun') }}</p>
            <strong>{{ status?.metrics.lastRun ? formatDate(status.metrics.lastRun) : '-' }}</strong>
            <small>{{ status?.service.mode || '-' }}</small>
          </article>
        </div>

        <section class="content-grid">
          <article class="section-block">
            <div class="section-header">
              <div>
                <p class="eyebrow">Targets</p>
                <h2>{{ t('backupSources') }}</h2>
              </div>
            </div>
            <ul class="target-list">
              <li v-for="target in targets" :key="target.id">
                <component :is="targetIcon(target)" :size="18" aria-hidden="true" />
                <div>
                  <strong>{{ target.name }}</strong>
                  <span>{{ target.location }}</span>
                </div>
                <span :class="['badge', `badge-${target.state}`]">{{ target.state === 'ready' ? t('ready') : t('state') }}</span>
              </li>
              <li v-if="targets.length === 0">{{ t('emptyTargets') }}</li>
            </ul>
          </article>

          <article class="section-block">
            <div class="section-header">
              <div>
                <p class="eyebrow">Recent</p>
                <h2>{{ t('runLogs') }}</h2>
              </div>
            </div>
            <ul class="log-list">
              <li v-for="line in logs.slice(0, 4)" :key="line.id" :class="`log-${line.level}`">
                <time>{{ line.time }}</time>
                <span>{{ line.message }}</span>
              </li>
            </ul>
          </article>
        </section>
      </section>

      <section v-if="activePage === 'cloud'" class="page-stack">
        <div class="provider-grid">
          <article v-for="provider in providers" :key="provider.id" class="provider-card">
            <div class="provider-top">
              <span class="provider-icon">
                <Cloud :size="22" aria-hidden="true" />
              </span>
              <span :class="['badge', `badge-${provider.state}`]">{{ providerStateLabel(provider) }}</span>
            </div>
            <h3>{{ provider.name }}</h3>
            <dl class="compact-list">
              <div>
                <dt>{{ t('remote') }}</dt>
                <dd>{{ provider.remoteName }}:</dd>
              </div>
              <div>
                <dt>{{ t('directory') }}</dt>
                <dd>{{ provider.remotePath }}</dd>
              </div>
            </dl>
            <button class="primary-button" type="button" @click="openAuth(provider)">
              <KeyRound :size="16" aria-hidden="true" />
              {{ t('authorize') }}
            </button>
          </article>
        </div>
      </section>

      <section v-if="activePage === 'plans'" class="page-stack">
        <section class="section-block">
          <div class="section-header">
            <div>
              <p class="eyebrow">Create</p>
              <h2>{{ t('newPlan') }}</h2>
            </div>
          </div>

          <form class="plan-form" @submit.prevent="savePlan">
            <label>
              <span>{{ t('taskName') }}</span>
              <input v-model="planForm.name" type="text" required />
            </label>

            <label>
              <span>{{ t('backupContent') }}</span>
              <select v-model="planForm.kind">
                <option value="full">{{ t('all') }}</option>
                <option value="website">{{ t('website') }}</option>
                <option value="database">{{ t('database') }}</option>
              </select>
            </label>

            <label>
              <span>{{ t('backupTarget') }}</span>
              <select v-model="planForm.target">
                <option v-for="target in targetOptions" :key="target.value" :value="target.value">
                  {{ target.label }}
                </option>
              </select>
            </label>

            <label>
              <span>{{ t('cloudDrive') }}</span>
              <select v-model="planForm.providerId">
                <option v-for="provider in providers" :key="provider.id" :value="provider.id">
                  {{ provider.name }}
                </option>
              </select>
            </label>

            <label>
              <span>{{ t('remotePath') }}</span>
              <input v-model="planForm.remotePath" type="text" required />
            </label>

            <label>
              <span>{{ t('executionCycle') }}</span>
              <select v-model="scheduleForm.type">
                <option value="daily">{{ t('daily') }}</option>
                <option value="weekly">{{ t('weekly') }}</option>
                <option value="monthly">{{ t('monthly') }}</option>
                <option value="interval">{{ t('interval') }}</option>
                <option value="custom">{{ t('custom') }}</option>
              </select>
            </label>

            <label v-if="scheduleForm.type !== 'interval' && scheduleForm.type !== 'custom'">
              <span>{{ t('at') }}</span>
              <input v-model="scheduleForm.time" type="time" />
            </label>

            <label v-if="scheduleForm.type === 'weekly'">
              <span>{{ t('weekly') }}</span>
              <select v-model="scheduleForm.weekday">
                <option value="1">{{ t('monday') }}</option>
                <option value="2">{{ t('tuesday') }}</option>
                <option value="3">{{ t('wednesday') }}</option>
                <option value="4">{{ t('thursday') }}</option>
                <option value="5">{{ t('friday') }}</option>
                <option value="6">{{ t('saturday') }}</option>
                <option value="0">{{ t('sunday') }}</option>
              </select>
            </label>

            <label v-if="scheduleForm.type === 'monthly'">
              <span>{{ t('dayOfMonth') }}</span>
              <input v-model.number="scheduleForm.monthDay" type="number" min="1" max="28" />
            </label>

            <label v-if="scheduleForm.type === 'interval'">
              <span>{{ t('every') }}</span>
              <input v-model.number="scheduleForm.intervalHours" type="number" min="1" max="24" />
            </label>

            <label v-if="scheduleForm.type === 'custom'">
              <span>{{ t('customCron') }}</span>
              <input v-model="scheduleForm.customCron" type="text" />
            </label>

            <label>
              <span>{{ t('retention') }}</span>
              <input v-model.number="planForm.retentionCopies" type="number" min="1" max="60" required />
            </label>

            <label>
              <span>{{ t('encryption') }}</span>
              <select v-model="planForm.encrypted">
                <option :value="true">{{ t('enabled') }}</option>
                <option :value="false">{{ t('disabled') }}</option>
              </select>
            </label>

            <label v-if="planForm.encrypted">
              <span>{{ t('encryptionPassword') }}</span>
              <input
                v-model="planForm.encryptionPassword"
                type="password"
                autocomplete="new-password"
                minlength="12"
                :placeholder="archivePasswordConfigured ? t('leaveBlankKeepPassword') : t('minimumPasswordHint')"
              />
              <small>{{ archivePasswordConfigured ? t('encryptionPasswordConfigured') : t('encryptionPasswordHelp') }}</small>
            </label>

            <label v-if="planForm.encrypted">
              <span>{{ t('confirmEncryptionPassword') }}</span>
              <input
                v-model="planForm.encryptionPasswordConfirm"
                type="password"
                autocomplete="new-password"
                minlength="12"
                :placeholder="archivePasswordConfigured ? t('leaveBlankKeepPassword') : t('minimumPasswordHint')"
              />
            </label>

            <div class="form-actions">
              <button class="primary-button" type="submit" :disabled="savingPlan">
                <Save :size="18" aria-hidden="true" />
                {{ savingPlan ? t('saving') : t('savePlan') }}
              </button>
            </div>
          </form>
        </section>

        <section class="section-block">
          <div class="section-header">
            <div>
              <p class="eyebrow">Plans</p>
              <h2>{{ t('planList') }}</h2>
            </div>
            <Plus :size="18" aria-hidden="true" />
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{{ t('name') }}</th>
                  <th>{{ t('content') }}</th>
                  <th>{{ t('cloudDrive') }}</th>
                  <th>{{ t('schedule') }}</th>
                  <th>{{ t('retention') }}</th>
                  <th>{{ t('state') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="plan in plans" :key="plan.id">
                  <td>
                    <strong>{{ plan.name }}</strong>
                    <small>{{ plan.remotePath }}</small>
                  </td>
                  <td>{{ planKindLabel(plan.kind) }}</td>
                  <td>{{ providerName(plan.providerId) }}</td>
                  <td>{{ readableSchedule(plan.cron) }}</td>
                  <td>{{ t('keepCopies', { count: plan.retentionCopies }) }}</td>
                  <td><span :class="['badge', `badge-${plan.state}`]">{{ plan.state === 'draft' ? t('draft') : t('enabled') }}</span></td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>

      <section v-if="activePage === 'restore'" class="page-stack">
        <section class="section-block">
          <div class="section-header">
            <div>
              <p class="eyebrow">Restore</p>
              <h2>{{ t('restoreDecrypt') }}</h2>
            </div>
            <FileDown :size="18" aria-hidden="true" />
          </div>

          <form class="restore-form" @submit.prevent="decryptRestoreFile">
            <label class="upload-zone">
              <UploadCloud :size="32" aria-hidden="true" />
              <strong>{{ restoreFile ? restoreFile.name : t('chooseEncryptedFile') }}</strong>
              <span>{{ t('restoreUploadHint') }}</span>
              <input type="file" accept=".enc,application/octet-stream" @change="selectRestoreFile" />
            </label>

            <div v-if="restoreFile" class="restore-summary">
              <span>{{ t('selectedFile') }}</span>
              <strong>{{ restoreFile.name }}</strong>
              <small>{{ (restoreFile.size / 1024 / 1024).toFixed(2) }} MB</small>
            </div>

            <ul class="restore-facts">
              <li>
                <CheckCircle2 :size="18" aria-hidden="true" />
                <div>
                  <strong>{{ t('temporaryOnly') }}</strong>
                  <span>{{ t('temporaryOnlyHint') }}</span>
                </div>
              </li>
              <li>
                <LockKeyhole :size="18" aria-hidden="true" />
                <div>
                  <strong>{{ t('usesArchivePassword') }}</strong>
                  <span>{{ t('usesArchivePasswordHint') }}</span>
                </div>
              </li>
            </ul>

            <div class="form-actions">
              <button class="primary-button" type="submit" :disabled="decryptingRestore || !restoreFile">
                <Download :size="18" aria-hidden="true" />
                {{ decryptingRestore ? t('decrypting') : t('decryptAndDownload') }}
              </button>
            </div>
          </form>
        </section>
      </section>

      <section v-if="activePage === 'logs'" class="page-stack">
        <section class="content-grid">
          <article class="section-block">
            <div class="section-header">
              <div>
                <p class="eyebrow">Jobs</p>
                <h2>{{ t('backupPlans') }}</h2>
              </div>
            </div>
            <ul class="target-list">
              <li v-for="job in jobs" :key="job.id">
                <ListChecks :size="18" aria-hidden="true" />
                <div>
                  <strong>{{ job.type }}</strong>
                  <span>{{ formatDate(job.startedAt) }}</span>
                </div>
                <span :class="['badge', `badge-${job.state}`]">{{ job.state }}</span>
              </li>
            </ul>
          </article>

          <article class="section-block">
            <div class="section-header">
              <div>
                <p class="eyebrow">Logs</p>
                <h2>{{ t('runLogs') }}</h2>
              </div>
            </div>
            <ul class="log-list">
              <li v-for="line in logs" :key="line.id" :class="`log-${line.level}`">
                <time>{{ line.time }}</time>
                <span>{{ line.message }}</span>
              </li>
            </ul>
          </article>
        </section>
      </section>

      <section v-if="activePage === 'account'" class="page-stack">
        <section class="content-grid">
          <article class="section-block">
            <div class="section-header">
              <div>
                <p class="eyebrow">Password</p>
                <h2>{{ t('changePassword') }}</h2>
              </div>
              <LockKeyhole :size="18" aria-hidden="true" />
            </div>
            <form class="security-form" @submit.prevent="submitPasswordChange">
              <label>
                <span>{{ t('currentPassword') }}</span>
                <input v-model="accountForm.currentPassword" type="password" autocomplete="current-password" required />
              </label>
              <label>
                <span>{{ t('newPassword') }}</span>
                <input v-model="accountForm.newPassword" type="password" autocomplete="new-password" required minlength="12" />
              </label>
              <button class="primary-button" type="submit">{{ t('changePassword') }}</button>
            </form>
          </article>

          <article class="section-block">
            <div class="section-header">
              <div>
                <p class="eyebrow">2FA</p>
                <h2>{{ t('twoFactor') }}</h2>
              </div>
              <Smartphone :size="18" aria-hidden="true" />
            </div>
            <div v-if="!authState.twoFactorEnabled" class="security-form">
              <button class="secondary-button" type="button" @click="startTotpSetup">{{ t('setup2fa') }}</button>
              <template v-if="totpSetup">
                <div class="totp-qr-panel">
                  <div v-if="totpQrSvg" class="totp-qr" v-html="totpQrSvg"></div>
                  <div>
                    <strong>{{ t('scanTotpQr') }}</strong>
                    <span>{{ t('scanTotpQrHint') }}</span>
                  </div>
                </div>
                <label>
                  <span>{{ t('totpSecret') }}</span>
                  <input :value="totpSetup.secret" readonly />
                </label>
                <label>
                  <span>{{ t('otpauthUrl') }}</span>
                  <input :value="totpSetup.otpauthUrl" readonly />
                </label>
                <label>
                  <span>{{ t('totpCode') }}</span>
                  <input v-model="accountForm.totpCode" inputmode="numeric" autocomplete="one-time-code" />
                </label>
                <button class="primary-button" type="button" @click="submitTotpEnable">{{ t('enable2fa') }}</button>
              </template>
            </div>
            <form v-else class="security-form" @submit.prevent="submitTotpDisable">
              <label>
                <span>{{ t('password') }}</span>
                <input v-model="accountForm.disablePassword" type="password" autocomplete="current-password" required />
              </label>
              <label>
                <span>{{ t('totpCode') }}</span>
                <input v-model="accountForm.disableCode" inputmode="numeric" autocomplete="one-time-code" required />
              </label>
              <button class="secondary-button" type="submit">{{ t('disable2fa') }}</button>
            </form>
          </article>
        </section>

        <section class="section-block session-block">
          <div class="section-header">
            <div>
              <p class="eyebrow">Session</p>
              <h2>{{ t('currentSession') }}</h2>
            </div>
          </div>
          <div class="session-row">
            <p>{{ t('currentSessionHint') }}</p>
            <button class="secondary-button danger-button" type="button" @click="submitLogout">
              <LogOut :size="18" aria-hidden="true" />
              {{ t('logout') }}
            </button>
          </div>
        </section>
      </section>
    </main>

    <div v-if="authProvider" class="modal-backdrop" @click.self="closeAuth">
      <section class="auth-modal" role="dialog" aria-modal="true" :aria-label="t('authGuide')">
        <header class="modal-header">
          <div>
            <p class="eyebrow">{{ t('cloudAuth') }}</p>
            <h2>{{ authProvider.name }}</h2>
          </div>
          <button class="icon-button" type="button" :aria-label="t('close')" @click="closeAuth">
            <X :size="18" aria-hidden="true" />
          </button>
        </header>

        <div class="step-flow">
          <article class="step-item">
            <span class="step-number">1</span>
            <div class="step-body">
              <h3>{{ t('copyCommand') }}</h3>
              <p>{{ t('authStep1') }}</p>
              <div class="auth-command-row">
                <input :value="authValue" type="text" readonly />
                <button class="secondary-button" type="button" @click="copyText(authValue)">
                  <Copy :size="16" aria-hidden="true" />
                  {{ t('copyCommand') }}
                </button>
              </div>
            </div>
          </article>
          <article class="step-item">
            <span class="step-number">2</span>
            <div class="step-body">
              <h3>{{ t('authGuide') }}</h3>
              <p>{{ t('authStep2') }}</p>
              <p>{{ t('authStep3') }}</p>
            </div>
          </article>
          <article class="step-item">
            <span class="step-number">3</span>
            <div class="step-body">
              <h3>{{ t('verificationUrl') }}</h3>
              <textarea v-model="verificationUrl" :placeholder="t('verificationUrl')" rows="5"></textarea>
            </div>
          </article>
        </div>

        <footer class="modal-actions">
          <button class="secondary-button" type="button" @click="closeAuth">{{ t('close') }}</button>
          <button class="primary-button" type="button" @click="confirmAuth">
            <CheckCircle2 :size="18" aria-hidden="true" />
            {{ t('confirmNow') }}
          </button>
        </footer>
      </section>
    </div>
  </div>
</template>
