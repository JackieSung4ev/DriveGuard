#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="driveguard"
DISPLAY_NAME="DriveGuard"
SHORT_APP_NAME="dg"
CRON_MARKER_BEGIN="# DRIVEGUARD_BEGIN"
CRON_MARKER_END="# DRIVEGUARD_END"
INSTALL_PATH="/usr/local/bin/${APP_NAME}"
SHORT_INSTALL_PATH="/usr/local/bin/${SHORT_APP_NAME}"
CONFIG_DIR="${CONFIG_DIR:-/etc/${APP_NAME}}"
CONFIG_FILE="${CONFIG_FILE:-${CONFIG_DIR}/config.conf}"
SITES_FILE="${SITES_FILE:-${CONFIG_DIR}/sites.list}"
DATABASES_FILE="${DATABASES_FILE:-${CONFIG_DIR}/databases.list}"
POSTGRES_DATABASES_FILE="${POSTGRES_DATABASES_FILE:-${CONFIG_DIR}/postgres.databases.list}"
ARCHIVE_PASSWORD_FILE="${ARCHIVE_PASSWORD_FILE:-${CONFIG_DIR}/archive.pass}"
MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-${CONFIG_DIR}/mysql.cnf}"
POSTGRES_PASSFILE="${POSTGRES_PASSFILE:-${CONFIG_DIR}/postgres.pgpass}"
STATE_DIR="${STATE_DIR:-/var/lib/${APP_NAME}}"
LOG_DIR="${LOG_DIR:-/var/log/${APP_NAME}}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/backup.log}"
RCLONE_LOG_FILE="${RCLONE_LOG_FILE:-${LOG_DIR}/rclone.log}"
LOCK_FILE="${LOCK_FILE:-${STATE_DIR}/backup.lock}"
UPDATE_REPO_DIR="${UPDATE_REPO_DIR:-}"

RCLONE_REMOTE="${RCLONE_REMOTE:-cloud}"
RCLONE_REMOTE_PATH="${RCLONE_REMOTE_PATH:-driveguard}"
RCLONE_CHUNK_SIZE="${RCLONE_CHUNK_SIZE:-64M}"
KEEP_COPIES="${KEEP_COPIES:-7}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/${APP_NAME}}"
BACKUP_SCOPE_KIND="${BACKUP_SCOPE_KIND:-full}"
BACKUP_SCOPE_NAME="${BACKUP_SCOPE_NAME:-}"
BACKUP_SCOPE_LOCATION="${BACKUP_SCOPE_LOCATION:-}"
BACKUP_SCOPE_EXCLUDES="${BACKUP_SCOPE_EXCLUDES:-}"
AUTO_DISCOVER_SITES="${AUTO_DISCOVER_SITES:-1}"
AUTO_DISCOVER_DATABASES="${AUTO_DISCOVER_DATABASES:-1}"
SITE_ROOTS="${SITE_ROOTS:-/www/wwwroot /var/www /srv/www /usr/share/nginx/html}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_SOCKET="${MYSQL_SOCKET:-}"
MYSQLDUMP_BIN="${MYSQLDUMP_BIN:-}"
MYSQL_BIN="${MYSQL_BIN:-}"
POSTGRES_ENABLED="${POSTGRES_ENABLED:-auto}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DEFAULT_DB="${POSTGRES_DEFAULT_DB:-postgres}"
PGDUMP_BIN="${PGDUMP_BIN:-}"
PSQL_BIN="${PSQL_BIN:-}"
CRON_EXPR="${CRON_EXPR:-0 3 * * *}"
ENABLE_CRON_GUARD="${ENABLE_CRON_GUARD:-1}"

timestamp() {
  date '+%F %T'
}

script_self() {
  readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || printf '%s\n' "$0"
}

log() {
  local msg="$*"
  local line="[$(timestamp)] ${msg}"
  printf '%s\n' "$line"
  if [[ -d "$LOG_DIR" ]]; then
    printf '%s\n' "$line" >> "$LOG_FILE"
  fi
}

die() {
  log "Error: $*"
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Please run as root: sudo bash $0"
  fi
}

current_source_dir() {
  local src
  src="$(script_self)"
  (cd "$(dirname "$src")" >/dev/null 2>&1 && pwd -P)
}

find_update_repo_dir() {
  local src_dir
  if [[ -n "$UPDATE_REPO_DIR" && -d "$UPDATE_REPO_DIR" && -e "$UPDATE_REPO_DIR/.git" ]]; then
    printf '%s\n' "$UPDATE_REPO_DIR"
    return 0
  fi

  src_dir="$(current_source_dir)" || return 1
  if [[ -e "$src_dir/.git" ]]; then
    printf '%s\n' "$src_dir"
    return 0
  fi
  return 1
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
  SITES_FILE="${SITES_FILE:-${CONFIG_DIR}/sites.list}"
  DATABASES_FILE="${DATABASES_FILE:-${CONFIG_DIR}/databases.list}"
  POSTGRES_DATABASES_FILE="${POSTGRES_DATABASES_FILE:-${CONFIG_DIR}/postgres.databases.list}"
  ARCHIVE_PASSWORD_FILE="${ARCHIVE_PASSWORD_FILE:-${CONFIG_DIR}/archive.pass}"
  MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-${CONFIG_DIR}/mysql.cnf}"
  POSTGRES_PASSFILE="${POSTGRES_PASSFILE:-${CONFIG_DIR}/postgres.pgpass}"
  STATE_DIR="${STATE_DIR:-/var/lib/${APP_NAME}}"
  LOG_DIR="${LOG_DIR:-/var/log/${APP_NAME}}"
  LOG_FILE="${LOG_FILE:-${LOG_DIR}/backup.log}"
  RCLONE_LOG_FILE="${RCLONE_LOG_FILE:-${LOG_DIR}/rclone.log}"
  LOCK_FILE="${LOCK_FILE:-${STATE_DIR}/backup.lock}"
  UPDATE_REPO_DIR="${UPDATE_REPO_DIR:-}"
  RCLONE_REMOTE="${RCLONE_REMOTE:-cloud}"
  RCLONE_REMOTE_PATH="${RCLONE_REMOTE_PATH:-driveguard}"
  RCLONE_CHUNK_SIZE="${RCLONE_CHUNK_SIZE:-64M}"
  KEEP_COPIES="${KEEP_COPIES:-7}"
  BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/${APP_NAME}}"
  BACKUP_SCOPE_KIND="${BACKUP_SCOPE_KIND:-full}"
  BACKUP_SCOPE_NAME="${BACKUP_SCOPE_NAME:-}"
  BACKUP_SCOPE_LOCATION="${BACKUP_SCOPE_LOCATION:-}"
  BACKUP_SCOPE_EXCLUDES="${BACKUP_SCOPE_EXCLUDES:-}"
  AUTO_DISCOVER_SITES="${AUTO_DISCOVER_SITES:-1}"
  AUTO_DISCOVER_DATABASES="${AUTO_DISCOVER_DATABASES:-1}"
  SITE_ROOTS="${SITE_ROOTS:-/www/wwwroot /var/www /srv/www /usr/share/nginx/html}"
  MYSQL_HOST="${MYSQL_HOST:-localhost}"
  MYSQL_PORT="${MYSQL_PORT:-3306}"
  MYSQL_SOCKET="${MYSQL_SOCKET:-}"
  MYSQLDUMP_BIN="${MYSQLDUMP_BIN:-}"
  MYSQL_BIN="${MYSQL_BIN:-}"
  POSTGRES_ENABLED="${POSTGRES_ENABLED:-auto}"
  POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
  POSTGRES_PORT="${POSTGRES_PORT:-5432}"
  POSTGRES_USER="${POSTGRES_USER:-postgres}"
  POSTGRES_DEFAULT_DB="${POSTGRES_DEFAULT_DB:-postgres}"
  PGDUMP_BIN="${PGDUMP_BIN:-}"
  PSQL_BIN="${PSQL_BIN:-}"
  CRON_EXPR="${CRON_EXPR:-0 3 * * *}"
  ENABLE_CRON_GUARD="${ENABLE_CRON_GUARD:-1}"
}

