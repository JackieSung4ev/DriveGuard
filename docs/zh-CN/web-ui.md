# DriveGuard Web UI 规划

DriveGuard 继续保留当前 Bash CLI，作为稳定的命令行版本和安装入口。Web UI 以 monorepo 的方式新增，这样 `dg` 的现有工作流不受影响，同时逐步演进 Go 后端和 Vue 控制台。

## 仓库结构

```text
driveguard.sh                 稳定的 Bash CLI 与安装入口
README.md                     项目概览和快速开始
docs/                         Wiki 文档
docs/web-ui.md                Web UI 架构与路线
docs/zh-CN/web-ui.md          中文 Web UI 规划
web/                          Vue 3 + Vite 前端
server/                       Go API 服务
```

后端规划：

```text
server/
  cmd/driveguardd/            HTTP 服务入口
  internal/api/               路由、handler、响应类型
  internal/driveguard/        对 DriveGuard 命令的封装
  internal/jobs/              任务状态管理
```

前端规划：

```text
web/
  src/App.vue                 控制台外壳和仪表盘
  src/services/api.ts         API 客户端；只有显式设置 VITE_USE_MOCKS=true 才使用 mock 数据
  src/types.ts                前端共享类型
  src/assets/main.css         设计 token 和响应式布局
```

## 产品边界

第一版 Web UI 是运维控制台，不直接取代 CLI 安装器。主流程要更接近服务器面板插件：

- 先登录本地管理员账号
- 支持修改密码和 TOTP 二步验证
- 先授权云盘
- 再创建定时备份计划
- 选择网站、数据库或全量备份
- 选择目标云盘和云端目录
- 上传加密备份文件，在临时目录中解密，然后下载恢复文件
- 查看最近任务和日志
- 自动识别浏览器语言，并支持手动切换中文/英文
- 对需要 root 或 Linux 工具的命令返回清晰错误

后端第一期可以先封装 `driveguard.sh`。等 API 和界面稳定后，再逐步把核心备份逻辑迁移到 Go。

第一期云盘先收窄到 Google Drive 和 Microsoft OneDrive，底层仍通过 `rclone` 授权和上传。

授权界面采用三步流程：复制指定云盘的 `dg auth` 命令、打开生成的 OAuth 链接、再把跳转后的验证 URL 粘贴回来确认。Web UI 分支里 `sudo dg auth` 会变成云盘选择器，也支持 `sudo dg auth google` 和 `sudo dg auth onedrive` 直接进入指定云盘授权；高级 `rclone config` 仍保留为兜底入口。

## API 初版

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
GET  /api/v1/backup-plans
POST /api/v1/backup-plans
GET  /api/v1/logs?lines=80
GET  /api/v1/jobs
GET  /api/v1/jobs/{id}
POST /api/v1/jobs/backup
```

开发阶段默认监听 `127.0.0.1`。正式部署时应放在带 TLS 和认证的反向代理之后。

本地账号系统使用 PBKDF2-HMAC-SHA256 存储密码哈希，使用 HttpOnly SameSite 会话 Cookie，写操作 API 需要 CSRF token，并支持 TOTP 二步验证。认证文件默认在 Linux/macOS 使用 `/etc/driveguard/web-auth.json`，Windows 开发环境使用 `driveguard-auth.json`。

## 安全注意

- 没有 TLS 和认证时不要暴露到公网。
- API 不返回备份密码、数据库密码、OAuth token 或完整 `rclone.conf`。
- 恢复/解密上传只能使用临时文件，并在响应结束后删除上传文件和解密文件。
- 备份、cron、恢复、卸载都属于特权操作。
- UI 中的破坏性操作需要明确确认。

## 构建顺序

1. 先做基于页面的 sidebar 导航。
2. 增加本地管理员登录、修改密码和 TOTP 设置。
3. 增加 Google Drive 和 OneDrive 授权页面。
4. 增加网站、数据库、全量备份的定时任务表单，支持每天、每周、每月、间隔和自定义 cron。
5. 再做 Go HTTP 服务，提供认证、健康检查、状态、云盘、计划、日志和任务接口。
6. 开发环境通过 Vite proxy 连接 Go 服务。
7. API 稳定后，再把前端构建产物嵌入或交给 Go 服务托管。
