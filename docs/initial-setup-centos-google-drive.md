# 初始配置实战：CentOS Stream 8 + Google Drive

这篇记录一次真实的 DriveGuard 初始配置流程：服务器是 CentOS Stream 8，通过 Xshell 操作，备份目标是 Google Drive，并希望最终写入：

```text
gdrive:backup/site/
gdrive:backup/database/
```

## 1. 安装 git

如果服务器提示：

```text
bash: git: command not found
```

先安装 git。遇到 Cloudflare 源 404 时，临时禁用它：

```bash
dnf --disablerepo=cloudflare install -y git
git --version
```

然后拉取 DriveGuard：

```bash
cd /home/opc
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
bash driveguard.sh install
```

如果 `dg` 提示找不到，但 `/usr/local/bin/dg` 已存在，说明当前 shell 的 `PATH` 没有 `/usr/local/bin`。可以直接建到现有 PATH：

```bash
ln -sfn /usr/local/bin/driveguard /usr/bin/dg
ln -sfn /usr/local/bin/driveguard /usr/bin/driveguard
dg help
```

## 2. 安装依赖

现在 DriveGuard 已支持在 CentOS/RHEL 系自动安装依赖：

```bash
dg install-deps
```

它会安装 `git`、`cronie`、`openssl`、`tar`、`gzip`、`util-linux`、`curl`、`unzip`、MariaDB 客户端和 PostgreSQL 客户端；如果系统源没有 `rclone`，会自动改用 rclone 官方安装脚本。

如果遇到第三方源元数据错误，例如 Cloudflare repo 404，可以临时禁用坏源后重试：

```bash
dnf --disablerepo=cloudflare install -y git
dg install-deps
```

如果需要数据库备份，确认 MySQL/PostgreSQL dump 工具可用：

```bash
mysqldump --version || mariadb-dump --version
pg_dump --version
```

## 3. 配置 Google Drive remote

进入配置：

```bash
dg auth
```

建议 remote 命名为：

```text
gdrive
```

Google Drive 配置里常见选项：

| 提示 | 推荐选择 | 说明 |
| --- | --- | --- |
| `root_folder_id>` | 直接回车 | 让 DriveGuard 通过远程目录写入 `backup/` |
| `service_account_file>` | 直接回车 | 个人 Google 账号 OAuth 不需要 |
| `Edit advanced config?` | `n` | 普通备份不需要高级配置 |

想写入 `gdrive:backup/site/` 和 `gdrive:backup/database/` 时，不要填 `root_folder_id`。稍后在 `dg configure` 里把云端远程目录填成 `backup`。

如果 rclone 问是否自动打开浏览器：

```text
Use web browser to automatically authenticate rclone with remote?
```

Xshell/SSH 服务器选：

```text
n
```

## 4. Windows 本地授权

服务器会显示一条命令，类似：

```bash
rclone authorize "drive" "..."
```

Windows 上安装 rclone：

```powershell
winget install Rclone.Rclone
```

如果提示 `Path environment variable modified; restart your shell to use the new value.`，关闭 PowerShell，重新打开后检查：

```powershell
rclone version
```

然后在 Windows PowerShell 执行服务器给出的 `rclone authorize "drive" "..."` 命令。浏览器授权成功后，PowerShell 会输出一段 JSON token。把整段 JSON 粘回 Xshell 服务器窗口。

这段 JSON 是真实访问 token，不要发到聊天、截图或公开仓库。

## 5. 处理 Google OAuth 403

如果授权时报：

```text
错误 403：access_denied
此应用正在测试中
```

说明 Google OAuth 应用还在测试状态，当前 Gmail 没有权限。两种处理方式：

1. 在 Google Cloud Console 的 Google Auth Platform 里进入 `目标对象`，把授权用的 Gmail 加入测试用户。
2. 或把发布状态切到正式版。

切到正式版后，可能看到：

```text
此应用未经 Google 验证
```

