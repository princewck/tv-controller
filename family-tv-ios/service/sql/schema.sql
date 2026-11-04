PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

-- 设备令牌仅存SHA-256，明文只在配发时写入权限0600的本地文件。
CREATE TABLE IF NOT EXISTS devices (
  device_name TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN(0,1)),
  last_heartbeat_ms INTEGER,
  created_at INTEGER NOT NULL
) STRICT;
-- 原始使用流水不可被“充值”覆盖。timestamp 为UTC Unix秒；小数保留采样精度。
CREATE TABLE IF NOT EXISTS usage_events (
  id INTEGER PRIMARY KEY,
  timestamp INTEGER NOT NULL,
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  app_package TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL CHECK(duration_seconds BETWEEN 1 AND 10)
) STRICT;
CREATE INDEX IF NOT EXISTS usage_device_time ON usage_events(device_name,timestamp);
CREATE INDEX IF NOT EXISTS usage_time_app ON usage_events(timestamp,app_package);
CREATE TABLE IF NOT EXISTS daily_usage (
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  day TEXT NOT NULL,
  watched_seconds INTEGER NOT NULL DEFAULT 0 CHECK(watched_seconds>=0),
  credit_seconds INTEGER NOT NULL DEFAULT 0 CHECK(credit_seconds>=0),
  PRIMARY KEY(device_name,day)
) STRICT;
-- 心跳幂等键：同一个event_id重复传输不会再次计时。
CREATE TABLE IF NOT EXISTS heartbeat_receipts (
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  event_id TEXT NOT NULL,
  received_ms INTEGER NOT NULL,
  PRIMARY KEY(device_name,event_id)
) STRICT;
CREATE TABLE IF NOT EXISTS launch_tickets (
  token_hash TEXT PRIMARY KEY,
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  expires_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS browser_sessions (
  token_hash TEXT PRIMARY KEY,
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  csrf TEXT NOT NULL,
  expires_ms INTEGER NOT NULL,
  exam_day TEXT NOT NULL,
  streak INTEGER NOT NULL DEFAULT 0 CHECK(streak BETWEEN 0 AND 3),
  question_id TEXT,
  question_text TEXT,
  expected_answer INTEGER,
  question_expires_ms INTEGER,
  ready_nonce TEXT,
  last_answer_ms INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE TABLE IF NOT EXISTS unlock_grants (
  nonce TEXT PRIMARY KEY,
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  day TEXT NOT NULL,
  seconds INTEGER NOT NULL,
  created_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS answer_receipts (
  session_hash TEXT NOT NULL REFERENCES browser_sessions(token_hash) ON DELETE CASCADE,
  attempt_id TEXT NOT NULL,
  response_json TEXT NOT NULL,
  created_ms INTEGER NOT NULL,
  PRIMARY KEY(session_hash,attempt_id)
) STRICT;
PRAGMA user_version=1;

-- 服务端答题状态独立于播放器报告。答题中即使误报is_playing=true，也不计观看时长。
CREATE TABLE IF NOT EXISTS math_sessions (
  id TEXT PRIMARY KEY,
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  day TEXT NOT NULL,
  opened_ms INTEGER NOT NULL,
  last_seen_ms INTEGER NOT NULL,
  completed_ms INTEGER,
  status TEXT NOT NULL CHECK(status IN('open','completed','day_rollover','admin_released','adult_verified','rest_reset')),
  answer_count INTEGER NOT NULL DEFAULT 0,
  wrong_count INTEGER NOT NULL DEFAULT 0,
  reward_seconds INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE UNIQUE INDEX IF NOT EXISTS one_open_math_session ON math_sessions(device_name) WHERE status='open';
CREATE TABLE IF NOT EXISTS control_events (
  id INTEGER PRIMARY KEY,
  timestamp INTEGER NOT NULL,
  device_name TEXT NOT NULL REFERENCES devices(device_name),
  event_type TEXT NOT NULL,
  math_session_id TEXT,
  details_json TEXT NOT NULL DEFAULT '{}'
) STRICT;
CREATE INDEX IF NOT EXISTS control_events_device_time ON control_events(device_name,timestamp);
PRAGMA user_version=2;

CREATE TABLE IF NOT EXISTS policy_settings (
 id INTEGER PRIMARY KEY CHECK(id=1), config_json TEXT NOT NULL, updated_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS policy_cycles (
 device_name TEXT PRIMARY KEY REFERENCES devices(device_name),
 stage INTEGER NOT NULL DEFAULT 0 CHECK(stage>=0),
 stage_used_seconds INTEGER NOT NULL DEFAULT 0 CHECK(stage_used_seconds>=0),
 last_playing_ms INTEGER,
 started_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS time_overrides (
 id TEXT PRIMARY KEY,
 device_name TEXT NOT NULL REFERENCES devices(device_name),
 created_ms INTEGER NOT NULL,
 expires_ms INTEGER NOT NULL,
 remaining_seconds INTEGER NOT NULL CHECK(remaining_seconds>=0),
 granted_seconds INTEGER NOT NULL,
 source TEXT NOT NULL CHECK(source IN('admin','adult'))
) STRICT;
CREATE INDEX IF NOT EXISTS override_device_time ON time_overrides(device_name,expires_ms);
CREATE TABLE IF NOT EXISTS admin_sessions (
 token_hash TEXT PRIMARY KEY,
 csrf TEXT NOT NULL,
 created_ms INTEGER NOT NULL,
 expires_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS admin_audit (
 id INTEGER PRIMARY KEY,
 timestamp INTEGER NOT NULL,
 action TEXT NOT NULL,
 details_json TEXT NOT NULL
) STRICT;
PRAGMA user_version=3;

-- v4：所有权单独建表，兼容既有设备名、令牌和流水，不重建或清空旧业务表。
CREATE TABLE IF NOT EXISTS tenants (
 tenant_id TEXT PRIMARY KEY, label TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN(0,1)), created_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS users (
 user_id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, tenant_id TEXT NOT NULL UNIQUE REFERENCES tenants(tenant_id),
 password_json TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN(0,1)), created_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS device_ownership (
 device_name TEXT PRIMARY KEY REFERENCES devices(device_name), tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id), label TEXT NOT NULL
) STRICT;
CREATE INDEX IF NOT EXISTS devices_by_tenant ON device_ownership(tenant_id,device_name);
CREATE TABLE IF NOT EXISTS tenant_policies (
 tenant_id TEXT PRIMARY KEY REFERENCES tenants(tenant_id), config_json TEXT NOT NULL, updated_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS admin_session_owners (
 token_hash TEXT PRIMARY KEY REFERENCES admin_sessions(token_hash) ON DELETE CASCADE,
 user_id TEXT REFERENCES users(user_id), tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id)
) STRICT;
CREATE TABLE IF NOT EXISTS tenant_audit (
 id INTEGER PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id), actor TEXT NOT NULL,
 timestamp INTEGER NOT NULL, action TEXT NOT NULL, details_json TEXT NOT NULL
) STRICT;
CREATE INDEX IF NOT EXISTS tenant_audit_time ON tenant_audit(tenant_id,timestamp);
PRAGMA user_version=4;

-- 清理频繁运行；使用时间索引避免设备增多后每分钟全表扫描。
CREATE INDEX IF NOT EXISTS receipts_expiry ON heartbeat_receipts(received_ms);
CREATE INDEX IF NOT EXISTS tickets_expiry ON launch_tickets(expires_ms);
CREATE INDEX IF NOT EXISTS browser_expiry ON browser_sessions(expires_ms);
CREATE INDEX IF NOT EXISTS answer_expiry ON answer_receipts(created_ms);
CREATE INDEX IF NOT EXISTS admin_expiry ON admin_sessions(expires_ms);

CREATE TABLE IF NOT EXISTS tenant_learning (
 tenant_id TEXT PRIMARY KEY REFERENCES tenants(tenant_id), config_json TEXT NOT NULL, updated_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS question_payloads (
 question_id TEXT PRIMARY KEY, payload_json TEXT NOT NULL, expires_ms INTEGER NOT NULL
) STRICT;
CREATE INDEX IF NOT EXISTS question_payload_expiry ON question_payloads(expires_ms);
PRAGMA user_version=5;

CREATE TABLE IF NOT EXISTS display_agent_tokens (
 id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id), device_name TEXT NOT NULL REFERENCES devices(device_name),
 token_hash TEXT NOT NULL UNIQUE, expires_ms INTEGER NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, created_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS display_jobs (
 id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id), device_name TEXT NOT NULL REFERENCES devices(device_name),
 agent_id TEXT REFERENCES display_agent_tokens(id), request_id TEXT NOT NULL, intent TEXT NOT NULL, document_json TEXT NOT NULL,
 digest TEXT NOT NULL, context_digest TEXT NOT NULL, review_status TEXT NOT NULL CHECK(review_status IN('pending','allow','deny','error')),
 review_policy TEXT, state TEXT NOT NULL DEFAULT 'draft' CHECK(state IN('draft','published','cancelled')),
 created_ms INTEGER NOT NULL, expires_ms INTEGER, opened_ms INTEGER, visible_ms INTEGER,
 UNIQUE(device_name,request_id)
) STRICT;
CREATE INDEX IF NOT EXISTS display_device_live ON display_jobs(device_name,state,expires_ms);
CREATE INDEX IF NOT EXISTS display_agent_quota ON display_jobs(agent_id,created_ms);
PRAGMA user_version=6;
CREATE TABLE IF NOT EXISTS client_capabilities (
 device_name TEXT PRIMARY KEY REFERENCES devices(device_name), display_supported INTEGER NOT NULL, received_ms INTEGER NOT NULL
) STRICT;

-- Family TV mobile control. Additive migration keeps older clients usable.
CREATE TABLE IF NOT EXISTS mobile_control (
 device_name TEXT PRIMARY KEY REFERENCES devices(device_name),
 paused INTEGER NOT NULL DEFAULT 0 CHECK(paused IN(0,1)),
 revision INTEGER NOT NULL DEFAULT 1,
 applied_revision INTEGER NOT NULL DEFAULT 0,
 enforcement_result TEXT,
 applied_ms INTEGER
) STRICT;

CREATE TABLE IF NOT EXISTS installation_tickets (
 code_hash TEXT PRIMARY KEY,
 device_name TEXT NOT NULL REFERENCES devices(device_name),
 expires_ms INTEGER NOT NULL,
 redeemed_ms INTEGER
) STRICT;
CREATE TABLE IF NOT EXISTS installation_health (
 device_name TEXT PRIMARY KEY REFERENCES devices(device_name),
 initial_boot INTEGER,
 latest_boot INTEGER,
 adb_enabled INTEGER,
 permissions_ok INTEGER,
 stopped_ms INTEGER,
 resumed_ms INTEGER,
 received_ms INTEGER NOT NULL,
 adb_closed_boot INTEGER
) STRICT;
