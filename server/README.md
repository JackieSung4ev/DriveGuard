# DriveGuard Go API

Go HTTP API for the DriveGuard Web UI.

```bash
go run ./cmd/driveguardd
```

Environment:

```text
DRIVEGUARD_ADDR=127.0.0.1:8080
DRIVEGUARD_SCRIPT=../driveguard.sh
```

The first API version wraps the existing `driveguard.sh` commands. Run it on the target Linux host with the permissions required by the selected DriveGuard action.

Endpoints:

```text
GET  /api/v1/health
GET  /api/v1/status
GET  /api/v1/logs?lines=80
GET  /api/v1/jobs
GET  /api/v1/jobs/{id}
POST /api/v1/jobs/backup
```
