# GDrive Backup Guard

GDrive Backup Guard 是一个面向 Debian/Ubuntu 服务器的独立 Google Drive 备份脚本。它可以通过中文交互菜单配置 Google Drive 授权、网站目录备份、MySQL/MariaDB 数据库备份、加密、定时任务、日志、保留份数清理和 cron 守护。

项目现在只保留可独立运行的脚本：

```text
gdrive-backup-guard.sh
```

它不依赖宝塔插件运行环境；如果服务器安装了宝塔面板，可以选择从宝塔数据库导入网站和数据库列表。

## 功能

- Debian/Ubuntu 依赖自动安装。
- 中文菜单管理配置、授权、备份列表、定时任务和卸载。
- 使用 `rclone` 完成 Google Drive OAuth 授权和上传。
- 支持从宝塔面板导入网站和数据库列表。
- 支持手动维护网站目录和数据库列表。
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

运行依赖：

- `bash`
- `rclone`
- `cron`
- `openssl`
- `tar`
- `gzip`
- `sqlite3`
- `mysqldump` 或 `mariadb-dump`
- `systemd`，仅 cron 守护功能需要

## 快速开始

进入中文菜单：

```bash
sudo bash gdrive-backup-guard.sh menu
```

推荐首次配置顺序：

```bash
sudo bash gdrive-backup-guard.sh install-deps
sudo bash gdrive-backup-guard.sh auth
sudo bash gdrive-backup-guard.sh configure
sudo bash gdrive-backup-guard.sh import-bt
sudo bash gdrive-backup-guard.sh cron
sudo bash gdrive-backup-guard.sh install-guard
sudo bash gdrive-backup-guard.sh backup
```

如果不是宝塔服务器，可以跳过 `import-bt`，在菜单里手动添加网站和数据库。

## 安装依赖

```bash
sudo bash gdrive-backup-guard.sh install-deps
```

脚本会检查 Debian/Ubuntu，并通过 `apt-get` 安装常用依赖。

## Google Drive 授权

```bash
sudo bash gdrive-backup-guard.sh auth
```

授权由 `rclone config` 完成。建议：

- remote 名称使用默认值 `gdrive`。
- Storage 选择 Google Drive。
- scope 可选 `drive` 或 `drive.file`。
- 无浏览器服务器按 `rclone` 提示在本地电脑授权，再把 token 粘回服务器。

授权完成后脚本会检查 `gdrive:` 是否可访问。

## 配置文件

默认配置目录：

```text
/etc/gdrive-backup-guard
```

主要文件：

```text
/etc/gdrive-backup-guard/config.conf
/etc/gdrive-backup-guard/sites.list
/etc/gdrive-backup-guard/databases.list
/etc/gdrive-backup-guard/archive.pass
/etc/gdrive-backup-guard/mysql.cnf
```

默认本地目录：

```text
/var/backups/gdrive-backup-guard
/var/lib/gdrive-backup-guard
/var/log/gdrive-backup-guard
```

敏感文件会设置为 `600` 权限，建议只允许 root 访问。

## 基础配置

```bash
sudo bash gdrive-backup-guard.sh configure
```

可配置：

- rclone remote 名称，默认 `gdrive`
- Google Drive 远程目录，默认 `bt_backup`
- 每个网站/数据库保留份数，默认 `7`
- 本地备份暂存目录
- cron 定时表达式，默认 `0 3 * * *`
- MySQL host/port/socket
- 备份加密密码
- MySQL 账号和密码

## 从宝塔导入

如果服务器安装了宝塔面板，脚本会读取：

```text
/www/server/panel/data/default.db
```

导入命令：

```bash
sudo bash gdrive-backup-guard.sh import-bt
```

导入后生成：

```text
/etc/gdrive-backup-guard/sites.list
/etc/gdrive-backup-guard/databases.list
```

## 网站列表

文件：

```text
/etc/gdrive-backup-guard/sites.list
```

格式：

```text
站点名称|站点目录|排除项
```

示例：

```text
example.com|/www/wwwroot/example.com|.git,cache,logs
blog.example.com|/www/wwwroot/blog.example.com|
```

排除项用英文逗号分隔，路径相对于站点目录。

## 数据库列表

文件：

```text
/etc/gdrive-backup-guard/databases.list
```

格式是一行一个数据库名：

```text
example_db
blog_db
```

## 手动备份

```bash
sudo bash gdrive-backup-guard.sh backup
```

脚本会：

1. 使用锁文件避免多个备份任务同时运行。
2. 遍历网站列表并打包。
3. 遍历数据库列表并导出。
4. 使用 `openssl` 加密备份包。
5. 使用 `rclone` 上传到 Google Drive。
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

Google Drive 默认目录：

```text
bt_backup/site/站点名/
bt_backup/database/数据库名/
```

## 加密和解密

加密算法：

```text
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000
```

解密：

```bash
sudo bash gdrive-backup-guard.sh decrypt 源文件.enc 输出文件
```

示例：

```bash
sudo bash gdrive-backup-guard.sh decrypt Web_example.com_20260604_030000.tar.gz.enc Web_example.com.tar.gz
tar -xzf Web_example.com.tar.gz
```

