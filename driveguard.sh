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
ARCHIVE_PASSWORD_FILE="${ARCHIVE_PASSWORD_FILE:-${CONFIG_DIR}/archive.pass}"
MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-${CONFIG_DIR}/mysql.cnf}"
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
AUTO_DISCOVER_SITES="${AUTO_DISCOVER_SITES:-1}"
AUTO_DISCOVER_DATABASES="${AUTO_DISCOVER_DATABASES:-1}"
SITE_ROOTS="${SITE_ROOTS:-/www/wwwroot /var/www /srv/www /usr/share/nginx/html}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_SOCKET="${MYSQL_SOCKET:-}"
MYSQLDUMP_BIN="${MYSQLDUMP_BIN:-}"
MYSQL_BIN="${MYSQL_BIN:-}"
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
  log "错误：$*"
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "请使用 root 用户运行：sudo bash $0"
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
  ARCHIVE_PASSWORD_FILE="${ARCHIVE_PASSWORD_FILE:-${CONFIG_DIR}/archive.pass}"
  MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-${CONFIG_DIR}/mysql.cnf}"
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
  AUTO_DISCOVER_SITES="${AUTO_DISCOVER_SITES:-1}"
  AUTO_DISCOVER_DATABASES="${AUTO_DISCOVER_DATABASES:-1}"
  SITE_ROOTS="${SITE_ROOTS:-/www/wwwroot /var/www /srv/www /usr/share/nginx/html}"
  MYSQL_HOST="${MYSQL_HOST:-localhost}"
  MYSQL_PORT="${MYSQL_PORT:-3306}"
  MYSQL_SOCKET="${MYSQL_SOCKET:-}"
  MYSQLDUMP_BIN="${MYSQLDUMP_BIN:-}"
  MYSQL_BIN="${MYSQL_BIN:-}"
  CRON_EXPR="${CRON_EXPR:-0 3 * * *}"
  ENABLE_CRON_GUARD="${ENABLE_CRON_GUARD:-1}"
}

ensure_dirs() {
  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" "$BACKUP_ROOT"
  mkdir -p "$BACKUP_ROOT/site" "$BACKUP_ROOT/database" "$BACKUP_ROOT/path"
  touch "$SITES_FILE" "$DATABASES_FILE" "$LOG_FILE" "$RCLONE_LOG_FILE"
  chmod 700 "$CONFIG_DIR" "$STATE_DIR" "$BACKUP_ROOT" 2>/dev/null || true
  chmod 600 "$CONFIG_FILE" "$SITES_FILE" "$DATABASES_FILE" "$LOG_FILE" "$RCLONE_LOG_FILE" 2>/dev/null || true
}