如果 OAuth Client 是你自己创建的，可以展开高级选项，选择继续前往，然后允许授权。

## 6. 保存 remote

服务器收到 token 后，rclone 会问是否配置 Shared Drive：

```text
Configure this as a Shared Drive?
```

个人 Google Drive 选：

```text
n
```

看到：

```text
Keep this "gdrive" remote?
```

选：

```text
y
```

回到 rclone 主菜单后输入：

```text
q
```

验证 remote：

```bash
rclone lsd gdrive:
rclone mkdir gdrive:backup
rclone lsf gdrive:backup
```

## 7. 配置 DriveGuard

运行：

```bash
dg configure
```

关键项这样填：

```text
rclone remote 名称 [cloud]: gdrive
云端远程目录 [driveguard]: backup
每个站点/数据库保留份数 [7]: 7
本地备份暂存目录 [/var/backups/driveguard]: 直接回车
定时表达式 cron [0 3 * * *]: 直接回车
MySQL host [localhost]: 直接回车
MySQL port [3306]: 直接回车
MySQL socket，留空则使用 host/port: 直接回车
PostgreSQL 备份，auto=自动检测 1=启用 0=关闭 [auto]: 本机 PostgreSQL 直接回车；远程 PostgreSQL 填 1；不备份填 0
PostgreSQL host [localhost]: 直接回车或填写实际地址
PostgreSQL port [5432]: 直接回车
PostgreSQL 用户 [postgres]: 填写备份用户
PostgreSQL 连接库 [postgres]: 直接回车
是否现在设置备份加密密码: y
是否现在设置 MySQL 连接信息: 需要备份数据库就 y
是否现在设置 PostgreSQL 连接密码: 已检测到或已启用 PostgreSQL 就 y
```

配置完成后会生成：

```text
/etc/driveguard/config.conf
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
/etc/driveguard/postgres.pgpass
```

## 8. 添加网站和数据库

进入菜单：

```bash
dg menu
```

常用入口：

```text
4. 管理网站备份列表
5. 管理数据库备份列表
```

`dg backup` 默认会自动发现常见网站目录、MySQL/MariaDB 非系统数据库，以及自动检测到或已启用 PostgreSQL 后的非模板库。菜单里的列表仍然有用：可以补充特殊网站路径、设置网站排除项，或显式指定数据库。

如果你想检查或手动维护 MySQL/MariaDB 数据库列表：

```bash
nl -ba /etc/driveguard/databases.list
```

如果你想检查或手动维护 PostgreSQL 数据库列表：

```bash
nl -ba /etc/driveguard/postgres.databases.list
```

文件里一行一个数据库名，例如：

```text
example_db
blog_db
```

网站会分别上传到：

```text
gdrive:backup/site/站点名/
```

数据库会分别上传到：

```text
gdrive:backup/database/数据库名/
gdrive:backup/database/postgresql/数据库名/
```

每个站点、每个数据库都会独立保留指定份数，例如 7 份。

## 9. 首次备份和定时任务

先手动跑一次：

```bash
dg backup
dg log 100
```

确认成功后再安装定时任务：

```bash
dg cron
dg install-guard
```

查看状态：

```bash
dg status
systemctl status driveguard-cron-guard.timer
```

## 10. 常见结论

- 网站和数据库都会加密，文件后缀分别是 `.tar.gz.enc` 和 `.sql.gz.enc`。
- 多个网站、MySQL/MariaDB 数据库和 PostgreSQL 数据库会分别备份、分别上传、分别按保留份数清理。
- 以后更新 DriveGuard，可以直接执行 `dg update`，或在 `dg menu` 中选择“更新 DriveGuard 脚本”。
- `root_folder_id` 是限制 remote 根目录用的；只想写到 `backup/` 时，更简单的是在 `dg configure` 里把云端远程目录填 `backup`。
- 自建 Google OAuth Client 的 token 和 refresh token 都是敏感信息，不要公开。
