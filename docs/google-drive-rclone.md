# Google Drive rclone Setup

This page documents Google Drive as a DriveGuard remote. DriveGuard itself works with any `rclone` remote that supports basic directory and file operations.

Chinese version: [Chinese docs](zh-CN/google-drive-rclone.md)

References:

- rclone Google Drive documentation: https://rclone.org/drive/
- rclone config documentation: https://rclone.org/commands/rclone_config/
- Chinese rclone tutorial used as a setup reference: https://www.cnblogs.com/zxhoo/p/19639636

## Prerequisite

Check that `rclone` is installed:

```bash
rclone version
```

If it is missing:

```bash
curl -fsSL https://rclone.org/install.sh | bash
```

DriveGuard defaults to a remote named `cloud`. If your Google Drive remote is named `gdrive`, set that name in `sudo dg configure`.

## Start Configuration

Recommended entrypoint:

```bash
sudo dg auth
```

Direct rclone entrypoint:

```bash
rclone config
```

In the interactive flow:

1. Choose `n` to create a new remote.
2. Set `name` to `cloud`, or another name such as `gdrive`.
3. For `Storage`, enter `drive`. rclone's numeric menu changes by version, so typing `drive` is the safest.

## Client ID and Client Secret

rclone asks for `client_id` and `client_secret`. For first-time personal use, you can press Enter and use rclone's default client.

Create your own OAuth client later if you hit API limits, speed issues, or authorization restrictions:

1. Open Google Cloud Console.
2. Create or select a project.
3. Enable Google Drive API.
4. Create an OAuth Client ID with application type `Desktop app`.
5. Paste the Client ID and Client Secret into rclone.

## Scope

Common choices:

- `drive`: full read/write access to Google Drive. Easiest for backups.
- `drive.file`: more restricted, but can make visibility and restore workflows less obvious.

If unsure, choose `drive`. Read-only scopes do not work for DriveGuard because it must create folders, upload files, and delete old backups.

## Common Optional Prompts

- `root_folder_id`: leave blank unless you want the remote root to be a specific Google Drive folder.
- `service_account_file`: leave blank for personal Google OAuth.
- `Edit advanced config?`: choose `n` for normal backups.

### Back Up into a `backup` Folder

There are two common approaches.

The simpler approach is to leave `root_folder_id` blank and set DriveGuard's remote directory to `backup` in `sudo dg configure`. The final layout is:

```text
cloud:backup/site/
cloud:backup/database/
cloud:backup/database/postgresql/
```

DriveGuard creates the folder with `rclone mkdir` before uploading if it does not exist.

The more restricted approach is to create a `backup` folder in Google Drive, open it in the browser, and copy the folder ID from the URL:

```text
https://drive.google.com/drive/folders/FOLDER_ID_HERE
```

Paste that ID into `root_folder_id>`. Then `cloud:` points directly at that folder. If DriveGuard's remote directory remains `driveguard`, the final layout becomes:

```text
backup/driveguard/site/
backup/driveguard/database/
backup/driveguard/database/postgresql/
```

If you want DriveGuard files directly under `backup/site/` and `backup/database/`, leave the DriveGuard remote directory blank.

## Authorization

If the server has a browser, `Use web browser to automatically authenticate rclone with remote?` can be `y`.

For an SSH/Xshell server, choose `n`:

1. rclone prints a `rclone authorize "drive" ...` command.
2. Install rclone on your local computer and run that exact command.
3. Complete Google login and authorization in the local browser.
4. Paste the returned token JSON into the server prompt.

For a personal Google Drive, choose `n` when rclone asks about Shared Drives. For a team/shared drive, choose `y` and select the target drive.

Finally choose `y` to keep the remote, then quit the rclone config menu.

## Verification

If the remote name is `cloud`:

```bash
rclone lsd cloud:
```

Verify the basic operations DriveGuard needs:

```bash
rclone mkdir cloud:driveguard/_test
rclone lsf cloud:driveguard
rclone rmdir cloud:driveguard/_test
```

If these commands work, DriveGuard can use the remote.

## Connect DriveGuard

Run:

```bash
sudo dg configure
```

Important values:

- `rclone remote name`: enter `cloud`, `gdrive`, or your actual remote name.
- `remote directory`: keep `driveguard`, or use `backup` if you want the Google Drive folder layout described above.
- Set the backup encryption password.
- Set MySQL/MariaDB or PostgreSQL connection details if database backups are needed.

Test:

```bash
sudo dg backup
sudo dg status
sudo dg log 100
```

## Troubleshooting

- `rclone remote does not exist`: the remote name in `dg configure` does not match `rclone listremotes`.
- Google Drive connection failed: run `sudo dg auth` again, or test with `rclone lsd remote:`.
- `insufficient permissions`: the scope may be read-only. Reconfigure with a writable scope.
- Slow upload or rate limits: consider using your own Google OAuth Client ID, or reduce concurrency/chunk settings.