ensure_dirs() {
  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" "$BACKUP_ROOT"
  mkdir -p "$BACKUP_ROOT/site" "$BACKUP_ROOT/database" "$BACKUP_ROOT/path"
  touch "$SITES_FILE" "$DATABASES_FILE" "$POSTGRES_DATABASES_FILE" "$LOG_FILE" "$RCLONE_LOG_FILE"
  chmod 700 "$CONFIG_DIR" "$STATE_DIR" "$BACKUP_ROOT" 2>/dev/null || true
  chmod 600 "$CONFIG_FILE" "$SITES_FILE" "$DATABASES_FILE" "$POSTGRES_DATABASES_FILE" "$POSTGRES_PASSFILE" "$LOG_FILE" "$RCLONE_LOG_FILE" 2>/dev/null || true
}

save_config() {
  ensure_dirs
  umask 077
  {
    printf '# %s configuration file, generated at: %s\n' "$DISPLAY_NAME" "$(timestamp)"
    for key in \
      SITES_FILE DATABASES_FILE POSTGRES_DATABASES_FILE \
      ARCHIVE_PASSWORD_FILE MYSQL_DEFAULTS_FILE POSTGRES_PASSFILE \
      STATE_DIR LOG_DIR LOG_FILE RCLONE_LOG_FILE LOCK_FILE \
      UPDATE_REPO_DIR \
      RCLONE_REMOTE RCLONE_REMOTE_PATH RCLONE_CHUNK_SIZE KEEP_COPIES \
      BACKUP_ROOT BACKUP_SCOPE_KIND BACKUP_SCOPE_NAME BACKUP_SCOPE_LOCATION BACKUP_SCOPE_EXCLUDES \
      AUTO_DISCOVER_SITES AUTO_DISCOVER_DATABASES SITE_ROOTS \
      MYSQL_HOST MYSQL_PORT MYSQL_SOCKET MYSQLDUMP_BIN MYSQL_BIN \
      POSTGRES_ENABLED POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_DEFAULT_DB PGDUMP_BIN PSQL_BIN \
      CRON_EXPR ENABLE_CRON_GUARD
    do
      printf '%s=%q\n' "$key" "${!key}"
    done
  } > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

pause_enter() {
  read -r -p "Press Enter to continue..." _
}

confirm() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]
}

sanitize_name() {
  local raw="$1"
  raw="${raw// /_}"
  printf '%s' "$raw" | sed 's/[^A-Za-z0-9._-]/_/g'
}

valid_positive_int() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

pgpass_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//:/\\:}"
  printf '%s' "$value"
}

install_dependencies() {
  require_root
  local distro=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    distro="${ID:-} ${ID_LIKE:-}"
  fi

  if [[ "$distro" == *debian* || "$distro" == *ubuntu* || ( -z "$distro" && -x /usr/bin/apt-get ) ]]; then
    install_debian_dependencies
  elif [[ "$distro" == *rhel* || "$distro" == *fedora* || "$distro" == *centos* || "$distro" == *rocky* || "$distro" == *almalinux* || "$distro" == *ol* || ( -z "$distro" && ( -x /usr/bin/dnf || -x /usr/bin/yum ) ) ]]; then
    install_rhel_dependencies
  else
    die "Supported systems: Debian/Ubuntu/CentOS/RHEL family. Detected: ${PRETTY_NAME:-unknown}"
  fi

  ensure_dirs
  ensure_cron_service || true
  log "Dependency check complete"
}

install_debian_dependencies() {
  have apt-get || die "apt-get not found; this system does not look like Debian/Ubuntu"
  log "Installing dependencies: git, rclone, cron, openssl, MySQL/PostgreSQL clients, etc."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates cron git rclone openssl tar gzip util-linux postgresql-client
  if ! have mysqldump && ! have mariadb-dump; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y default-mysql-client \
      || DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-client
  fi
}

install_rhel_dependencies() {
  local pkg_mgr
  if have dnf; then
    pkg_mgr="dnf"
  elif have yum; then
    pkg_mgr="yum"
  else
    die "dnf/yum not found; this system does not look like CentOS/RHEL"
  fi

  log "Installing dependencies: git, rclone, cronie, openssl, MySQL/MariaDB/PostgreSQL clients, etc."
  rhel_install_packages "$pkg_mgr" bash ca-certificates cronie git openssl tar gzip util-linux curl unzip mariadb postgresql

  if ! have mysqldump && ! have mariadb-dump; then
    rhel_install_packages "$pkg_mgr" mariadb
  fi

  if ! have rclone; then
    if ! rhel_install_packages "$pkg_mgr" rclone; then
      log "rclone is not available from system repositories; falling back to the official rclone installer"
      install_rclone_official
    fi
  fi
}

rhel_install_packages() {
  local pkg_mgr="$1"
  shift
  if "$pkg_mgr" install -y "$@"; then
    return 0
  fi
  if [[ -d /etc/yum.repos.d ]] && grep -Rqs '^\[cloudflare\]' /etc/yum.repos.d; then
    log "Detected cloudflare repo; retrying with that repo temporarily disabled"
    "$pkg_mgr" --disablerepo=cloudflare install -y "$@"
    return $?
  fi
  return 1
}

install_rclone_official() {
  have curl || die "curl not found; cannot download the official rclone installer"
  local installer
  installer="$(mktemp)"
  if curl -fsSL https://rclone.org/install.sh -o "$installer"; then
    bash "$installer"
    rm -f "$installer"
  else
    rm -f "$installer"
    die "Failed to download the official rclone installer; check network connectivity and retry"
  fi
  have rclone || die "rclone is still unavailable after installation; run manually: curl -fsSL https://rclone.org/install.sh | bash"
}

ensure_cron_service() {
  local service_name
  if have systemctl; then
    for service_name in cron crond; do
      if systemctl list-unit-files "${service_name}.service" >/dev/null 2>&1 || systemctl status "$service_name" >/dev/null 2>&1; then
        systemctl enable "$service_name" >/dev/null 2>&1 || true
        if ! systemctl is-active --quiet "$service_name"; then
          systemctl restart "$service_name" >/dev/null 2>&1 || systemctl start "$service_name" >/dev/null 2>&1 || continue
        fi
        systemctl is-active --quiet "$service_name" && return 0
      fi
    done
  elif have service; then
    for service_name in cron crond; do
      service "$service_name" status >/dev/null 2>&1 && return 0
      service "$service_name" start >/dev/null 2>&1 && return 0
    done
  fi
  return 1
}

