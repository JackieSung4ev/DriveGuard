#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="driveguard-web"
SERVICE_NAME="driveguardd"
REPO_URL="${REPO_URL:-https://github.com/JackieSung4ev/DriveGuard.git}"
BRANCH="${BRANCH:-feature/web-ui}"
INSTALL_DIR="${INSTALL_DIR:-/opt/driveguard-web}"
WEB_ROOT="${WEB_ROOT:-/var/www/driveguard}"
API_ADDR="${DRIVEGUARD_ADDR:-127.0.0.1:8080}"
GO_VERSION="${GO_VERSION:-1.22.12}"
ENV_DIR="${ENV_DIR:-/etc/driveguard}"
ENV_FILE="${ENV_FILE:-${ENV_DIR}/driveguardd.env}"
AUTH_FILE="${DRIVEGUARD_AUTH_FILE:-${ENV_DIR}/web-auth.json}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BACKEND_BIN="/usr/local/bin/${SERVICE_NAME}"
CLI_BIN="/usr/local/bin/dg"
LANG_CHOICE="${DRIVEGUARD_WEB_LANG:-auto}"
ASSUME_YES="${ASSUME_YES:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
SOURCE_DIR="${SOURCE_DIR:-$SCRIPT_DIR}"

timestamp() {
  date '+%F %T'
}

detect_language() {
  if [[ "$LANG_CHOICE" == "zh" || "$LANG_CHOICE" == "en" ]]; then
    return 0
  fi
  case "${LC_ALL:-${LANG:-}}" in
    zh*|ZH*) LANG_CHOICE="zh" ;;
    *) LANG_CHOICE="en" ;;
  esac
}

choose_language() {
  printf 'Language / 语言:\n'
  printf '  1) English\n'
  printf '  2) 中文\n'
  read -r -p 'Select [1/2]: ' answer
  case "$answer" in
    2) LANG_CHOICE="zh" ;;
    *) LANG_CHOICE="en" ;;
  esac
}

msg() {
  local key="$1"
  case "${LANG_CHOICE}:${key}" in
    zh:need_root) printf '请使用 root 运行，例如 sudo bash driveguard-web.sh %s\n' "${2:-install}" ;;
    zh:missing_source) printf '当前目录不是 DriveGuard 仓库，且未找到 %s\n' "$SOURCE_DIR" ;;
    zh:deps_done) printf '依赖检查完成\n' ;;
    zh:node_old) printf 'Node.js 版本过低，Vite 需要 Node.js 20.19+ 或 22.12+\n' ;;
    zh:go_old) printf 'Go 版本过低，后端需要 Go 1.22+\n' ;;
    zh:install_done) printf '安装完成\n' ;;
    zh:update_done) printf '更新完成\n' ;;
    zh:frontend_done) printf '前端构建并发布完成：%s\n' "$WEB_ROOT" ;;
    zh:backend_done) printf '后端构建并安装完成：%s\n' "$BACKEND_BIN" ;;
    zh:oauth_done) printf 'Google OAuth 配置已写入：%s\n' "$ENV_FILE" ;;
    zh:uninstall_done) printf 'Web UI 已卸载。CLI、备份文件和 /etc/driveguard 默认保留。\n' ;;
    zh:cancelled) printf '已取消\n' ;;
    zh:status_title) printf 'DriveGuard Web 状态\n' ;;
    zh:confirm_uninstall) printf '这会停止并移除 Web API 服务和静态前端，不会删除备份文件。继续？[y/N]: ' ;;
    zh:installing_deps) printf '正在安装依赖\n' ;;
    zh:building_backend) printf '正在构建后端\n' ;;
    zh:building_frontend) printf '正在构建前端\n' ;;
    zh:publishing_frontend) printf '正在发布前端到 %s\n' "$WEB_ROOT" ;;
    zh:restarting_service) printf '正在重启 %s\n' "$SERVICE_NAME" ;;
    en:need_root) printf 'Please run as root, for example: sudo bash driveguard-web.sh %s\n' "${2:-install}" ;;
    en:missing_source) printf 'Current directory is not a DriveGuard repository and %s was not found\n' "$SOURCE_DIR" ;;
    en:deps_done) printf 'Dependency check complete\n' ;;
    en:node_old) printf 'Node.js is too old. Vite requires Node.js 20.19+ or 22.12+\n' ;;
    en:go_old) printf 'Go is too old. The backend requires Go 1.22+\n' ;;
    en:install_done) printf 'Install complete\n' ;;
    en:update_done) printf 'Update complete\n' ;;
    en:frontend_done) printf 'Frontend built and published: %s\n' "$WEB_ROOT" ;;
    en:backend_done) printf 'Backend built and installed: %s\n' "$BACKEND_BIN" ;;
    en:oauth_done) printf 'Google OAuth configuration written to: %s\n' "$ENV_FILE" ;;
    en:uninstall_done) printf 'Web UI uninstalled. CLI, backups, and /etc/driveguard are kept by default.\n' ;;
    en:cancelled) printf 'Cancelled\n' ;;
    en:status_title) printf 'DriveGuard Web status\n' ;;
    en:confirm_uninstall) printf 'This will stop and remove the Web API service and static frontend, but keep backups. Continue? [y/N]: ' ;;
    en:installing_deps) printf 'Installing dependencies\n' ;;
    en:building_backend) printf 'Building backend\n' ;;
    en:building_frontend) printf 'Building frontend\n' ;;
    en:publishing_frontend) printf 'Publishing frontend to %s\n' "$WEB_ROOT" ;;
    en:restarting_service) printf 'Restarting %s\n' "$SERVICE_NAME" ;;
    *) printf '%s\n' "$key" ;;
  esac
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    msg need_root "${1:-install}"
    exit 1
  fi
}

have() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi
  printf '%s' "$prompt"
  local answer
  read -r answer
  [[ "$answer" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]
}

version_ge() {
  local current="${1#v}"
  local required="${2#v}"
  local highest
  highest="$(printf '%s\n%s\n' "$required" "$current" | sort -V | tail -n 1)"
  [[ "$highest" == "$current" ]]
}

node_ok() {
  have node || return 1
  local version major
  version="$(node -v | sed 's/^v//')"
  major="${version%%.*}"
  case "$major" in
    20) version_ge "$version" "20.19.0" ;;
    22) version_ge "$version" "22.12.0" ;;
    23|24|25|26|27|28|29) return 0 ;;
    *) return 1 ;;
  esac
}

go_ok() {
  have go || return 1
  local version
  version="$(go version | awk '{print $3}' | sed 's/^go//')"
  version_ge "$version" "1.22.0"
}

detect_pkg_manager() {
  if have apt-get; then
    printf 'apt'
  elif have dnf; then
    printf 'dnf'
  elif have yum; then
    printf 'yum'
  else
    printf 'unknown'
  fi
}

install_core_packages() {
  local manager
  manager="$(detect_pkg_manager)"
  case "$manager" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl git rsync tar gzip openssl build-essential cron golang-go
      ;;
    dnf)
      dnf install -y ca-certificates curl git rsync tar gzip openssl gcc make cronie golang
      systemctl enable --now crond >/dev/null 2>&1 || true
      ;;
    yum)
      yum install -y ca-certificates curl git rsync tar gzip openssl gcc make cronie golang
      systemctl enable --now crond >/dev/null 2>&1 || true
      ;;
    *)
      printf 'Unsupported package manager. Install git curl rsync rclone Go 1.22+ and Node.js 20.19+ manually.\n'
      return 1
      ;;
  esac
}

install_node20() {
  if node_ok; then
    return 0
  fi

  local manager
  manager="$(detect_pkg_manager)"
  case "$manager" in
    apt)
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
      apt-get install -y nodejs
      ;;
    dnf)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
      dnf install -y nodejs
      ;;
    yum)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
      yum install -y nodejs
      ;;
  esac

  if ! node_ok; then
    msg node_old
    exit 1
  fi
}

install_go_official() {
  if go_ok; then
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      msg go_old
      printf 'Unsupported CPU architecture for automatic Go install: %s\n' "$(uname -m)"
      exit 1
      ;;
  esac

  local tarball="/tmp/go${GO_VERSION}.linux-${arch}.tar.gz"
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" -o "$tarball"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tarball"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -f "$tarball"
}

install_deps() {
  require_root deps
  msg installing_deps
  install_core_packages
  install_node20
  install_go_official
  ensure_source
  bash "$SOURCE_DIR/driveguard.sh" install-deps

  if ! go_ok; then
    msg go_old
    printf 'Install Go 1.22+ from https://go.dev/dl/ and rerun this command.\n'
    exit 1
  fi
  msg deps_done
}

ensure_source() {
  if [[ -f "$SOURCE_DIR/driveguard.sh" && -d "$SOURCE_DIR/server" && -d "$SOURCE_DIR/web" ]]; then
    return 0
  fi

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    SOURCE_DIR="$INSTALL_DIR"
    return 0
  fi

  if [[ ! -e "$INSTALL_DIR" ]]; then
    git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    SOURCE_DIR="$INSTALL_DIR"
    return 0
  fi

  msg missing_source
  exit 1
}

