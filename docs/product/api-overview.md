# API 概览

Schema Version: `1.0`

Base URL: `https://api.builddock.example.com/v1`

## 1. 认证

| 调用方 | 方式 | 用途 |
|--------|------|------|
| 触发方（API / Agent 系统） | `Authorization: Bearer api_xxx` | 创建任务、管理设备 |
| CLI Agent | `Authorization: Bearer dtok_xxx` | 注册、心跳、执行任务 |
| Web Dashboard | Session / OAuth | 用户登录 |

## 2. 通用约定

### 2.1 请求头

```http
Content-Type: application/json
Authorization: Bearer <token>
X-Request-Id: <uuid>          # 可选，链路追踪
X-Idempotency-Key: <key>      # 创建任务时可选
```

### 2.2 响应格式

成功：

```json
{
  "data": { },
  "meta": {
    "request_id": "req_xxx"
  }
}
```

错误：

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "required_labels.owner is required",
    "details": {}
  },
  "meta": {
    "request_id": "req_xxx"
  }
}
```

### 2.3 分页

```http
GET /v1/tasks?limit=20&cursor=task_01JXYZ
```

```json
{
  "data": [],
  "pagination": {
    "next_cursor": "task_01JABC",
    "has_more": true
  }
}
```

### 2.4 错误码

| HTTP | code | 说明 |
|------|------|------|
| 400 | `VALIDATION_ERROR` | 请求参数无效 |
| 401 | `UNAUTHORIZED` | 未认证 |
| 403 | `FORBIDDEN` | 无权限 |
| 404 | `NOT_FOUND` | 资源不存在 |
| 409 | `CONFLICT` | 幂等冲突 / lease 无效 |
| 429 | `RATE_LIMITED` | 限流 |
| 500 | `INTERNAL_ERROR` | 服务器错误 |

## 3. 资源 API

### 3.1 设备（Devices）

| Method | Path | 说明 | 认证 |
|--------|------|------|------|
| POST | `/devices/registration-tokens` | 创建注册 Token | API Key |
| POST | `/devices/register` | 设备注册 | Registration Token |
| GET | `/devices` | 列出设备 | API Key |
| GET | `/devices/{id}` | 获取设备详情 | API Key |
| PATCH | `/devices/{id}` | 更新设备（name、labels） | API Key |
| DELETE | `/devices/{id}` | 吊销设备 | API Key |
| POST | `/devices/{id}/approve` | 审批设备 | API Key |
| POST | `/devices/{id}/reject` | 拒绝设备 | API Key |
| POST | `/devices/{id}/capabilities` | 上报 Capability | Device Token |
| POST | `/devices/{id}/heartbeat` | 心跳 | Device Token |
| POST | `/devices/{id}/tasks:poll` | 长轮询领取任务 | Device Token |

### 3.2 任务（Tasks）

| Method | Path | 说明 | 认证 |
|--------|------|------|------|
| POST | `/tasks` | 创建任务 | API Key |
| GET | `/tasks` | 列出任务 | API Key |
| GET | `/tasks/{id}` | 获取任务详情 | API Key |
| POST | `/tasks/{id}/cancel` | 取消任务 | API Key |
| GET | `/tasks/{id}/events` | 获取事件列表 | API Key |
| GET | `/tasks/{id}/events/stream` | SSE 事件流 | API Key |
| GET | `/tasks/{id}/logs` | 获取日志 | API Key |
| GET | `/tasks/{id}/logs/stream` | SSE 日志流 | API Key |
| POST | `/tasks/{id}/accept` | Agent 接受任务 | Device Token |
| POST | `/tasks/{id}/lease:renew` | 续租 | Device Token |
| POST | `/tasks/{id}/events` | 上报事件 | Device Token |
| POST | `/tasks/{id}/artifacts` | 上传产物 | Device Token |
| POST | `/tasks/{id}/artifacts:prepare` | 获取预签名上传 URL | Device Token |
| POST | `/tasks/{id}/complete` | 提交结果 | Device Token |

### 3.3 产物（Artifacts）

| Method | Path | 说明 | 认证 |
|--------|------|------|------|
| GET | `/artifacts/{id}` | 获取产物元数据 | API Key |
| GET | `/artifacts/{id}/download` | 下载产物（redirect 到 signed URL） | API Key |

### 3.4 设备组（V1.1）

| Method | Path | 说明 | 认证 |
|--------|------|------|------|
| POST | `/device-groups` | 创建设备组 | API Key |
| GET | `/device-groups` | 列出设备组 | API Key |
| GET | `/device-groups/{id}` | 获取设备组 | API Key |
| PATCH | `/device-groups/{id}` | 更新设备组 | API Key |
| DELETE | `/device-groups/{id}` | 删除设备组 | API Key |

### 3.5 密钥（Secrets，V1.1）

| Method | Path | 说明 | 认证 |
|--------|------|------|------|
| POST | `/secrets` | 创建密钥 | API Key |
| GET | `/secrets` | 列出密钥（不含值） | API Key |
| DELETE | `/secrets/{id}` | 删除密钥 | API Key |

## 4. 核心 API 详情

### 4.1 创建任务

```http
POST /v1/tasks
Authorization: Bearer api_xxx
Content-Type: application/json
X-Idempotency-Key: proj-abc:test:9f3a
```

Request Body：见 [Task Schema](./task-schema.md)

Response `201 Created`：

```json
{
  "data": {
    "id": "task_01JXYZ...",
    "org_id": "org_xxx",
    "schema_version": "1.0",
    "spec": {},
    "placement": {},
    "runtime": {
      "status": "queued",
      "queued_at": "2026-07-30T15:00:01Z"
    },
    "result": null,
    "created_at": "2026-07-30T15:00:00Z",
    "links": {
      "self": "/v1/tasks/task_01JXYZ...",
      "events": "/v1/tasks/task_01JXYZ.../events/stream",
      "logs": "/v1/tasks/task_01JXYZ.../logs/stream"
    }
  }
}
```

### 4.2 列出任务

```http
GET /v1/tasks?status=running&device_id=dev_01JABC&limit=20
```

Query 参数：

| 参数 | 说明 |
|------|------|
| `status` | 过滤状态 |
| `device_id` | 过滤设备 |
| `created_after` | ISO 8601 |
| `created_before` | ISO 8601 |
| `metadata.source` | 元数据过滤 |
| `limit` | 默认 20，最大 100 |
| `cursor` | 分页游标 |

### 4.3 SSE 事件流

```http
GET /v1/tasks/{id}/events/stream
Authorization: Bearer api_xxx
Accept: text/event-stream
```

```
event: status_changed
data: {"status":"running","timestamp":"2026-07-30T15:00:05Z"}

