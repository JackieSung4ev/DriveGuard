# DriveGuard Wiki

**Languages:** [English](README.md) | [中文](zh-CN/wiki.md)

This folder contains task-oriented DriveGuard documentation. The root README stays focused on the project overview, quick start, and common commands; detailed setup, authorization, restore, and troubleshooting steps live here.

## Documents

| Document | Use case |
| --- | --- |
| [CentOS Stream 8 + Google Drive setup](initial-setup-centos-google-drive.md) | Install dependencies, configure Google OAuth, set up database connections, and run the first backup |
| [Google Drive rclone setup](google-drive-rclone.md) | Understand Google Drive remotes, `root_folder_id`, authorization tokens, and the `backup` folder |
| [Restore backups](restore-backups.md) | Decrypt `.enc` files, extract website backups, and import MySQL/PostgreSQL dumps |
| [Web UI plan](web-ui.md) | Monorepo layout, Vue console scope, Go API boundary, and security notes |
| [Chinese docs](zh-CN/wiki.md) | Chinese documentation index |

## Suggested Reading Order

1. First deployment: start with [CentOS Stream 8 + Google Drive setup](initial-setup-centos-google-drive.md).
2. Google Drive details only: read [Google Drive rclone setup](google-drive-rclone.md).
3. Already have a working remote: go back to the [root README](../README.md), then run `dg configure` and `dg backup`.
4. Need to restore a downloaded `.enc` file: read [Restore backups](restore-backups.md).
5. Planning or running the next Web UI: read [Web UI plan](web-ui.md).

## Documentation Boundary

- README: what DriveGuard is, what it can do, and how to start quickly.
- Wiki: exact prompts, configuration choices, troubleshooting, and restore steps.
