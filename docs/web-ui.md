# DriveGuard Web UI Guide

**Languages:** [English](web-ui.md) | [中文](zh-CN/web-ui.md)

The DriveGuard Web UI is the default product path for browser-based server backups. It provides a Vue console, a Go API service, and a deployment helper while continuing to use the same encrypted backup engine as the CLI. If you prefer terminal-only operation, use the [CLI guide](cli.md).

## What It Installs

- `driveguard-web.sh` as the Web UI installer and maintenance helper
- `driveguardd` as the local Go API service
- The Vue 3 + Vite frontend as static assets behind your web server
- The DriveGuard CLI engine for backup, cron, restore, and cloud-storage operations
- A systemd service for the API on Linux servers

## Quick Start

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard-web.sh install
```

If DriveGuard Web UI is already installed, update it from the installed source directory:

```bash
cd /opt/driveguard-web
sudo bash driveguard-web.sh update
```

When `WEB_ROOT` is not set, `install`, `update`, and `update-frontend` try to detect the active Nginx/server-panel site root that proxies `/api` to `driveguardd`. Set `WEB_ROOT=/path/to/site` only when you need to override auto-detection.

## Repository Layout

```text
driveguard.sh                 Bash CLI and backup engine
driveguard-web.sh             Web UI installer and maintenance helper
README.md                     Project overview and product paths
docs/                         Documentation
docs/web-ui.md                Web UI guide
docs/zh-CN/web-ui.md          Chinese Web UI guide
web/                          Vue 3 + Vite frontend
server/                       Go API service
```

Backend layout:

```text
server/
  cmd/driveguardd/            HTTP service entrypoint
  internal/api/               Routes, handlers, response types
  internal/driveguard/        Adapter around DriveGuard commands
  internal/jobs/              In-process job tracking
```

Frontend layout:

```text
web/
  src/App.vue                 Console shell and dashboard views
  src/services/api.ts         API client; mock data is opt-in with VITE_USE_MOCKS=true
  src/types.ts                Shared frontend types
  src/assets/main.css         Design tokens and responsive layout
```

## Product Boundary

The Web UI is an operations console for server backups. It does not remove or hide the CLI; instead, it wraps the stable CLI engine with a browser workflow:

- Sign in with a local administrator account
- Change password and enable TOTP two-factor authentication
- Authorize a cloud drive provider
- Create or edit a scheduled backup plan
- Pick website, database, or full backup scope
- Pick the destination provider and remote directory
- Run an encrypted backup job and inspect recent jobs
- Review service logs and backup logs
- Decrypt and restore uploaded backup files through a temporary workspace
- Auto-detect browser language with a manual English/Chinese switch
- Return clear API errors when a command requires root or Linux-only tools

The current scheduled-backup implementation intentionally maps the Web UI form to the existing single CLI schedule. "Save and enable" updates the CLI config file, installs the root crontab entry with `dg cron`, and installs the systemd cron guard with `dg install-guard`. Multi-plan orchestration can be added later after the single-plan server-panel workflow stays reliable.

Current Web UI provider support is verified with Google Drive. Microsoft OneDrive may appear as a provider in the UI and CLI engine, but the Web UI authorization/workflow is not ready yet; use `sudo dg auth onedrive` from the CLI for OneDrive until the browser flow is completed. Advanced `rclone config` remains available through the CLI for other providers.

Google Drive can use direct Web OAuth when the server has `DRIVEGUARD_PUBLIC_URL`, `DRIVEGUARD_GOOGLE_CLIENT_ID`, and `DRIVEGUARD_GOOGLE_CLIENT_SECRET` configured. The Google OAuth client must be a Web application client with this authorized redirect URI:

```text
${DRIVEGUARD_PUBLIC_URL}/api/v1/cloud/google/callback
```

The callback exchanges the authorization code on the server and writes the token to the selected rclone remote, defaulting to `gdrive:`. When Google Web OAuth is not configured, the UI falls back to the CLI-style authorization flow.

## API Shape

```text
GET  /api/v1/health
GET  /api/v1/auth/state
POST /api/v1/auth/bootstrap
POST /api/v1/auth/login
POST /api/v1/auth/logout
POST /api/v1/auth/password
POST /api/v1/auth/totp/setup
POST /api/v1/auth/totp/enable
POST /api/v1/auth/totp/disable
POST /api/v1/security/archive-password
POST /api/v1/restore/decrypt
GET  /api/v1/status
GET  /api/v1/cloud-providers
GET  /api/v1/cloud/google/auth-url
GET  /api/v1/cloud/google/callback
GET  /api/v1/backup-plans
POST /api/v1/backup-plans
GET  /api/v1/logs?lines=80
GET  /api/v1/jobs
GET  /api/v1/jobs/{id}
POST /api/v1/jobs/backup
```

The API defaults to `127.0.0.1` during development. Public deployment should sit behind a reverse proxy with TLS and authentication.

The local account system stores password hashes with PBKDF2-HMAC-SHA256, uses HttpOnly SameSite session cookies, protects mutating API calls with CSRF tokens, and supports TOTP two-factor authentication. The default auth file is `/etc/driveguard/web-auth.json` on Linux/macOS and `driveguard-auth.json` on Windows development machines.

## Deployment Script

`driveguard-web.sh` keeps Web UI operations separate from the standalone CLI path while automating server-side work:

- English/Chinese menu selection
- Dependency checks for Go, Node.js, rclone, git, curl, rsync, and cron
- Full install for `driveguardd`, the systemd unit, the frontend build, and static web publishing
- Full updates, backend-only updates, and frontend-only updates
- Auto-detection of the Nginx/server-panel web root when publishing frontend assets
- API health checks, systemd state checks, and journal log viewing
- Google OAuth setup, including client ID/secret extraction from a Google OAuth client JSON file
- Web UI uninstall while keeping CLI config and backup files by default

Common commands:

```bash
sudo bash driveguard-web.sh install
sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json
sudo bash driveguard-web.sh update
sudo bash driveguard-web.sh status
sudo bash driveguard-web.sh logs 120
```

## Local Development

Run the backend and frontend separately:

```bash
cd server
go run ./cmd/driveguardd

cd ../web
npm install
npm run dev
```

The Vite dev server proxies `/api` to `http://127.0.0.1:8080`. To preview the UI without the Go API, run:

```bash
cd web
npm run dev:mock
```

## Security Notes

- Do not expose DriveGuard on a public interface without TLS and authentication.
- Do not return secret values such as archive passwords, database passwords, OAuth tokens, or full `rclone.conf` contents.
- Restore/decrypt uploads must use temporary files only and delete both encrypted and decrypted files after the response finishes.
- Treat backup, cron, restore, and uninstall actions as privileged operations.
- Keep destructive operations behind explicit confirmation in the UI.
