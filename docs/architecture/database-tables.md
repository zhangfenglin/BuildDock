# 数据表字段字典

Schema Version: `1.0`

完整 DDL 见 [`migrations/000001_init.sql`](./migrations/000001_init.sql)。

---

## 1. organizations

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | 主键，`org_` + ULID |
| `name` | TEXT | NO | — | 组织名称，1–128 字符 |
| `created_at` | TIMESTAMPTZ | NO | now() | 创建时间 |
| `updated_at` | TIMESTAMPTZ | NO | now() | 更新时间（trigger 维护） |

**关系**：一对多 `api_keys`、`devices`、`tasks`。

---

## 2. api_keys

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `key_` + ULID |
| `org_id` | TEXT | NO | — | FK → organizations |
| `name` | TEXT | NO | — | 密钥描述，如 "CI pipeline" |
| `key_hash` | TEXT | NO | — | SHA-256(完整 api_key)，唯一 |
| `key_prefix` | TEXT | NO | — | 明文前缀，如 `api_abcd1234`，便于 UI 识别 |
| `last_used_at` | TIMESTAMPTZ | YES | — | 最近一次认证成功 |
| `revoked_at` | TIMESTAMPTZ | YES | — | 吊销时间；非空即失效 |
| `created_at` | TIMESTAMPTZ | NO | now() | — |

**索引**：`idx_api_keys_org_active (org_id) WHERE revoked_at IS NULL`

**安全**：库中永不存明文 key。

---

## 3. registration_tokens

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `rtok_` + ULID |
| `org_id` | TEXT | NO | — | FK → organizations |
| `token_hash` | TEXT | NO | — | SHA-256(reg_token) |
| `labels` | JSONB | NO | `{}` | 注册时预置到 device.labels |
| `expires_at` | TIMESTAMPTZ | NO | — | 过期时间，默认创建后 1h |
| `used_at` | TIMESTAMPTZ | YES | — | 使用时间，非空即作废 |
| `used_by_device_id` | TEXT | YES | — | 注册产生的 device_id |
| `created_at` | TIMESTAMPTZ | NO | now() | — |

**业务规则**：`used_at IS NOT NULL OR expires_at > now()` 才有效。

---

## 4. devices

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `dev_` + ULID |
| `org_id` | TEXT | NO | — | FK → organizations |
| `name` | TEXT | NO | — | 用户命名 |
| `status` | device_status | NO | PENDING | 连接/生命周期状态 |
| `approval_status` | approval_status | NO | PENDING | 审批状态 |
| `machine_id` | TEXT | NO | — | 机器唯一 ID，注册后不可变 |
| `hostname` | TEXT | NO | — | 主机名 |
| `platform` | TEXT | NO | — | darwin / linux / windows |
| `arch` | TEXT | NO | — | arm64 / amd64 |
| `labels` | JSONB | NO | `{}` | 路由标签 |
| `agent_version` | TEXT | YES | — | Agent  semver |
| `agent_cli` | TEXT | NO | builddock-agent | CLI 名称 |
| `connected_at` | TIMESTAMPTZ | YES | — | 首次/最近连接建立 |
| `last_seen_at` | TIMESTAMPTZ | YES | — | 最近心跳时间 |
| `generation` | INT | NO | 0 | 递增，lease fencing |
| `available_slots` | INT | NO | 1 | 当前可接任务数 |
| `active_tasks` | INT | NO | 0 | 正在执行任务数 |
| `max_concurrent_tasks` | INT | NO | 3 | 并发上限（Agent 上报或默认） |
| `device_token_hash` | TEXT | YES | — | SHA-256(dtok_) |
| `revoked_at` | TIMESTAMPTZ | YES | — | 吊销时间 |
| `created_at` | TIMESTAMPTZ | NO | now() | — |
| `updated_at` | TIMESTAMPTZ | NO | now() | — |

**唯一约束**：`(org_id, machine_id)`

**GraphQL 映射**：

| DB 列 | GraphQL 字段 |
|-------|-------------|
| machine_id, hostname, platform, arch | `Device.fingerprint.*` |
| agent_version, agent_cli, connected_at, last_seen_at | `Device.agent.*` |
| labels | `Device.labels` |

**心跳更新列**：`last_seen_at`, `generation`, `available_slots`, `active_tasks`, `status`

---