save_config() {
  ensure_dirs
  umask 077
  {
    printf '# %s 配置文件，生成时间：%s\n' "$DISPLAY_NAME" "$(timestamp)"
    for key in \
      SITES_FILE DATABASES_FILE ARCHIVE_PASSWORD_FILE MYSQL_DEFAULTS_FILE \
      STATE_DIR LOG_DIR LOG_FILE RCLONE_LOG_FILE LOCK_FILE \
      UPDATE_REPO_DIR \
      RCLONE_REMOTE RCLONE_REMOTE_PATH RCLONE_CHUNK_SIZE KEEP_COPIES \
      BACKUP_ROOT AUTO_DISCOVER_SITES AUTO_DISCOVER_DATABASES SITE_ROOTS \
      MYSQL_HOST MYSQL_PORT MYSQL_SOCKET MYSQLDUMP_BIN MYSQL_BIN \
      CRON_EXPR ENABLE_CRON_GUARD
    do
      printf '%s=%q\n' "$key" "${!key}"
    done
  } > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

pause_enter() {
  read -r -p "按回车继续..." _
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
    die "当前脚本支持 Debian/Ubuntu/CentOS/RHEL 系，检测到：${PRETTY_NAME:-unknown}"
  fi

  ensure_dirs
  ensure_cron_service || true
  log "依赖检查完成"
}

install_debian_dependencies() {
  have apt-get || die "未找到 apt-get，当前系统不像 Debian/Ubuntu"
  log "开始安装依赖：git、rclone、cron、openssl、MySQL 客户端等"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates cron git rclone openssl tar gzip util-linux
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
    die "未找到 dnf/yum，当前系统不像 CentOS/RHEL"
  fi

  log "开始安装依赖：git、rclone、cronie、openssl、MySQL/MariaDB 客户端等"
  rhel_install_packages "$pkg_mgr" bash ca-certificates cronie git openssl tar gzip util-linux curl unzip mariadb

  if ! have mysqldump && ! have mariadb-dump; then
    rhel_install_packages "$pkg_mgr" mariadb
  fi

  if ! have rclone; then
    if ! rhel_install_packages "$pkg_mgr" rclone; then
      log "系统源未提供 rclone，改用 rclone 官方安装脚本"
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
    log "检测到 cloudflare repo，安装失败后临时禁用该 repo 重试"
    "$pkg_mgr" --disablerepo=cloudflare install -y "$@"
    return $?
  fi
  return 1
}

install_rclone_official() {
  have curl || die "未找到 curl，无法下载 rclone 官方安装脚本"
  local installer
  installer="$(mktemp)"
  if curl -fsSL https://rclone.org/install.sh -o "$installer"; then
    bash "$installer"
    rm -f "$installer"
  else
    rm -f "$installer"
    die "下载 rclone 官方安装脚本失败，请检查网络后重试"
  fi
  have rclone || die "rclone 安装后仍不可用，请手动执行：curl -fsSL https://rclone.org/install.sh | bash"
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
    log "脚本已安装到：$INSTALL_PATH"
  else
    chmod 700 "$INSTALL_PATH" 2>/dev/null || true
  fi
  if have ln; then
    ln -sfn "$INSTALL_PATH" "$SHORT_INSTALL_PATH"
  else
    install -m 700 "$INSTALL_PATH" "$SHORT_INSTALL_PATH"
  fi
  log "短命令已安装：${APP_NAME}、${SHORT_APP_NAME}"
}

install_cli() {
  install_self
}

update_self() {
  require_root
  load_config
  have git || die "未找到 git，请先执行：$SHORT_APP_NAME install-deps，或手动安装 git"

  local repo_dir script_path
  repo_dir="$(find_update_repo_dir)" || die "未找到源码仓库路径，请进入 DriveGuard 仓库执行：git pull && bash driveguard.sh install"
  script_path="${repo_dir}/driveguard.sh"
  [[ -f "$script_path" ]] || die "源码仓库中未找到脚本：$script_path"

  log "开始更新源码仓库：$repo_dir"
  git -C "$repo_dir" pull --ff-only

  [[ -f "$script_path" ]] || die "更新后未找到脚本：$script_path"
  UPDATE_REPO_DIR="$repo_dir"
  save_config
  bash "$script_path" install
  log "脚本已更新到最新版本"
}

check_rclone_remote() {
  load_config
  have rclone || die "未找到 rclone，请先执行安装依赖"
  if ! rclone listremotes | grep -qx "${RCLONE_REMOTE}:"; then
    die "rclone remote 不存在：${RCLONE_REMOTE}:，请先配置云盘 remote"
  fi
  if rclone lsd "${RCLONE_REMOTE}:" >/dev/null 2>>"$RCLONE_LOG_FILE"; then
    log "rclone remote 连接正常：${RCLONE_REMOTE}:"
  else
    die "rclone remote 连接失败，请重新授权或查看：$RCLONE_LOG_FILE"
  fi
}

configure_rclone_remote() {
  require_root
  load_config
  ensure_dirs
  have rclone || die "未找到 rclone，请先执行安装依赖"

  printf '\nrclone 云盘 remote 配置说明：\n'
  printf '1. 下面会进入 rclone config。\n'
  printf '2. 新建 remote 时建议名称填写：%s，或使用你已有的 remote 名称。\n' "$RCLONE_REMOTE"
  printf '3. Storage 选择你的目标存储，例如 Google Drive、OneDrive、S3、WebDAV、SFTP 等。\n'
  printf '4. 如果该存储需要浏览器授权，按 rclone 提示在本地电脑授权，再把 token 粘回来。\n\n'

  if rclone listremotes | grep -qx "${RCLONE_REMOTE}:"; then
    if confirm "检测到 ${RCLONE_REMOTE}: 已存在，是否先尝试重新授权"; then
      rclone config reconnect "${RCLONE_REMOTE}:"
    else
      rclone config
    fi
  else
    rclone config
  fi

  local new_remote
  read -r -p "请输入本脚本要使用的 rclone remote 名称 [${RCLONE_REMOTE}]: " new_remote
  if [[ -n "$new_remote" ]]; then
    RCLONE_REMOTE="$new_remote"
    save_config
  fi
  check_rclone_remote
}

set_archive_password() {
  require_root
  load_config
  ensure_dirs
  local pass1 pass2
  read -r -s -p "请输入备份加密密码： " pass1
  printf '\n'
  read -r -s -p "请再次输入备份加密密码： " pass2
  printf '\n'
  [[ -n "$pass1" ]] || die "密码不能为空"
  [[ "$pass1" == "$pass2" ]] || die "两次密码不一致"
  umask 077
  printf '%s' "$pass1" > "$ARCHIVE_PASSWORD_FILE"
  chmod 600 "$ARCHIVE_PASSWORD_FILE"
  log "备份加密密码已保存到：$ARCHIVE_PASSWORD_FILE"
}

configure_mysql_auth() {
  require_root
  load_config
  ensure_dirs
  local mysql_user mysql_pass
  read -r -p "MySQL 用户 [root]: " mysql_user
  mysql_user="${mysql_user:-root}"
  read -r -s -p "MySQL 密码： " mysql_pass
  printf '\n'

  [[ -n "$mysql_pass" ]] || die "MySQL 密码不能为空"
  umask 077
  {
    printf '[client]\n'
    printf 'user=%s\n' "$mysql_user"
    printf 'password=%s\n' "$mysql_pass"
  } > "$MYSQL_DEFAULTS_FILE"
  chmod 600 "$MYSQL_DEFAULTS_FILE"
  log "MySQL 连接配置已保存到：$MYSQL_DEFAULTS_FILE"
}

configure_general() {
  require_root
  load_config
  ensure_dirs

  local input
  read -r -p "rclone remote 名称 [${RCLONE_REMOTE}]: " input
  [[ -n "$input" ]] && RCLONE_REMOTE="$input"

  read -r -p "云端远程目录 [${RCLONE_REMOTE_PATH}]: " input
  [[ -n "$input" ]] && RCLONE_REMOTE_PATH="${input#/}"
  RCLONE_REMOTE_PATH="${RCLONE_REMOTE_PATH%/}"

  read -r -p "每个站点/数据库保留份数 [${KEEP_COPIES}]: " input
  if [[ -n "$input" ]]; then
    valid_positive_int "$input" || die "保留份数必须是正整数"
    KEEP_COPIES="$input"
  fi

  read -r -p "本地备份暂存目录 [${BACKUP_ROOT}]: " input
  [[ -n "$input" ]] && BACKUP_ROOT="$input"

  read -r -p "定时表达式 cron [${CRON_EXPR}]: " input
  [[ -n "$input" ]] && CRON_EXPR="$input"

  read -r -p "MySQL host [${MYSQL_HOST}]: " input
  [[ -n "$input" ]] && MYSQL_HOST="$input"

  read -r -p "MySQL port [${MYSQL_PORT}]: " input
  [[ -n "$input" ]] && MYSQL_PORT="$input"

  read -r -p "MySQL socket，留空则使用 host/port [${MYSQL_SOCKET}]: " input
  MYSQL_SOCKET="$input"

  save_config

  if confirm "是否现在设置备份加密密码"; then
    set_archive_password
  fi
  if confirm "是否现在设置 MySQL 连接信息"; then
    configure_mysql_auth
  fi

  save_config
  log "基础配置已保存：$CONFIG_FILE"
}

list_file_numbered() {
  local file="$1"
  if [[ -s "$file" ]]; then
    nl -ba "$file"
  else
    printf '暂无配置\n'
  fi
}

delete_list_line() {
  local file="$1"
  local line_no
  list_file_numbered "$file"
  read -r -p "请输入要删除的行号： " line_no
  [[ "$line_no" =~ ^[0-9]+$ ]] || die "行号必须是数字"
  sed -i.bak "${line_no}d" "$file"
  rm -f "${file}.bak"
}

add_site_entry() {
  local name path excludes tmp
  read -r -p "站点名称： " name
  read -r -p "站点目录，例如 /www/wwwroot/example.com： " path
  read -r -p "排除项，多个用英文逗号分隔，例如 .git,cache,logs [可留空]： " excludes
  [[ -n "$name" && -n "$path" ]] || die "站点名称和目录不能为空"
  tmp="$(mktemp)"
  awk -F'|' -v site_name="$name" '$1 != site_name' "$SITES_FILE" > "$tmp" 2>/dev/null || true
  printf '%s|%s|%s\n' "$name" "$path" "$excludes" >> "$tmp"
  mv "$tmp" "$SITES_FILE"
  chmod 600 "$SITES_FILE"
  log "已添加/更新站点：$name"
}

add_database_entry() {
  local name tmp
  read -r -p "数据库名称： " name
  [[ -n "$name" ]] || die "数据库名称不能为空"
  tmp="$(mktemp)"
  grep -v -Fx "$name" "$DATABASES_FILE" > "$tmp" 2>/dev/null || true
  printf '%s\n' "$name" >> "$tmp"
  mv "$tmp" "$DATABASES_FILE"
  chmod 600 "$DATABASES_FILE"
  log "已添加/更新数据库：$name"
}

manage_sites_menu() {
  require_root
  load_config
  ensure_dirs
  while true; do
    printf '\n网站备份列表：\n'
    list_file_numbered "$SITES_FILE"
    printf '\n1. 添加/更新网站\n2. 删除网站\n0. 返回\n'
    local choice
    read -r -p "请选择： " choice
    case "$choice" in
      1) add_site_entry ;;
      2) delete_list_line "$SITES_FILE" ;;
      0) return 0 ;;
      *) printf '无效选择\n' ;;
    esac
  done
}

