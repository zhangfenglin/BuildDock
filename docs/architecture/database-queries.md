# sqlc 查询目录

Schema Version: `1.0`

实现时 SQL 文件位于 `backend/internal/repository/queries/*.sql`，由 sqlc 生成 Go 代码。

---

## 1. 组织与认证

### CreateOrganization

```sql
-- name: CreateOrganization :one
INSERT INTO organizations (id, name)
VALUES ($1, $2)
RETURNING *;
```

### GetAPIKeyByHash

```sql
-- name: GetAPIKeyByHash :one
SELECT * FROM api_keys
WHERE key_hash = $1 AND revoked_at IS NULL;
```

### TouchAPIKeyLastUsed

```sql
-- name: TouchAPIKeyLastUsed :exec
UPDATE api_keys SET last_used_at = now() WHERE id = $1;
```

### CreateRegistrationToken

```sql
-- name: CreateRegistrationToken :one
INSERT INTO registration_tokens (id, org_id, token_hash, labels, expires_at)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;
```

### GetRegistrationTokenByHash

```sql
-- name: GetRegistrationTokenByHash :one
SELECT * FROM registration_tokens
WHERE token_hash = $1
  AND used_at IS NULL
  AND expires_at > now();
```

### MarkRegistrationTokenUsed

```sql
-- name: MarkRegistrationTokenUsed :exec
UPDATE registration_tokens
SET used_at = now(), used_by_device_id = $2
WHERE id = $1 AND used_at IS NULL;
```

---

## 2. 设备

### CreateDevice

```sql
-- name: CreateDevice :one
INSERT INTO devices (
    id, org_id, name, machine_id, hostname, platform, arch,
    labels, device_token_hash, max_concurrent_tasks
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
RETURNING *;
```

### GetDeviceByID

```sql
-- name: GetDeviceByID :one
SELECT * FROM devices WHERE id = $1 AND org_id = $2;
```

### GetDeviceByTokenHash

```sql
-- name: GetDeviceByTokenHash :one
SELECT * FROM devices
WHERE device_token_hash = $1
  AND revoked_at IS NULL;
```

### ListDevices

```sql
-- name: ListDevices :many
SELECT * FROM devices
WHERE org_id = $1
  AND ($2::device_status IS NULL OR status = $2)
  AND ($3::approval_status IS NULL OR approval_status = $3)
  AND ($4::jsonb IS NULL OR labels @> $4)
  AND (created_at, id) < ($5, $6)
ORDER BY created_at DESC, id DESC
LIMIT $7;
```

### UpdateDeviceHeartbeat

```sql
-- name: UpdateDeviceHeartbeat :one
UPDATE devices
SET last_seen_at = now(),
    status = $2,
    generation = $3,
    active_tasks = $4,
    available_slots = $5,
    connected_at = COALESCE(connected_at, now())
WHERE id = $1 AND revoked_at IS NULL
RETURNING *;
```

### ApproveDevice

```sql
-- name: ApproveDevice :one
UPDATE devices
SET approval_status = 'APPROVED', updated_at = now()
WHERE id = $1 AND org_id = $2 AND approval_status = 'PENDING'
RETURNING *;
```

### RevokeDevice

```sql
-- name: RevokeDevice :one
UPDATE devices
SET status = 'REVOKED',
    revoked_at = now(),
    device_token_hash = NULL
WHERE id = $1 AND org_id = $2
RETURNING *;
```

### UpsertDeviceCapability

```sql
-- name: UpsertDeviceCapability :one
INSERT INTO device_capabilities (
    device_id, schema_version, generation, reported_at,
    system, resources, load, network, runtimes, handlers, labels, constraints
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
ON CONFLICT (device_id) DO UPDATE SET
    schema_version = EXCLUDED.schema_version,
    generation = EXCLUDED.generation,
    reported_at = EXCLUDED.reported_at,
    system = EXCLUDED.system,
    resources = EXCLUDED.resources,
    load = EXCLUDED.load,
    network = EXCLUDED.network,
    runtimes = EXCLUDED.runtimes,
    handlers = EXCLUDED.handlers,
    labels = EXCLUDED.labels,
    constraints = EXCLUDED.constraints,
    updated_at = now()
RETURNING *;
```

### ListSchedulableDevices

```sql
-- name: ListSchedulableDevices :many
SELECT * FROM v_schedulable_devices
WHERE org_id = $1;
```

### MarkDevicesOffline

```sql
-- name: MarkDevicesOffline :execrows
UPDATE devices
SET status = 'OFFLINE'
WHERE status = 'ONLINE'
  AND last_seen_at < now() - ($1::int * interval '1 second');
```

---

## 3. 任务 — CRUD

### CreateTask

```sql
-- name: CreateTask :one
INSERT INTO tasks (
    id, org_id, spec, placement, runtime_status,
    idempotency_key, created_by, deadline_at, queued_at
) VALUES (
    $1, $2, $3, $4, 'QUEUED',
    $5, $6,
    ($4->>'deadlineAt')::timestamptz,
    now()
)
RETURNING *;
```

