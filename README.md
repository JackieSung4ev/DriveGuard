# DriveGuard

DriveGuard 是一个面向 Linux 服务器的独立云端备份脚本。它通过 `rclone` 连接任意兼容的云盘、对象存储或远程文件系统，例如 Google Drive、OneDrive、S3、WebDAV、SFTP，并通过中文交互菜单配置网站目录备份、MySQL/MariaDB 数据库备份、加密、定时任务、日志、保留份数清理和 cron 守护。

项目入口脚本：

```text
driveguard.sh
```

安装短命令后可以直接使用：

```bash
sudo driveguard menu
sudo dg backup
```

## 功能

- Debian/Ubuntu 依赖自动安装。
- 中文菜单管理配置、授权、备份列表、定时任务和卸载。
- 使用 `rclone` 完成云盘 remote 授权和上传。
- 支持任意满足基础文件操作的 `rclone` remote，例如 Google Drive、OneDrive、Dropbox、S3 兼容对象存储、WebDAV、SFTP。
- 手动维护网站目录和数据库列表。
- 网站备份为 `.tar.gz.enc`。
- 数据库备份为 `.sql.gz.enc`。
- 使用 `openssl aes-256-cbc` 加密备份包。
- 支持 cron 定时备份。
- 支持 systemd timer 守护 cron。
- 支持设置每个网站/数据库保留份数，并自动清理更多旧备份。
- 支持主日志、rclone 日志和 cron 输出日志。
- 支持卸载脚本、定时任务和守护服务，并可选择是否保留本地配置、日志和备份。

## 系统要求

推荐系统：

- Debian 10+
- Ubuntu 18.04+

`sudo dg install-deps` 目前只自动处理 Debian/Ubuntu。CentOS、Oracle Linux 等发行版可以手动安装依赖后使用 DriveGuard。

运行依赖：

- `bash`
- `rclone`
- `cron`
- `openssl`
- `tar`
- `gzip`
- `mysqldump` 或 `mariadb-dump`
- `systemd`，仅 cron 守护功能需要

## 快速开始

先安装短命令：

```bash
sudo bash driveguard.sh install
```

之后可以用 `dg` 完成首次配置：

```bash
sudo dg install-deps
sudo dg auth
sudo dg configure
sudo dg cron
sudo dg install-guard
sudo dg backup
```

也可以不安装短命令，直接运行源码脚本：

```bash
sudo bash driveguard.sh menu
```

## rclone 云盘配置

```bash
sudo dg auth
```

DriveGuard 不直接绑定某一家云盘，真正上传由 `rclone` 完成。你只需要先在 `rclone` 里配置一个 remote，然后在 `dg configure` 里填写这个 remote 名称。

默认 remote 名称是 `cloud`，云端目录是 `driveguard`。如果你已有 remote，例如 `onedrive`、`s3backup` 或 `gdrive`，也可以在配置时改成已有名称。

### 通用配置流程

运行：

```bash
sudo dg auth
```

进入 `rclone config` 后，常见流程是：

1. 选择 `n` 新建 remote。
2. `name` 建议填 `cloud`，或填一个能表达用途的名字，例如 `onedrive`、`s3backup`。
3. `Storage` 选择你的目标存储类型。
4. 按 `rclone` 提示填写授权、密钥、endpoint 或账号信息。
5. 如果服务器无浏览器，选择非自动配置，按提示在本地电脑完成授权，再把 token 粘回服务器。
6. 保存 remote 后，脚本会检查 `remote:` 是否可访问。

你也可以直接手动验证：

```bash
rclone lsd cloud:
```

### 常见后端提示

- Google Drive：Storage 选择 Google Drive，`client_id` 和 `client_secret` 可以先留空，scope 通常选 `drive` 或 `drive.file`。
- OneDrive / Dropbox：通常按提示走浏览器 OAuth 授权即可。
- S3 兼容对象存储：需要填写 provider、access key、secret key、region、endpoint 等信息。
- WebDAV：需要填写 URL、用户名和密码。
- SFTP：需要填写主机、端口、用户名，以及密码或 SSH key。

只要 `rclone` 支持，并且 remote 支持这些操作，DriveGuard 就可以使用：

- `rclone lsd remote:`
- `rclone mkdir remote:path`
- `rclone copy 本地文件 remote:path`
- `rclone lsf remote:path --files-only`
- `rclone deletefile remote:path/file`

因此常见的 OneDrive、Dropbox、S3 兼容对象存储、WebDAV、SFTP 等都可以作为备份目标。配置方法是在 `rclone config` 里选择对应 Storage，完成授权后，在 `dg configure` 中把 remote 名称改成对应名称。

例如 remote 名叫 `s3backup`：

```bash
sudo dg configure
```

把 `rclone remote 名称` 填成：

```text
s3backup
```

## 配置文件

默认配置目录：

```text
/etc/driveguard
```

主要文件：

```text
/etc/driveguard/config.conf
/etc/driveguard/sites.list
/etc/driveguard/databases.list
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
```

默认本地目录：

```text
/var/backups/driveguard
/var/lib/driveguard
/var/log/driveguard
```

敏感文件会设置为 `600` 权限，建议只允许 root 访问。

## 基础配置

```bash
sudo dg configure
```

可配置：

- rclone remote 名称，默认 `cloud`
- 云端远程目录，默认 `driveguard`
- 每个网站/数据库保留份数，默认 `7`
- 本地备份暂存目录
- cron 定时表达式，默认 `0 3 * * *`
- MySQL host/port/socket
- 备份加密密码
- MySQL 账号和密码

