# DriveGuard

![Shell](https://img.shields.io/badge/shell-bash-4EAA25)
![Remote](https://img.shields.io/badge/remote-rclone-3F79AD)
![Encryption](https://img.shields.io/badge/encryption-AES--256--CBC-blue)
![Cron](https://img.shields.io/badge/schedule-cron%20%2B%20systemd-lightgrey)

DriveGuard 是一个面向 Linux 服务器的独立云端备份脚本。它通过 `rclone` 连接任意兼容的云盘、对象存储或远程文件系统，并把网站目录、MySQL/MariaDB 数据库加密后定时上传。

```bash
sudo bash driveguard.sh install
sudo dg menu
```

## 能做什么

| 能力 | 说明 |
| --- | --- |
| 云端目标 | 支持满足基础文件操作的 `rclone` remote，例如 Google Drive、OneDrive、Dropbox、S3、WebDAV、SFTP |
| 网站备份 | 每个站点单独打包成 `.tar.gz.enc` |
| 数据库备份 | 每个数据库单独导出成 `.sql.gz.enc` |
| 自动发现 | 立即备份默认扫描常见网站目录，并查询所有非系统数据库 |
| 加密 | 使用 `openssl aes-256-cbc`，未设置密码时不会上传明文 |
| 定时 | 写入 root crontab，并可安装 systemd timer 守护 cron |
| 保留策略 | 每个站点、每个数据库分别保留指定份数 |
| 管理方式 | 中文交互菜单，也支持命令行子命令 |

## 快速开始

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard.sh install
```

Debian/Ubuntu、CentOS/RHEL 系可以自动安装依赖：

```bash
sudo dg install-deps
```

CentOS/RHEL 系会安装 `git`、`cronie`、`openssl`、`tar`、`gzip`、`util-linux`、`curl`、`unzip` 和 MariaDB 客户端；如果系统源没有 `rclone`，会自动改用 rclone 官方安装脚本。实战步骤见 [CentOS Stream 8 + Google Drive 初始配置](docs/initial-setup-centos-google-drive.md)。

首次配置：

```bash
sudo dg auth
sudo dg configure
sudo dg menu
sudo dg backup
```

确认手动备份成功后再启用定时：

```bash
sudo dg cron
sudo dg install-guard
```

## 文档导航

| 文档 | 你会用到它的时机 |
| --- | --- |
| [DriveGuard Wiki](docs/README.md) | 查看所有场景化文档 |
| [初始配置实战：CentOS Stream 8 + Google Drive](docs/initial-setup-centos-google-drive.md) | 从空服务器一路配置到 `gdrive:backup/site/` 和 `gdrive:backup/database/` |
| [Google Drive rclone 初始化配置](docs/google-drive-rclone.md) | 理解 Google OAuth、`root_folder_id`、Windows 授权和 `backup` 文件夹 |
| [恢复备份](docs/restore-backups.md) | 解密 `.enc` 文件，再解压网站或导入数据库 |

## 备份路径

DriveGuard 默认 remote 名称是 `cloud`，云端目录是 `driveguard`：

```text
cloud:driveguard/site/站点名/
cloud:driveguard/database/数据库名/
```

如果你把 remote 配成 `gdrive`，并在 `dg configure` 里把云端远程目录填成 `backup`，最终会写到：

```text
gdrive:backup/site/站点名/
gdrive:backup/database/数据库名/
```

## 自动发现

`sudo dg backup` 默认会自动发现：

- 网站目录：`/www/wwwroot /var/www /srv/www /usr/share/nginx/html`
- 数据库：MySQL/MariaDB 中除 `information_schema`、`mysql`、`performance_schema`、`sys` 外的数据库

`/etc/driveguard/sites.list` 和 `/etc/driveguard/databases.list` 仍然可用，用来补充特殊网站路径、设置排除项，或显式指定数据库。

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `sudo dg menu` | 打开中文菜单 |
| `sudo dg update` | 从 GitHub 拉取并更新脚本 |
| `sudo dg auth` | 配置或检查 rclone remote |
| `sudo dg configure` | 配置 remote、远程目录、保留份数、密码和 MySQL |
| `sudo dg backup` | 立即执行一次备份 |
| `sudo dg decrypt 源.enc 输出文件` | 解密备份文件，恢复前必须先做这一步 |
| `sudo dg cron` | 安装或更新 cron 定时任务 |
| `sudo dg install-guard` | 安装 systemd cron 守护 |
| `sudo dg status` | 查看当前配置 |
| `sudo dg log 100` | 查看最近日志 |
| `sudo dg uninstall` | 卸载脚本和定时任务 |

## 配置文件

```text
/etc/driveguard/config.conf
/etc/driveguard/sites.list
/etc/driveguard/databases.list
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
```

本地备份、状态和日志默认在：

```text
/var/backups/driveguard
/var/lib/driveguard
/var/log/driveguard
```

## 列表格式

网站列表 `/etc/driveguard/sites.list`：

```text
站点名称|站点目录|排除项
example.com|/var/www/example.com|.git,cache,logs
```

数据库列表 `/etc/driveguard/databases.list`：

```text
example_db
blog_db
```

## 安全约定

- 不要提交 `/etc/driveguard`、`rclone.conf`、OAuth token、数据库密码或加密密码。
- 备份密码请离线保存，丢失后 `.enc` 文件无法恢复。
- 建议给备份使用单独云端账号、bucket 或文件夹。
- 建议定期下载一个备份包，测试解密、解压和数据库导入。

## 验证和排障

```bash
bash -n driveguard.sh
bash driveguard.sh help
rclone lsd cloud:
sudo dg status
sudo dg log 200
```

常见问题：

| 问题 | 处理 |
| --- | --- |
| `未找到 rclone` | 先安装 rclone，再执行 `sudo dg auth` |
| `rclone remote 不存在` | remote 名称和 `sudo dg configure` 里的名称不一致 |
| `未设置备份加密密码` | 执行 `sudo dg configure` 并设置密码 |
| `未配置 MySQL 连接信息` | 只备份网站可忽略；备份数据库需配置 MySQL |
| `PROCESS privilege` / `dump tablespaces` | 新版脚本会自动对支持的 dump 工具加 `--no-tablespaces`，更新后重试 |
| 上传失败 | 看 `/var/log/driveguard/rclone.log`，并单独测试 `rclone lsd remote:` |

## 卸载

```bash
sudo dg uninstall
```

卸载会移除脚本、cron 和 systemd timer，但不会删除云端已上传的备份。本地配置、日志和备份目录会逐项询问后再删除。