update_source() {
  ensure_source
  if [[ -d "$SOURCE_DIR/.git" ]]; then
    git -C "$SOURCE_DIR" fetch origin "$BRANCH"
    git -C "$SOURCE_DIR" checkout "$BRANCH"
    git -C "$SOURCE_DIR" pull --ff-only origin "$BRANCH"
  fi
}

ensure_env_file() {
  require_root
  install -d -m 0700 "$ENV_DIR"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

shell_quote() {
  printf '%q' "$1"
}

set_env_value() {
  local key="$1"
  local value="$2"
  ensure_env_file

  local tmp
  tmp="$(mktemp)"
  grep -v -E "^${key}=" "$ENV_FILE" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$(shell_quote "$value")" >> "$tmp"
  install -m 0600 "$tmp" "$ENV_FILE"
  rm -f "$tmp"
}

env_value() {
  local key="$1"
  [[ -f "$ENV_FILE" ]] || return 0
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | sed "s/^'//;s/'$//"
}

write_default_env() {
  ensure_env_file
  set_env_value DRIVEGUARD_ADDR "$API_ADDR"
  set_env_value DRIVEGUARD_SCRIPT "$CLI_BIN"
  set_env_value DRIVEGUARD_AUTH_FILE "$AUTH_FILE"
  if [[ -z "$(env_value DRIVEGUARD_GOOGLE_REMOTE || true)" ]]; then
    set_env_value DRIVEGUARD_GOOGLE_REMOTE "gdrive"
  fi
  if [[ -z "$(env_value DRIVEGUARD_GOOGLE_SCOPE || true)" ]]; then
    set_env_value DRIVEGUARD_GOOGLE_SCOPE "drive.file"
  fi
}

extract_json_value() {
  local key="$1"
  local file="$2"
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" "$file" | head -n 1
}

configure_google_oauth() {
  require_root oauth
  ensure_env_file

  local public_url="${PUBLIC_URL:-}"
  local client_id="${GOOGLE_CLIENT_ID:-}"
  local client_secret="${GOOGLE_CLIENT_SECRET:-}"
  local json_file="${GOOGLE_CLIENT_JSON:-}"
  local remote="${GOOGLE_REMOTE:-gdrive}"
  local scope="${GOOGLE_SCOPE:-drive.file}"

  if [[ -z "$json_file" && "${1:-}" != "" ]]; then
    json_file="$1"
  fi

  if [[ -n "$json_file" ]]; then
    [[ -r "$json_file" ]] || { printf 'Cannot read Google OAuth JSON: %s\n' "$json_file"; exit 1; }
    client_id="$(extract_json_value client_id "$json_file")"
    client_secret="$(extract_json_value client_secret "$json_file")"
  fi

  if [[ -z "$public_url" ]]; then
    [[ "$ASSUME_YES" == "1" ]] && { printf 'PUBLIC_URL is required\n'; exit 1; }
    read -r -p 'Public URL, e.g. https://backup.example.com: ' public_url
  fi
  if [[ -z "$client_id" ]]; then
    [[ "$ASSUME_YES" == "1" ]] && { printf 'GOOGLE_CLIENT_ID is required\n'; exit 1; }
    read -r -p 'Google OAuth client ID: ' client_id
  fi
  if [[ -z "$client_secret" ]]; then
    [[ "$ASSUME_YES" == "1" ]] && { printf 'GOOGLE_CLIENT_SECRET is required\n'; exit 1; }
    read -r -s -p 'Google OAuth client secret: ' client_secret
    printf '\n'
  fi
  if [[ "$ASSUME_YES" != "1" ]]; then
    read -r -p "rclone remote name [${remote}]: " input_remote
    remote="${input_remote:-$remote}"
    read -r -p "Google scope [${scope}]: " input_scope
    scope="${input_scope:-$scope}"
  fi

  set_env_value DRIVEGUARD_PUBLIC_URL "${public_url%/}"
  set_env_value DRIVEGUARD_GOOGLE_CLIENT_ID "$client_id"
  set_env_value DRIVEGUARD_GOOGLE_CLIENT_SECRET "$client_secret"
  set_env_value DRIVEGUARD_GOOGLE_REMOTE "$remote"
  set_env_value DRIVEGUARD_GOOGLE_SCOPE "$scope"
  msg oauth_done
  printf 'Redirect URI: %s/api/v1/cloud/google/callback\n' "${public_url%/}"
}

show_google_oauth() {
  printf 'ENV_FILE=%s\n' "$ENV_FILE"
  for key in DRIVEGUARD_PUBLIC_URL DRIVEGUARD_GOOGLE_CLIENT_ID DRIVEGUARD_GOOGLE_REMOTE DRIVEGUARD_GOOGLE_SCOPE; do
    printf '%s=%s\n' "$key" "$(env_value "$key" || true)"
  done
  local secret
  secret="$(env_value DRIVEGUARD_GOOGLE_CLIENT_SECRET || true)"
  if [[ -n "$secret" ]]; then
    printf 'DRIVEGUARD_GOOGLE_CLIENT_SECRET=%s\n' '********'
  else
    printf 'DRIVEGUARD_GOOGLE_CLIENT_SECRET=\n'
  fi
}

install_cli() {
  require_root
  ensure_source
  bash "$SOURCE_DIR/driveguard.sh" install
}

build_backend() {
  ensure_source
  msg building_backend
  go_ok || { msg go_old; exit 1; }
  (cd "$SOURCE_DIR/server" && go build -o "$SERVICE_NAME" ./cmd/driveguardd)
}

install_backend() {
  require_root backend
  build_backend
  install -m 0755 "$SOURCE_DIR/server/$SERVICE_NAME" "$BACKEND_BIN"
  install -d -m 0700 "$ENV_DIR"
  write_default_env
  install -m 0644 "$SOURCE_DIR/server/deploy/driveguardd.service" "$SERVICE_FILE"
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
  msg backend_done
}

build_frontend() {
  ensure_source
  msg building_frontend
  node_ok || { msg node_old; exit 1; }
  (cd "$SOURCE_DIR/web" && npm ci && npm run build)
}

publish_frontend() {
  require_root frontend
  ensure_source
  [[ -d "$SOURCE_DIR/web/dist" ]] || build_frontend
  msg publishing_frontend
  install -d -m 0755 "$WEB_ROOT"
  rsync -a --delete --exclude '.user.ini' "$SOURCE_DIR/web/dist/" "$WEB_ROOT/"
  msg frontend_done
}

install_all() {
  require_root install
  install_deps
  ensure_source
  install_cli
  install_backend
  build_frontend
  publish_frontend
  msg install_done
  status_check
}

update_all() {
  require_root update
  update_source
  install_cli
  install_backend
  build_frontend
  publish_frontend
  msg update_done
  status_check
}

update_backend() {
  require_root update-backend
  update_source
  install_cli
  install_backend
  status_check
}

update_frontend() {
  require_root update-frontend
  update_source
  build_frontend
  publish_frontend
}

restart_service() {
  require_root restart
  msg restarting_service
  systemctl restart "$SERVICE_NAME"
}

status_check() {
  msg status_title
  printf 'Source: %s\n' "$SOURCE_DIR"
  printf 'Web root: %s\n' "$WEB_ROOT"
  printf 'API: http://%s/api/v1/health\n' "$API_ADDR"
  if have systemctl; then
    systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1 \
      && printf 'systemd: active\n' \
      || printf 'systemd: not active\n'
  fi
  if have curl; then
    curl -fsS "http://${API_ADDR}/api/v1/health" || true
    printf '\n'
  fi
  if have "$CLI_BIN"; then
    "$CLI_BIN" status || true
  fi
}

show_logs() {
  if have journalctl; then
    journalctl -u "$SERVICE_NAME" -n "${1:-80}" --no-pager
  else
    printf 'journalctl not found\n'
  fi
}

remove_dir_safely() {
  local target="$1"
  [[ -n "$target" && "$target" != "/" ]] || {
    printf 'Refusing to remove unsafe path: %s\n' "$target"
    exit 1
  }
  rm -rf -- "$target"
}

uninstall_web() {
  require_root uninstall
  local prompt
  prompt="$(msg confirm_uninstall)"
  if ! confirm "$prompt"; then
    msg cancelled
    return 0
  fi

  systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "$SERVICE_FILE" "$BACKEND_BIN"
  systemctl daemon-reload >/dev/null 2>&1 || true

  if [[ "${REMOVE_WEB_ROOT:-0}" == "1" ]]; then
    remove_dir_safely "$WEB_ROOT"
  fi
  if [[ "${REMOVE_SOURCE:-0}" == "1" && "$SOURCE_DIR" == "$INSTALL_DIR" ]]; then
    remove_dir_safely "$INSTALL_DIR"
  fi
  if [[ "${PURGE_CONFIG:-0}" == "1" ]]; then
    rm -f -- "$ENV_FILE" "$AUTH_FILE"
  fi
  msg uninstall_done
}

print_help() {
  cat <<EOF
DriveGuard Web installer

Usage:
  sudo bash driveguard-web.sh [command] [options]

Commands:
  menu                 Interactive menu
  deps                 Install/check system dependencies
  install              Install CLI, Web API service, and frontend
  update               Pull branch and update CLI, backend, and frontend
  update-backend       Pull branch, rebuild backend, restart service
  update-frontend      Pull branch, rebuild and publish frontend
  build-backend        Build backend only
  build-frontend       Build frontend only
  publish-frontend     Publish web/dist to WEB_ROOT
  oauth [json-file]    Set Google OAuth env, optionally extracting from client JSON
  oauth-show           Show current OAuth env without printing the secret
  status               Check API, systemd, and dg status
  logs [lines]         Show driveguardd journal logs
  restart              Restart driveguardd
  uninstall            Remove Web API service and static frontend
  help                 Show this help

Options/env:
  --lang en|zh
  --yes
  INSTALL_DIR=/opt/driveguard-web
  WEB_ROOT=/www/wwwroot/example.com
  PUBLIC_URL=https://backup.example.com
  GOOGLE_CLIENT_JSON=/root/client_secret.json
  GOOGLE_CLIENT_ID=...
  GOOGLE_CLIENT_SECRET=...
  GOOGLE_REMOTE=gdrive
  GOOGLE_SCOPE=drive.file

Examples:
  sudo bash driveguard-web.sh --lang zh install
  sudo WEB_ROOT=/www/wwwroot/example.com bash driveguard-web.sh update
  sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json
EOF
}

menu() {
  if [[ "$LANG_CHOICE" == "auto" ]]; then
    choose_language
  fi
  while true; do
    if [[ "$LANG_CHOICE" == "zh" ]]; then
      cat <<EOF

DriveGuard Web 菜单
  1) 安装/修复依赖
  2) 完整安装
  3) 完整更新
  4) 只更新后端
  5) 只更新前端
  6) 配置 Google OAuth
  7) 查看 OAuth 配置
  8) API 状态检测
  9) 查看后端日志
 10) 重启后端服务
 11) 卸载 Web UI
  0) 退出
