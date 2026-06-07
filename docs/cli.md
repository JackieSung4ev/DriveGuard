# DriveGuard CLI Guide

**Languages:** [English](cli.md) | [中文](zh-CN/cli.md)

Use this guide if you prefer terminal-first backups or want to operate DriveGuard without the Web UI. The CLI is the same backup engine used by the Web UI.

## Quick Start

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

## Common Commands

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
| `sudo dg guard-cron` | Check and start the cron service |
| `sudo dg status` | Show current configuration |
| `sudo dg log 100` | Show recent logs |
| `sudo dg uninstall` | Remove the script and scheduled jobs |

## Cloud Drive Support

The CLI has guided authorization for Google Drive and Microsoft OneDrive:

```bash
sudo dg auth google
sudo dg auth onedrive
```

For other storage providers, choose advanced `rclone config` from `sudo dg auth` and configure any rclone remote that supports basic directory and file operations, such as S3, WebDAV, SFTP, or another rclone backend.

## Key Paths

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

## Related Docs

- [Root README](../README.md) for the Web UI first path.
- [Google Drive rclone setup](google-drive-rclone.md) for remote authorization details.
- [Restore backups](restore-backups.md) for decrypting and restoring `.enc` files.
