# DriveGuard Wiki

**语言 / Languages:** [中文](wiki.md) | [English](../README.md)

这里存放 DriveGuard 的场景化操作文档。根目录 README 保持 Web UI 概览、快速开始和 Web UI 常用命令；终端优先的 CLI 细节放在 CLI 指南，更细的配置、授权、恢复和排障步骤放在 Wiki 文档里。

## 文档列表

| 文档 | 适用场景 |
| --- | --- |
| [初始配置实战：CentOS Stream 8 + Google Drive](initial-setup-centos-google-drive.md) | 从空服务器开始安装依赖、处理 Google OAuth、配置数据库连接并完成首次备份 |
| [Google Drive rclone 初始化配置](google-drive-rclone.md) | 单独理解 Google Drive remote、`root_folder_id`、授权 token 和 `backup` 文件夹 |
| [恢复备份](restore-backups.md) | 下载 `.enc` 后的服务器或 Windows 解密命令、网站解压、MySQL/PostgreSQL 导入 |
| [CLI 指南](cli.md) | 终端优先的安装、备份、定时、日志和命令参考 |
| [Web UI 规划](web-ui.md) | Web 控制台、Go API、仓库结构和安全边界 |

## 推荐阅读顺序

1. 第一次部署：先看 [初始配置实战](initial-setup-centos-google-drive.md)。
2. 只想理解 Google Drive remote：看 [Google Drive rclone 初始化配置](google-drive-rclone.md)。
3. 偏好终端方式备份：使用 [CLI 指南](cli.md)。
4. 要恢复下载下来的 `.enc` 文件：看 [恢复备份](restore-backups.md)。
5. 准备使用或开发 Web 控制台：看 [Web UI 规划](web-ui.md)。

## 内容边界

- README：Web UI 是什么、能做什么、怎么快速跑起来。
- CLI 指南：终端优先的安装、备份、定时、日志和命令参考。
- Wiki：具体怎么填、遇到报错怎么排、恢复时每一步怎么做。