manage_databases_menu() {
  require_root
  load_config
  ensure_dirs
  while true; do
    printf '\n数据库备份列表：\n'
    list_file_numbered "$DATABASES_FILE"
    printf '\n1. 添加/更新数据库\n2. 删除数据库\n0. 返回\n'
    local choice
    read -r -p "请选择： " choice
    case "$choice" in
      1) add_database_entry ;;
      2) delete_list_line "$DATABASES_FILE" ;;
      0) return 0 ;;
      *) printf '无效选择\n' ;;
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
    log "未找到 mysql/mariadb 客户端，无法自动发现数据库"
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
    log "自动发现数据库失败，请检查 MySQL 连接信息：$MYSQL_DEFAULTS_FILE"
    return 0
  fi
  printf '%s\n' "$output" \
    | grep -Ev '^(information_schema|mysql|performance_schema|sys)$' \
    | sed '/^[[:space:]]*$/d' || true
}

remote_dir_for() {
  local subdir="$1"
  if [[ -n "$RCLONE_REMOTE_PATH" ]]; then
    printf '%s:%s/%s\n' "$RCLONE_REMOTE" "${RCLONE_REMOTE_PATH%/}" "$subdir"
  else
    printf '%s:%s\n' "$RCLONE_REMOTE" "$subdir"
  fi
}