### GetTaskByID

```sql
-- name: GetTaskByID :one
SELECT * FROM tasks WHERE id = $1 AND org_id = $2;
```

### GetTaskByIdempotencyKey

```sql
-- name: GetTaskByIdempotencyKey :one
SELECT * FROM tasks
WHERE org_id = $1 AND idempotency_key = $2;
```

### ListTasks

```sql
-- name: ListTasks :many
SELECT * FROM tasks
WHERE org_id = $1
  AND ($2::task_status IS NULL OR runtime_status = $2)
  AND ($3::text IS NULL OR assigned_device_id = $3)
  AND ($4::timestamptz IS NULL OR created_at >= $4)
  AND ($5::timestamptz IS NULL OR created_at <= $5)
  AND (created_at, id) < ($6, $7)
ORDER BY created_at DESC, id DESC
LIMIT $8;
```

### RequestCancelTask

```sql
-- name: RequestCancelTask :one
UPDATE tasks
SET cancel_requested = true, updated_at = now()
WHERE id = $1 AND org_id = $2
  AND runtime_status IN ('QUEUED', 'ASSIGNING', 'ASSIGNED', 'RUNNING')
RETURNING *;
```

---

## 4. 任务 — 调度队列

### ClaimQueuedTask

```sql
-- name: ClaimQueuedTask :one
UPDATE tasks
SET runtime_status = 'ASSIGNING', updated_at = now()
WHERE id = (
    SELECT id FROM tasks
    WHERE runtime_status = 'QUEUED'
      AND (deadline_at IS NULL OR deadline_at > now())
    ORDER BY created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
RETURNING *;
```

### RevertAssigningTask

```sql
-- name: RevertAssigningTask :exec
UPDATE tasks
SET runtime_status = 'QUEUED', updated_at = now()
WHERE id = $1 AND runtime_status = 'ASSIGNING';
```

### AssignTaskToDevice

```sql
-- name: AssignTaskToDevice :one
UPDATE tasks
SET runtime_status = 'ASSIGNED',
    assigned_device_id = $2,
    lease_id = $3,
    lease_generation = $4,
    lease_expires_at = $5,
    assigned_at = now(),
    updated_at = now()
WHERE id = $1 AND runtime_status = 'ASSIGNING'
RETURNING *;
```

### GetAssignedTaskForDevice

```sql
-- name: GetAssignedTaskForDevice :one
SELECT * FROM tasks
WHERE assigned_device_id = $1
  AND runtime_status = 'ASSIGNED'
  AND lease_expires_at > now()
ORDER BY assigned_at ASC
LIMIT 1;
```

### RequeueExpiredAssignments

```sql
-- name: RequeueExpiredAssignments :execrows
UPDATE tasks
SET runtime_status = 'QUEUED',
    assigned_device_id = NULL,
    lease_id = NULL,
    lease_generation = NULL,
    lease_expires_at = NULL,
    assigned_at = NULL,
    updated_at = now()
WHERE runtime_status = 'ASSIGNED'
  AND lease_expires_at < now();
```

### ExpireQueuedPastDeadline

```sql
-- name: ExpireQueuedPastDeadline :execrows
UPDATE tasks
SET runtime_status = 'EXPIRED',
    finished_at = now(),
    updated_at = now()
WHERE runtime_status = 'QUEUED'
  AND deadline_at IS NOT NULL
  AND deadline_at < now();
```

---

## 5. 任务 — Agent 执行

### AcceptTask

```sql
-- name: AcceptTask :one
UPDATE tasks
SET runtime_status = 'RUNNING',
    started_at = now(),
    updated_at = now()
WHERE id = $1
  AND assigned_device_id = $2
  AND lease_id = $3
  AND lease_generation = $4
  AND runtime_status = 'ASSIGNED'
  AND lease_expires_at > now()
RETURNING *;
```

### RenewTaskLease

```sql
-- name: RenewTaskLease :one
UPDATE tasks
SET lease_expires_at = $5, updated_at = now()
WHERE id = $1
  AND lease_id = $2
  AND lease_generation = $3
  AND assigned_device_id = $4
  AND runtime_status IN ('ASSIGNED', 'RUNNING')
RETURNING *;
```

### CompleteTask

```sql
-- name: CompleteTask :one
UPDATE tasks
SET runtime_status = $3,
    result = $4,
    finished_at = now(),
    failure_reason = $5,
    lease_id = NULL,
    lease_expires_at = NULL,
    updated_at = now()
WHERE id = $1
  AND lease_id = $2
  AND runtime_status = 'RUNNING'
RETURNING *;
```

### IncrementDeviceActiveTasks

