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
  src/services/api.ts         API 客户端，开发环境带兜底 mock 数据
  src/types.ts                前端共享类型
  src/assets/main.css         设计 token 和响应式布局
```

## 产品边界

第一版 Web UI 是运维控制台，不直接取代 CLI 安装器。它优先覆盖日常查看和安全操作：

- 当前配置与健康状态总览
- 网站、数据库备份目标摘要
- 手动触发备份
- 最近任务和日志
- cron 与 guard 状态可见
- 对需要 root 或 Linux 工具的命令返回清晰错误

后端第一期可以先封装 `driveguard.sh`。等 API 和界面稳定后，再逐步把核心备份逻辑迁移到 Go。

## API 初版

```text
GET  /api/v1/health
GET  /api/v1/status
GET  /api/v1/logs?lines=80
GET  /api/v1/jobs
GET  /api/v1/jobs/{id}
POST /api/v1/jobs/backup
```

开发阶段默认监听 `127.0.0.1`。正式部署时应放在带 TLS 和认证的反向代理之后。

## 安全注意

- 没有认证时不要暴露到公网。
- API 不返回备份密码、数据库密码、OAuth token 或完整 `rclone.conf`。
- 备份、cron、恢复、卸载都属于特权操作。
- UI 中的破坏性操作需要明确确认。

## 构建顺序

1. 先做 Vue 控制台，并提供 mock 兜底数据，让前端不依赖后端也能开发。
2. 再做 Go HTTP 服务，提供健康检查、状态、日志和任务接口。
3. 开发环境通过 Vite proxy 连接 Go 服务。
4. API 稳定后，再把前端构建产物嵌入或交给 Go 服务托管。
