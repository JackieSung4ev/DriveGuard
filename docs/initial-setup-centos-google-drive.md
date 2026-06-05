# Initial Setup: CentOS Stream 8 + Google Drive

This guide documents a real first-time DriveGuard setup on a CentOS Stream 8 server over SSH/Xshell, using Google Drive as the remote target. The final layout is:

```text
gdrive:backup/site/
gdrive:backup/database/
gdrive:backup/database/postgresql/
```

Chinese version: [Chinese docs](zh-CN/initial-setup-centos-google-drive.md)

## 1. Install Git

If the server says:

```text
bash: git: command not found
```

install Git first. If a third-party repository such as Cloudflare returns metadata errors, disable it temporarily:

```bash
dnf --disablerepo=cloudflare install -y git
git --version
```

Clone and install DriveGuard:

```bash
cd /home/opc
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
bash driveguard.sh install
```

If `dg` is not found but `/usr/local/bin/dg` exists, your current `PATH` does not include `/usr/local/bin`. Add a symlink in an existing PATH directory:

```bash
ln -sfn /usr/local/bin/driveguard /usr/bin/dg
ln -sfn /usr/local/bin/driveguard /usr/bin/driveguard
dg help
```

## 2. Install Dependencies

DriveGuard can install dependencies automatically on Debian/Ubuntu and CentOS/RHEL-like systems:

```bash
dg install-deps
```

On CentOS/RHEL-like systems, this installs `git`, `cronie`, `openssl`, `tar`, `gzip`, `util-linux`, `curl`, `unzip`, MariaDB client tools, and PostgreSQL client tools. If the package repository does not provide `rclone`, DriveGuard falls back to the official rclone installer.

Verify database dump tools if you plan to back up databases:

```bash
mysqldump --version || mariadb-dump --version
pg_dump --version
```

## 3. Configure the Google Drive Remote

Start rclone configuration from DriveGuard:

```bash
dg auth
```

Recommended remote name:

```text
gdrive
```

Common Google Drive options:

| Prompt | Recommended value | Why |
| --- | --- | --- |
| `root_folder_id>` | press Enter | Let DriveGuard write into `backup/` through its remote path setting |
| `service_account_file>` | press Enter | Personal Google OAuth does not need a service account |
| `Edit advanced config?` | `n` | Advanced config is not needed for normal backups |

If you want the final path to be `gdrive:backup/site/` and `gdrive:backup/database/`, leave `root_folder_id` empty. Later, set the DriveGuard remote path to `backup` in `dg configure`.

When rclone asks whether to open a browser automatically:

```text
Use web browser to automatically authenticate rclone with remote?
```

On an SSH/Xshell server, choose:

```text
n
```

## 4. Authorize from Windows

The server will print a command similar to:

```bash
rclone authorize "drive" "..."
```

Install rclone on Windows:

```powershell
winget install Rclone.Rclone
```

If the installer says the PATH was modified, close PowerShell and open it again:

```powershell
rclone version
```

Run the exact `rclone authorize "drive" "..."` command shown by the server. After browser authorization succeeds, PowerShell prints a JSON token. Paste that entire JSON back into the SSH/Xshell server prompt.

The token is sensitive. Do not post it in chats, screenshots, logs, or public repositories.

## 5. Handle Google OAuth 403

If Google returns:

```text
Error 403: access_denied
This app is in testing
```

the OAuth app is still in testing mode and your Gmail account is not allowed yet. You can either:

1. Add your Gmail address as a test user in Google Cloud Console under Google Auth Platform.
2. Switch the OAuth app publishing status to production.

After switching to production, Google may show an unverified-app warning. If you created the OAuth client yourself, expand the advanced section and continue.

## 6. Save and Verify the Remote

When rclone asks about Shared Drives:

```text
Configure this as a Shared Drive?
```

For a personal Google Drive, choose:

```text
n
```

When it asks whether to keep the remote:

```text
Keep this "gdrive" remote?
```

choose:

```text
y
```

Return to the rclone main menu and quit:

```text
q
```

Verify the remote:

```bash
rclone lsd gdrive:
rclone mkdir gdrive:backup
rclone lsf gdrive:backup
```

## 7. Configure DriveGuard

Run:

```bash
dg configure
```

Typical values:

```text
rclone remote name [cloud]: gdrive
remote directory [driveguard]: backup
retention copies per site/database [7]: 7
local backup staging directory [/var/backups/driveguard]: press Enter
cron expression [0 3 * * *]: press Enter
MySQL host [localhost]: press Enter
MySQL port [3306]: press Enter
MySQL socket, leave blank to use host/port: press Enter
PostgreSQL backup, auto=auto-detect 1=enable 0=disable [auto]: press Enter for local PostgreSQL; enter 1 for remote PostgreSQL; enter 0 to disable
PostgreSQL host [localhost]: press Enter or enter the actual host
PostgreSQL port [5432]: press Enter
PostgreSQL user [postgres]: enter the backup user
PostgreSQL connection database [postgres]: press Enter
set backup encryption password now: y
set MySQL connection now: y if you need MySQL/MariaDB backups
set PostgreSQL password now: y if PostgreSQL was detected or enabled
```

Generated sensitive files:

```text
/etc/driveguard/config.conf
/etc/driveguard/archive.pass
/etc/driveguard/mysql.cnf
/etc/driveguard/postgres.pgpass
```

## 8. Website and Database Lists

Open the menu:

```bash
dg menu
```

Useful entries:

```text
4. Manage website backup list
5. Manage database backup list
```

`dg backup` automatically discovers common website roots, non-system MySQL/MariaDB databases, and PostgreSQL non-template databases when PostgreSQL is detected or enabled. Manual lists are still useful for special paths, excludes, or explicit database names.

Manual MySQL/MariaDB list:

```bash
nl -ba /etc/driveguard/databases.list
```

Manual PostgreSQL list:

```bash
nl -ba /etc/driveguard/postgres.databases.list
```

Each line is one database name:

```text
example_db
blog_db
```

Remote layout:

```text
gdrive:backup/site/site-name/
gdrive:backup/database/mysql-db-name/
gdrive:backup/database/postgresql/postgres-db-name/
```

Each site and database keeps its own retention count.

## 9. First Backup and Scheduling

Run a manual backup first:

```bash
dg backup
dg log 100
```

Enable scheduling only after the manual backup succeeds:

```bash
dg cron
dg install-guard
```

Check status:

```bash
dg status
systemctl status driveguard-cron-guard.timer
```

## 10. Useful Conclusions

- Website backups end with `.tar.gz.enc`.
- Database backups end with `.sql.gz.enc`.
- Multiple websites and databases are backed up, uploaded, and pruned independently.
- Update DriveGuard with `dg update` or menu option `11`.
- `root_folder_id` limits the remote root. If you only want to write into `backup/`, it is usually simpler to set DriveGuard's remote directory to `backup`.
- OAuth tokens and refresh tokens are sensitive. Keep them private.
