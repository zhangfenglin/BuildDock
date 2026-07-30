-- BuildDock PostgreSQL Init Schema (Design Reference)
-- Schema Version: 1.0
-- 设计参考文件，实现时复制到 backend/migrations/

-- ─────────────────────────────────────────────
-- Extensions
-- ─────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────
CREATE TYPE device_status AS ENUM (
    'PENDING', 'ONLINE', 'OFFLINE', 'DRAINING', 'REVOKED'
);

CREATE TYPE approval_status AS ENUM (
    'PENDING', 'APPROVED', 'REJECTED'
);

CREATE TYPE task_status AS ENUM (
    'PENDING', 'QUEUED', 'ASSIGNING', 'ASSIGNED',
    'RUNNING', 'SUCCEEDED', 'FAILED', 'CANCELLED', 'TIMED_OUT', 'EXPIRED'
);

CREATE TYPE task_event_type AS ENUM (
    'STATUS_CHANGED', 'LOG', 'PROGRESS', 'ARTIFACT',
    'METRIC', 'TOOL_CALL', 'HEARTBEAT'
);

CREATE TYPE log_stream AS ENUM ('STDOUT', 'STDERR');

CREATE TYPE webhook_delivery_status AS ENUM (
    'PENDING', 'SUCCESS', 'FAILED'
);

-- ─────────────────────────────────────────────
-- Helper: auto-update updated_at
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────
-- organizations
-- ─────────────────────────────────────────────
CREATE TABLE organizations (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 128),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_organizations_updated_at
    BEFORE UPDATE ON organizations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─────────────────────────────────────────────
-- api_keys
-- ─────────────────────────────────────────────
CREATE TABLE api_keys (
    id           TEXT PRIMARY KEY,
    org_id       TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name         TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 128),
    key_hash     TEXT NOT NULL UNIQUE,
    key_prefix   TEXT NOT NULL CHECK (char_length(key_prefix) BETWEEN 4 AND 16),
    last_used_at TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

CREATE INDEX idx_api_keys_org_active ON api_keys(org_id) WHERE revoked_at IS NULL;

-- ─────────────────────────────────────────────
-- registration_tokens
-- ─────────────────────────────────────────────
CREATE TABLE registration_tokens (
    id                TEXT PRIMARY KEY,
    org_id            TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    token_hash        TEXT NOT NULL UNIQUE,
    labels            JSONB NOT NULL DEFAULT '{}',
    expires_at        TIMESTAMPTZ NOT NULL,
    used_at           TIMESTAMPTZ,
    used_by_device_id TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at),
    CHECK (used_at IS NULL OR used_at >= created_at)
);

CREATE INDEX idx_reg_tokens_valid ON registration_tokens(org_id, expires_at)
    WHERE used_at IS NULL;

-- ─────────────────────────────────────────────
-- devices
-- ─────────────────────────────────────────────
CREATE TABLE devices (
    id                TEXT PRIMARY KEY,
    org_id            TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name              TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 128),
    status            device_status NOT NULL DEFAULT 'PENDING',
    approval_status   approval_status NOT NULL DEFAULT 'PENDING',

    machine_id        TEXT NOT NULL,
    hostname          TEXT NOT NULL,
    platform          TEXT NOT NULL,
    arch              TEXT NOT NULL,

    labels            JSONB NOT NULL DEFAULT '{}',

    agent_version     TEXT,
    agent_cli         TEXT NOT NULL DEFAULT 'builddock-agent',
    connected_at      TIMESTAMPTZ,
    last_seen_at      TIMESTAMPTZ,

    generation        INT NOT NULL DEFAULT 0 CHECK (generation >= 0),
    available_slots   INT NOT NULL DEFAULT 1 CHECK (available_slots >= 0),
    active_tasks      INT NOT NULL DEFAULT 0 CHECK (active_tasks >= 0),
    max_concurrent_tasks INT NOT NULL DEFAULT 3 CHECK (max_concurrent_tasks >= 1),

    device_token_hash TEXT,
    revoked_at        TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (org_id, machine_id),
    CHECK (active_tasks <= max_concurrent_tasks),
    CHECK (revoked_at IS NULL OR status = 'REVOKED')
);