encrypt_file() {
  local src="$1"
  local dest="$2"
  [[ -s "$ARCHIVE_PASSWORD_FILE" ]] || die "未设置备份加密密码，请先在菜单中设置"
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
    -in "$src" -out "$dest" -pass "file:${ARCHIVE_PASSWORD_FILE}" >/dev/null
  chmod 600 "$dest"
}

decrypt_backup_file() {
  require_root
  load_config
  local src="${1:-}"
  local dest="${2:-}"
  [[ -n "$src" && -n "$dest" ]] || die "用法：$0 decrypt 源文件.enc 输出文件"
  [[ -s "$ARCHIVE_PASSWORD_FILE" ]] || die "未找到密码文件：$ARCHIVE_PASSWORD_FILE"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
    -in "$src" -out "$dest" -pass "file:${ARCHIVE_PASSWORD_FILE}"
  log "已解密：$dest"
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
    log "已清理本地过期备份：$dir/${files[$i]}"
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
      log "已清理远程过期备份：${remote_dir}/${files[$i]}"
    fi
  done
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
  [[ -d "$path" ]] || die "站点目录不存在：$name -> $path"

  safe_name="$(sanitize_name "$name")"
  ts="$(date '+%Y%m%d_%H%M%S')"
  dest_dir="$BACKUP_ROOT/site/$safe_name"
  mkdir -p "$dest_dir"
  tmp_file="${dest_dir}/Web_${safe_name}_${ts}.tar.gz"
  final_file="${tmp_file}.enc"
  parent="$(dirname "$path")"
  base="$(basename "$path")"

  log "开始备份网站：$name"
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
  log "网站备份完成：$name -> $final_file"
}

