# DriveGuard Web UI 指南

**语言 / Languages:** [中文](web-ui.md) | [English](../web-ui.md)

DriveGuard Web UI 是项目默认的浏览器操作入口。它包含 Vue 控制台、Go API 服务和服务器部署脚本，同时继续复用 CLI 的加密备份引擎。如果你偏好纯终端操作，请阅读 [CLI 指南](cli.md)。

## 安装内容

- `driveguard-web.sh`：Web UI 安装和维护脚本
- `driveguardd`：本地 Go API 服务
- Vue 3 + Vite 前端静态资源
- DriveGuard CLI 引擎，用于备份、cron、恢复和云端操作
- Linux 服务器上的 systemd API 服务

## 快速开始

```bash
git clone https://github.com/JackieSung4ev/DriveGuard.git
cd DriveGuard
sudo bash driveguard-web.sh install
```

如果服务器上已经安装过 DriveGuard Web UI，以后更新就运行：

```bash
cd /opt/driveguard-web
sudo bash driveguard-web.sh update
```

未设置 `WEB_ROOT` 时，`install`、`update` 和 `update-frontend` 会自动检测当前把 `/api` 代理到 `driveguardd` 的 Nginx/服务器面板站点目录。只有需要覆盖自动检测结果时，才手动传入 `WEB_ROOT=/path/to/site`。

## 仓库结构

```text
driveguard.sh                 Bash CLI 和备份引擎
driveguard-web.sh             Web UI 安装和维护脚本
README.md                     项目概览和产品入口
docs/                         文档
docs/web-ui.md                英文 Web UI 指南
docs/zh-CN/web-ui.md          中文 Web UI 指南
web/                          Vue 3 + Vite 前端
server/                       Go API 服务
```

后端结构：

```text
server/
  cmd/driveguardd/            HTTP 服务入口
  internal/api/               路由、handler 和响应类型
  internal/driveguard/        DriveGuard 命令适配层
  internal/jobs/              进程内任务状态管理
```

前端结构：

```text
web/
  src/App.vue                 控制台外壳和仪表盘视图
  src/services/api.ts         API 客户端；只有设置 VITE_USE_MOCKS=true 才使用 mock 数据
  src/types.ts                前端共享类型
  src/assets/main.css         设计 token 和响应式布局
```

## 产品边界

Web UI 是服务器备份运维控制台，不会替代或隐藏 CLI，而是在稳定 CLI 引擎上提供浏览器工作流：

- 登录本地管理员账号
- 修改密码并启用 TOTP 二步验证
- 授权云端存储
- 创建或编辑定时备份计划
- 选择网站、数据库或全量备份范围
- 选择目标云盘和云端目录
- 执行加密备份任务并查看最近任务
- 查看服务日志和备份日志
- 通过临时工作目录解密和恢复上传的备份文件
- 自动识别浏览器语言，并支持手动切换中文/英文
- 对需要 root 或 Linux 工具的命令返回清晰 API 错误

当前备份计划实现会把 Web UI 表单映射到现有 CLI 的单一计划配置。“保存并启用”会更新 CLI 配置文件，通过 `dg cron` 安装 root crontab，并通过 `dg install-guard` 安装 systemd cron 守护。多计划编排可以在单计划服务器面板流程稳定后再扩展。

初始云端支持聚焦在 Google Drive 和 Microsoft OneDrive，底层仍通过 `rclone` 授权和上传。其他高级 provider 可以继续通过 CLI 的 `rclone config` 处理。

服务器配置 `DRIVEGUARD_PUBLIC_URL`、`DRIVEGUARD_GOOGLE_CLIENT_ID` 和 `DRIVEGUARD_GOOGLE_CLIENT_SECRET` 后，Google Drive 可以使用 Web OAuth 直连授权。Google OAuth client 必须是 Web application 类型，并加入这个 Authorized redirect URI：

```text
${DRIVEGUARD_PUBLIC_URL}/api/v1/cloud/google/callback
```

回调会在服务器端交换授权码，并把 token 写入选中的 rclone remote，默认 remote 是 `gdrive:`。如果没有配置 Google Web OAuth，界面会回退到 CLI 风格的授权流程。

## API 形状

```text
GET  /api/v1/health
GET  /api/v1/auth/state
POST /api/v1/auth/bootstrap
POST /api/v1/auth/login
POST /api/v1/auth/logout
POST /api/v1/auth/password
POST /api/v1/auth/totp/setup
POST /api/v1/auth/totp/enable
POST /api/v1/auth/totp/disable
POST /api/v1/security/archive-password
POST /api/v1/restore/decrypt
GET  /api/v1/status
GET  /api/v1/cloud-providers
GET  /api/v1/cloud/google/auth-url
GET  /api/v1/cloud/google/callback
GET  /api/v1/backup-plans
POST /api/v1/backup-plans
GET  /api/v1/logs?lines=80
GET  /api/v1/jobs
GET  /api/v1/jobs/{id}
POST /api/v1/jobs/backup
```

开发环境默认监听 `127.0.0.1`。正式部署应放在带 TLS 和认证的反向代理之后。

本地账号系统使用 PBKDF2-HMAC-SHA256 存储密码哈希，使用 HttpOnly SameSite 会话 Cookie，写操作 API 需要 CSRF token，并支持 TOTP 二步验证。认证文件在 Linux/macOS 默认位于 `/etc/driveguard/web-auth.json`，Windows 开发环境使用 `driveguard-auth.json`。

## 部署脚本

`driveguard-web.sh` 让 Web UI 操作和独立 CLI 入口保持分离，同时自动完成服务器侧工作：

- 中英文菜单
- Go、Node.js、rclone、git、curl、rsync 和 cron 依赖检查
- 安装 `driveguardd`、systemd 服务、前端构建和静态资源发布
- 全量更新、仅后端更新、仅前端更新
- 发布前端时自动检测 Nginx/服务器面板站点根目录
- API 健康检查、systemd 状态检查和 journal 日志查看
- Google OAuth 配置，并从 OAuth client JSON 提取 client ID/secret
- 卸载 Web UI，同时默认保留 CLI 配置和备份文件

常用命令：

```bash
sudo bash driveguard-web.sh install
sudo PUBLIC_URL=https://backup.example.com bash driveguard-web.sh oauth /root/client_secret.json
sudo bash driveguard-web.sh update
sudo bash driveguard-web.sh status
sudo bash driveguard-web.sh logs 120
```

## 本地开发

后端和前端分开运行：

```bash
cd server
go run ./cmd/driveguardd

cd ../web
npm install
npm run dev
```

Vite 开发服务器会把 `/api` 代理到 `http://127.0.0.1:8080`。如果只想预览 UI、不启动 Go API，可以运行：

```bash
cd web
npm run dev:mock
```

## 安全注意

- 没有 TLS 和认证时，不要把 DriveGuard 暴露到公网。
- API 不返回备份密码、数据库密码、OAuth token 或完整 `rclone.conf`。
- 恢复/解密上传只能使用临时文件，并在响应结束后删除上传文件和解密文件。
- 备份、cron、恢复和卸载都属于特权操作。
- UI 中的破坏性操作需要明确确认。
