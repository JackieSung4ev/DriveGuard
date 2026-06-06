# DriveGuard Web UI Plan

DriveGuard keeps the current Bash CLI as the stable command-line and installer entrypoint. The Web UI is added as a monorepo layer so the existing `dg` workflow remains available while the Go service and Vue console evolve.

## Repository Layout

```text
driveguard.sh                 Stable Bash CLI and installer
README.md                     Project overview and quick start
docs/                         Wiki-style documentation
docs/web-ui.md                Web UI architecture and roadmap
docs/zh-CN/web-ui.md          Chinese Web UI plan
web/                          Vue 3 + Vite frontend
server/                       Go API service
```

Planned backend layout:

```text
server/
  cmd/driveguardd/            HTTP service entrypoint
  internal/api/               Routes, handlers, response types
  internal/driveguard/        Adapter around DriveGuard commands
  internal/jobs/              In-process job tracking
```

Planned frontend layout:

```text
web/
  src/App.vue                 Console shell and dashboard view
  src/services/api.ts         API client; mock data is opt-in with VITE_USE_MOCKS=true
  src/types.ts                Shared frontend types
  src/assets/main.css         Design tokens and responsive layout
```

## Product Boundary

The first Web UI version is an operations console, not a replacement for the CLI installer. Its primary workflow should feel like a server panel plugin:

- Sign in with a local administrator account
- Change password and enable TOTP two-factor authentication
- Authorize a cloud drive provider
- Create a scheduled backup plan
- Pick website, database, or full backup scope
- Pick destination provider and remote directory
- Upload an encrypted backup file, decrypt it in a temporary workspace, and download the restored file
- Review recent jobs and logs
- Auto-detect browser language with a manual English/Chinese switch
- Keep safe API errors when a command requires root or Linux-only tools

The backend can initially wrap `driveguard.sh` commands. Core backup logic can move into Go later after the API surface is stable.

Initial provider support is intentionally narrow: Google Drive and Microsoft OneDrive through `rclone`.

The authorization UI follows a three-step pattern: copy the provider-specific `dg auth` command, open the generated OAuth link, then paste the redirected verification URL back for confirmation. The Web UI branch keeps `sudo dg auth` as a provider picker and supports direct commands like `sudo dg auth google` and `sudo dg auth onedrive`; advanced `rclone config` remains available as a fallback.

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
GET  /api/v1/backup-plans
POST /api/v1/backup-plans
GET  /api/v1/logs?lines=80
GET  /api/v1/jobs
GET  /api/v1/jobs/{id}
POST /api/v1/jobs/backup
```

The API should default to `127.0.0.1` during development. Public deployment should sit behind a reverse proxy with TLS and authentication.

The local account system stores password hashes with PBKDF2-HMAC-SHA256, uses HttpOnly SameSite session cookies, protects mutating API calls with CSRF tokens, and supports TOTP two-factor authentication. The default auth file is `/etc/driveguard/web-auth.json` on Linux/macOS and `driveguard-auth.json` on Windows development machines.

## Security Notes

- Do not expose DriveGuard on a public interface without TLS and authentication.
- Do not return secret values such as archive passwords, database passwords, OAuth tokens, or full `rclone.conf` contents.
- Restore/decrypt uploads must use temporary files only and delete both encrypted and decrypted files after the response finishes.
- Treat backup, cron, restore, and uninstall actions as privileged operations.
- Keep destructive operations behind explicit confirmation in the UI.

## Build Order

1. Build the Vue console with page-based sidebar navigation.
2. Add local administrator login, password change, and TOTP setup.
3. Add Google Drive and OneDrive provider authorization pages.
4. Add a scheduled backup form with readable daily, weekly, monthly, interval, and custom cron options.
5. Add the Go HTTP service with auth, health, status, provider, plan, log, and job endpoints.
6. Connect the frontend to the Go service through Vite proxy during development.
7. Package the frontend into static assets for the Go service after the API is stable.