CREATE TRIGGER trg_devices_updated_at
    BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_devices_org_status ON devices(org_id, status);
CREATE INDEX idx_devices_pending_approval ON devices(org_id)
    WHERE approval_status = 'PENDING';
CREATE INDEX idx_devices_labels ON devices USING GIN (labels jsonb_path_ops);
CREATE INDEX idx_devices_schedulable ON devices(org_id, active_tasks, available_slots)
    WHERE status = 'ONLINE' AND approval_status = 'APPROVED' AND revoked_at IS NULL;

-- ─────────────────────────────────────────────
-- device_capabilities
-- ─────────────────────────────────────────────
CREATE TABLE device_capabilities (
    device_id       TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    schema_version  TEXT NOT NULL DEFAULT '1.0',
    generation      INT NOT NULL CHECK (generation >= 0),
    reported_at     TIMESTAMPTZ NOT NULL,

    system          JSONB,
    resources       JSONB,
    load            JSONB,
    network         JSONB,
    runtimes        JSONB NOT NULL DEFAULT '[]',
    handlers        JSONB NOT NULL DEFAULT '[]',
    labels          JSONB NOT NULL DEFAULT '{}',
    constraints     JSONB,

    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_device_cap_handlers ON device_capabilities USING GIN (handlers jsonb_path_ops);
CREATE INDEX idx_device_cap_runtimes ON device_capabilities USING GIN (runtimes jsonb_path_ops);
CREATE INDEX idx_device_cap_labels ON device_capabilities USING GIN (labels jsonb_path_ops);

-- ─────────────────────────────────────────────
-- tasks
-- ─────────────────────────────────────────────
CREATE TABLE tasks (
    id                   TEXT PRIMARY KEY,
    org_id               TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    schema_version       TEXT NOT NULL DEFAULT '1.0',

    spec                 JSONB NOT NULL,
    placement            JSONB NOT NULL,

    runtime_status       task_status NOT NULL DEFAULT 'PENDING',
    attempt              INT NOT NULL DEFAULT 1 CHECK (attempt >= 1),
    assigned_device_id   TEXT REFERENCES devices(id) ON DELETE SET NULL,
    cancel_requested     BOOLEAN NOT NULL DEFAULT false,
    failure_reason       TEXT,

    lease_id             TEXT,
    lease_generation     INT,
    lease_expires_at     TIMESTAMPTZ,

    queued_at            TIMESTAMPTZ,
    assigned_at          TIMESTAMPTZ,
    started_at           TIMESTAMPTZ,
    finished_at          TIMESTAMPTZ,
    deadline_at          TIMESTAMPTZ,

    result               JSONB,

    idempotency_key      TEXT,
    created_by           JSONB,

    --  denormalized for query / index
    spec_type            TEXT GENERATED ALWAYS AS (spec->>'type') STORED,
    spec_name            TEXT GENERATED ALWAYS AS (spec->>'name') STORED,

    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CHECK (
        (runtime_status NOT IN ('ASSIGNED', 'RUNNING') AND assigned_device_id IS NULL)
        OR assigned_device_id IS NOT NULL
        OR runtime_status IN ('ASSIGNING', 'ASSIGNED', 'RUNNING')
    ),
    CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at)
);

