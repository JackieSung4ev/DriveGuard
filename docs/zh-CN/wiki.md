# DriveGuard Wiki

**语言 / Languages:** [中文](wiki.md) | [English](../README.md)

这里存放 DriveGuard 的场景化操作文档。根 README 负责说明两个产品入口：Web UI 是默认的浏览器工作流，CLI 是独立的终端优先工作流。更细的安装、授权、恢复和排障步骤放在这里。

## 文档列表

| 文档 | 适用场景 |
| --- | --- |
| [初始配置实战：CentOS Stream 8 + Google Drive](initial-setup-centos-google-drive.md) | 从空服务器开始安装依赖、处理 Google OAuth、配置数据库连接并完成首次备份 |
| [Google Drive rclone 配置](google-drive-rclone.md) | 单独理解 Google Drive remote、`root_folder_id`、授权 token 和云端目录行为 |
| [恢复备份](restore-backups.md) | 下载 `.enc` 后的解密命令、网站解压、MySQL/PostgreSQL 导入 |
| [Web UI 指南](web-ui.md) | 浏览器工作流、安装脚本、部署、Go API 边界和安全说明 |
| [CLI 指南](cli.md) | 终端优先的安装、备份、定时、日志、恢复和命令参考 |

## 推荐阅读顺序

1. 第一次部署：先看 [初始配置实战](initial-setup-centos-google-drive.md)。
2. 只想理解 Google Drive remote：看 [Google Drive rclone 配置](google-drive-rclone.md)。
3. 偏好浏览器控制台：使用 [Web UI 指南](web-ui.md)。
4. 偏好终端方式备份：使用 [CLI 指南](cli.md)。
5. 要恢复下载下来的 `.enc` 文件：看 [恢复备份](restore-backups.md)。

## 内容边界

- README：产品入口概览、Web UI 快速开始、CLI 快速开始和常用命令。
- Web UI 指南：浏览器工作流、部署脚本、API 形状和安全边界。
- CLI 指南：终端优先的安装、备份、定时、日志、恢复和命令参考。
- Wiki：具体怎么填、遇到报错怎么排、恢复时每一步怎么做。
