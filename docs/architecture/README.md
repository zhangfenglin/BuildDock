# 项目架构设计

BuildDock 采用 **Monorepo** 组织，后端与 CLI 使用 **Go**，前端使用 **Vite + TypeScript**。

## 文档索引

| 文档 | 说明 |
|------|------|
| [Monorepo 结构](./monorepo.md) | 仓库目录、模块划分、依赖关系 |
| [后端架构（Go）](./backend.md) | GraphQL Server、领域层、调度器、存储 |
| [CLI 命令设计](./cli-commands.md) | login / remote-control / status 命令契约 |
| [CLI Agent 架构（Go）](./cli.md) | builddock 模块、Executor、运行时 |
| [前端架构（Vite + TS）](./frontend.md) | Web Dashboard、GraphQL 客户端、页面结构 |
| [基础设施与部署](./infrastructure.md) | PostgreSQL、Redis、对象存储、Docker、CI |
| [数据库设计](./database.md) | 总览、ER、生命周期 |
| [数据表字段字典](./database-tables.md) | 逐表逐列说明 |
| [JSONB 结构约定](./database-jsonb.md) | spec/placement/result JSON |
| [sqlc 查询目录](./database-queries.md) | Repository 查询与事务 |
| [Init DDL](./migrations/000001_init.sql) | 完整初始化 SQL |
| [认证与授权](./auth.md) | Token 模型、RBAC、限流 |
| [调度器设计](./scheduler.md) | Placement 匹配、Lease、后台 Worker |
| [端到端集成](./integration.md) | 三端协作链路、联调清单 |

## 技术栈总览

| 层级 | 技术 | 说明 |
|------|------|------|
| API | GraphQL（gqlgen） | Query / Mutation / Subscription |
| 后端 | Go 1.22+ | 单一 `server` 二进制 |
| CLI | Go 1.22+ | 单一 `builddock-agent` 二进制 |
| 前端 | Vite 6 + TypeScript 5 + React 19 | SPA Dashboard |
| GraphQL Client | urql + graphql-ws | Query/Mutation + Subscription |
| UI | Tailwind CSS + shadcn/ui | 组件库 |
| 数据库 | PostgreSQL 16 | 主存储 + 任务队列 |
| 缓存/事件 | Redis 7（可选） | Subscription fan-out、限流 |
| 对象存储 | MinIO / S3 | 产物与日志归档 |

## 与产品文档的关系

```
docs/product/          → 做什么（产品模型、API 契约）
docs/api/              → GraphQL Schema 定义
docs/architecture/     → 怎么做（代码结构、模块、部署）
```
