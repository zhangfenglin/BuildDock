# GraphQL API 概览

Schema Version: `1.0`

## 1. 设计决策

BuildDock **以 GraphQL 作为唯一对外 API 契约**，覆盖触发方、Web/Mobile Dashboard 与 CLI Agent。

| 决策 | 选择 | 理由 |
|------|------|------|
| API 风格 | GraphQL | 多端（Web/Mobile/Agent）共享 Schema；按需取字段；Subscription 原生支持实时追踪 |
| 端点 | `POST /graphql` | Query / Mutation |
| 实时 | `WS /graphql`（graphql-transport-ws） | Subscription：任务事件、日志、设备状态 |
| Agent 长轮询 | `pollTask` Mutation | 服务端阻塞 resolver，Agent 无需额外 REST 端点 |
| 产物上传 | `prepareArtifactUpload` + HTTP PUT | 大文件不走 GraphQL body；预签名 URL |
| Schema 文件 | [`graphql-schema.graphql`](../api/graphql-schema.graphql) | 实现阶段单一契约来源 |

### 1.1 为何不保留 REST

- Web / Mobile / 外部 Agent 系统字段需求不同，GraphQL 避免 over-fetching
- 任务详情 + events + logs + device 可一次 query 聚合
- Subscription 替代 SSE，Dashboard 与 Mobile 共用同一套订阅
- CLI Agent 通过 Mutation 完成全部交互，降低 Agent 实现复杂度

### 1.2 混合传输（仅二进制）

| 操作 | 协议 | 说明 |
|------|------|------|
| Query / Mutation / Subscription | GraphQL | 全部控制面交互 |
| 产物文件上传 | HTTP PUT | 预签名 URL，不经过 GraphQL body |
| Webhook 回调 | HTTP POST | 平台 → 调用方，出站通知 |

## 2. 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `https://api.builddock.example.com/graphql` | POST | Query、Mutation |
| `wss://api.builddock.example.com/graphql` | WebSocket | Subscription |
| `https://storage.builddock.example.com/...` | PUT | 产物上传（预签名） |

## 3. 认证

所有 GraphQL 请求携带：

```http
Authorization: Bearer <token>
Content-Type: application/json
X-Request-Id: <uuid>
```

| 调用方 | Token | 可用操作 |
|--------|-------|----------|
| 触发方 / 外部 Agent | `api_xxx` | Query: devices, tasks；Mutation: createTask, cancelTask, approveDevice... |
| CLI Agent | `dtok_xxx` | Mutation: heartbeat, pollTask, reportEvents, completeTask... |
| 设备注册 | `reg_xxx` | 仅 `registerDevice` mutation |
| Web Dashboard | Session / OAuth | 全部 Query + Subscription（按 RBAC） |

### 3.1 注册例外

`registerDevice` 使用 Registration Token，不需要 API Key 或 Device Token：

```graphql
mutation Register($input: RegisterDeviceInput!) {
  registerDevice(input: $input) {
    device { id name approvalStatus }
    deviceToken
    pollIntervalMs
    heartbeatIntervalMs
  }
}
```

## 4. 通用约定

### 4.1 请求格式

```http
POST /graphql
Authorization: Bearer api_xxx
Content-Type: application/json

{
  "query": "mutation CreateTask($input: CreateTaskInput!) { createTask(input: $input) { id runtime { status } } }",
  "variables": {
    "input": {
      "spec": { "type": "SHELL", "name": "test", "payload": { "command": "echo hi" }, "timeoutSec": 300 },
      "placement": { "mode": "ANY" }
    }
  },
  "operationName": "CreateTask"
}
```

### 4.2 响应格式

成功：

```json
{
  "data": {
    "createTask": {
      "id": "task_01JXYZ...",
      "runtime": { "status": "QUEUED" }
    }
  },
  "extensions": {
    "requestId": "req_xxx"
  }
}
```

错误（GraphQL errors + 业务 errors）：

```json
{
  "data": null,
  "errors": [
    {
      "message": "required_labels.owner is required",
      "extensions": {
        "code": "VALIDATION_ERROR",
        "field": ["input", "placement", "requiredLabels"]
      }
    }
  ],
  "extensions": {
    "requestId": "req_xxx"
  }
}
```

Mutation 业务错误也可通过 payload 返回（不抛异常）：

```graphql
type MutationPayload {
  success: Boolean!
  errors: [UserError!]
}
```

### 4.3 分页（Relay Cursor Connections）

```graphql
query ListTasks {
  tasks(status: RUNNING, first: 20, after: "task_01JABC") {
    edges {
      node { id runtime { status } spec }
      cursor
    }
    pageInfo {
      hasNextPage
      endCursor
    }
    totalCount
  }
}
```

