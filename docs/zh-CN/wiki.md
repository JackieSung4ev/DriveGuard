# DriveGuard Wiki

这里存放 DriveGuard 的场景化操作文档。项目首页 README 只保留能力概览、快速开始和常用命令；具体配置、授权、恢复和排障步骤都沉淀在这里。

## 文档列表

| 文档 | 适用场景 |
| --- | --- |
| [初始配置实战：CentOS Stream 8 + Google Drive](initial-setup-centos-google-drive.md) | 从空服务器开始安装依赖、处理 Google OAuth、配置数据库连接并完成首次备份 |
| [Google Drive rclone 初始化配置](google-drive-rclone.md) | 单独理解 Google Drive remote、`root_folder_id`、授权 token 和 `backup` 文件夹 |
| [恢复备份](restore-backups.md) | 下载 `.enc` 后的服务器/Windows 解密命令、网站解压、MySQL/PostgreSQL 导入 |

## 推荐阅读顺序

1. 第一次部署：先看 [初始配置实战](initial-setup-centos-google-drive.md)。
2. 只想理解 Google Drive remote：看 [Google Drive rclone 初始化配置](google-drive-rclone.md)。
3. 已经配置好 remote：回到项目 [README](../README.md) 执行 `dg configure` 和 `dg backup`。
4. 要恢复下载下来的 `.enc` 文件，或查解密命令：看 [恢复备份](restore-backups.md)。

## 内容边界

- README：项目是什么、能做什么、怎么快速跑起来。
- Wiki：具体怎么填、遇到报错怎么排、恢复时每一步怎么做。