EOF
    else
      cat <<EOF

DriveGuard Web menu
  1) Install/check dependencies
  2) Full install
  3) Full update
  4) Update backend only
  5) Update frontend only
  6) Configure Google OAuth
  7) Show OAuth config
  8) API status check
  9) Show backend logs
 10) Restart backend service
 11) Uninstall Web UI
  0) Exit
EOF
    fi
    read -r -p '> ' choice
    case "$choice" in
      1) install_deps ;;
      2) install_all ;;
      3) update_all ;;
      4) update_backend ;;
      5) update_frontend ;;
      6) configure_google_oauth ;;
      7) show_google_oauth ;;
      8) status_check ;;
      9) show_logs 120 ;;
      10) restart_service ;;
      11) uninstall_web ;;
      0) exit 0 ;;
    esac
  done
}

parse_args() {
  COMMAND=""
  POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)
        LANG_CHOICE="${2:-en}"
        shift 2
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --install-dir)
        INSTALL_DIR="${2:?}"
        shift 2
        ;;
      --web-root)
        WEB_ROOT="${2:?}"
        shift 2
        ;;
      --public-url)
        PUBLIC_URL="${2:?}"
        shift 2
        ;;
      --google-json)
        GOOGLE_CLIENT_JSON="${2:?}"
        shift 2
        ;;
      --client-id)
        GOOGLE_CLIENT_ID="${2:?}"
        shift 2
        ;;
      --client-secret)
        GOOGLE_CLIENT_SECRET="${2:?}"
        shift 2
        ;;
      --)
        shift
        POSITIONAL+=("$@")
        break
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1"
        exit 1
        ;;
      *)
        if [[ -z "$COMMAND" ]]; then
          COMMAND="$1"
        else
          POSITIONAL+=("$1")
        fi
        shift
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  detect_language

  case "${COMMAND:-menu}" in
    menu|"") menu ;;
    deps|install-deps) install_deps ;;
    install) install_all ;;
    update) update_all ;;
    update-backend) update_backend ;;
    update-frontend) update_frontend ;;
    build-backend) build_backend ;;
    build-frontend) build_frontend ;;
    publish-frontend) publish_frontend ;;
    oauth|google-oauth) configure_google_oauth "${POSITIONAL[0]:-}" ;;
    oauth-show|google-oauth-show) show_google_oauth ;;
    status|check) status_check ;;
    logs) show_logs "${POSITIONAL[0]:-80}" ;;
    restart) restart_service ;;
    uninstall) uninstall_web ;;
    help|-h|--help) print_help ;;
    *)
      printf 'Unknown command: %s\n' "$COMMAND"
      print_help
      exit 1
      ;;
  esac
}

main "$@"
