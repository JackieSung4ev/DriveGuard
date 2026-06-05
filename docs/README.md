# DriveGuard Wiki

这里存放 DriveGuard 的场景化配置文档。README 只保留项目入口和常用命令，具体步骤沉淀在这里。

## 文档列表

| 文档 | 适用场景 |
| --- | --- |
| [初始配置实战：CentOS Stream 8 + Google Drive](initial-setup-centos-google-drive.md) | 从空服务器开始安装 git/rclone、处理 Google OAuth、配置 `backup` 目录并完成首次备份 |
| [Google Drive rclone 初始化配置](google-drive-rclone.md) | 单独配置 Google Drive remote，理解 `root_folder_id`、授权 token 和 `backup` 文件夹 |
| [恢复备份](restore-backups.md) | 下载 `.enc` 后的服务器/Windows 解密命令、网站解压和数据库导入 |

## 推荐阅读顺序

1. 第一次部署：先看 [初始配置实战](initial-setup-centos-google-drive.md)。
2. 只想理解 Google Drive remote：看 [Google Drive rclone 初始化配置](google-drive-rclone.md)。
3. 已经配置好 remote：回到项目 [README](../README.md) 执行 `dg configure` 和 `dg backup`。
4. 要恢复下载下来的 `.enc` 文件，或查解密命令：看 [恢复备份](restore-backups.md)。