install_self() {
  require_root
  load_config
  local src src_dir
  src="$(script_self)"
  src_dir="$(current_source_dir)" || src_dir=""
  if [[ -n "$src_dir" && -e "$src_dir/.git" ]]; then
    UPDATE_REPO_DIR="$src_dir"
    save_config
  fi
  if [[ "$src" != "$INSTALL_PATH" ]]; then
    install -m 700 "$src" "$INSTALL_PATH"
    log "Script installed to: $INSTALL_PATH"
  else
    chmod 700 "$INSTALL_PATH" 2>/dev/null || true
  fi
  if have ln; then
    ln -sfn "$INSTALL_PATH" "$SHORT_INSTALL_PATH"
  else
    install -m 700 "$INSTALL_PATH" "$SHORT_INSTALL_PATH"
  fi
  log "Short commands installed: ${APP_NAME}, ${SHORT_APP_NAME}"
}

install_cli() {
  install_self
}

update_self() {
  require_root
  load_config
  have git || die "git not found; run: $SHORT_APP_NAME install-deps, or install git manually"

  local repo_dir script_path
  repo_dir="$(find_update_repo_dir)" || die "Source repository path not found; enter the DriveGuard repository and run: git pull && bash driveguard.sh install"
  script_path="${repo_dir}/driveguard.sh"
  [[ -f "$script_path" ]] || die "Script not found in source repository: $script_path"

  log "Updating source repository: $repo_dir"
  git -C "$repo_dir" pull --ff-only

  [[ -f "$script_path" ]] || die "Script not found after update: $script_path"
  UPDATE_REPO_DIR="$repo_dir"
  save_config
  bash "$script_path" install
  log "Script updated to the latest version"
}

check_rclone_remote() {
  load_config
  have rclone || die "rclone not found; install dependencies first"
  if ! rclone listremotes | grep -qx "${RCLONE_REMOTE}:"; then
    die "rclone remote does not exist: ${RCLONE_REMOTE}:; configure the cloud remote first"
  fi
  if rclone lsd "${RCLONE_REMOTE}:" >/dev/null 2>>"$RCLONE_LOG_FILE"; then
    log "rclone remote connection OK: ${RCLONE_REMOTE}:"
  else
    die "rclone remote connection failed; reauthorize or check: $RCLONE_LOG_FILE"
  fi
}

configure_rclone_remote() {
  require_root
  load_config
  ensure_dirs
  have rclone || die "rclone not found; install dependencies first"

  printf '\nrclone cloud remote setup notes:\n'
  printf '1. The script will open rclone config.\n'
  printf '2. For a new remote, suggested name: %s, or use an existing remote name.\n' "$RCLONE_REMOTE"
  printf '3. Choose your target storage, such as Google Drive, OneDrive, S3, WebDAV, or SFTP.\n'
  printf '4. If browser authorization is required, authorize on your local computer and paste the token back here.\n\n'

  if rclone listremotes | grep -qx "${RCLONE_REMOTE}:"; then
    if confirm "Detected ${RCLONE_REMOTE}: already exists. Try reconnecting first"; then
      rclone config reconnect "${RCLONE_REMOTE}:"
    else
      rclone config
    fi
  else
    rclone config
  fi

  local new_remote
  read -r -p "Enter the rclone remote name for this script [${RCLONE_REMOTE}]: " new_remote
  if [[ -n "$new_remote" ]]; then
    RCLONE_REMOTE="$new_remote"
    save_config
  fi
  check_rclone_remote
}

configure_quick_cloud_remote() {
  require_root
  load_config
  ensure_dirs
  have rclone || die "rclone not found; install dependencies first"

  local provider="${1:-}"
  local backend remote label
  case "${provider,,}" in
    google|gdrive|google-drive|drive)
      backend="drive"
      remote="gdrive"
      label="Google Drive"
      ;;
    onedrive|one-drive|microsoft|microsoft-onedrive)
      backend="onedrive"
      remote="onedrive"
      label="Microsoft OneDrive"
      ;;
    *)
      die "Unknown cloud provider: ${provider}. Use google or onedrive."
      ;;
  esac

  printf '\n%s quick authorization\n' "$label"
  printf '1. DriveGuard will create or reconnect the rclone remote: %s:\n' "$remote"
  printf '2. Open the OAuth link shown by rclone in your browser.\n'
  printf '3. Paste the returned token or URL when prompted.\n\n'

  local input
  read -r -p "Remote name [${remote}]: " input
  if [[ -n "$input" ]]; then
    remote="$input"
  fi

  if rclone listremotes | grep -qx "${remote}:"; then
    if confirm "Detected ${remote}: already exists. Reconnect it now"; then
      rclone config reconnect "${remote}:"
    else
      printf 'Keeping existing remote: %s:\n' "$remote"
    fi
  else
    rclone config create "$remote" "$backend" config_is_local=false
  fi

  RCLONE_REMOTE="$remote"
  save_config
  check_rclone_remote
}

configure_cloud_auth() {
  local provider="${1:-}"
  if [[ -n "$provider" ]]; then
    configure_quick_cloud_remote "$provider"
    return
  fi

  printf '\nCloud authorization\n'
  printf '1. Google Drive\n'
  printf '2. Microsoft OneDrive\n'
  printf '3. Advanced rclone config\n'
  read -r -p "Choose provider [1]: " provider

  case "${provider:-1}" in
    1|google|gdrive|google-drive) configure_quick_cloud_remote google ;;
    2|onedrive|one-drive|microsoft) configure_quick_cloud_remote onedrive ;;
    3|advanced|rclone) configure_rclone_remote ;;
    *) die "Invalid provider choice" ;;
  esac
}

set_archive_password() {
  require_root
  load_config
  ensure_dirs
  local pass1 pass2
  read -r -s -p "Enter backup encryption password: " pass1
  printf '\n'
  read -r -s -p "Enter backup encryption password again: " pass2
  printf '\n'
  [[ -n "$pass1" ]] || die "Password cannot be empty"
  [[ "$pass1" == "$pass2" ]] || die "Passwords do not match"
  umask 077
  printf '%s' "$pass1" > "$ARCHIVE_PASSWORD_FILE"
  chmod 600 "$ARCHIVE_PASSWORD_FILE"
  log "Backup encryption password saved to: $ARCHIVE_PASSWORD_FILE"
}

configure_mysql_auth() {
  require_root
  load_config
  ensure_dirs
  local mysql_user mysql_pass
  read -r -p "MySQL user [root]: " mysql_user
  mysql_user="${mysql_user:-root}"
  read -r -s -p "MySQL password: " mysql_pass
  printf '\n'

  [[ -n "$mysql_pass" ]] || die "MySQL Password cannot be empty"
  umask 077
  {
    printf '[client]\n'
    printf 'user=%s\n' "$mysql_user"
    printf 'password=%s\n' "$mysql_pass"
  } > "$MYSQL_DEFAULTS_FILE"
  chmod 600 "$MYSQL_DEFAULTS_FILE"
  log "MySQL connection config saved to: $MYSQL_DEFAULTS_FILE"
}

configure_postgres_auth() {
  require_root
  load_config
  ensure_dirs
  local pg_user pg_pass
  read -r -p "PostgreSQL user [${POSTGRES_USER}]: " pg_user
  POSTGRES_USER="${pg_user:-$POSTGRES_USER}"
  read -r -s -p "PostgreSQL password: " pg_pass
  printf '\n'

  [[ -n "$pg_pass" ]] || die "PostgreSQL Password cannot be empty"
  umask 077
  printf '%s:%s:*:%s:%s\n' \
    "$(pgpass_escape "$POSTGRES_HOST")" \
    "$(pgpass_escape "$POSTGRES_PORT")" \
    "$(pgpass_escape "$POSTGRES_USER")" \
    "$(pgpass_escape "$pg_pass")" > "$POSTGRES_PASSFILE"
  chmod 600 "$POSTGRES_PASSFILE"
  POSTGRES_ENABLED=1
  save_config
  log "PostgreSQL password saved to: $POSTGRES_PASSFILE"
}