### 4.4 幂等

`createTask` 支持：

- Header: `X-Idempotency-Key: proj-abc:test:9f3a`
- 或 input: `idempotencyKey` / `spec.idempotencyKey`

重复请求返回同一 Task，不重复创建。

### 4.5 错误码（extensions.code）

| code | 说明 |
|------|------|
| `VALIDATION_ERROR` | 输入无效 |
| `UNAUTHORIZED` | 未认证 |
| `FORBIDDEN` | 无权限 |
| `NOT_FOUND` | 资源不存在 |
| `CONFLICT` | 幂等冲突 / lease 无效 |
| `RATE_LIMITED` | 限流 |
| `INTERNAL_ERROR` | 服务器错误 |

## 5. Query

| Query | 认证 | 说明 |
|-------|------|------|
| `viewer` | 任意 | 当前认证主体 |
| `device(id)` | API Key | 设备详情（含 capability） |
| `devices(...)` | API Key | 设备列表 |
| `task(id)` | API Key | 任务详情（含 runtime、result） |
| `tasks(...)` | API Key | 任务列表 |
| `artifact(id)` | API Key | 产物元数据 |

### 5.1 任务详情（聚合查询）

```graphql
query GetTask($id: ID!) {
  task(id: $id) {
    id
    spec
    placement
    runtime {
      status
      assignedDevice { id name status }
      progress { percent message }
      lease { leaseId expiresAt }
    }
    result {
      status
      exitCode
      durationMs
      output { structured }
      artifacts { id name url sizeBytes }
    }
    events(first: 50, types: [LOG, PROGRESS]) {
      edges {
        node { timestamp type data }
      }
    }
    logs(stream: STDOUT, first: 100) {
      edges {
        node { timestamp line }
      }
    }
  }
}
```

## 6. Mutation

### 6.1 平台 / 触发方（API Key）

| Mutation | 说明 |
|----------|------|
| `createRegistrationToken` | 创建设备注册 Token |
| `createTask` | 创建任务 |
| `cancelTask` | 取消任务 |
| `updateDevice` | 更新设备 name / labels |
| `approveDevice` | 审批设备 |
| `rejectDevice` | 拒绝设备 |
| `revokeDevice` | 吊销设备 |

### 6.2 设备注册

| Mutation | 认证 | 说明 |
|----------|------|------|
| `registerDevice` | Registration Token | 设备首次注册 |

### 6.3 CLI Agent（Device Token）

| Mutation | 说明 |
|----------|------|
| `reportCapabilities` | 上报完整 Capability |
| `heartbeat` | 心跳 |
| `pollTask` | 长轮询领取任务 |
| `acceptTask` | 接受任务 |
| `renewLease` | 续租 |
| `reportEvents` | 上报事件（单条/批量） |
| `prepareArtifactUpload` | 获取预签名上传 URL |
| `confirmArtifactUpload` | 确认上传完成 |
| `completeTask` | 提交结果 |

## 7. 核心 Mutation 示例

### 7.1 创建任务

```graphql
mutation CreateTask($input: CreateTaskInput!) {
  createTask(input: $input) {
    id
    runtime { status queuedAt }
    createdAt
  }
}
```

Variables：

```json
{
  "input": {
    "spec": {
      "type": "SCRIPT",
      "name": "validate-pr",
      "payload": {
        "language": "bash",
        "source": {
          "kind": "inline",
          "content": "#!/usr/bin/env bash\nnpm ci && npm test"
        },
        "cwd": "/workspace/app"
      },
      "timeoutSec": 3600,
      "trustLevel": "TRUSTED",
      "metadata": { "source": "custom-agent", "pr": "123" }
    },
    "placement": {
      "mode": "CAPABILITY_MATCH",
      "requiredLabels": { "owner": "alice" },
      "requiredHandlers": ["script"],
      "requiredRuntimes": [{ "name": "node", "version": ">=20" }],
      "strategy": "LEAST_LOADED"
    },
    "idempotencyKey": "proj-abc:pr-123"
  }
}
```

### 7.2 Agent 长轮询

```graphql
mutation PollTask($input: PollTaskInput!) {
  pollTask(input: $input) {
    task {
      id
      lease { leaseId expiresAt }
      spec
      resolvedSecrets
    }
  }
}
```

Variables：

```json
{
  "input": {
    "deviceId": "dev_01JABC...",
    "generation": 43,
    "availableSlots": 1,
    "supportedTypes": ["SHELL", "SCRIPT"],
    "timeoutMs": 30000
  }
}
```

- 有任务：返回 `task` 对象
- 无任务：`task` 为 `null`（Agent 立即重试或等待 `pollIntervalMs`）

