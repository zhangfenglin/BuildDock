# 产品概述

## 1. 一句话定位

**BuildDock 是面向任意 Agent 系统的「用户设备任务运行时 + 控制面」——让外部系统通过 API 触发任务，在用户自有设备上执行，并通过 API / Web / Mobile 追踪结果。**

## 2. 要解决的问题

AI Agent、自动化系统、CI 工具等在生成代码或执行计划后，常常面临：

| 痛点 | 说明 |
|------|------|
| 云端执行受限 | 云沙箱资源固定、环境不一致、无法访问内网/私有依赖 |
| 本地执行不可调度 | Agent 在用户笔记本上跑，但缺少中心化调度与追踪 |
| 触发与执行分离 | 触发方（API/Agent）与执行方（用户设备）之间缺少标准协议 |
| 不可观测 | 任务下发后难以统一查看日志、状态、产物 |

BuildDock 提供统一的**控制面**，连接「任意触发源」与「用户注册设备」。

## 3. 核心能力

```
触发源（API / Webhook / Agent / CI）
        │
        ▼
   BuildDock 平台
   ├── 任务调度（Placement）
   ├── 队列与 Lease
   ├── 日志 / 事件 / 产物存储
   └── Web / Mobile 追踪
        │
        ▼
   用户设备 CLI Agent
   ├── 注册 & 心跳
   ├── 能力上报
   ├── 任务消费 & 执行
   └── 结果回传
```

### 3.1 平台侧

- 设备注册与审批（可选）
- 通用任务创建 GraphQL API
- 基于 Capability 的任务路由
- 任务生命周期管理（排队、分配、执行、重试、超时、取消）
- 日志流式推送、产物存储
- Web Dashboard / Mobile 状态追踪
- Webhook 事件回调

### 3.2 设备侧（CLI Agent）

- 单二进制，用户本地安装
- 出站连接平台（无需开入站端口）
- 上报设备能力与负载
- 拉取并执行任务
- 流式上报日志与进度

## 4. 目标用户

| 用户 | 场景 |
|------|------|
| 个人开发者 | 让 AI Agent 在自己机器上跑 build/test，平台统一追踪 |
| 小团队 | 共享设备池，按标签路由任务 |
| 平台/Agent 构建者 | 通过 API 将执行任务 offload 到用户设备 |
| 企业内部 | 内网环境、私有依赖、合规审计 |

## 5. 非目标（明确不做）

- **不是**完整 CI/CD 平台（不提供 pipeline DSL、不替代 GitHub Actions）
- **不是**云沙箱（不在平台侧托管 compute，E2B/Modal 是互补关系）
- **不是**纯 Fleet 运维工具（不是 Huginn/Edge Core 的 SSH 管理替代品）
- **不绑定**任何特定 IDE 或 Agent 产品（Cursor 只是可能的触发源之一）

## 6. 产品定位语

> **Bring Your Own Compute for Agents**

或中文：

> **任意 Agent 的执行层基础设施**

## 7. MVP 边界

### 第一期（MVP）

| 模块 | 范围 |
|------|------|
| 任务类型 | `shell`、`script` |
| Placement | `device_id`、 `required_labels`、`required_handlers` |
| Capability | `handlers`、`labels`、`load`、`runtimes` |
| 结果 | exit_code、stdout/stderr、artifacts |
| 事件 | `status_changed`、`log` |
| 信任级别 | 仅 `trusted` |
| 安全 | 见 [安全要求](./security.md) MVP 16 项 |
| 触发 | GraphQL API + Webhook |
| 客户端 | CLI Agent + Web Dashboard |

### 第二期

| 模块 | 范围 |
|------|------|
| 任务类型 | `http`、`docker`、`plugin`、`agent_message` |
| Placement | 完整 `capability_match` + 多种 strategy |
| 客户端 | Mobile App |
| 集成 | MCP Server |
| 安全 | `untrusted` 任务 + sandbox；见 [安全要求](./security.md) V2 |
| 编排 | `composite` 多步任务 |

## 8. 成功指标（MVP）

- 设备注册到首次任务执行 < 5 分钟
- 任务状态从 `queued` 到 `running` P95 < 10 秒（设备在线）
- 日志端到端延迟 P95 < 2 秒
- Agent 断线重连后任务不丢失（lease 过期可 re-queue）