configure_general() {
  require_root
  load_config
  ensure_dirs

  local input
  read -r -p "rclone remote name [${RCLONE_REMOTE}]: " input
  [[ -n "$input" ]] && RCLONE_REMOTE="$input"

  read -r -p "Remote directory [${RCLONE_REMOTE_PATH}]: " input
  [[ -n "$input" ]] && RCLONE_REMOTE_PATH="${input#/}"
  RCLONE_REMOTE_PATH="${RCLONE_REMOTE_PATH%/}"

  read -r -p "Retention copies per site/database [${KEEP_COPIES}]: " input
  if [[ -n "$input" ]]; then
    valid_positive_int "$input" || die "Retention copies must be a positive integer"
    KEEP_COPIES="$input"
  fi

  read -r -p "Local backup staging directory [${BACKUP_ROOT}]: " input
  [[ -n "$input" ]] && BACKUP_ROOT="$input"

  read -r -p "Cron expression [${CRON_EXPR}]: " input
  [[ -n "$input" ]] && CRON_EXPR="$input"

  read -r -p "MySQL host [${MYSQL_HOST}]: " input
  [[ -n "$input" ]] && MYSQL_HOST="$input"

  read -r -p "MySQL port [${MYSQL_PORT}]: " input
  [[ -n "$input" ]] && MYSQL_PORT="$input"

  read -r -p "MySQL socket; leave blank to use host/port [${MYSQL_SOCKET}]: " input
  MYSQL_SOCKET="$input"

  read -r -p "PostgreSQL backup, auto=auto-detect 1=enable 0=disable [${POSTGRES_ENABLED}]: " input
  if [[ -n "$input" ]]; then
    [[ "$input" == "auto" || "$input" == "0" || "$input" == "1" ]] || die "PostgreSQL backup must be auto, 0, or 1"
    POSTGRES_ENABLED="$input"
  fi

  if postgres_backup_enabled; then
    read -r -p "PostgreSQL host [${POSTGRES_HOST}]: " input
    [[ -n "$input" ]] && POSTGRES_HOST="$input"

    read -r -p "PostgreSQL port [${POSTGRES_PORT}]: " input
    [[ -n "$input" ]] && POSTGRES_PORT="$input"

    read -r -p "PostgreSQL user [${POSTGRES_USER}]: " input
    [[ -n "$input" ]] && POSTGRES_USER="$input"

    read -r -p "PostgreSQL connection database [${POSTGRES_DEFAULT_DB}]: " input
    [[ -n "$input" ]] && POSTGRES_DEFAULT_DB="$input"
  fi

  save_config

  if confirm "Set backup encryption password now"; then
    set_archive_password
  fi
  if confirm "Set MySQL connection now"; then
    configure_mysql_auth
  fi
  if postgres_backup_enabled && confirm "Set PostgreSQL password now"; then
    configure_postgres_auth
  fi

  save_config
  log "Base configuration saved: $CONFIG_FILE"
}

list_file_numbered() {
  local file="$1"
  if [[ -s "$file" ]]; then
    nl -ba "$file"
  else
    printf 'No entries configured\n'
  fi
}

delete_list_line() {
  local file="$1"
  local line_no
  list_file_numbered "$file"
  read -r -p "Enter the line number to delete: " line_no
  [[ "$line_no" =~ ^[0-9]+$ ]] || die "Line number must be numeric"
  sed -i.bak "${line_no}d" "$file"
  rm -f "${file}.bak"
}

add_site_entry() {
  local name path excludes tmp
  read -r -p "Site name: " name
  read -r -p "Site directory, e.g. /www/wwwroot/example.com: " path
  read -r -p "Excludes, comma-separated, e.g. .git,cache,logs [optional]: " excludes
  [[ -n "$name" && -n "$path" ]] || die "Site name and directory cannot be empty"
  tmp="$(mktemp)"
  awk -F'|' -v site_name="$name" '$1 != site_name' "$SITES_FILE" > "$tmp" 2>/dev/null || true
  printf '%s|%s|%s\n' "$name" "$path" "$excludes" >> "$tmp"
  mv "$tmp" "$SITES_FILE"
  chmod 600 "$SITES_FILE"
  log "Added/updated site: $name"
}

add_database_entry() {
  local file="$1"
  local label="$2"
  local name tmp
  read -r -p "Database name: " name
  [[ -n "$name" ]] || die "Database name cannot be empty"
  tmp="$(mktemp)"
  grep -v -Fx "$name" "$file" > "$tmp" 2>/dev/null || true
  printf '%s\n' "$name" >> "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
  log "Added/updated ${label} database: $name"
}

manage_sites_menu() {
  require_root
  load_config
  ensure_dirs
  while true; do
    printf '\nWebsite backup list:\n'
    list_file_numbered "$SITES_FILE"
    printf '\n1. Add/update website\n2. Delete website\n0. Back\n'
    local choice
    read -r -p "Choose: " choice
    case "$choice" in
      1) add_site_entry ;;
      2) delete_list_line "$SITES_FILE" ;;
      0) return 0 ;;
      *) printf 'Invalid choice\n' ;;
    esac
  done
}

manage_databases_menu() {
  require_root
  load_config
  ensure_dirs
  while true; do
    printf '\nMySQL/MariaDB database backup list:\n'
    list_file_numbered "$DATABASES_FILE"
    printf '\nPostgreSQL database backup list:\n'
    list_file_numbered "$POSTGRES_DATABASES_FILE"
    printf '\n1. Add/update MySQL/MariaDB database\n'
    printf '2. Delete MySQL/MariaDB database\n'
    printf '3. Add/update PostgreSQL database\n'
    printf '4. Delete PostgreSQL database\n'
    printf '0. Back\n'
    local choice
    read -r -p "Choose: " choice
    case "$choice" in
      1) add_database_entry "$DATABASES_FILE" "MySQL/MariaDB" ;;
      2) delete_list_line "$DATABASES_FILE" ;;
      3) add_database_entry "$POSTGRES_DATABASES_FILE" "PostgreSQL" ;;
      4) delete_list_line "$POSTGRES_DATABASES_FILE" ;;
      0) return 0 ;;
      *) printf 'Invalid choice\n' ;;
    esac
  done
}

find_mysqldump_bin() {
  local candidate
  for candidate in "$MYSQLDUMP_BIN" mysqldump mariadb-dump; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == */* && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [[ "$candidate" != */* ]] && have "$candidate"; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

mysqldump_supports_no_tablespaces() {
  local dump_bin="$1"
  "$dump_bin" --help 2>/dev/null | grep -q -- '--no-tablespaces'
}

find_mysql_client_bin() {
  local candidate
  for candidate in "$MYSQL_BIN" mysql mariadb; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == */* && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [[ "$candidate" != */* ]] && have "$candidate"; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

find_pg_dump_bin() {
  local candidate
  for candidate in "$PGDUMP_BIN" pg_dump; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == */* && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [[ "$candidate" != */* ]] && have "$candidate"; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