### 7.3 Agent 提交结果

```graphql
mutation CompleteTask($input: CompleteTaskInput!) {
  completeTask(input: $input) {
    success
    errors { code message }
  }
}
```

### 7.4 取消任务

```graphql
mutation CancelTask($taskId: ID!) {
  cancelTask(input: { taskId: $taskId, reason: "User cancelled" }) {
    id
    runtime { status cancelRequested }
  }
}
```

## 8. Subscription

Web / Mobile 通过 WebSocket 订阅，`connection_init` 携带 Bearer Token。

### 8.1 任务事件流

```graphql
subscription TaskEvents($taskId: ID!) {
  taskEventStream(taskId: $taskId, types: [LOG, PROGRESS, STATUS_CHANGED]) {
    id
    timestamp
    type
    data
  }
}
```

### 8.2 任务状态变更

```graphql
subscription TaskUpdated($taskId: ID!) {
  taskUpdated(taskId: $taskId) {
    id
    runtime { status progress { percent message } }
    result { status exitCode }
  }
}
```

### 8.3 设备状态

```graphql
subscription DeviceOnline($deviceId: ID) {
  deviceStatusChanged(deviceId: $deviceId) {
    id
    status
    agent { lastSeenAt }
    capability { load { availableSlots activeTasks } }
  }
}
```

### 8.4 Dashboard 新任务

```graphql
subscription NewTasks($orgId: ID!) {
  taskCreated(orgId: $orgId) {
    id
    spec
    runtime { status }
    createdAt
  }
}
```

## 9. 产物上传流程

GraphQL 不传输文件二进制，走预签名 URL：

```
1. Agent: prepareArtifactUpload mutation → uploadUrl + artifactId
2. Agent: HTTP PUT 文件到 uploadUrl
3. Agent: confirmArtifactUpload mutation
4. Agent: completeTask 时引用 artifactIds
```

```graphql
mutation PrepareUpload($input: PrepareArtifactUploadInput!) {
  prepareArtifactUpload(input: $input) {
    artifactId
    uploadUrl
  }
}
```

## 10. Webhook 回调

Webhook 仍为出站 HTTP POST（非 GraphQL），格式不变。见 [§11](#11-webhook-回调)。

## 11. Webhook 回调

```http
POST https://example.com/hooks/builddock
Content-Type: application/json
X-BuildDock-Signature: sha256=...
X-BuildDock-Event: task.completed
```

```json
{
  "event": "task.completed",
  "timestamp": "2026-07-30T15:04:32Z",
  "task": {
    "id": "task_01JXYZ...",
    "runtime": { "status": "SUCCEEDED" },
    "result": {}
  }
}
```

| event | 触发时机 |
|-------|----------|
| `task.queued` | 入队 |
| `task.started` | 开始执行 |
| `task.progress` | 进度更新 |
| `task.completed` | 成功 |
| `task.failed` | 失败 |
| `task.cancelled` | 取消 |
| `task.timed_out` | 超时 |

签名：`HMAC-SHA256(webhook_secret, request_body)`

## 12. 速率限制

| 操作 | 限制 |
|------|------|
| `createTask` | 100/min per API Key |
| Query `tasks` / `devices` | 300/min |
| `pollTask` | 无硬限（长轮询） |
| `reportEvents` | 1000 events/min per device |
| Subscription 连接 | 10 concurrent per subject |

超限：`errors[].extensions.code = RATE_LIMITED`，HTTP 429。

## 13. 客户端 SDK 建议

| 客户端 | 推荐 |
|--------|------|
| Web Dashboard | Apollo Client / urql + graphql-ws |
| Mobile | Apollo iOS/Android / gql |
| CLI Agent (Go) | shurcooL/graphql + gorilla/websocket（Subscription 可选） |
| 外部触发方 | 任意 GraphQL HTTP 客户端 |

Agent MVP 仅需 HTTP POST `/graphql`（Mutation），无需 WebSocket。

## 14. MVP 裁剪

| 能力 | MVP | V1.1 | V2 |
|------|-----|------|-----|
| Query: devices, tasks | ✅ | | |
| Mutation: 平台 + Agent 全套 | ✅ | | |
| Subscription: taskEventStream | ✅ | | |
| Subscription: taskUpdated | ✅ | | |
| Subscription: deviceStatusChanged | | ✅ | |
| Subscription: taskCreated | | ✅ | |
| GraphQL Schema 文件 | ✅ | | |
| 设备组 / Secrets Mutation | | ✅ | |
| Agent GraphQL Subscription | | | ✅ |

完整 Schema 定义：[`docs/api/graphql-schema.graphql`](../api/graphql-schema.graphql)
