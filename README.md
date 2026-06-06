<p align="center">
  <img src="docs/assets/logo.png" alt="DriveGuard" width="220">
</p>

# DriveGuard

**Languages:** [English](README.md) | [中文](docs/zh-CN/README.md)

English is the default project language. DriveGuard is a Web UI-first backup system for Linux servers, with an independent CLI for terminal-first operation. Both product paths use the same encrypted backup engine for websites, MySQL/MariaDB, and PostgreSQL, then upload encrypted files to rclone-compatible cloud storage.

![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![Remote](https://img.shields.io/badge/remote-rclone-3F79AD)
![Database](https://img.shields.io/badge/database-MySQL%20%7C%20MariaDB%20%7C%20PostgreSQL-336791)
![Encryption](https://img.shields.io/badge/encryption-AES--256--CBC-blue)
![Schedule](https://img.shields.io/badge/schedule-cron%20%2B%20systemd-lightgrey)

## Product Paths

| Path | Best for | Entry point | Guide |
| --- | --- | --- | --- |
| Web UI (default) | Browser-based backup plans, cloud authorization, logs, restore actions, and account security | `driveguard-web.sh` | [Web UI guide](docs/web-ui.md) |
| CLI | SSH-only servers, automation, minimal installations, and terminal-first backups | `driveguard.sh` / `dg` | [CLI guide](docs/cli.md) |

## Web UI

Use the Web UI when you want the DriveGuard console as the main operating surface. It installs the Go API service, publishes the Vue frontend, keeps the CLI backup engine available, and manages the full server-panel workflow from a browser.

### Install

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard-web.sh install
```

### Update

If DriveGuard Web UI is already installed on a server, update it from the installed source directory:

```bash
cd /opt/driveguard-web
sudo bash driveguard-web.sh update
```

`install`, `update`, and `update-frontend` auto-detect the active Nginx/server-panel site root that proxies `/api` to `driveguardd` when `WEB_ROOT` is not set. Use `WEB_ROOT=/path/to/site` only when you need to override that detection.

### Common Web UI Commands

| Command | Purpose |
| --- | --- |
| `sudo bash driveguard-web.sh menu` | Open the interactive Web UI management menu |
| `sudo bash driveguard-web.sh install` | Install the CLI engine, Go API service, systemd unit, and frontend |
| `cd /opt/driveguard-web && sudo bash driveguard-web.sh update` | Pull `main` and update CLI, backend, and frontend |
| `sudo bash driveguard-web.sh update-backend` | Rebuild the Go API service and restart `driveguardd` |
| `sudo bash driveguard-web.sh update-frontend` | Rebuild and publish the frontend only |
| `sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json` | Configure Google OAuth from a client JSON file |
| `sudo bash driveguard-web.sh oauth-show` | Show OAuth settings without printing the secret |
| `sudo bash driveguard-web.sh status` | Check API health, systemd state, and current DriveGuard configuration |
| `sudo bash driveguard-web.sh logs 120` | Show recent `driveguardd` journal logs |
| `sudo bash driveguard-web.sh restart` | Restart the backend service |
| `sudo bash driveguard-web.sh uninstall` | Remove the Web API service and static frontend |

## CLI

Use the CLI when you prefer a terminal-only workflow or want DriveGuard without the Web UI service. The CLI can install dependencies, authorize cloud storage, configure backup scope, run backups, install cron, inspect logs, decrypt files, and restore backups.

### Quick Start

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard.sh install
sudo dg install-deps
sudo dg auth google
sudo dg configure
sudo dg backup
```

Enable scheduled backups only after a manual backup succeeds:

```bash
sudo dg cron
sudo dg install-guard
```

### Common CLI Commands

| Command | Purpose |
| --- | --- |
| `sudo dg menu` | Open the interactive CLI menu |
| `sudo dg update` | Pull the latest GitHub version and reinstall the CLI |
| `sudo dg install-deps` | Install system dependencies |
| `sudo dg auth` | Choose Google Drive, OneDrive, or advanced `rclone` authorization |
| `sudo dg configure` | Configure remote storage, encryption password, database access, and schedule |
| `sudo dg backup` | Run a backup immediately |
| `sudo dg cron` | Install or update cron jobs |
| `sudo dg status` | Show the current configuration |
| `sudo dg log 100` | Show recent DriveGuard logs |
| `sudo dg decrypt source.enc output` | Decrypt a backup file |
| `sudo dg uninstall` | Remove the CLI script and scheduled jobs |

See the [CLI guide](docs/cli.md) for the full command reference and terminal-first restore flow.

## Backup Model

DriveGuard encrypts backups before upload. Website archives are stored as `.tar.gz.enc`; MySQL/MariaDB/PostgreSQL dumps are stored as `.sql.gz.enc`. By default, cloud backups are organized under the configured remote directory:

```text
remote:driveguard/site/
remote:driveguard/database/
remote:driveguard/database/postgresql/
```

Important local paths:

```text
/etc/driveguard/config.conf
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
/etc/driveguard/postgres.pgpass
/var/backups/driveguard
/var/log/driveguard
```

## Local Development

Run the Go API service and Vue frontend separately:

```bash
cd server
go run ./cmd/driveguardd

cd ../web
npm install
npm run dev
```

The Vite dev server proxies `/api` to `http://127.0.0.1:8080`. To preview the UI without starting the Go API, run `npm run dev:mock` in `web/`.

## Documentation

| Document | When to use it |
| --- | --- |
| [Documentation index](docs/README.md) | Main wiki-style documentation index |
| [Web UI guide](docs/web-ui.md) | Web UI architecture, installer, deployment, API boundary, and security notes |
| [CLI guide](docs/cli.md) | Terminal-first install, backup, schedule, logs, restore, and command reference |
| [CentOS Stream 8 + Google Drive setup](docs/initial-setup-centos-google-drive.md) | Full first-time setup from a clean server |
| [Google Drive rclone setup](docs/google-drive-rclone.md) | OAuth, `root_folder_id`, Windows authorization, and Drive folder behavior |
| [Restore backups](docs/restore-backups.md) | Decrypt `.enc` files, extract websites, and import MySQL/PostgreSQL dumps |
| [Chinese docs](docs/zh-CN/wiki.md) | Chinese documentation |

## Security Notes

- Do not commit `/etc/driveguard`, `rclone.conf`, OAuth tokens, database passwords, or encryption passwords.
- Store the backup password offline. Encrypted `.enc` files cannot be restored without it.
- Prefer a dedicated cloud account, bucket, or folder for backups.
- Periodically download a sample backup and test decryption, extraction, and database import.