find_psql_bin() {
  local candidate
  for candidate in "$PSQL_BIN" psql; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == */* && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [[ "$candidate" != */* ]] && have "$candidate"; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

postgres_detected() {
  if have pg_isready && pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -q >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$POSTGRES_HOST" == "localhost" || "$POSTGRES_HOST" == "127.0.0.1" || "$POSTGRES_HOST" == "::1" ]]; then
    [[ -S "/var/run/postgresql/.s.PGSQL.${POSTGRES_PORT}" || -S "/tmp/.s.PGSQL.${POSTGRES_PORT}" ]] && return 0
  fi
  return 1
}

postgres_backup_enabled() {
  case "$POSTGRES_ENABLED" in
    1|yes|true|on) return 0 ;;
    0|no|false|off) return 1 ;;
    auto|"") postgres_detected ;;
    *) return 1 ;;
  esac
}

postgres_status_label() {
  case "$POSTGRES_ENABLED" in
    auto|"")
      if postgres_detected; then
        printf 'auto (detected)'
      else
        printf 'auto (not detected)'
      fi
      ;;
    1|yes|true|on) printf '1 (enabled)' ;;
    0|no|false|off) printf '0 (disabled)' ;;
    *) printf '%s' "$POSTGRES_ENABLED" ;;
  esac
}

discover_sites() {
  local root child found name
  for root in $SITE_ROOTS; do
    [[ -d "$root" ]] || continue
    if [[ -e "$root/index.html" || -e "$root/index.htm" || -e "$root/index.php" || -e "$root/.htaccess" ]]; then
      name="$(basename "$root")"
      printf '%s|%s|\n' "$name" "$root"
      continue
    fi
    found=0
    while IFS= read -r child; do
      found=1
      name="$(basename "$child")"
      printf '%s|%s|\n' "$name" "$child"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
    if [[ "$found" -eq 0 ]]; then
      name="$(basename "$root")"
      printf '%s|%s|\n' "$name" "$root"
    fi
  done
}

discover_databases() {
  [[ -s "$MYSQL_DEFAULTS_FILE" ]] || return 0
  local client_bin output
  client_bin="$(find_mysql_client_bin)" || {
    log "mysql/mariadb client not found; cannot auto-discover databases"
    return 0
  }

  local mysql_cmd=("$client_bin" "--defaults-extra-file=$MYSQL_DEFAULTS_FILE" "-N" "-B")
  if [[ -n "$MYSQL_SOCKET" ]]; then
    mysql_cmd+=("--socket=$MYSQL_SOCKET")
  else
    mysql_cmd+=("--host=$MYSQL_HOST" "--port=$MYSQL_PORT")
  fi
  mysql_cmd+=("-e" "show databases;")

  if ! output="$("${mysql_cmd[@]}" 2>>"$LOG_FILE")"; then
    log "Database auto-discovery failed; check MySQL connection info: $MYSQL_DEFAULTS_FILE"
    return 0
  fi
  printf '%s\n' "$output" \
    | grep -Ev '^(information_schema|mysql|performance_schema|sys)$' \
    | sed '/^[[:space:]]*$/d' || true
}

discover_postgres_databases() {
  postgres_backup_enabled || return 0
  [[ -s "$POSTGRES_PASSFILE" ]] || return 0
  local psql_bin output
  psql_bin="$(find_psql_bin)" || {
    log "psql not found; cannot auto-discover PostgreSQL databases"
    return 0
  }

  local query="select datname from pg_database where datallowconn and not datistemplate and datname <> 'postgres' order by datname;"
  local psql_cmd=("$psql_bin" "-h" "$POSTGRES_HOST" "-p" "$POSTGRES_PORT" "-U" "$POSTGRES_USER" "-d" "$POSTGRES_DEFAULT_DB" "-At" "-c" "$query")

  if ! output="$(PGPASSFILE="$POSTGRES_PASSFILE" "${psql_cmd[@]}" 2>>"$LOG_FILE")"; then
    log "PostgreSQL auto-discovery failed; check connection info: $POSTGRES_PASSFILE"
    return 0
  fi
  printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' || true
}

remote_dir_for() {
  local subdir="$1"
  local base="${RCLONE_REMOTE_PATH#/}"
  base="${base%/}"
  subdir="${subdir#/}"
  subdir="${subdir%/}"
  if [[ -n "$base" && -n "$subdir" ]]; then
    printf '%s:%s/%s\n' "$RCLONE_REMOTE" "$base" "$subdir"
  elif [[ -n "$base" ]]; then
    printf '%s:%s\n' "$RCLONE_REMOTE" "$base"
  else
    printf '%s:%s\n' "$RCLONE_REMOTE" "$subdir"
  fi
}

encrypt_file() {
  local src="$1"
  local dest="$2"
  [[ -s "$ARCHIVE_PASSWORD_FILE" ]] || die "Backup encryption password is not set; configure it first"
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
    -in "$src" -out "$dest" -pass "file:${ARCHIVE_PASSWORD_FILE}" >/dev/null
  chmod 600 "$dest"
}

decrypt_backup_file() {
  require_root
  load_config
  local src="${1:-}"
  local dest="${2:-}"
  [[ -n "$src" && -n "$dest" ]] || die "Usage: $0 decrypt source.enc output"
  [[ -s "$ARCHIVE_PASSWORD_FILE" ]] || die "Password file not found: $ARCHIVE_PASSWORD_FILE"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
    -in "$src" -out "$dest" -pass "file:${ARCHIVE_PASSWORD_FILE}"
  log "Decrypted: $dest"
}

