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
  src/services/api.ts         API client with development fallback data
  src/types.ts                Shared frontend types
  src/assets/main.css         Design tokens and responsive layout
```

## Product Boundary

The first Web UI version is an operations console, not a replacement for the CLI installer. It should make routine checks and actions easier:

- Current configuration and health overview
- Website and database backup target summaries
- Manual backup action
- Recent job and log visibility
- Cron/guard visibility
- Safe API errors when a command requires root or Linux-only tools

The backend can initially wrap `driveguard.sh` commands. Core backup logic can move into Go later after the API surface is stable.

## API Shape

```text
GET  /api/v1/health
GET  /api/v1/status
GET  /api/v1/logs?lines=80
GET  /api/v1/jobs
GET  /api/v1/jobs/{id}
POST /api/v1/jobs/backup
```

The API should default to `127.0.0.1` during development. Public deployment should sit behind a reverse proxy with TLS and authentication.

## Security Notes

- Do not expose DriveGuard on a public interface without authentication.
- Do not return secret values such as archive passwords, database passwords, OAuth tokens, or full `rclone.conf` contents.
- Treat backup, cron, restore, and uninstall actions as privileged operations.
- Keep destructive operations behind explicit confirmation in the UI.

## Build Order

1. Build the Vue console with mocked API fallback so UI work can continue without a running daemon.
2. Add the Go HTTP service with health, status, logs, and job endpoints.
3. Connect the frontend to the Go service through Vite proxy during development.
4. Package the frontend into static assets for the Go service after the API is stable.
