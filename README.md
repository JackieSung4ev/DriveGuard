# DriveGuard

**Languages:** [English](README.md) | [中文](docs/zh-CN/README.md)

![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![Remote](https://img.shields.io/badge/remote-rclone-3F79AD)
![Database](https://img.shields.io/badge/database-MySQL%20%7C%20MariaDB%20%7C%20PostgreSQL-336791)
![Encryption](https://img.shields.io/badge/encryption-AES--256--CBC-blue)
![Schedule](https://img.shields.io/badge/schedule-cron%20%2B%20systemd-lightgrey)

DriveGuard is a standalone Linux backup script for websites and databases. It uses `rclone` to upload encrypted backups to Google Drive, OneDrive, Dropbox, S3, WebDAV, SFTP, or any other compatible remote.

```bash
sudo bash driveguard.sh install
sudo dg menu
```

## ✅ Status

The shell-based version remains the stable command-line version for the current scope: install, dependency checks, encrypted website backups, MySQL/MariaDB/PostgreSQL backups, auto-discovery, scheduled jobs, remote upload, retention cleanup, restore helpers, and self-update.

The next generation Web UI is planned inside this repository as a monorepo: `web/` for the Vue 3 + Vite console, `server/` for the Go API service, and `driveguard.sh` kept as the compatibility entrypoint. The first Web workflow focuses on local account security, Google Drive and Microsoft OneDrive authorization, and scheduled backup plans. Split repositories later only if the Web UI becomes a separate product line.

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

## 🚀 Quick Start

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

## 📚 Documentation

| Document | When to use it |
| --- | --- |
| [DriveGuard Wiki](docs/README.md) | Main documentation index |
| [CentOS Stream 8 + Google Drive setup](docs/initial-setup-centos-google-drive.md) | Full first-time setup from a clean server |
| [Google Drive rclone setup](docs/google-drive-rclone.md) | OAuth, `root_folder_id`, Windows authorization, and `backup` folder behavior |
| [Restore backups](docs/restore-backups.md) | Decrypt `.enc` files, extract websites, and import MySQL/PostgreSQL dumps |
| [Web UI plan](docs/web-ui.md) | Vue 3 + Vite frontend, Go API service, monorepo layout, and security boundary |
| [Chinese docs](docs/zh-CN/wiki.md) | Chinese documentation |

## 🧭 Common Commands

| Command | Purpose |
| --- | --- |
| `sudo dg menu` | Open the interactive menu |
| `sudo dg update` | Pull the latest GitHub version and reinstall |
| `sudo dg install-deps` | Install system dependencies |
| `sudo dg auth` | Choose Google Drive, OneDrive, or advanced `rclone` authorization |
| `sudo dg auth google` / `sudo dg auth onedrive` | Start provider-specific cloud authorization |
| `sudo dg configure` | Configure the remote, password, database connections, and schedule |
| `sudo dg backup` | Run a backup immediately |
| `sudo dg decrypt source.enc output` | Decrypt a backup file |
| `sudo dg cron` | Install or update cron jobs |
| `sudo dg install-guard` | Install the systemd cron guard |
| `sudo dg status` | Show current configuration |
| `sudo dg log 100` | Show recent logs |
| `sudo dg uninstall` | Remove the script and scheduled jobs |

## Web UI Development

The CLI remains the stable production entrypoint. The next Web UI is split into a Vue frontend and a Go API service:

```bash
cd server
go run ./cmd/driveguardd

cd ../web
npm install
npm run dev
```

The Vite dev server proxies `/api` to `http://127.0.0.1:8080`. See [Web UI plan](docs/web-ui.md) for the repository layout and API boundary.

## Web UI Deployment Script

The `feature/web-ui` branch includes a server-side helper for the Web UI product:

```bash
sudo bash driveguard-web.sh --lang zh menu
```

Common commands:

```bash
sudo WEB_ROOT=/www/wwwroot/example.com bash driveguard-web.sh install
sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json
sudo WEB_ROOT=/www/wwwroot/example.com bash driveguard-web.sh update
sudo bash driveguard-web.sh status
```

The script supports English/Chinese menus, dependency checks, system install, update, uninstall, backend-only updates, frontend-only updates, API health checks, and Google OAuth client ID/secret extraction from a Google OAuth client JSON file.

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
