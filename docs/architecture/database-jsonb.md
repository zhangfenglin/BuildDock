# JSONB 结构约定

Schema Version: `1.0`

PostgreSQL 使用 JSONB 存储半结构化数据。Go 层通过 `domain` 包 struct 序列化/反序列化，**应用层校验**，MVP 不使用 PG `CHECK (jsonb_schema)` 扩展。

---

## 1. tasks.spec（TaskSpec）

```json
{
  "type": "SHELL",
  "name": "run-tests",
  "description": "optional",
  "payload": {},
  "timeoutSec": 1800,
  "retry": { "maxAttempts": 2, "backoffSec": 10 },
  "idempotencyKey": "optional",
  "env": { "KEY": "value" },
  "secretRefs": [{ "ref": "sec/npm_token", "env": "NPM_TOKEN" }],
  "workingDir": "/workspace/app",
  "artifactCollect": [{ "path": "dist/**", "name": "dist" }],
  "callbacks": {
    "webhook": "https://...",
    "events": ["queued", "started", "completed", "failed"]
  },
  "trustLevel": "TRUSTED",
  "metadata": { "source": "custom-agent", "correlationId": "..." }
}
```

| 字段 | 类型 | 必填 | 校验 |
|------|------|------|------|
| type | string enum | ✅ | SHELL/SCRIPT/... |
| name | string | ✅ | 1–128 字符 |
| payload | object | ✅ | 依 type 校验 |
| timeoutSec | int | ✅ | 1–86400 |
| trustLevel | string | | 默认 TRUSTED |

**payload by type**：

<details>
<summary>SHELL</summary>

```json
{ "command": "npm test", "shell": "/bin/bash", "cwd": "/path" }
```
</details>

<details>
<summary>SCRIPT</summary>

```json
{
  "language": "bash",
  "source": { "kind": "inline", "content": "#!/usr/bin/env bash\n..." },
  "args": [],
  "cwd": "/path"
}
```
</details>

**存储键名**：DB 存 **camelCase**（与 GraphQL input 一致），Go struct tag `json:"timeoutSec"`。

---

## 2. tasks.placement（Placement）

```json
{
  "mode": "CAPABILITY_MATCH",
  "deviceId": null,
  "deviceIds": [],
  "group": null,
  "requiredLabels": { "owner": "alice" },
  "preferredLabels": { "gpu": "true" },
  "requiredHandlers": ["script"],
  "requiredRuntimes": [{ "name": "node", "version": ">=20.0.0" }],
  "resourceRequirements": {
    "minMemoryBytes": 2147483648,
    "minDiskFreeBytes": 1073741824
  },
  "networkRequirements": { "egress": "full" },
  "strategy": "LEAST_LOADED",
  "scheduleAt": null,
  "deadlineAt": "2026-07-30T16:00:00Z"
}
```

创建 task 时：`deadlineAt` 同步写入列 `tasks.deadline_at` 便于索引。

---

## 3. tasks.result（TaskResult）

```json
{
  "status": "SUCCEEDED",
  "exitCode": 0,
  "startedAt": "2026-07-30T15:00:05Z",
  "finishedAt": "2026-07-30T15:04:32Z",
  "durationMs": 267000,
  "output": {
    "stdoutRef": "log://task_xxx/stdout",
    "stderrRef": "log://task_xxx/stderr",
    "structured": { "testsPassed": 128 }
  },
  "artifactIds": ["art_xxx"],
  "error": null
}
```

失败时 `error`：

```json
{
  "code": "EXECUTION_ERROR",
  "message": "Command exited with code 1",
  "details": { "command": "npm test" }
}
```

---

## 4. tasks.created_by

```json
{
  "type": "API_KEY",
  "id": "key_01J...",
  "subject": "agent:session-123"
}
```

| type | 说明 |
|------|------|
| API_KEY | API Key 触发 |
| USER | OAuth 用户（V1.1） |
| SYSTEM | 系统内部 |

---

## 5. device_capabilities.handlers

```json
[
  {
    "type": "shell",
    "version": "1.0",
    "enabled": true
  },
  {
    "type": "script",
    "version": "1.0",
    "enabled": true,
    "languages": ["bash", "python", "node"]
  },
  {
    "type": "plugin",
    "version": "1.0",
    "enabled": true,
    "plugins": ["browser", "git"]
  }
]
```

**调度匹配**：`requiredHandlers` 中每个值必须存在 `enabled=true` 且 `type` 匹配的条目。

---

## 6. device_capabilities.runtimes

```json
[
  { "name": "node", "version": "22.4.0" },
  { "name": "python", "version": "3.12.4" },
  { "name": "docker", "version": "27.0.0" }
]
```

**版本比较**：应用层 semver，`>=20.0.0` 由 `github.com/Masterminds/semver/v3` 解析。

---

## 7. device_capabilities.load

```json
{
  "cpuUsage": 0.35,
  "memoryUsage": 0.62,
  "activeTasks": 1,
  "availableSlots": 2
}
```

心跳时仅更新 `load`；全量 `reportCapabilities` 时更新全部块。

---

## 8. device_capabilities.constraints

```json
{
  "maxConcurrentTasks": 3,
  "maxTaskTimeoutSec": 7200,
  "allowUntrustedTasks": false
}
```

同步到 `devices.max_concurrent_tasks` 列（若 present）。

---

## 9. devices.labels / capability.labels

扁平 string map：

```json
{ "owner": "alice", "env": "dev", "os": "macos", "gpu": "true" }
```

**匹配规则**：`requiredLabels` 每个 key 在 device.labels ∪ capability.labels 中值相等。

**索引**：GIN `jsonb_path_ops` 支持 `@>` 包含查询：

```sql
SELECT * FROM devices WHERE labels @> '{"owner":"alice"}';
```

---

## 10. Go Domain 映射示例

```go
// 示意，非实现代码
type TaskSpec struct {
    Type        TaskType          `json:"type"`
    Name        string            `json:"name"`
    Payload     json.RawMessage   `json:"payload"`
    TimeoutSec  int               `json:"timeoutSec"`
    TrustLevel  TrustLevel        `json:"trustLevel"`
    Metadata    map[string]string `json:"metadata,omitempty"`
}

func (r *TaskRepo) Insert(ctx context.Context, t *domain.Task) error {
    specJSON, _ := json.Marshal(t.Spec)
    // INSERT ... spec = $specJSON
}
```

sqlc 可将 JSONB 列映射为 `[]byte` 或 `pgtype.JSONB`，Service 层做 marshal/unmarshal。

---

## 11. 校验层级

| 层级 | 职责 |
|------|------|
| GraphQL | 必填、类型、enum |
| Service | 业务规则、payload 按 type 校验 |
| Domain | 状态机、placement 合法性 |
| DB | CHECK 约束、FK、NOT NULL |

JSONB 内部结构 **不在 DB 层强制**，保持迁移灵活性。
