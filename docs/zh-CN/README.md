<p align="center">
  <img src="../assets/logo.png" alt="DriveGuard" width="220">
</p>

# DriveGuard

**语言 / Languages:** [中文](README.md) | [English](../../README.md)

英语是项目默认语言。DriveGuard 是一个 Web UI 优先的 Linux 服务器备份系统，同时保留独立 CLI，适合偏好纯终端的用户。两种入口共用同一套加密备份引擎，可备份网站、MySQL/MariaDB 和 PostgreSQL，并把加密文件上传到兼容 `rclone` 的云端存储。

![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![Remote](https://img.shields.io/badge/remote-rclone-3F79AD)
![Database](https://img.shields.io/badge/database-MySQL%20%7C%20MariaDB%20%7C%20PostgreSQL-336791)
![Encryption](https://img.shields.io/badge/encryption-AES--256--CBC-blue)
![Schedule](https://img.shields.io/badge/schedule-cron%20%2B%20systemd-lightgrey)

## 产品入口

| 入口 | 适合场景 | 入口脚本 | 文档 |
| --- | --- | --- | --- |
| Web UI（默认） | 在浏览器里管理备份计划、云端授权、运行日志、恢复操作和账号安全 | `driveguard-web.sh` | [Web UI 指南](web-ui.md) |
| CLI | 只通过 SSH 操作、自动化脚本、最小化安装和终端优先的备份流程 | `driveguard.sh` / `dg` | [CLI 指南](cli.md) |

## Web UI

如果你希望用控制台管理 DriveGuard，优先使用 Web UI。它会安装 Go API 服务、发布 Vue 前端、保留 CLI 备份引擎，并提供接近服务器面板插件的完整操作体验。

### 安装

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard-web.sh install
```

### 更新

如果服务器上已经安装过 DriveGuard Web UI，以后更新就运行：

```bash
cd /opt/driveguard-web
sudo bash driveguard-web.sh update
```

未设置 `WEB_ROOT` 时，`install`、`update` 和 `update-frontend` 会自动检测当前把 `/api` 代理到 `driveguardd` 的 Nginx/服务器面板站点目录。只有需要覆盖自动检测结果时，才手动传入 `WEB_ROOT=/path/to/site`。

### Web UI 常用命令

| 命令 | 作用 |
| --- | --- |
| `sudo bash driveguard-web.sh menu` | 打开 Web UI 管理菜单 |
| `sudo bash driveguard-web.sh install` | 安装 CLI 引擎、Go API 服务、systemd 服务和前端 |
| `cd /opt/driveguard-web && sudo bash driveguard-web.sh update` | 拉取 `main` 并更新 CLI、后端和前端 |
| `sudo bash driveguard-web.sh update-backend` | 只重建 Go API 服务并重启 `driveguardd` |
| `sudo bash driveguard-web.sh update-frontend` | 只重建并发布前端 |
| `sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json` | 从 Google OAuth client JSON 配置授权环境 |
| `sudo bash driveguard-web.sh oauth-show` | 查看 OAuth 配置，不打印密钥 |
| `sudo bash driveguard-web.sh status` | 检查 API 健康、systemd 状态和当前 DriveGuard 配置 |
| `sudo bash driveguard-web.sh logs 120` | 查看最近的 `driveguardd` 日志 |
| `sudo bash driveguard-web.sh restart` | 重启后端服务 |
| `sudo bash driveguard-web.sh uninstall` | 移除 Web API 服务和静态前端 |

## CLI

如果你偏好纯命令行，或者服务器不需要 Web UI 服务，可以单独使用 CLI。CLI 能安装依赖、授权云端、配置备份范围、立即备份、安装 cron、查看日志、解密文件和恢复备份。

### 快速开始

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard.sh install
sudo dg install-deps
sudo dg auth google
sudo dg configure
sudo dg backup
```

确认手动备份成功后，再启用定时任务：

```bash
sudo dg cron
sudo dg install-guard
```

### CLI 常用命令

| 命令 | 作用 |
| --- | --- |
| `sudo dg menu` | 打开 CLI 交互菜单 |
| `sudo dg update` | 从 GitHub 拉取最新版并重新安装 CLI |
| `sudo dg install-deps` | 安装系统依赖 |
| `sudo dg auth` | 选择 Google Drive、OneDrive 或高级 `rclone` 授权 |
| `sudo dg configure` | 配置 remote、加密密码、数据库访问和定时任务 |
| `sudo dg backup` | 立即执行一次备份 |
| `sudo dg cron` | 安装或更新 cron 定时任务 |
| `sudo dg status` | 查看当前配置 |
| `sudo dg log 100` | 查看最近日志 |
| `sudo dg decrypt source.enc output` | 解密备份文件 |
| `sudo dg uninstall` | 移除 CLI 脚本和定时任务 |

完整命令说明和终端恢复流程见 [CLI 指南](cli.md)。

## 备份模型

DriveGuard 会先在服务器本地加密，再上传到云端。网站会打包为 `.tar.gz.enc`；MySQL/MariaDB/PostgreSQL 会导出为 `.sql.gz.enc`。默认云端目录结构如下：

```text
remote:driveguard/site/
remote:driveguard/database/
remote:driveguard/database/postgresql/
```

关键本地路径：

```text
/etc/driveguard/config.conf
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
/etc/driveguard/postgres.pgpass
/var/backups/driveguard
/var/log/driveguard
```

## 本地开发

本地开发时，Go API 服务和 Vue 前端分开运行：

```bash
cd server
go run ./cmd/driveguardd

cd ../web
npm install
npm run dev
```

Vite 开发服务器会把 `/api` 代理到 `http://127.0.0.1:8080`。如果只想预览界面、不启动 Go API，可以在 `web/` 目录运行 `npm run dev:mock`。

## 文档

| 文档 | 适用场景 |
| --- | --- |
| [中文文档索引](wiki.md) | 查看完整中文文档 |
| [Web UI 指南](web-ui.md) | Web UI 架构、安装脚本、部署、API 边界和安全说明 |
| [CLI 指南](cli.md) | 终端优先的安装、备份、定时、日志、恢复和命令参考 |
| [CentOS Stream 8 + Google Drive 初始配置](initial-setup-centos-google-drive.md) | 从空服务器配置到首次备份 |
| [Google Drive rclone 配置](google-drive-rclone.md) | OAuth、`root_folder_id`、Windows 授权和云端目录行为 |
| [恢复备份](restore-backups.md) | 解密 `.enc` 文件、恢复网站并导入 MySQL/PostgreSQL |

## 安全提醒

- 不要提交 `/etc/driveguard`、`rclone.conf`、OAuth token、数据库密码或加密密码。
- 备份密码请离线保存；丢失后 `.enc` 文件无法恢复。
- 建议给备份使用单独的云端账号、bucket 或文件夹。
- 建议定期下载样本备份，测试解密、解压和数据库导入。