backup_database() {
  local db_name="$1"
  local safe_name ts dest_dir tmp_file final_file dump_bin
  [[ -s "$MYSQL_DEFAULTS_FILE" ]] || die "未配置 MySQL 连接信息，请先在菜单中设置"
  dump_bin="$(find_mysqldump_bin)" || die "未找到 mysqldump/mariadb-dump"

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
  dump_cmd+=(--single-transaction --quick --routines --events --triggers --hex-blob --databases "$db_name")

  log "开始备份数据库：$db_name"
  "${dump_cmd[@]}" | gzip -9 > "$tmp_file"
  encrypt_file "$tmp_file" "$final_file"
  rm -f -- "$tmp_file"
  upload_and_prune "$final_file" "database/$safe_name"
  prune_local_dir "$dest_dir" "$KEEP_COPIES"
  log "数据库备份完成：$db_name -> $final_file"
}

backup_all() {
  require_root
  load_config
  ensure_dirs
  have flock || die "缺少 flock，请先安装 util-linux"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "已有备份任务正在运行，本次退出"
    exit 0
  fi

  ensure_cron_service || log "提醒：cron 服务检查失败，请手动确认 cron 是否运行"

  local site_count=0
  local db_count=0
  local name path excludes db_name site_key
  local -A seen_site_paths=()
  local -A seen_databases=()

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
    log "自动发现网站目录：$SITE_ROOTS"
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
    log "未找到可备份网站；可在 $SITES_FILE 添加站点，或设置 SITE_ROOTS"
  fi

  if [[ -s "$DATABASES_FILE" ]]; then
    while IFS= read -r db_name; do
      [[ -z "${db_name//[[:space:]]/}" || "${db_name:0:1}" == "#" ]] && continue
      [[ -n "${seen_databases[$db_name]+x}" ]] && continue
      seen_databases["$db_name"]=1
      backup_database "$db_name"
      db_count=$((db_count + 1))
    done < "$DATABASES_FILE"
  fi

  if [[ "$AUTO_DISCOVER_DATABASES" == "1" ]]; then
    log "自动发现 MySQL/MariaDB 数据库"
    while IFS= read -r db_name; do
      [[ -z "${db_name//[[:space:]]/}" || "${db_name:0:1}" == "#" ]] && continue
      [[ -n "${seen_databases[$db_name]+x}" ]] && continue
      seen_databases["$db_name"]=1
      backup_database "$db_name"
      db_count=$((db_count + 1))
    done < <(discover_databases)
  fi

  if [[ "$db_count" -eq 0 ]]; then
    log "未找到可备份数据库；可在 $DATABASES_FILE 添加数据库，或检查 MySQL 连接信息"
  fi

  log "本次备份结束：网站 ${site_count} 个，数据库 ${db_count} 个，保留 ${KEEP_COPIES} 份"
}