prune_local_dir() {
  local dir="$1"
  local keep="$2"
  valid_positive_int "$keep" || return 0
  [[ -d "$dir" ]] || return 0
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name '*.enc' -printf '%f\n' | sort -r)
  local i
  for ((i = keep; i < ${#files[@]}; i++)); do
    rm -f -- "$dir/${files[$i]}"
    log "Pruned old local backup: $dir/${files[$i]}"
  done
}

prune_remote_dir() {
  local remote_dir="$1"
  local keep="$2"
  valid_positive_int "$keep" || return 0
  mapfile -t files < <(rclone lsf "$remote_dir" --files-only 2>>"$RCLONE_LOG_FILE" | grep -E '\.enc$' | sort -r || true)
  local i
  for ((i = keep; i < ${#files[@]}; i++)); do
    [[ -n "${files[$i]}" ]] || continue
    if rclone deletefile "${remote_dir}/${files[$i]}" >>"$RCLONE_LOG_FILE" 2>&1; then
      log "Pruned old remote backup: ${remote_dir}/${files[$i]}"
    fi
  done
}

prepare_remote_layout() {
  local base display_base remote_root remote_site remote_database
  base="${RCLONE_REMOTE_PATH#/}"
  base="${base%/}"
  display_base="${base:-}"
  remote_site="$(remote_dir_for "site")"
  remote_database="$(remote_dir_for "database")"

  check_rclone_remote
  if [[ -n "$base" ]]; then
    remote_root="$(remote_dir_for "")"
    rclone mkdir "$remote_root" >>"$RCLONE_LOG_FILE" 2>&1
  fi
  rclone mkdir "$remote_site" >>"$RCLONE_LOG_FILE" 2>&1
  rclone mkdir "$remote_database" >>"$RCLONE_LOG_FILE" 2>&1
  if [[ -n "$display_base" ]]; then
    log "Remote backup folders ready: ${RCLONE_REMOTE}:${display_base}/site and ${RCLONE_REMOTE}:${display_base}/database"
  else
    log "Remote backup folders ready: ${RCLONE_REMOTE}:site and ${RCLONE_REMOTE}:database"
  fi
}

prepare_remote_command() {
  require_root
  load_config
  ensure_dirs
  prepare_remote_layout
}

upload_and_prune() {
  local local_file="$1"
  local subdir="$2"
  local remote_dir
  remote_dir="$(remote_dir_for "$subdir")"
  check_rclone_remote
  rclone mkdir "$remote_dir" >>"$RCLONE_LOG_FILE" 2>&1
  rclone copy "$local_file" "$remote_dir" \
    --transfers 1 --checkers 4 --drive-chunk-size "$RCLONE_CHUNK_SIZE" \
    --log-file "$RCLONE_LOG_FILE" --log-level INFO
  prune_remote_dir "$remote_dir" "$KEEP_COPIES"
}

backup_site() {
  local name="$1"
  local path="$2"
  local excludes="${3:-}"
  local safe_name ts dest_dir tmp_file final_file parent base exclude
  local -a tar_args exclude_items
  [[ -d "$path" ]] || die "Site directory does not exist: $name -> $path"

  safe_name="$(sanitize_name "$name")"
  ts="$(date '+%Y%m%d_%H%M%S')"
  dest_dir="$BACKUP_ROOT/site/$safe_name"
  mkdir -p "$dest_dir"
  tmp_file="${dest_dir}/Web_${safe_name}_${ts}.tar.gz"
  final_file="${tmp_file}.enc"
  parent="$(dirname "$path")"
  base="$(basename "$path")"

  log "Backing up website: $name"
  tar_args=(-czf "$tmp_file" -C "$parent")
  if [[ -n "$excludes" ]]; then
    IFS=',' read -r -a exclude_items <<< "$excludes"
    for exclude in "${exclude_items[@]}"; do
      exclude="${exclude#"${exclude%%[![:space:]]*}"}"
      exclude="${exclude%"${exclude##*[![:space:]]}"}"
      [[ -n "$exclude" ]] && tar_args+=(--exclude="${base}/${exclude}")
    done
  fi
  tar_args+=("$base")
  tar "${tar_args[@]}"
  encrypt_file "$tmp_file" "$final_file"
  rm -f -- "$tmp_file"
  upload_and_prune "$final_file" "site/$safe_name"
  prune_local_dir "$dest_dir" "$KEEP_COPIES"
  log "Website backup complete: $name -> $final_file"
}

backup_database() {
  local db_name="$1"
  local safe_name ts dest_dir tmp_file final_file dump_bin
  [[ -s "$MYSQL_DEFAULTS_FILE" ]] || die "MySQL connection info is not configured; set it in the menu first"
  dump_bin="$(find_mysqldump_bin)" || die "mysqldump/mariadb-dump not found"

  safe_name="$(sanitize_name "$db_name")"
  ts="$(date '+%Y%m%d_%H%M%S')"
  dest_dir="$BACKUP_ROOT/database/$safe_name"
  mkdir -p "$dest_dir"
  tmp_file="${dest_dir}/Db_${safe_name}_${ts}.sql.gz"
  final_file="${tmp_file}.enc"

  local dump_cmd=("$dump_bin" "--defaults-extra-file=$MYSQL_DEFAULTS_FILE")
  if [[ -n "$MYSQL_SOCKET" ]]; then
    dump_cmd+=("--socket=$MYSQL_SOCKET")
  else
    dump_cmd+=("--host=$MYSQL_HOST" "--port=$MYSQL_PORT")
  fi
  dump_cmd+=(--single-transaction --quick --routines --events --triggers --hex-blob)
  if mysqldump_supports_no_tablespaces "$dump_bin"; then
    dump_cmd+=(--no-tablespaces)
  fi
  dump_cmd+=(--databases "$db_name")

  log "Backing up MySQL/MariaDB database: $db_name"
  "${dump_cmd[@]}" | gzip -9 > "$tmp_file"
  encrypt_file "$tmp_file" "$final_file"
  rm -f -- "$tmp_file"
  upload_and_prune "$final_file" "database/$safe_name"
  prune_local_dir "$dest_dir" "$KEEP_COPIES"
  log "MySQL/MariaDB database backup complete: $db_name -> $final_file"
}

backup_postgres_database() {
  local db_name="$1"
  local safe_name ts dest_dir tmp_file final_file dump_bin
  postgres_backup_enabled || die "PostgreSQL backup is disabled or PostgreSQL was not detected; configure it first"
  [[ -s "$POSTGRES_PASSFILE" ]] || die "PostgreSQL password is not configured; set it in the menu first"
  dump_bin="$(find_pg_dump_bin)" || die "pg_dump not found"

  safe_name="$(sanitize_name "$db_name")"
  ts="$(date '+%Y%m%d_%H%M%S')"
  dest_dir="$BACKUP_ROOT/database/postgresql/$safe_name"
  mkdir -p "$dest_dir"
  tmp_file="${dest_dir}/Pg_${safe_name}_${ts}.sql.gz"
  final_file="${tmp_file}.enc"

  local dump_cmd=("$dump_bin" "-h" "$POSTGRES_HOST" "-p" "$POSTGRES_PORT" "-U" "$POSTGRES_USER" "--format=plain" "--no-owner" "--no-privileges" "$db_name")

  log "Backing up PostgreSQL database: $db_name"
  PGPASSFILE="$POSTGRES_PASSFILE" "${dump_cmd[@]}" | gzip -9 > "$tmp_file"
  encrypt_file "$tmp_file" "$final_file"
  rm -f -- "$tmp_file"
  upload_and_prune "$final_file" "database/postgresql/$safe_name"
  prune_local_dir "$dest_dir" "$KEEP_COPIES"
  log "PostgreSQL database backup complete: $db_name -> $final_file"
}

backup_all() {
  require_root
  load_config
  ensure_dirs
  have flock || die "flock is missing; install util-linux first"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "A backup job is already running; exiting"
    exit 0
  fi

  ensure_cron_service || log "Warning: cron service check failed; verify cron manually"
  prepare_remote_layout

  local site_count=0
  local mysql_count=0
  local postgres_count=0
  local name path excludes db_name site_key
  local -A seen_site_paths=()
  local -A seen_databases=()
  local -A seen_postgres_databases=()

  case "${BACKUP_SCOPE_KIND,,}" in
    full|"")
      ;;
    website|site)
      [[ -n "$BACKUP_SCOPE_NAME" && -n "$BACKUP_SCOPE_LOCATION" ]] || die "BACKUP_SCOPE_NAME and BACKUP_SCOPE_LOCATION are required for website scope"
      backup_site "$BACKUP_SCOPE_NAME" "$BACKUP_SCOPE_LOCATION" "${BACKUP_SCOPE_EXCLUDES:-}"
      log "Backup finished: websites 1, MySQL/MariaDB databases 0, PostgreSQL databases 0, retention ${KEEP_COPIES} copies"
      return 0
      ;;
    mysql|mariadb|database)
      [[ -n "$BACKUP_SCOPE_NAME" ]] || die "BACKUP_SCOPE_NAME is required for MySQL/MariaDB scope"
      backup_database "$BACKUP_SCOPE_NAME"
      log "Backup finished: websites 0, MySQL/MariaDB databases 1, PostgreSQL databases 0, retention ${KEEP_COPIES} copies"
      return 0
      ;;
    postgresql|postgres)
      [[ -n "$BACKUP_SCOPE_NAME" ]] || die "BACKUP_SCOPE_NAME is required for PostgreSQL scope"
      postgres_backup_enabled || die "PostgreSQL backup is disabled"
      backup_postgres_database "$BACKUP_SCOPE_NAME"
      log "Backup finished: websites 0, MySQL/MariaDB databases 0, PostgreSQL databases 1, retention ${KEEP_COPIES} copies"
      return 0
      ;;
    *)
      die "Unsupported BACKUP_SCOPE_KIND: $BACKUP_SCOPE_KIND"
      ;;
  esac

  if [[ -s "$SITES_FILE" ]]; then
    while IFS='|' read -r name path excludes; do
      [[ -z "${name//[[:space:]]/}" || "${name:0:1}" == "#" ]] && continue
      site_key="$path"
      [[ -n "${seen_site_paths[$site_key]+x}" ]] && continue
      seen_site_paths["$site_key"]=1
      backup_site "$name" "$path" "${excludes:-}"
      site_count=$((site_count + 1))
    done < "$SITES_FILE"
  fi

  if [[ "$AUTO_DISCOVER_SITES" == "1" ]]; then
    log "Auto-discovering website directories: $SITE_ROOTS"
    while IFS='|' read -r name path excludes; do
      [[ -n "$name" && -n "$path" ]] || continue
      site_key="$path"
      [[ -n "${seen_site_paths[$site_key]+x}" ]] && continue
      seen_site_paths["$site_key"]=1
      backup_site "$name" "$path" "${excludes:-}"
      site_count=$((site_count + 1))
    done < <(discover_sites)
  fi

  if [[ "$site_count" -eq 0 ]]; then
    log "No websites found for backup; add sites in $SITES_FILE or configure SITE_ROOTS"
  fi

  if [[ -s "$DATABASES_FILE" ]]; then
    while IFS= read -r db_name; do
      [[ -z "${db_name//[[:space:]]/}" || "${db_name:0:1}" == "#" ]] && continue
      [[ -n "${seen_databases[$db_name]+x}" ]] && continue
      seen_databases["$db_name"]=1
      backup_database "$db_name"
      mysql_count=$((mysql_count + 1))
    done < "$DATABASES_FILE"
  fi

  if [[ "$AUTO_DISCOVER_DATABASES" == "1" ]]; then
    log "Auto-discovering MySQL/MariaDB databases"
    while IFS= read -r db_name; do
      [[ -z "${db_name//[[:space:]]/}" || "${db_name:0:1}" == "#" ]] && continue
      [[ -n "${seen_databases[$db_name]+x}" ]] && continue
      seen_databases["$db_name"]=1
      backup_database "$db_name"
      mysql_count=$((mysql_count + 1))
    done < <(discover_databases)
  fi

  if postgres_backup_enabled && [[ ! -s "$POSTGRES_PASSFILE" ]]; then
    log "PostgreSQL was detected or enabled, but no password is configured; skipping PostgreSQL backup. Run dg configure."
  elif postgres_backup_enabled; then
    if [[ -s "$POSTGRES_DATABASES_FILE" ]]; then
      while IFS= read -r db_name; do
        [[ -z "${db_name//[[:space:]]/}" || "${db_name:0:1}" == "#" ]] && continue
        [[ -n "${seen_postgres_databases[$db_name]+x}" ]] && continue
        seen_postgres_databases["$db_name"]=1
        backup_postgres_database "$db_name"
        postgres_count=$((postgres_count + 1))
      done < "$POSTGRES_DATABASES_FILE"
    fi

    if [[ "$AUTO_DISCOVER_DATABASES" == "1" ]]; then
      log "Auto-discovering PostgreSQL databases"
      while IFS= read -r db_name; do
        [[ -z "${db_name//[[:space:]]/}" || "${db_name:0:1}" == "#" ]] && continue
        [[ -n "${seen_postgres_databases[$db_name]+x}" ]] && continue
        seen_postgres_databases["$db_name"]=1
        backup_postgres_database "$db_name"
        postgres_count=$((postgres_count + 1))
      done < <(discover_postgres_databases)
    fi
  elif [[ -s "$POSTGRES_DATABASES_FILE" ]]; then
    log "PostgreSQL backup is disabled; skipped: $POSTGRES_DATABASES_FILE"
  fi

  if [[ "$mysql_count" -eq 0 && "$postgres_count" -eq 0 ]]; then
    log "No databases found for backup; add databases in $DATABASES_FILE or $POSTGRES_DATABASES_FILE, or check connection info"
  fi

  log "Backup finished: websites ${site_count}, MySQL/MariaDB databases ${mysql_count}, PostgreSQL databases ${postgres_count}, retention ${KEEP_COPIES} copies"
}

install_cron_entries() {
  require_root
  load_config
  ensure_dirs
  install_self
  valid_positive_int "$KEEP_COPIES" || die "KEEP_COPIES must be a positive integer"

  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null \
    | sed -e "/${CRON_MARKER_BEGIN}/,/${CRON_MARKER_END}/d" > "$tmp" || true
  {
    printf '%s\n' "$CRON_MARKER_BEGIN"
    printf 'SHELL=/bin/bash\n'
    printf 'PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n'
    printf '%s %s backup >> %s/cron.log 2>&1\n' "$CRON_EXPR" "$INSTALL_PATH" "$LOG_DIR"
    printf '%s\n' "$CRON_MARKER_END"
  } >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  ensure_cron_service || die "Cron entries were written, but the cron service failed to start"
  log "Cron job installed: $CRON_EXPR"
}

guard_cron() {
  require_root
  load_config
  ensure_dirs
  ensure_cron_service || die "cron service guard failed"
  if [[ "$ENABLE_CRON_GUARD" == "1" ]]; then
    if ! crontab -l 2>/dev/null | grep -Fq "$CRON_MARKER_BEGIN"; then
      install_cron_entries
    fi
  fi
  log "cron guard check complete"
}

install_systemd_guard() {
  require_root
  load_config
  ensure_dirs
  install_self
  have systemctl || die "systemctl not found; cannot install systemd guard"
  [[ -d /run/systemd/system ]] || die "Current environment does not look like a running systemd environment"

  cat > /etc/systemd/system/${APP_NAME}-cron-guard.service <<EOF
[Unit]
Description=${APP_NAME} cron guard

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} guard-cron
EOF

  cat > /etc/systemd/system/${APP_NAME}-cron-guard.timer <<EOF
[Unit]
Description=Run ${APP_NAME} cron guard periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${APP_NAME}-cron-guard.timer"
  log "cron guard timer installed: ${APP_NAME}-cron-guard.timer"
}

