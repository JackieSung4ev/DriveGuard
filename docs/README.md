# DriveGuard Wiki

**Languages:** [English](README.md) | [中文](zh-CN/wiki.md)

This folder contains task-oriented DriveGuard documentation. The root README stays focused on the Web UI overview, quick start, and Web UI commands; terminal-first CLI details live in the CLI guide, while detailed setup, authorization, restore, and troubleshooting steps live here.

## Documents

| Document | Use case |
| --- | --- |
| [CentOS Stream 8 + Google Drive setup](initial-setup-centos-google-drive.md) | Install dependencies, configure Google OAuth, set up database connections, and run the first backup |
| [Google Drive rclone setup](google-drive-rclone.md) | Understand Google Drive remotes, `root_folder_id`, authorization tokens, and the `backup` folder |
| [Restore backups](restore-backups.md) | Decrypt `.enc` files, extract website backups, and import MySQL/PostgreSQL dumps |
| [CLI guide](cli.md) | Terminal-first install, backup, schedule, logs, and CLI command reference |
| [Web UI plan](web-ui.md) | Monorepo layout, Vue console scope, Go API boundary, and security notes |
| [Chinese docs](zh-CN/wiki.md) | Chinese documentation index |

## Suggested Reading Order

1. First deployment: start with [CentOS Stream 8 + Google Drive setup](initial-setup-centos-google-drive.md).
2. Google Drive details only: read [Google Drive rclone setup](google-drive-rclone.md).
3. Prefer terminal-first backups: use the [CLI guide](cli.md).
4. Need to restore a downloaded `.enc` file: read [Restore backups](restore-backups.md).
5. Planning or running the next Web UI: read [Web UI plan](web-ui.md).

## Documentation Boundary

- README: what the Web UI is, what it can do, and how to start quickly.
- CLI guide: terminal-first install, backup, schedule, logs, and command reference.
- Wiki: exact prompts, configuration choices, troubleshooting, and restore steps.
