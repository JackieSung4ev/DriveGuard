<p align="center">
  <img src="docs/assets/logo.png" alt="DriveGuard logo" width="180">
</p>

# DriveGuard

**Languages:** [English](README.md) | [中文](docs/zh-CN/README.md)

English is the default project language. Prefer terminal-first backups? Read the [CLI guide](docs/cli.md).

![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![Remote](https://img.shields.io/badge/remote-rclone-3F79AD)
![Database](https://img.shields.io/badge/database-MySQL%20%7C%20MariaDB%20%7C%20PostgreSQL-336791)
![Encryption](https://img.shields.io/badge/encryption-AES--256--CBC-blue)
![Schedule](https://img.shields.io/badge/schedule-cron%20%2B%20systemd-lightgrey)

DriveGuard is a Web UI project for managing encrypted Linux website and database backups. The console helps you connect Google Drive or OneDrive, create scheduled backup plans, inspect run logs, restore encrypted files, and manage local account security while reusing the proven DriveGuard CLI engine under the hood.

## 🚀 Web UI Quick Start

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard-web.sh install
```

Already installed on a server? Pull the latest Web UI, backend, CLI wrapper, and published frontend:

```bash
cd /opt/driveguard-web
sudo bash driveguard-web.sh update
```

Prefer a pure command-line workflow? Read the [CLI guide](docs/cli.md).

## ✅ Status

The Web UI is the main product surface in this repository: `web/` contains the Vue 3 + Vite console, `server/` contains the Go API service, and `driveguard-web.sh` installs and updates the full Web experience.

The shell-based CLI remains the stable compatibility entrypoint for terminal users: install, dependency checks, encrypted website backups, MySQL/MariaDB/PostgreSQL backups, auto-discovery, scheduled jobs, remote upload, retention cleanup, restore helpers, and self-update.

## ✨ Features

| Icon | Feature | Summary |
| --- | --- | --- |
| ☁️ | Remote storage | Works with Google Drive, OneDrive, Dropbox, S3, WebDAV, SFTP, and other `rclone` remotes |
| 🌐 | Website backup | Archives each site as `.tar.gz.enc` |
| 🗄️ | Database backup | Supports MySQL, MariaDB, and PostgreSQL as `.sql.gz.enc` |
| 🔎 | Auto-discovery | Finds common website roots and non-system databases; PostgreSQL uses `auto` detection by default |
| 🔐 | Encryption | Uses OpenSSL AES-256-CBC; plaintext is not uploaded |
| ⏱️ | Scheduling | Installs root crontab entries and an optional systemd cron guard |
| 🧹 | Retention | Keeps a configurable number of backups per site/database |
| 🧭 | Management | Provides both a command-line interface and an interactive menu |

## 🧭 Web UI Common Commands

| Command | Purpose |
| --- | --- |
| `sudo bash driveguard-web.sh menu` | Open the interactive Web UI installer menu |
| `sudo bash driveguard-web.sh install` | Install the CLI wrapper, Go API service, and frontend |
| `cd /opt/driveguard-web && sudo bash driveguard-web.sh update` | Pull the latest main branch and update CLI, backend, and frontend |
| `sudo bash driveguard-web.sh update-backend` | Rebuild the Go API service and restart `driveguardd` |
| `sudo bash driveguard-web.sh update-frontend` | Rebuild and publish the frontend only |
| `sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json` | Configure Google OAuth from a client JSON file |
| `sudo bash driveguard-web.sh oauth-show` | Show OAuth environment values without printing the secret |
| `sudo bash driveguard-web.sh status` | Check API health, systemd state, and CLI status |
| `sudo bash driveguard-web.sh logs 120` | Show recent `driveguardd` journal logs |
| `sudo bash driveguard-web.sh restart` | Restart the backend service |
| `sudo bash driveguard-web.sh uninstall` | Remove the Web API service and static frontend |

When `WEB_ROOT` is not set, `install`, `update`, and `update-frontend` try to detect the active Nginx/server-panel site root that proxies `/api` to `driveguardd`. Set `WEB_ROOT=/path/to/site` only when you want to override that detection.

## 📚 Documentation

| Document | When to use it |
| --- | --- |
| [DriveGuard Wiki](docs/README.md) | Main documentation index |
| [CentOS Stream 8 + Google Drive setup](docs/initial-setup-centos-google-drive.md) | Full first-time setup from a clean server |
| [Google Drive rclone setup](docs/google-drive-rclone.md) | OAuth, `root_folder_id`, Windows authorization, and `backup` folder behavior |
| [Restore backups](docs/restore-backups.md) | Decrypt `.enc` files, extract websites, and import MySQL/PostgreSQL dumps |
| [CLI guide](docs/cli.md) | Terminal-first install, backup, schedule, logs, and CLI command reference |
| [Web UI plan](docs/web-ui.md) | Vue 3 + Vite frontend, Go API service, monorepo layout, and security boundary |
| [Chinese docs](docs/zh-CN/wiki.md) | Chinese documentation |

## Web UI Development

For local development, run the Go API service and the Vue frontend separately:

```bash
cd server
go run ./cmd/driveguardd

cd ../web
npm install
npm run dev
```

The Vite dev server proxies `/api` to `http://127.0.0.1:8080`. If you only want to preview the UI without starting the Go API, run `npm run dev:mock` in `web/`. See [Web UI plan](docs/web-ui.md) for the repository layout and API boundary.

## Web UI Deployment Script

The main branch includes a server-side helper for the Web UI product:

```bash
sudo bash driveguard-web.sh --lang zh menu
```

The script supports English/Chinese menus, dependency checks, system install, update, uninstall, backend-only updates, frontend-only updates, API health checks, and Google OAuth client ID/secret extraction from a Google OAuth client JSON file. See [Web UI Common Commands](#web-ui-common-commands) for daily operations.

## 📁 Key Paths

```text
/etc/driveguard/config.conf
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
/etc/driveguard/postgres.pgpass
/var/backups/driveguard
/var/log/driveguard
```

Default remote layout:

```text
remote:driveguard/site/
remote:driveguard/database/
remote:driveguard/database/postgresql/
```

## 🌐 Language

English is the default language for the project and documentation. Chinese documentation is maintained under [docs/zh-CN](docs/zh-CN/wiki.md).

## 🔒 Security Notes

- Do not commit `/etc/driveguard`, `rclone.conf`, OAuth tokens, database passwords, or encryption passwords.
- Store the backup password offline. Encrypted `.enc` files cannot be restored without it.
- Prefer a dedicated cloud account, bucket, or folder for backups.
- Periodically download a sample backup and test decryption, extraction, and database import.
