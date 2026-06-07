# DriveGuard CLI 指南

**语言 / Languages:** [中文](cli.md) | [English](../cli.md)

如果你偏好终端方式备份，或者想在没有 Web UI 的服务器上运行 DriveGuard，请使用这份指南。CLI 也是 Web UI 底层复用的备份引擎。

## 快速开始

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard.sh install
sudo dg install-deps
sudo dg auth google
sudo dg configure
sudo dg backup
```

确认手动备份成功后再启用定时：

```bash
sudo dg cron
sudo dg install-guard
```

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `sudo dg menu` | 打开交互菜单 |
| `sudo dg update` | 从 GitHub 拉取并更新脚本 |
| `sudo dg install-deps` | 安装系统依赖 |
| `sudo dg auth` | 选择 Google Drive、OneDrive 或高级 `rclone` 授权 |
| `sudo dg auth google` / `sudo dg auth onedrive` | 直接进入指定云盘的授权流程 |
| `sudo dg configure` | 配置 remote、密码、数据库连接和定时参数 |
| `sudo dg backup` | 立即执行一次备份 |
| `sudo dg decrypt 源.enc 输出文件` | 解密备份文件 |
| `sudo dg cron` | 安装或更新 cron 定时任务 |
| `sudo dg install-guard` | 安装 systemd cron 守护 |
| `sudo dg guard-cron` | 检查并启动 cron 服务 |
| `sudo dg status` | 查看当前配置 |
| `sudo dg log 100` | 查看最近日志 |
| `sudo dg uninstall` | 卸载脚本和定时任务 |

## 云盘支持

CLI 已提供 Google Drive 和 Microsoft OneDrive 的引导式授权：

```bash
sudo dg auth google
sudo dg auth onedrive
```

其他云端存储可以在 `sudo dg auth` 中选择高级 `rclone config`，配置任何支持基础目录和文件操作的 rclone remote，例如 S3、WebDAV、SFTP 或其他 rclone backend。

## 关键路径

```text
/etc/driveguard/config.conf
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
/etc/driveguard/postgres.pgpass
/var/backups/driveguard
/var/log/driveguard
```

云端默认结构：

```text
remote:driveguard/site/
remote:driveguard/database/
remote:driveguard/database/postgresql/
```

## 相关文档

- [根 README](../../README.md)：Web UI 优先的安装和更新入口。
- [Google Drive rclone 初始化配置](google-drive-rclone.md)：云端 remote 和授权细节。
- [恢复备份](restore-backups.md)：解密并恢复 `.enc` 文件。