CREATE TRIGGER trg_tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE UNIQUE INDEX idx_tasks_idempotency ON tasks(org_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX idx_tasks_org_status_created ON tasks(org_id, runtime_status, created_at DESC);
CREATE INDEX idx_tasks_org_device ON tasks(org_id, assigned_device_id, runtime_status);
CREATE INDEX idx_tasks_queued_fifo ON tasks(created_at ASC)
    WHERE runtime_status = 'QUEUED';
CREATE INDEX idx_tasks_assigned_lease ON tasks(lease_expires_at)
    WHERE runtime_status = 'ASSIGNED' AND lease_expires_at IS NOT NULL;
CREATE INDEX idx_tasks_running_timeout ON tasks(started_at, spec)
    WHERE runtime_status = 'RUNNING';
CREATE INDEX idx_tasks_deadline ON tasks(deadline_at)
    WHERE runtime_status = 'QUEUED' AND deadline_at IS NOT NULL;
CREATE INDEX idx_tasks_spec_type ON tasks(org_id, spec_type);
CREATE INDEX idx_tasks_metadata ON tasks USING GIN ((spec->'metadata') jsonb_path_ops);

-- ─────────────────────────────────────────────
-- task_leases
-- ─────────────────────────────────────────────
CREATE TABLE task_leases (
    id              TEXT PRIMARY KEY,
    task_id         TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    device_id       TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    generation      INT NOT NULL CHECK (generation >= 0),
    granted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    renewed_at      TIMESTAMPTZ,
    released_at     TIMESTAMPTZ,
    release_reason  TEXT,
    CHECK (expires_at > granted_at),
    CHECK (released_at IS NULL OR released_at >= granted_at)
);

CREATE UNIQUE INDEX idx_task_leases_one_active ON task_leases(task_id)
    WHERE released_at IS NULL;

CREATE INDEX idx_task_leases_device_active ON task_leases(device_id)
    WHERE released_at IS NULL;

-- ─────────────────────────────────────────────
-- task_events
-- ─────────────────────────────────────────────
CREATE TABLE task_events (
    id          TEXT PRIMARY KEY,
    task_id     TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    device_id   TEXT REFERENCES devices(id) ON DELETE SET NULL,
    event_type  task_event_type NOT NULL,
    data        JSONB NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_task_events_task_time ON task_events(task_id, created_at ASC);
CREATE INDEX idx_task_events_task_type ON task_events(task_id, event_type, created_at ASC);

-- ─────────────────────────────────────────────
-- task_logs
-- ─────────────────────────────────────────────
CREATE TABLE task_logs (
    id          BIGSERIAL PRIMARY KEY,
    task_id     TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    stream      log_stream NOT NULL,
    line        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_task_logs_task_seq ON task_logs(task_id, id ASC);

-- ─────────────────────────────────────────────
-- artifacts
-- ─────────────────────────────────────────────
CREATE TABLE artifacts (
    id               TEXT PRIMARY KEY,
    org_id           TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    task_id          TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    storage_key      TEXT NOT NULL UNIQUE,
    size_bytes       BIGINT NOT NULL CHECK (size_bytes >= 0),
    content_type     TEXT NOT NULL,
    upload_confirmed BOOLEAN NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_artifacts_task ON artifacts(task_id);
CREATE UNIQUE INDEX idx_artifacts_task_name ON artifacts(task_id, name);

-- ─────────────────────────────────────────────
-- webhook_deliveries
-- ─────────────────────────────────────────────
CREATE TABLE webhook_deliveries (
    id            TEXT PRIMARY KEY,
    org_id        TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    task_id       TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    url           TEXT NOT NULL,
    event         TEXT NOT NULL,
    payload       JSONB NOT NULL,
    status        webhook_delivery_status NOT NULL DEFAULT 'PENDING',
    attempts      INT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error    TEXT,
    next_retry_at TIMESTAMPTZ,
    delivered_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_webhook_pending ON webhook_deliveries(next_retry_at)
    WHERE status = 'PENDING';

-- ─────────────────────────────────────────────
-- Views
-- ─────────────────────────────────────────────
CREATE VIEW v_schedulable_devices AS
SELECT
    d.*,
    c.handlers,
    c.runtimes,
    c.resources,
    c.load,
    c.constraints AS cap_constraints
FROM devices d
JOIN device_capabilities c ON c.device_id = d.id
WHERE d.status = 'ONLINE'
  AND d.approval_status = 'APPROVED'
  AND d.revoked_at IS NULL
  AND d.available_slots > 0;

-- ─────────────────────────────────────────────
-- Dev seed (optional)
-- ─────────────────────────────────────────────
-- INSERT INTO organizations (id, name) VALUES ('org_default', 'Default');