install_cron_entries() {
  require_root
  load_config
  ensure_dirs
  install_self
  valid_positive_int "$KEEP_COPIES" || die "KEEP_COPIES 必须是正整数"

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
  ensure_cron_service || die "定时任务已写入，但 cron 服务启动失败"
  log "定时任务已安装：$CRON_EXPR"
}

guard_cron() {
  require_root
  load_config
  ensure_dirs
  ensure_cron_service || die "cron 服务守护失败"
  if [[ "$ENABLE_CRON_GUARD" == "1" ]]; then
    if ! crontab -l 2>/dev/null | grep -Fq "$CRON_MARKER_BEGIN"; then
      install_cron_entries
    fi
  fi
  log "cron 守护检查完成"
}

install_systemd_guard() {
  require_root
  load_config
  ensure_dirs
  install_self
  have systemctl || die "未找到 systemctl，无法安装 systemd 守护"
  [[ -d /run/systemd/system ]] || die "当前环境不像正在运行的 systemd"

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
  log "cron 守护 timer 已安装：${APP_NAME}-cron-guard.timer"
}

remove_cron_entries() {
  if ! have crontab; then
    log "未找到 crontab，跳过 cron 定时任务清理"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null \
    | sed -e "/${CRON_MARKER_BEGIN}/,/${CRON_MARKER_END}/d" > "$tmp" || true
  crontab "$tmp"
  rm -f "$tmp"
  log "已移除 cron 定时任务"
}

remove_systemd_guard() {
  if ! have systemctl; then
    log "未找到 systemctl，跳过 systemd 守护清理"
    return 0
  fi

  systemctl disable --now "${APP_NAME}-cron-guard.timer" >/dev/null 2>&1 || true
  systemctl stop "${APP_NAME}-cron-guard.service" >/dev/null 2>&1 || true
  rm -f \
    "/etc/systemd/system/${APP_NAME}-cron-guard.service" \
    "/etc/systemd/system/${APP_NAME}-cron-guard.timer"
  systemctl daemon-reload >/dev/null 2>&1 || true
  log "已移除 systemd cron 守护"
}

remove_path_if_confirmed() {
  local label="$1"
  local target="$2"
  local resolved
  [[ -n "$target" && -e "$target" ]] || return 0
  resolved="$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")"
  case "$resolved" in
    /|/etc|/var|/usr|/usr/local|/var/log|/var/lib|/var/backups|/root|/home)
      log "拒绝删除高危路径：$resolved"
      return 0
      ;;
  esac

  if confirm "是否删除${label}：${target}"; then
    rm -rf -- "$target"
    log "已删除${label}：$target"
  else
    log "已保留${label}：$target"
  fi
}

uninstall_app() {
  require_root
  load_config

  printf '\n卸载说明：\n'
  printf '  - 会移除本脚本安装的 cron 定时任务。\n'
  printf '  - 会移除本脚本安装的 systemd cron 守护。\n'
  printf '  - 不会删除云端已上传的备份。\n'
  printf '  - 配置、密码、日志、本地备份目录会逐项询问后再删除。\n\n'
  confirm "确认开始卸载 ${DISPLAY_NAME}" || return 0

  remove_cron_entries
  remove_systemd_guard

  remove_path_if_confirmed "配置和密钥目录" "$CONFIG_DIR"
  remove_path_if_confirmed "本地备份暂存目录" "$BACKUP_ROOT"
  remove_path_if_confirmed "状态目录" "$STATE_DIR"
  remove_path_if_confirmed "日志目录" "$LOG_DIR"
  local current_script
  current_script="$(script_self)"
  if [[ -e "$INSTALL_PATH" ]]; then
    rm -f -- "$INSTALL_PATH"
    log "已删除安装脚本：$INSTALL_PATH"
  fi
  if [[ -L "$SHORT_INSTALL_PATH" || -e "$SHORT_INSTALL_PATH" ]]; then
    rm -f -- "$SHORT_INSTALL_PATH"
    log "已删除短命令：$SHORT_INSTALL_PATH"
  fi
  if [[ "$current_script" != "$INSTALL_PATH" ]]; then
    log "当前运行脚本未删除：$current_script"
  fi
  log "卸载完成"
}

