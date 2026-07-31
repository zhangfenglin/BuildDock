# 竞品分析

> 调研时间：2026-07-30

## 1. 需求定义

BuildDock 位于多个成熟品类的交叉空白：

- 用户自有设备注册
- 通用任务 dispatch API（不限特定 Agent 产品）
- CLI Agent 消费执行
- API + Web + Mobile 统一追踪

## 2. 竞品分层

### Tier 1：架构几乎一致

| 产品 | 模型 | 通信 | 任务类型 | 说明 |
|------|------|------|---------|------|
| [DevFleet](https://github.com/eviltwin7648/devfleet) | Hub + Go Agent + Web | 注册 + 心跳 + 轮询 | Shell 脚本 | 与 MVP 描述高度重合 |
| [Huginn](https://github.com/Sunderrrr/Huginn) | FastAPI Hub + Go Worker + MCP | 长轮询 | 命令执行 | 含 RBAC、审计 |
| [AgentGrid](https://github.com/hanfeihu/agentgrid) | Hub + Rust Worker | HTTP | command/HTTP/file/Docker/browser | AI 操作真实机器 |
| [Tikeo](https://github.com/yhyzgn/tikeo) | 调度 + Worker Tunnel | 出站 gRPC | 通用 Job + 工作流 | 工程化最完整 |
| [Windmill Agent Workers](https://www.windmill.dev/docs/core_concepts/agent_workers) | 主集群 + 远程 Agent | HTTP 出站 + JWT | 多语言脚本 | Enterprise |
| [remotecmd-cli](https://github.com/javimosch/remotecmd-cli) | Relay + Daemon | WebSocket 出站 | Shell，JSON 输出 | AI agent 友好 |

### Tier 2：Workflow 编排 + 自托管 Worker

| 产品 | 优势 | 与 BuildDock 差距 |
|------|------|------------------|
| [Hatchet](https://hatchet.run/) | DAG、持久化、可自托管 | Worker 是部署的容器，非用户笔记本 |
| [Temporal](https://temporal.io/) | 强一致工作流 | 学习曲线高，偏后端 infra |
| [Trigger.dev](https://trigger.dev/) | TS 友好、AI workflow | 默认跑在平台侧 |
| [Inngest Connect](https://www.inngest.com/docs/setup/connect) | 出站 WebSocket | Function 需预注册 |

### Tier 3：CI/CD Runner

GitHub Actions Runner、Buildkite Agent、Semaphore Agent、Woodpecker Agent 等。

- **可借鉴**：注册 token、长轮询、lease、日志流、artifact
- **差异**：绑定 repo/workflow YAML，非通用 agent task

### Tier 4：Edge / IoT Fleet

AWS IoT Greengrass、Propeller Proplet、Edge Core 等。

- 设备管理强，Agent 通用任务弱
- 过重，不适合开发者 workstation 场景

### Tier 5：云沙箱

E2B、Modal、Daytona、Blackbox Cloud Agent 等。

- 执行在云端，非用户设备
- 可作为 BuildDock 的云端 fallback，非直接竞品

### Tier 6：AI 编程专用

AstralOps、RemoteBridge、RCH、Microsoft UFO³ 等。

- 模式可参考（SSH proxy、hook offload、DeviceRegistry）
- 场景较窄或方向相反

## 3. 市场空白

目前没有产品同时做好：

1. 用户自有设备注册（含 NAT 后笔记本）
2. 通用任务 dispatch API
3. CLI Agent 消费
4. Web + Mobile 实时追踪
5. 面向外部 Agent 系统的开放集成

## 4. BuildDock 差异化

| 维度 | 差异化 |
|------|--------|
| 定位 | Developer-first，用户 workstation 而非 datacenter |
| 集成 | Agent-native API，结构化 I/O、MCP、Webhook |
| 体验 | 轻量 CLI 单二进制注册即用 |
| 追踪 | Web + Mobile 一等公民 |
| 开放 | 不限任何 Agent/IDE 产品 |

## 5. 推荐对标项目（实现参考优先级）

1. **DevFleet** — Agent 注册、轮询、SSE 日志流
2. **AgentGrid** — 任务类型与 capability 模型
3. **Tikeo** — Worker Tunnel、lease、fencing、RBAC
4. **Windmill Agent Workers** — 出站 HTTP + JWT + tag 路由
5. **Huginn** — MCP 集成、设备审批、审计

次要参考：Inngest Connect（WebSocket worker）、Buildkite Agent（日志/artifact）。

## 6. 架构共识（竞品验证）

| 模式 | 采用者 | 结论 |
|------|--------|------|
| 出站连接、无入站端口 | Semaphore、Buildkite、Windmill、Inngest | **必选** |
| HTTP 长轮询领任务 | DevFleet、Huginn、Buildkite | MVP 首选 |
| Lease + 心跳 | Tikeo、Woodpecker、GitHub Actions | **必选** |
| Capability/Label 路由 | AgentGrid、CircleCI、GitHub Actions | **必选** |
| 流式日志 | DevFleet SSE、Buildkite | **必选** |

## 7. 风险

| 风险 | 缓解 |
|------|------|
| 安全：远程代码执行 | sandbox、allowlist、审批、租户隔离 |
| 设备在线率 | 队列持久化、超时、重试、指定设备 fallback |
| 与 Workflow 引擎重叠 | 聚焦设备管理 + Agent API + 多端追踪 |
| 开源竞品 | 明确体验与 Mobile/Agent 集成差异化 |
