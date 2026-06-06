<p align="center">
  <img src="../assets/favicon.jpg" alt="DriveGuard favicon" width="48"><br>
  <img src="../assets/logo.png" alt="DriveGuard logo" width="180">
</p>

# DriveGuard

**语言 / Languages:** [中文](README.md) | [English](../../README.md)

英语是项目默认语言。偏好终端方式备份？请阅读 [CLI 指南](cli.md)。

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

想使用纯命令行流程？请阅读 [CLI 指南](cli.md)。

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

## 🧭 Web UI 常用命令

| 命令 | 作用 |
| --- | --- |
| `sudo bash driveguard-web.sh menu` | 打开 Web UI 安装管理菜单 |
| `sudo bash driveguard-web.sh install` | 安装 CLI 包装脚本、Go API 服务和前端 |
| `cd /opt/driveguard-web && sudo bash driveguard-web.sh update` | 拉取 main 分支并更新 CLI、后端和前端 |
| `sudo bash driveguard-web.sh update-backend` | 只重建 Go API 服务并重启 `driveguardd` |
| `sudo bash driveguard-web.sh update-frontend` | 只重建并发布前端 |
| `sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json` | 从 Google OAuth client JSON 配置授权环境 |
| `sudo bash driveguard-web.sh oauth-show` | 查看 OAuth 环境配置，不打印密钥 |
| `sudo bash driveguard-web.sh status` | 检查 API 健康、systemd 状态和 CLI 状态 |
| `sudo bash driveguard-web.sh logs 120` | 查看最近的 `driveguardd` 日志 |
| `sudo bash driveguard-web.sh restart` | 重启后端服务 |
| `sudo bash driveguard-web.sh uninstall` | 移除 Web API 服务和静态前端 |

未设置 `WEB_ROOT` 时，`install`、`update` 和 `update-frontend` 会尝试自动检测当前把 `/api` 代理到 `driveguardd` 的 Nginx/宝塔站点目录。只有需要覆盖自动检测时，才手动传 `WEB_ROOT=/path/to/site`。

## 📚 Wiki

| 文档 | 适用场景 |
| --- | --- |
| [DriveGuard Wiki](wiki.md) | 查看完整文档索引 |
| [CentOS Stream 8 + Google Drive 初始配置](initial-setup-centos-google-drive.md) | 从空服务器配置到首次备份 |
| [Google Drive rclone 初始化配置](google-drive-rclone.md) | Google Drive remote、OAuth、`root_folder_id`、Windows 授权 |
| [恢复备份](restore-backups.md) | 解密 `.enc`、解压网站、导入 MySQL/PostgreSQL |
| [CLI 指南](cli.md) | 终端优先的安装、备份、定时、日志和命令参考 |
| [Web UI 文档](web-ui.md) | Web 控制台、Go API、仓库结构和安全边界 |

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
