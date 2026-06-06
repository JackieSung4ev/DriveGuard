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

## Scheduled Plans

`POST /api/v1/backup-plans` now has a real enable path. When the request sends `enabled: true`, the API updates the existing DriveGuard CLI config and runs the stable CLI commands:

```text
dg cron
dg install-guard
```

The Web UI currently controls the same single global schedule used by the CLI. Saving and enabling a Web plan updates `RCLONE_REMOTE`, `RCLONE_REMOTE_PATH`, `KEEP_COPIES`, `CRON_EXPR`, and `ENABLE_CRON_GUARD` in the CLI config file, then installs the root crontab entry and the systemd cron guard timer.

Because those actions write `/etc/driveguard`, root crontab, and `/etc/systemd/system`, run `driveguardd` as a privileged service on production hosts.

## Systemd Process Guard

A production unit template is available at `server/deploy/driveguardd.service`.

```bash
sudo install -m 0755 /opt/driveguard-web/server/driveguardd /usr/local/bin/driveguardd
sudo install -m 0644 /opt/driveguard-web/server/deploy/driveguardd.service /etc/systemd/system/driveguardd.service
sudo install -d -m 0700 /etc/driveguard
sudo touch /etc/driveguard/driveguardd.env
sudo chmod 600 /etc/driveguard/driveguardd.env
sudo systemctl daemon-reload
sudo systemctl enable --now driveguardd
sudo systemctl status driveguardd
```

Put deployment-specific values and OAuth secrets in `/etc/driveguard/driveguardd.env`, for example:

```text
DRIVEGUARD_PUBLIC_URL=https://backup.example.com
DRIVEGUARD_GOOGLE_CLIENT_ID=your-google-oauth-client-id
DRIVEGUARD_GOOGLE_CLIENT_SECRET=your-google-oauth-client-secret
DRIVEGUARD_GOOGLE_REMOTE=gdrive
DRIVEGUARD_GOOGLE_SCOPE=drive.file
```

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