## 5. device_capabilities

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `device_id` | TEXT | NO | — | PK，FK → devices |
| `schema_version` | TEXT | NO | 1.0 | Capability schema 版本 |
| `generation` | INT | NO | — | 与 devices.generation 同步 |
| `reported_at` | TIMESTAMPTZ | NO | — | 上报时间 |
| `system` | JSONB | YES | — | platform, os_version, hostname |
| `resources` | JSONB | YES | — | cpu_cores, memory_bytes, gpu[] |
| `load` | JSONB | YES | — | cpu_usage, memory_usage, active_tasks, available_slots |
| `network` | JSONB | YES | — | egress, private_reachable, tags |
| `runtimes` | JSONB | NO | [] | [{name, version}] |
| `handlers` | JSONB | NO | [] | [{type, version, enabled, languages?, plugins?}] |
| `labels` | JSONB | NO | {} | 能力层标签（可覆盖 devices.labels 用于匹配） |
| `constraints` | JSONB | YES | — | max_concurrent_tasks, allow_untrusted_tasks |
| `updated_at` | TIMESTAMPTZ | NO | now() | — |

**策略**：UPSERT（`ON CONFLICT (device_id) DO UPDATE`），每设备一行。

**调度读取**：优先 JOIN `v_schedulable_devices` 视图。

---

## 6. tasks

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `task_` + ULID |
| `org_id` | TEXT | NO | — | FK → organizations |
| `schema_version` | TEXT | NO | 1.0 | — |
| `spec` | JSONB | NO | — | TaskSpec，创建后不可变 |
| `placement` | JSONB | NO | — | Placement，创建后不可变 |
| `runtime_status` | task_status | NO | PENDING | 当前状态 |
| `attempt` | INT | NO | 1 | 当前尝试次数 |
| `assigned_device_id` | TEXT | YES | — | FK → devices |
| `cancel_requested` | BOOLEAN | NO | false | 用户请求取消 |
| `failure_reason` | TEXT | YES | — | 失败摘要 |
| `lease_id` | TEXT | YES | — | 当前有效 lease |
| `lease_generation` | INT | YES | — | 分配时 device.generation |
| `lease_expires_at` | TIMESTAMPTZ | YES | — | Lease 过期时间 |
| `queued_at` | TIMESTAMPTZ | YES | — | 入队时间 |
| `assigned_at` | TIMESTAMPTZ | YES | — | 分配设备时间 |
| `started_at` | TIMESTAMPTZ | YES | — | Agent accept 时间 |
| `finished_at` | TIMESTAMPTZ | YES | — | 完成时间 |
| `deadline_at` | TIMESTAMPTZ | YES | — | 来自 placement.deadline_at |
| `result` | JSONB | YES | — | TaskResult |
| `idempotency_key` | TEXT | YES | — | 幂等键 |
| `created_by` | JSONB | YES | — | {type, id, subject} |
| `spec_type` | TEXT | STORED | generated | spec->>'type'，便于索引 |
| `spec_name` | TEXT | STORED | generated | spec->>'name' |
| `created_at` | TIMESTAMPTZ | NO | now() | — |
| `updated_at` | TIMESTAMPTZ | NO | now() | — |

**GraphQL 映射**：

| GraphQL | DB 来源 |
|---------|---------|
| `Task.spec` | spec |
| `Task.placement` | placement |
| `Task.runtime.*` | runtime_status, attempt, assigned_device_id, lease_*, timestamps, cancel_requested |
| `Task.result` | result |

**状态与时间戳写入规则**：

| 状态转换 | 写入字段 |
|----------|----------|
| → QUEUED | queued_at |
| → ASSIGNED | assigned_at, lease_*, assigned_device_id |
| → RUNNING | started_at |
| → 终态 | finished_at, result |

---

## 7. task_leases

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `lease_` + ULID |
| `task_id` | TEXT | NO | — | FK → tasks |
| `device_id` | TEXT | NO | — | FK → devices |
| `generation` | INT | NO | — | device.generation snapshot |
| `granted_at` | TIMESTAMPTZ | NO | now() | — |
| `expires_at` | TIMESTAMPTZ | NO | — | 默认 granted_at + 5min |
| `renewed_at` | TIMESTAMPTZ | YES | — | 最近续租 |
| `released_at` | TIMESTAMPTZ | YES | — | 释放时间 |
| `release_reason` | TEXT | YES | — | completed / expired / cancelled / requeued |