```sql
-- name: IncrementDeviceActiveTasks :exec
UPDATE devices
SET active_tasks = active_tasks + 1,
    available_slots = GREATEST(0, max_concurrent_tasks - active_tasks - 1)
WHERE id = $1;
```

### DecrementDeviceActiveTasks

```sql
-- name: DecrementDeviceActiveTasks :exec
UPDATE devices
SET active_tasks = GREATEST(0, active_tasks - 1),
    available_slots = LEAST(max_concurrent_tasks, max_concurrent_tasks - active_tasks + 1)
WHERE id = $1;
```

---

## 6. Lease 历史

### InsertTaskLease

```sql
-- name: InsertTaskLease :one
INSERT INTO task_leases (id, task_id, device_id, generation, expires_at)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;
```

### ReleaseTaskLease

```sql
-- name: ReleaseTaskLease :exec
UPDATE task_leases
SET released_at = now(), release_reason = $2
WHERE id = $1 AND released_at IS NULL;
```

---

## 7. 事件与日志

### InsertTaskEvents

```sql
-- name: InsertTaskEvents :copyfrom
INSERT INTO task_events (id, task_id, device_id, event_type, data)
VALUES ($1, $2, $3, $4, $5);
```

使用 sqlc `:copyfrom` 批量插入。

### ListTaskEvents

```sql
-- name: ListTaskEvents :many
SELECT * FROM task_events
WHERE task_id = $1
  AND ($2::task_event_type[] IS NULL OR event_type = ANY($2))
  AND (created_at, id) > ($3, $4)
ORDER BY created_at ASC, id ASC
LIMIT $5;
```

### InsertTaskLogs

```sql
-- name: InsertTaskLogs :copyfrom
INSERT INTO task_logs (task_id, stream, line)
VALUES ($1, $2, $3);
```

### ListTaskLogs

```sql
-- name: ListTaskLogs :many
SELECT * FROM task_logs
WHERE task_id = $1
  AND ($2::log_stream IS NULL OR stream = $2)
  AND id > $3
ORDER BY id ASC
LIMIT $4;
```

---

## 8. 产物

### CreateArtifact

```sql
-- name: CreateArtifact :one
INSERT INTO artifacts (id, org_id, task_id, name, storage_key, size_bytes, content_type)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;
```

### ConfirmArtifactUpload

```sql
-- name: ConfirmArtifactUpload :one
UPDATE artifacts
SET upload_confirmed = true
WHERE id = $1 AND task_id = $2
RETURNING *;
```

### ListArtifactsByTask

```sql
-- name: ListArtifactsByTask :many
SELECT * FROM artifacts
WHERE task_id = $1 AND upload_confirmed = true;
```

---

## 9. Webhook

### EnqueueWebhookDelivery

```sql
-- name: EnqueueWebhookDelivery :one
INSERT INTO webhook_deliveries (id, org_id, task_id, url, event, payload, next_retry_at)
VALUES ($1, $2, $3, $4, $5, $6, now())
RETURNING *;
```

### ClaimPendingWebhooks

```sql
-- name: ClaimPendingWebhooks :many
UPDATE webhook_deliveries
SET status = 'PENDING', attempts = attempts + 1
WHERE id IN (
    SELECT id FROM webhook_deliveries
    WHERE status = 'PENDING'
      AND next_retry_at <= now()
    ORDER BY next_retry_at
    FOR UPDATE SKIP LOCKED
    LIMIT $1
)
RETURNING *;
```

---

## 10. 事务边界建议

| 操作 | 事务内容 |
|------|----------|
| createTask | INSERT task + enqueue event |
| AssignTask | Claim + Match + AssignTaskToDevice + InsertTaskLease + IncrementActiveTasks |
| completeTask | CompleteTask + ReleaseTaskLease + DecrementActiveTasks + EnqueueWebhook |
| RequeueExpired | RequeueExpiredAssignments + ReleaseTaskLeases + DecrementActiveTasks |

使用 `pgx.Tx` 在 Service 层显式事务。

---

## 11. sqlc 配置（设计）

```yaml
# backend/sqlc.yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "internal/repository/queries"
    schema: "../../docs/architecture/migrations"
    gen:
      go:
        package: "repository"
        out: "internal/repository/gen"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_empty_slices: true
```

MVP 可将 schema 指向 `docs/architecture/migrations/` 直到 `backend/migrations/` 落地。

---

## 12. 查询与 GraphQL 映射

| GraphQL Operation | sqlc 查询 |
|-------------------|-----------|
| devices | ListDevices |
| device(id) | GetDeviceByID + GetDeviceCapability |
| tasks | ListTasks |
| task(id) | GetTaskByID |
| createTask | GetTaskByIdempotencyKey / CreateTask |
| registerDevice | CreateDevice + UpsertDeviceCapability |
| pollTask | GetAssignedTaskForDevice / Assign flow |
| acceptTask | AcceptTask |
| completeTask | CompleteTask |
| task.events | ListTaskEvents |
| task.logs | ListTaskLogs |
