# BuildDock

**Bring Your Own Compute for Agents** — 通用代理任务平台。

用户将设备注册到 BuildDock 后，任意系统可通过 API 触发任务；CLI Agent 在用户设备上消费执行，结果通过 API / Web / Mobile 追踪。

## 核心能力

- 设备注册与能力上报（Capability）
- 通用任务调度（Placement + Lease）
- CLI Agent 出站拉取任务
- 流式日志与产物回传
- Web Dashboard 实时追踪

## 文档

完整产品设计文档见 [docs/](./docs/README.md)：

| 文档 | 说明 |
|------|------|
| [产品概述](./docs/product/overview.md) | 定位、目标用户、MVP 边界 |
| [系统架构](./docs/product/architecture.md) | 组件、通信、数据流 |
| [Device Capability](./docs/product/device-capability.md) | 设备注册与能力模型 |
| [Task Schema](./docs/product/task-schema.md) | 通用任务结构与类型 |
| [Agent 协议](./docs/product/agent-protocol.md) | CLI Agent 交互协议 |
| [API 概览](./docs/product/api-overview.md) | REST API 设计 |
| [竞品分析](./docs/research/competitive-analysis.md) | 竞品调研 |

## 状态

当前阶段：**产品设计**（Schema Version `1.0`）

## License

TBD