remove_cron_entries() {
  if ! have crontab; then
    log "crontab not found; skipping cron cleanup"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null \
    | sed -e "/${CRON_MARKER_BEGIN}/,/${CRON_MARKER_END}/d" > "$tmp" || true
  crontab "$tmp"
  rm -f "$tmp"
  log "Removed cron jobs"
}

remove_systemd_guard() {
  if ! have systemctl; then
    log "systemctl not found; skipping systemd guard cleanup"
    return 0
  fi

  systemctl disable --now "${APP_NAME}-cron-guard.timer" >/dev/null 2>&1 || true
  systemctl stop "${APP_NAME}-cron-guard.service" >/dev/null 2>&1 || true
  rm -f \
    "/etc/systemd/system/${APP_NAME}-cron-guard.service" \
    "/etc/systemd/system/${APP_NAME}-cron-guard.timer"
  systemctl daemon-reload >/dev/null 2>&1 || true
  log "Removed systemd cron guard"
}

remove_path_if_confirmed() {
  local label="$1"
  local target="$2"
  local resolved
  [[ -n "$target" && -e "$target" ]] || return 0
  resolved="$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")"
  case "$resolved" in
    /|/etc|/var|/usr|/usr/local|/var/log|/var/lib|/var/backups|/root|/home)
      log "Refusing to delete dangerous path: $resolved"
      return 0
      ;;
  esac

  if confirm "Delete ${label}: ${target}"; then
    rm -rf -- "$target"
    log "Deleted ${label}: $target"
  else
    log "Kept ${label}: $target"
  fi
}