**唯一约束**：每 task 仅一条 `released_at IS NULL` 的有效 lease。

---

## 8. task_events

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `evt_` + ULID |
| `task_id` | TEXT | NO | — | FK → tasks CASCADE |
| `device_id` | TEXT | YES | — | 产生事件的设备 |
| `event_type` | task_event_type | NO | — | — |
| `data` | JSONB | NO | — | 事件载荷 |
| `created_at` | TIMESTAMPTZ | NO | now() | — |

**data 结构 by type**：

| event_type | data 示例 |
|------------|-----------|
| STATUS_CHANGED | `{"from":"ASSIGNED","to":"RUNNING"}` |
| LOG | `{"stream":"stdout","line":"..."}` |
| PROGRESS | `{"percent":45,"message":"..."}` |
| ARTIFACT | `{"artifactId":"art_..."}` |

**写入策略**：`reportEvents` 批量 INSERT；同时 LOG 类型可选双写 `task_logs`。

---

## 9. task_logs

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | BIGSERIAL | NO | auto | 单 task 内单调递增 |
| `task_id` | TEXT | NO | — | FK → tasks CASCADE |
| `stream` | log_stream | NO | — | STDOUT / STDERR |
| `line` | TEXT | NO | — | 单行文本，不含换行 |
| `created_at` | TIMESTAMPTZ | NO | now() | — |

**GraphQL**：`Task.logs(after: $cursor)` 使用 `(task_id, id)` 键集分页。

**Retention**：> 30 天归档 S3 后 DELETE；或按 task 完成后 7 天清理。

---

## 10. artifacts

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `art_` + ULID |
| `org_id` | TEXT | NO | — | FK → organizations |
| `task_id` | TEXT | NO | — | FK → tasks |
| `name` | TEXT | NO | — | 逻辑名称，同 task 内唯一 |
| `storage_key` | TEXT | NO | — | S3 key，全局唯一 |
| `size_bytes` | BIGINT | NO | — | 文件大小 |
| `content_type` | TEXT | NO | — | MIME |
| `upload_confirmed` | BOOLEAN | NO | false | confirmArtifactUpload 后置 true |
| `created_at` | TIMESTAMPTZ | NO | now() | — |

**storage_key 格式**：`artifacts/{org_id}/{task_id}/{artifact_id}/{filename}`

---

## 11. webhook_deliveries

| 列 | 类型 | NULL | 默认 | 说明 |
|----|------|------|------|------|
| `id` | TEXT | NO | — | `wh_` + ULID |
| `org_id` | TEXT | NO | — | FK → organizations |
| `task_id` | TEXT | NO | — | FK → tasks |
| `url` | TEXT | NO | — | 回调 URL |
| `event` | TEXT | NO | — | task.completed 等 |
| `payload` | JSONB | NO | — | 完整 webhook body |
| `status` | webhook_delivery_status | NO | PENDING | — |
| `attempts` | INT | NO | 0 | 已尝试次数 |
| `last_error` | TEXT | YES | — | 最近错误 |
| `next_retry_at` | TIMESTAMPTZ | YES | — | 下次重试 |
| `delivered_at` | TIMESTAMPTZ | YES | — | 成功时间 |
| `created_at` | TIMESTAMPTZ | NO | now() | — |

**重试**：指数退避 1m, 5m, 15m, 1h；最多 5 次。

---

## 12. device_groups（V1.1）

见 [`database.md`](./database.md#412-device_groupsv11)。

---

## 13. secrets（V1.1）

见 [`database.md`](./database.md#413-secretsv11)。

---

## 14. 视图 v_schedulable_devices

可调度设备的预 JOIN 视图，列 = `devices.*` + capability 关键 JSONB。

调度器 Query 优先使用此视图，避免 N+1。

---

## 15. ID 生成规范

| 前缀 | 实体 | 生成 |
|------|------|------|
| `org_` | organizations | ULID |
| `key_` | api_keys | ULID |
| `rtok_` | registration_tokens | ULID |
| `dev_` | devices | ULID |
| `task_` | tasks | ULID |
| `lease_` | task_leases | ULID |
| `evt_` | task_events | ULID |
| `art_` | artifacts | ULID |
| `wh_` | webhook_deliveries | ULID |

Go 实现推荐 `github.com/oklog/ulid/v2`。

Token 明文（非表 ID）：`api_`、`dtok_`、`reg_` + 32 字节 random base62。
