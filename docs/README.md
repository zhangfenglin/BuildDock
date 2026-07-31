# BuildDock 文档

BuildDock 是一个**用户设备注册 + 远程任务调度 + CLI Agent 执行 + 多端追踪**的通用代理任务平台。

## 文档索引

### 产品

| 文档 | 说明 |
|------|------|
| [产品概述](./product/overview.md) | 定位、目标用户、核心能力、MVP 边界 |
| [系统架构](./product/architecture.md) | 组件划分、通信模式、数据流 |
| [Device Capability 模型](./product/device-capability.md) | 设备注册、能力上报、心跳、标签 |
| [Task Schema](./product/task-schema.md) | 通用任务结构、类型、状态机、结果 |
| [Agent 协议](./product/agent-protocol.md) | CLI Agent 与平台的交互协议 |
| [GraphQL API 概览](./product/api-overview.md) | GraphQL Query / Mutation / Subscription |
| [GraphQL Schema](../api/graphql-schema.graphql) | 完整 Schema 定义文件 |

### 架构设计

| 文档 | 说明 |
|------|------|
| [架构设计索引](./architecture/README.md) | 技术栈、文档导航 |
| [Monorepo 结构](./architecture/monorepo.md) | 仓库目录与模块划分 |
| [后端架构（Go）](./architecture/backend.md) | gqlgen、分层、调度器 |
| [CLI 命令设计](./architecture/cli-commands.md) | login / start / stop / status |
| [CLI 架构（Go）](./architecture/cli.md) | Agent Runtime、Executor |
| [前端架构（Vite + TS）](./architecture/frontend.md) | Dashboard、urql |
| [数据库设计](./architecture/database.md) | PostgreSQL 总览 |
| [数据表字段字典](./architecture/database-tables.md) | 逐表逐列说明 |
| [JSONB 结构约定](./architecture/database-jsonb.md) | JSON 格式约定 |
| [sqlc 查询目录](./architecture/database-queries.md) | Repository SQL |
| [认证与授权](./architecture/auth.md) | Token、RBAC |
| [调度器设计](./architecture/scheduler.md) | Placement、Lease |
| [基础设施与部署](./architecture/infrastructure.md) | Docker、CI/CD |
| [端到端集成](./architecture/integration.md) | 三端协作与联调 |

### 调研

| 文档 | 说明 |
|------|------|
| [竞品分析](./research/competitive-analysis.md) | 竞品分层、差异化、借鉴点 |

## Schema 版本

当前设计文档对应 **Schema Version `1.0`**。