uninstall_app() {
  require_root
  load_config

  printf '\nUninstall notes:\n'
  printf '  - Removes cron jobs installed by this script.\n'
  printf '  - Removes the systemd cron guard installed by this script.\n'
  printf '  - Does not delete backups already uploaded to remote storage.\n'
  printf '  - Asks before removing config, secrets, logs, and local backup directories.\n\n'
  confirm "Confirm uninstall ${DISPLAY_NAME}" || return 0

  remove_cron_entries
  remove_systemd_guard

  remove_path_if_confirmed "config and secret directory" "$CONFIG_DIR"
  remove_path_if_confirmed "local backup staging directory" "$BACKUP_ROOT"
  remove_path_if_confirmed "state directory" "$STATE_DIR"
  remove_path_if_confirmed "log directory" "$LOG_DIR"
  local current_script
  current_script="$(script_self)"
  if [[ -e "$INSTALL_PATH" ]]; then
    rm -f -- "$INSTALL_PATH"
    log "Deleted installed script: $INSTALL_PATH"
  fi
  if [[ -L "$SHORT_INSTALL_PATH" || -e "$SHORT_INSTALL_PATH" ]]; then
    rm -f -- "$SHORT_INSTALL_PATH"
    log "Deleted short command: $SHORT_INSTALL_PATH"
  fi
  if [[ "$current_script" != "$INSTALL_PATH" ]]; then
    log "Current running script was not deleted: $current_script"
  fi
  log "Uninstall complete"
}

show_logs() {
  load_config
  ensure_dirs
  local lines="${1:-80}"
  printf '\nMain log: %s\n' "$LOG_FILE"
  tail -n "$lines" "$LOG_FILE" 2>/dev/null || true
  printf '\nrclone log: %s\n' "$RCLONE_LOG_FILE"
  tail -n 40 "$RCLONE_LOG_FILE" 2>/dev/null || true
}

print_status() {
  load_config
  ensure_dirs
  printf '\nCurrent configuration:\n'
  printf '  Config file: %s\n' "$CONFIG_FILE"
  printf '  Update repository: %s\n' "${UPDATE_REPO_DIR:-not recorded}"
  printf '  rclone remote: %s:\n' "$RCLONE_REMOTE"
  printf '  Remote directory: %s\n' "${RCLONE_REMOTE_PATH:-/}"
  printf '  Local directory: %s\n' "$BACKUP_ROOT"
  printf '  Retention copies: %s\n' "$KEEP_COPIES"
  if [[ "${BACKUP_SCOPE_KIND:-full}" != "full" ]]; then
    printf '  Backup scope: %s %s\n' "$BACKUP_SCOPE_KIND" "$BACKUP_SCOPE_NAME"
  else
    printf '  Backup scope: full\n'
  fi
  printf '  Auto-discover websites: %s\n' "$AUTO_DISCOVER_SITES"
  printf '  Website roots: %s\n' "$SITE_ROOTS"
  printf '  Auto-discover databases: %s\n' "$AUTO_DISCOVER_DATABASES"
  printf '  PostgreSQL backup: %s\n' "$(postgres_status_label)"
  printf '  Cron schedule: %s\n' "$CRON_EXPR"
  printf '  Website list: %s\n' "$SITES_FILE"
  printf '  MySQL/MariaDB database list: %s\n' "$DATABASES_FILE"
  printf '  PostgreSQL database list: %s\n' "$POSTGRES_DATABASES_FILE"
  printf '  Password file: %s\n' "$ARCHIVE_PASSWORD_FILE"
  printf '  MySQL config: %s\n' "$MYSQL_DEFAULTS_FILE"
  printf '  PostgreSQL password file: %s\n' "$POSTGRES_PASSFILE"
}

menu() {
  require_root
  load_config
  ensure_dirs
  while true; do
    printf '\n%s management menu\n' "$DISPLAY_NAME"
    printf '1. Install/check dependencies\n'
    printf '2. Configure/check rclone remote\n'
    printf '3. Base configuration and passwords\n'
    printf '4. Manage website backup list\n'
    printf '5. Manage database backup list\n'
    printf '6. Install/update cron jobs\n'
    printf '7. Install cron process guard\n'
    printf '8. Run a backup now\n'
    printf '9. Show logs\n'
    printf '10. Show current configuration\n'
    printf '11. Update DriveGuard script\n'
    printf '12. Uninstall script and scheduled guards\n'
    printf '0. Exit\n'
    local choice
    read -r -p "Choose: " choice
    case "$choice" in
      1) install_dependencies; pause_enter ;;
      2) configure_rclone_remote; pause_enter ;;
      3) configure_general; pause_enter ;;
      4) manage_sites_menu ;;
      5) manage_databases_menu ;;
      6) install_cron_entries; pause_enter ;;
      7) install_systemd_guard; pause_enter ;;
      8) backup_all; pause_enter ;;
      9) show_logs; pause_enter ;;
      10) print_status; pause_enter ;;
      11) update_self; pause_enter ;;
      12) uninstall_app; pause_enter ;;
      0) exit 0 ;;
      *) printf 'Invalid choice\n' ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage:
  $0 menu              Open interactive menu
  $0 install           Install/update driveguard and dg commands
  $0 update            Pull from Git repository and update script
  $0 install-deps      Install Debian/Ubuntu/CentOS/RHEL dependencies
  $0 auth [provider]   Authorize Google Drive/OneDrive, or open provider picker
  $0 configure         Configure base settings, passwords, and MySQL/PostgreSQL connections
  $0 prepare-remote    Create remote root, site, and database folders
  $0 cron              Install/update cron jobs
  $0 install-guard     Install systemd cron guard timer
  $0 guard-cron        Check and start cron service
  $0 backup            Run one backup immediately
  $0 log [lines]        Show logs
  $0 decrypt source.enc output
  $0 uninstall         Uninstall script, cron, and systemd guard

Config file:
  ${CONFIG_FILE}
EOF
}

main() {
  local cmd="${1:-menu}"
  case "$cmd" in
    menu) menu ;;
    install) install_cli ;;
    update) update_self ;;
    install-deps) install_dependencies ;;
    auth) configure_cloud_auth "${2:-}" ;;
    configure) configure_general ;;
    prepare-remote) prepare_remote_command ;;
    cron) install_cron_entries ;;
    install-guard) install_systemd_guard ;;
    guard-cron) guard_cron ;;
    backup) backup_all ;;
    log) show_logs "${2:-80}" ;;
    status) print_status ;;
    decrypt) decrypt_backup_file "${2:-}" "${3:-}" ;;
    uninstall) uninstall_app ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
