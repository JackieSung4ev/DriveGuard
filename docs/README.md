# DriveGuard Wiki

**Languages:** [English](README.md) | [中文](zh-CN/wiki.md)

This folder contains task-oriented DriveGuard documentation. The root README explains the two product paths: Web UI as the default browser workflow and CLI as the independent terminal-first workflow. Detailed setup, authorization, restore, and troubleshooting steps live here.

## Documents

| Document | Use case |
| --- | --- |
| [CentOS Stream 8 + Google Drive setup](initial-setup-centos-google-drive.md) | Install dependencies, configure Google OAuth, set up database connections, and run the first backup |
| [Google Drive rclone setup](google-drive-rclone.md) | Understand Google Drive remotes, `root_folder_id`, authorization tokens, and the default `driveguard` directory |
| [Restore backups](restore-backups.md) | Decrypt `.enc` files, extract website backups, and import MySQL/PostgreSQL dumps |
| [Web UI guide](web-ui.md) | Browser workflow, installer, deployment, Go API boundary, and security notes |
| [CLI guide](cli.md) | Terminal-first install, backup, schedule, logs, restore, and CLI command reference |
| [Chinese docs](zh-CN/wiki.md) | Chinese documentation index |

## Suggested Reading Order

1. First deployment: start with [CentOS Stream 8 + Google Drive setup](initial-setup-centos-google-drive.md).
2. Google Drive details only: read [Google Drive rclone setup](google-drive-rclone.md).
3. Prefer the browser workflow: use the [Web UI guide](web-ui.md).
4. Prefer terminal-first backups: use the [CLI guide](cli.md).
5. Need to restore a downloaded `.enc` file: read [Restore backups](restore-backups.md).

## Documentation Boundary

- README: product-path overview, Web UI quick start, CLI quick start, and common commands.
- Web UI guide: browser workflow, deployment script, API shape, and security boundary.
- CLI guide: terminal-first install, backup, schedule, logs, restore, and command reference.
- Wiki: exact prompts, configuration choices, troubleshooting, and restore steps.