show_logs() {
  load_config
  ensure_dirs
  local lines="${1:-80}"
  printf '\n主日志：%s\n' "$LOG_FILE"
  tail -n "$lines" "$LOG_FILE" 2>/dev/null || true
  printf '\nrclone 日志：%s\n' "$RCLONE_LOG_FILE"
  tail -n 40 "$RCLONE_LOG_FILE" 2>/dev/null || true
}

print_status() {
  load_config
  ensure_dirs
  printf '\n当前配置：\n'
  printf '  配置文件：%s\n' "$CONFIG_FILE"
  printf '  更新仓库：%s\n' "${UPDATE_REPO_DIR:-未记录}"
  printf '  rclone remote：%s:\n' "$RCLONE_REMOTE"
  printf '  远程目录：%s\n' "${RCLONE_REMOTE_PATH:-/}"
  printf '  本地目录：%s\n' "$BACKUP_ROOT"
  printf '  保留份数：%s\n' "$KEEP_COPIES"
  printf '  自动发现网站：%s\n' "$AUTO_DISCOVER_SITES"
  printf '  网站根目录：%s\n' "$SITE_ROOTS"
  printf '  自动发现数据库：%s\n' "$AUTO_DISCOVER_DATABASES"
  printf '  定时任务：%s\n' "$CRON_EXPR"
  printf '  网站列表：%s\n' "$SITES_FILE"
  printf '  数据库列表：%s\n' "$DATABASES_FILE"
  printf '  密码文件：%s\n' "$ARCHIVE_PASSWORD_FILE"
  printf '  MySQL 配置：%s\n' "$MYSQL_DEFAULTS_FILE"
}

menu() {
  require_root
  load_config
  ensure_dirs
  while true; do
    printf '\n%s 中文管理菜单\n' "$DISPLAY_NAME"
    printf '1. 安装/检查依赖\n'
    printf '2. rclone 云盘授权/检查\n'
    printf '3. 基础配置和密码\n'
    printf '4. 管理网站备份列表\n'
    printf '5. 管理数据库备份列表\n'
    printf '6. 安装/更新 cron 定时任务\n'
    printf '7. 安装 cron 进程守护\n'
    printf '8. 立即执行一次备份\n'
    printf '9. 查看日志\n'
    printf '10. 查看当前配置\n'
    printf '11. 更新 DriveGuard 脚本\n'
    printf '12. 卸载脚本和定时守护\n'
    printf '0. 退出\n'
    local choice
    read -r -p "请选择： " choice
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
      *) printf '无效选择\n' ;;
    esac
  done
}

usage() {
  cat <<EOF
用法：
  $0 menu              打开中文交互菜单
  $0 install           安装/更新 driveguard 和 dg 短命令
  $0 update            从 Git 仓库拉取并更新脚本
  $0 install-deps      安装 Debian/Ubuntu/CentOS/RHEL 依赖
  $0 auth              配置/检查 rclone 云盘 remote
  $0 configure         设置基础配置、密码、MySQL 连接
  $0 cron              安装/更新 cron 定时任务
  $0 install-guard     安装 systemd cron 守护 timer
  $0 guard-cron        检查并拉起 cron 服务
  $0 backup            立即执行一次备份
  $0 log [行数]         查看日志
  $0 decrypt 源.enc 输出文件
  $0 uninstall         卸载脚本、cron 和 systemd 守护

配置文件：
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
    auth) configure_rclone_remote ;;
    configure) configure_general ;;
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