## 网站列表

文件：

```text
/etc/driveguard/sites.list
```

格式：

```text
站点名称|站点目录|排除项
```

示例：

```text
example.com|/var/www/example.com|.git,cache,logs
blog.example.com|/srv/blog.example.com|
```

排除项用英文逗号分隔，路径相对于站点目录。

## 数据库列表

文件：

```text
/etc/driveguard/databases.list
```

格式是一行一个数据库名：

```text
example_db
blog_db
```

## 手动备份

```bash
sudo dg backup
```

脚本会：

1. 使用锁文件避免多个备份任务同时运行。
2. 遍历网站列表并打包。
3. 遍历数据库列表并导出。
4. 使用 `openssl` 加密备份包。
5. 使用 `rclone` 上传到云端 remote。
6. 按保留份数清理本地和远程旧备份。
7. 写入日志。

## 备份命名

网站备份：

```text
Web_站点名_YYYYMMDD_HHMMSS.tar.gz.enc
```

数据库备份：

```text
Db_数据库名_YYYYMMDD_HHMMSS.sql.gz.enc
```

云端默认目录：

```text
driveguard/site/站点名/
driveguard/database/数据库名/
```

## 加密和解密

加密算法：

```text
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000
```

解密：

```bash
sudo dg decrypt 源文件.enc 输出文件
```

示例：

```bash
sudo dg decrypt Web_example.com_20260604_030000.tar.gz.enc Web_example.com.tar.gz
tar -xzf Web_example.com.tar.gz
```

数据库恢复示例：

```bash
sudo dg decrypt Db_example_db_20260604_030000.sql.gz.enc Db_example_db.sql.gz
gzip -d Db_example_db.sql.gz
mysql --defaults-extra-file=/etc/driveguard/mysql.cnf example_db < Db_example_db.sql
```

## 定时任务

安装或更新 cron：

```bash
sudo dg cron
```

默认每天凌晨 3 点执行：

```text
0 3 * * *
```

脚本写入的 root crontab 会被包在标记中：

```text
# DRIVEGUARD_BEGIN
...
# DRIVEGUARD_END
```

再次运行 `cron` 会替换旧任务，不会重复添加。

## cron 守护

```bash
sudo dg install-guard
```

会创建：

```text
/etc/systemd/system/driveguard-cron-guard.service
/etc/systemd/system/driveguard-cron-guard.timer
```

作用：

- 定期检查 cron 服务是否运行。
- 如果脚本 cron 片段丢失，自动补回。

查看状态：

```bash
systemctl status driveguard-cron-guard.timer
```

## 日志

查看日志：

```bash
sudo dg log
```

日志路径：

```text
/var/log/driveguard/backup.log
/var/log/driveguard/rclone.log
/var/log/driveguard/cron.log
```

## 卸载

```bash
sudo dg uninstall
```

卸载会自动：

- 移除脚本写入的 root crontab 片段。
- 停止并删除 systemd cron 守护 service/timer。
- 删除安装到 `/usr/local/bin/driveguard` 的脚本副本。
- 删除短命令 `/usr/local/bin/dg`。

卸载不会删除云端已上传的备份。

下面这些本地目录会逐项询问后再删除：

```text
/etc/driveguard
/var/backups/driveguard
/var/lib/driveguard
/var/log/driveguard
```

如果只想停止自动备份但保留配置、日志和本地备份，卸载时选择保留对应目录即可。

## 常用命令

```bash
sudo bash driveguard.sh install
sudo dg menu
sudo dg install-deps
sudo dg auth
sudo dg configure
sudo dg cron
sudo dg install-guard
sudo dg guard-cron
sudo dg backup
sudo dg log 100
sudo dg status
sudo dg uninstall
```

`driveguard` 和 `dg` 等价，喜欢完整命令时可以把上面的 `dg` 换成 `driveguard`。

## 安全建议

- 不要把 `/etc/driveguard` 中的文件提交到 Git。
- 不要提交 `credentials.json`、`token.json`、`rclone.conf` 或任何包含密码/token 的文件。
- 备份加密密码请离线保存，否则 `.enc` 文件无法恢复。
- 建议定期手动下载一个备份包，测试解密、解压和数据库导入。
- 建议给云端备份使用专门账号、专门 bucket 或专门目录。

## 故障排查

检查 rclone remote：

```bash
rclone lsd cloud:
```

检查脚本配置：

```bash
sudo dg status
```

检查日志：

```bash
sudo dg log 200
```

检查 cron：

```bash
sudo systemctl status cron
sudo crontab -l
```

检查 systemd timer：

```bash
systemctl list-timers | grep driveguard
systemctl status driveguard-cron-guard.timer
```

常见问题：

- `未找到 rclone`：先执行 `sudo dg install-deps`。
- `rclone remote 不存在`：执行 `sudo dg auth`。
- `未设置备份加密密码`：执行 `sudo dg configure`。
- `未配置 MySQL 连接信息`：执行 `sudo dg configure` 并设置 MySQL。
- `数据库导出失败`：检查 `/etc/driveguard/mysql.cnf`、MySQL 权限和数据库名。
- `上传失败`：检查 `/var/log/driveguard/rclone.log` 和服务器到云端 remote 的网络连通性。

## 验证

本地语法检查：

```bash
bash -n driveguard.sh
bash driveguard.sh help
```

生产使用前建议在测试服务器完整跑通：

```bash
sudo dg backup
sudo dg decrypt 某个备份.enc 测试输出文件
```
