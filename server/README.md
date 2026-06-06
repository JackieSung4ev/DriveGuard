# DriveGuard Go API

Go HTTP API for the DriveGuard Web UI.

```bash
go run ./cmd/driveguardd
```

Environment:

```text
DRIVEGUARD_ADDR=127.0.0.1:8080
DRIVEGUARD_SCRIPT=../driveguard.sh
DRIVEGUARD_AUTH_FILE=/etc/driveguard/web-auth.json
DRIVEGUARD_PUBLIC_URL=https://backup.example.com
DRIVEGUARD_GOOGLE_CLIENT_ID=your-google-oauth-client-id
DRIVEGUARD_GOOGLE_CLIENT_SECRET=your-google-oauth-client-secret
DRIVEGUARD_GOOGLE_REMOTE=gdrive
DRIVEGUARD_GOOGLE_SCOPE=drive.file
```

`DRIVEGUARD_AUTH_FILE` defaults to `/etc/driveguard/web-auth.json` on Linux/macOS and `driveguard-auth.json` on Windows development machines.

For direct Google Drive Web OAuth, create or reuse a Google OAuth **Web application** client and add this authorized redirect URI:

```text
${DRIVEGUARD_PUBLIC_URL}/api/v1/cloud/google/callback
```

If the Google client is not configured, the Web UI falls back to the CLI `sudo dg auth google` flow.

The first API version wraps the existing `driveguard.sh` commands. Run it on the target Linux host with the permissions required by the selected DriveGuard action.

Endpoints:

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