event: log
data: {"stream":"stdout","line":"Running tests..."}

event: log
data: {"stream":"stdout","line":"PASS utils.test.ts"}

event: status_changed
data: {"status":"succeeded","timestamp":"2026-07-30T15:04:32Z"}
```

### 4.4 取消任务

```http
POST /v1/tasks/{id}/cancel
Authorization: Bearer api_xxx
```

```json
{
  "reason": "User requested cancellation"
}
```

仅 `queued`、`assigned`、`running` 可取消。

## 5. Webhook 回调

任务创建时可在 `spec.callbacks.webhook` 指定 URL。

### 5.1 请求格式

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
    "runtime": { "status": "succeeded" },
    "result": {}
  }
}
```

### 5.2 事件类型

| event | 触发时机 |
|-------|----------|
| `task.queued` | 入队 |
| `task.started` | 开始执行 |
| `task.progress` | 进度更新 |
| `task.completed` | 成功 |
| `task.failed` | 失败 |
| `task.cancelled` | 取消 |
| `task.timed_out` | 超时 |

### 5.3 签名验证

```
signature = HMAC-SHA256(webhook_secret, request_body)
```

## 6. 速率限制

| 端点 | 限制 |
|------|------|
| POST /tasks | 100 req/min per API Key |
| GET /tasks/* | 300 req/min |
| Agent poll | 无硬限（长轮询） |
| Agent events | 1000 events/min per device |

超限返回 `429` + `Retry-After` 头。

## 7. OpenAPI

完整 OpenAPI 3.1 规范将在实现阶段生成于：

```
docs/api/openapi.yaml
```

MVP 先以本文档 + [Task Schema](./task-schema.md) + [Agent 协议](./agent-protocol.md) 为契约来源。

## 8. MVP API 裁剪

| API | MVP | V1.1 | V2 |
|-----|-----|------|-----|
| Devices CRUD | ✅ | | |
| Device approve/reject | ✅ | | |
| Tasks CRUD | ✅ | | |
| Task cancel | ✅ | | |
| SSE events/logs | ✅ | | |
| Artifacts | ✅ | | |
| Device groups | | ✅ | |
| Secrets | | ✅ | |
| Webhook | ✅ | | |
| OpenAPI spec | | ✅ | |
