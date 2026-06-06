<p align="center">
  <img src="../assets/favicon.jpg" alt="DriveGuard favicon" width="48"><br>
  <img src="../assets/logo.png" alt="DriveGuard logo" width="180">
</p>

# DriveGuard

**语言 / Languages:** [中文](README.md) | [English](../../README.md)

英语是项目默认语言。偏好终端方式备份？[CLI 快速开始](#-cli-快速开始) 依然简单并完整支持。

![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![Remote](https://img.shields.io/badge/remote-rclone-3F79AD)
![Database](https://img.shields.io/badge/database-MySQL%20%7C%20MariaDB%20%7C%20PostgreSQL-336791)
![Encryption](https://img.shields.io/badge/encryption-AES--256--CBC-blue)
![Schedule](https://img.shields.io/badge/schedule-cron%20%2B%20systemd-lightgrey)

DriveGuard 是一个面向 Linux 服务器备份管理的 Web UI 项目。控制台可以连接 Google Drive 或 OneDrive、创建定时备份计划、查看运行日志、解密恢复文件，并管理本地账号安全；底层继续复用稳定的 DriveGuard CLI 备份引擎。

## 🚀 Web UI 快速开始

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard-web.sh install
```

服务器上已经安装过？可以一条命令更新 Web UI、后端、CLI 包装脚本和发布后的前端：

```bash
cd /opt/driveguard-web
sudo bash driveguard-web.sh update
```

想使用纯命令行流程？请跳到 [CLI 快速开始](#-cli-快速开始)。

## ✅ 当前状态

Web UI 是这个仓库的主要产品入口：`web/` 是 Vue 3 + Vite 控制台，`server/` 是 Go API 服务，`driveguard-web.sh` 负责安装和更新完整 Web 体验。

脚本版 CLI 仍是稳定的兼容入口，适合偏好终端的用户：安装、配置、加密备份、自动发现、定时任务、云端上传、保留清理、解密恢复和更新脚本都已覆盖。

## ✨ 核心能力

| 图标 | 能力 | 简述 |
| --- | --- | --- |
| ☁️ | 云端目标 | 支持 Google Drive、OneDrive、Dropbox、S3、WebDAV、SFTP 等 `rclone` remote |
| 🌐 | 网站备份 | 每个站点独立打包为 `.tar.gz.enc` |
| 🗄️ | 数据库备份 | 支持 MySQL、MariaDB、PostgreSQL，导出为 `.sql.gz.enc` |
| 🔎 | 自动发现 | 默认扫描常见网站目录和非系统数据库，PostgreSQL 默认 `auto` 检测 |
| 🔐 | 加密 | 使用 OpenSSL AES-256-CBC，未设置密码时不会上传明文 |
| ⏱️ | 定时 | 写入 root crontab，并可安装 systemd timer 守护 cron |
| 🧹 | 保留 | 每个站点、每个数据库分别保留指定份数 |
| 🧭 | 管理 | 中文菜单和命令行子命令都可用 |

## 🚀 CLI 快速开始

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

## 📚 Wiki

| 文档 | 适用场景 |
| --- | --- |
| [DriveGuard Wiki](wiki.md) | 查看完整文档索引 |
| [CentOS Stream 8 + Google Drive 初始配置](initial-setup-centos-google-drive.md) | 从空服务器配置到首次备份 |
| [Google Drive rclone 初始化配置](google-drive-rclone.md) | Google Drive remote、OAuth、`root_folder_id`、Windows 授权 |
| [恢复备份](restore-backups.md) | 解密 `.enc`、解压网站、导入 MySQL/PostgreSQL |

## 🧭 常用命令

| 命令 | 作用 |
| --- | --- |
| `sudo dg menu` | 打开中文菜单 |
| `sudo dg update` | 从 GitHub 拉取并更新脚本 |
| `sudo dg install-deps` | 安装系统依赖 |
| `sudo dg auth` | 选择 Google Drive、OneDrive 或高级 `rclone` 授权 |
| `sudo dg auth google` / `sudo dg auth onedrive` | 直接进入指定云盘的授权流程 |
| `sudo dg configure` | 配置 remote、密码、数据库连接和定时参数 |
| `sudo dg backup` | 立即执行一次备份 |
| `sudo dg decrypt 源.enc 输出文件` | 解密备份文件 |
| `sudo dg cron` | 安装或更新 cron 定时任务 |
| `sudo dg install-guard` | 安装 systemd cron 守护 |
| `sudo dg status` | 查看当前配置 |
| `sudo dg log 100` | 查看最近日志 |
| `sudo dg uninstall` | 卸载脚本和定时任务 |

## 📁 关键路径

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

## 🔒 安全提醒

- 不要提交 `/etc/driveguard`、`rclone.conf`、OAuth token、数据库密码或加密密码。
- 备份密码请离线保存，丢失后 `.enc` 文件无法恢复。
- 建议给备份使用单独云端账号、bucket 或文件夹。
- 建议定期抽样下载备份，测试解密、解压和数据库导入。
