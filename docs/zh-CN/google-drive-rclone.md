# Google Drive rclone 初始化配置

这篇是 DriveGuard 的 Google Drive remote 配置备忘。DriveGuard 仍然是通用 `rclone` 云端备份工具；这里仅记录 Google Drive 作为备份目标时的推荐流程。

参考资料：

- rclone 官方 Google Drive 文档：https://rclone.org/drive/
- rclone config 命令文档：https://rclone.org/commands/rclone_config/
- 博客园教程《rclone 完整使用教程》：https://www.cnblogs.com/zxhoo/p/19639636

## 前提

服务器上先确认有 `rclone`：

```bash
rclone version
```

如果没有，Linux 服务器可以使用 rclone 官方安装脚本：

```bash
curl -fsSL https://rclone.org/install.sh | bash
```

DriveGuard 默认 remote 名称是 `cloud`。如果你按本文把 Google Drive remote 命名为 `cloud`，后续 DriveGuard 可以直接使用默认值；如果命名为 `gdrive`，在 `sudo dg configure` 里把 remote 名称改成 `gdrive` 即可。

## 启动配置

推荐从 DriveGuard 进入 rclone 配置：

```bash
sudo dg auth
```

也可以直接运行：

```bash
rclone config
```

进入交互后：

1. 选择 `n` 新建 remote。
2. `name` 填 `cloud`，或填你喜欢的名称，例如 `gdrive`。
3. `Storage` 选择 Google Drive。rclone 的编号会随版本变化，直接输入 `drive` 最稳。

## Client ID 和 Client Secret

rclone 会询问 `client_id` 和 `client_secret`。首次使用可以直接回车留空，使用 rclone 默认配置。

如果后续遇到 Google API 限流、速度异常或授权限制，可以创建自己的 OAuth 客户端：

1. 打开 Google Cloud Console。
2. 创建或选择一个项目。
3. 启用 Google Drive API。
4. 创建 OAuth Client ID，应用类型选 Desktop app。
5. 把生成的 Client ID 和 Client Secret 填回 rclone。

## Scope 选择

用于备份上传时，常用选择：

- `drive`：完整读写 Google Drive，最省心。
- `drive.file`：只访问 rclone 创建或打开过的文件，更收敛，但可见范围较小。

如果不确定，先选 `drive`。只读 scope 不适合 DriveGuard，因为脚本需要创建目录、上传文件和清理旧备份。

## 可选项

常见情况可以这样选：

- `root_folder_id`：直接回车留空，除非你只想让 remote 固定到某个 Google Drive 文件夹。
- `service_account_file`：个人账号 OAuth 通常留空。
- `Edit advanced config?`：选 `n`。

如果想把备份限制在某个专门文件夹，可以在 Google Drive 网页打开该文件夹，从 URL 中复制文件夹 ID，填入 `root_folder_id`。

### 只备份到 backup 文件夹

如果你不想让 DriveGuard 在 Google Drive 根目录下创建内容，有两种做法。

第一种更简单：`root_folder_id` 留空，在 `sudo dg configure` 里把 `云端远程目录` 填成 `backup`。这样 rclone remote 仍指向整个 Google Drive，不限制 rclone 的可见范围，但 DriveGuard 只会把备份写到：

```text
cloud:driveguard/site/
cloud:driveguard/database/
```

如果 `backup` 文件夹不存在，DriveGuard 上传前会通过 `rclone mkdir` 自动创建。

第二种更收敛：让 rclone remote 的根目录就是 `backup` 文件夹。先在 Google Drive 网页新建一个 `backup` 文件夹，打开这个文件夹后，从浏览器地址栏复制最后那段文件夹 ID，例如：

```text
https://drive.google.com/drive/folders/这里就是文件夹ID
```

然后在 rclone 配置里把这个 ID 填到 `root_folder_id>`。这样 `cloud:` 的根目录就等于 Google Drive 里的 `backup` 文件夹。此时 DriveGuard 的 `云端远程目录` 可以继续保留 `driveguard`，最终路径会是：

```text
backup/driveguard/site/
backup/driveguard/database/
```

如果你希望所有 DriveGuard 文件直接放在 Google Drive 根目录下的 `driveguard/site/` 和 `driveguard/database/` 下，则保持 `云端远程目录` 为 `driveguard` 即可。

## 授权

如果服务器有浏览器，`Use web browser to automatically authenticate rclone with remote?` 可以选 `y`。

如果是 Xshell/SSH 连接的服务器，通常选 `n`：

1. rclone 会显示一条需要在本地电脑执行的 `rclone authorize "drive" ...` 命令。
2. 在本地电脑安装 rclone 并执行这条命令。
3. 本地浏览器完成 Google 登录和授权。
4. 把本地命令输出的 token JSON 粘回服务器终端。

随后 rclone 会询问是否配置 Shared Drive。个人 Google Drive 选 `n`；如果要备份到团队盘或共享盘，选 `y` 并按提示选择目标盘。

最后选择 `y` 保存 remote，然后退出配置。

## 验证

如果 remote 名称是 `cloud`：

```bash
rclone lsd cloud:
```

建议再验证 DriveGuard 需要的基础操作：

```bash
rclone mkdir cloud:driveguard/_test
rclone lsf cloud:driveguard
rclone rmdir cloud:driveguard/_test
```

如果这些命令正常，DriveGuard 就能使用这个 Google Drive remote。

## 接入 DriveGuard

配置 DriveGuard：

```bash
sudo dg configure
```

关键项：

- `rclone remote 名称`：填 `cloud`，或你的 remote 名称。
- `云端远程目录`：建议保留 `driveguard`。
- 设置备份加密密码。
- 如需数据库备份，设置 MySQL/MariaDB 或 PostgreSQL 连接信息。

然后执行一次备份测试：

```bash
sudo dg backup
sudo dg status
sudo dg log 100
```

## 常见问题

- `rclone remote 不存在`：remote 名称和 `dg configure` 中填写的名称不一致。
- `Google Drive 连接失败`：重新执行 `sudo dg auth`，或用 `rclone lsd remote:` 单独排查授权。
- `insufficient permissions`：scope 可能选成只读，重新配置并选择可写 scope。
- 上传慢或限流：可以考虑创建自己的 Google OAuth Client ID，或调低并发/分块参数。