数据库恢复示例：

```bash
sudo bash gdrive-backup-guard.sh decrypt Db_example_db_20260604_030000.sql.gz.enc Db_example_db.sql.gz
gzip -d Db_example_db.sql.gz
mysql --defaults-extra-file=/etc/gdrive-backup-guard/mysql.cnf example_db < Db_example_db.sql
```

## 定时任务

安装或更新 cron：

```bash
sudo bash gdrive-backup-guard.sh cron
```

默认每天凌晨 3 点执行：

```text
0 3 * * *
```

脚本写入的 root crontab 会被包在标记中：

```text
# GDRIVE_BACKUP_GUARD_BEGIN
...
# GDRIVE_BACKUP_GUARD_END
```

再次运行 `cron` 会替换旧任务，不会重复添加。

## cron 守护

```bash
sudo bash gdrive-backup-guard.sh install-guard
```

会创建：

```text
/etc/systemd/system/gdrive-backup-guard-cron-guard.service
/etc/systemd/system/gdrive-backup-guard-cron-guard.timer
```

作用：

- 定期检查 cron 服务是否运行。
- 如果脚本 cron 片段丢失，自动补回。

查看状态：

```bash
systemctl status gdrive-backup-guard-cron-guard.timer
```

## 日志

查看日志：

```bash
sudo bash gdrive-backup-guard.sh log
```

日志路径：

```text
/var/log/gdrive-backup-guard/backup.log
/var/log/gdrive-backup-guard/rclone.log
/var/log/gdrive-backup-guard/cron.log
```

## 卸载

```bash
sudo bash gdrive-backup-guard.sh uninstall
```

卸载会自动：

- 移除脚本写入的 root crontab 片段。
- 停止并删除 systemd cron 守护 service/timer。
- 删除安装到 `/usr/local/sbin/gdrive-backup-guard` 的脚本副本。
- 兼容清理旧名 `bt-gdrive-backup` 的 service/timer 和脚本副本。

卸载不会删除 Google Drive 上已上传的备份。

下面这些本地目录会逐项询问后再删除：

```text
/etc/gdrive-backup-guard
/var/backups/gdrive-backup-guard
/var/lib/gdrive-backup-guard
/var/log/gdrive-backup-guard
```

如果只想停止自动备份但保留配置、日志和本地备份，卸载时选择保留对应目录即可。

## 常用命令

```bash
sudo bash gdrive-backup-guard.sh menu
sudo bash gdrive-backup-guard.sh install-deps
sudo bash gdrive-backup-guard.sh auth
sudo bash gdrive-backup-guard.sh configure
sudo bash gdrive-backup-guard.sh import-bt
sudo bash gdrive-backup-guard.sh cron
sudo bash gdrive-backup-guard.sh install-guard
sudo bash gdrive-backup-guard.sh guard-cron
sudo bash gdrive-backup-guard.sh backup
sudo bash gdrive-backup-guard.sh log 100
sudo bash gdrive-backup-guard.sh status
sudo bash gdrive-backup-guard.sh uninstall
```

## 安全建议

- 不要把 `/etc/gdrive-backup-guard` 中的文件提交到 Git。
- 不要提交 `credentials.json`、`token.json`、`rclone.conf` 或任何包含密码/token 的文件。
- 备份加密密码请离线保存，否则 `.enc` 文件无法恢复。
- 建议定期手动下载一个备份包，测试解密、解压和数据库导入。
- 建议给 Google Drive 授权使用专门账号或专门目录。

## 故障排查

检查 Google Drive 授权：

```bash
rclone lsd gdrive:
```

检查脚本配置：

```bash
sudo bash gdrive-backup-guard.sh status
```

检查日志：

```bash
sudo bash gdrive-backup-guard.sh log 200
```

检查 cron：

```bash
sudo systemctl status cron
sudo crontab -l
```

检查 systemd timer：

```bash
systemctl list-timers | grep gdrive-backup-guard
systemctl status gdrive-backup-guard-cron-guard.timer
```

常见问题：

- `未找到 rclone`：先执行 `sudo bash gdrive-backup-guard.sh install-deps`。
- `rclone remote 不存在`：执行 `sudo bash gdrive-backup-guard.sh auth`。
- `未设置备份加密密码`：执行 `sudo bash gdrive-backup-guard.sh configure`。
- `未配置 MySQL 连接信息`：执行 `sudo bash gdrive-backup-guard.sh configure` 并设置 MySQL。
- `数据库导出失败`：检查 `/etc/gdrive-backup-guard/mysql.cnf`、MySQL 权限和数据库名。
- `上传失败`：检查 `/var/log/gdrive-backup-guard/rclone.log` 和服务器到 Google 的网络连通性。

## 验证

本地语法检查：

```bash
bash -n gdrive-backup-guard.sh
bash gdrive-backup-guard.sh help
```

生产使用前建议在测试服务器完整跑通：

```bash
sudo bash gdrive-backup-guard.sh backup
sudo bash gdrive-backup-guard.sh decrypt 某个备份.enc 测试输出文件
```
