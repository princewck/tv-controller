PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS households (
 id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, password_json TEXT NOT NULL,
 recovery_hash TEXT NOT NULL, policy_json TEXT NOT NULL, created_ms INTEGER NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS sessions (
 token_hash TEXT PRIMARY KEY, household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
 csrf TEXT NOT NULL, expires_ms INTEGER NOT NULL
) STRICT;
CREATE INDEX IF NOT EXISTS session_expiry ON sessions(expires_ms);
CREATE TABLE IF NOT EXISTS devices (
 id TEXT PRIMARY KEY, household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
 label TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, enabled INTEGER NOT NULL DEFAULT 1,
 created_ms INTEGER NOT NULL, last_heartbeat_ms INTEGER, paused INTEGER NOT NULL DEFAULT 0,
 revision INTEGER NOT NULL DEFAULT 1, applied_revision INTEGER NOT NULL DEFAULT 0,
 enforcement_result TEXT, applied_ms INTEGER, bonus_seconds INTEGER NOT NULL DEFAULT 0,
 bonus_expires_ms INTEGER, boot_count INTEGER, initial_boot INTEGER, closed_at_boot INTEGER,
 adb_enabled INTEGER, permissions_ok INTEGER, stopped_ms INTEGER, resumed_ms INTEGER
) STRICT;
CREATE INDEX IF NOT EXISTS household_devices ON devices(household_id);
CREATE TABLE IF NOT EXISTS installation_tickets (
 code_hash TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
 expires_ms INTEGER NOT NULL, redeemed_ms INTEGER, redeem_token_hash TEXT
) STRICT;
CREATE TABLE IF NOT EXISTS daily_usage (
 device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE, day TEXT NOT NULL,
 app_package TEXT NOT NULL, seconds INTEGER NOT NULL, PRIMARY KEY(device_id,day,app_package)
) STRICT;
CREATE TABLE IF NOT EXISTS heartbeat_receipts (
 device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,event_id TEXT NOT NULL,
 received_ms INTEGER NOT NULL,day TEXT NOT NULL,previous_day TEXT NOT NULL,
 app_package TEXT NOT NULL,seconds INTEGER NOT NULL,current_seconds INTEGER NOT NULL,
 is_playing INTEGER NOT NULL,PRIMARY KEY(device_id,event_id)
) STRICT;
CREATE TRIGGER IF NOT EXISTS consume_heartbeat AFTER INSERT ON heartbeat_receipts BEGIN
 INSERT INTO daily_usage(device_id,day,app_package,seconds)
 SELECT NEW.device_id,NEW.day,NEW.app_package,NEW.current_seconds WHERE NEW.is_playing=1 AND NEW.current_seconds>0
 ON CONFLICT(device_id,day,app_package) DO UPDATE SET seconds=seconds+excluded.seconds;
 INSERT INTO daily_usage(device_id,day,app_package,seconds)
 SELECT NEW.device_id,NEW.previous_day,NEW.app_package,NEW.seconds-NEW.current_seconds WHERE NEW.is_playing=1 AND NEW.seconds>NEW.current_seconds
 ON CONFLICT(device_id,day,app_package) DO UPDATE SET seconds=seconds+excluded.seconds;
 UPDATE devices SET last_heartbeat_ms=NEW.received_ms,
 bonus_seconds=CASE WHEN NEW.is_playing=1 AND bonus_expires_ms>NEW.received_ms THEN MAX(0,bonus_seconds-NEW.seconds) ELSE bonus_seconds END
 WHERE id=NEW.device_id;
END;
CREATE TABLE IF NOT EXISTS operations (
 household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,kind TEXT NOT NULL,device_id TEXT NOT NULL,
 body_hash TEXT NOT NULL,payload_json TEXT NOT NULL,created_ms INTEGER NOT NULL, PRIMARY KEY(household_id,request_id)
) STRICT;
CREATE TABLE IF NOT EXISTS subscriptions (
 original_id TEXT PRIMARY KEY,household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
 transaction_id TEXT NOT NULL,product_id TEXT NOT NULL,environment TEXT NOT NULL,
 expires_ms INTEGER NOT NULL,revoked INTEGER NOT NULL,signed_ms INTEGER NOT NULL
) STRICT;
CREATE INDEX IF NOT EXISTS household_subscription ON subscriptions(household_id,expires_ms);
CREATE TABLE IF NOT EXISTS rate_limits (
 key TEXT PRIMARY KEY,count INTEGER NOT NULL,reset_ms INTEGER NOT NULL
) STRICT;

CREATE TRIGGER IF NOT EXISTS apply_operation AFTER INSERT ON operations BEGIN
 UPDATE devices SET paused=json_extract(NEW.payload_json,'$.paused'),revision=revision+1 WHERE id=NEW.device_id AND household_id=NEW.household_id AND NEW.kind='pause';
 UPDATE devices SET bonus_seconds=json_extract(NEW.payload_json,'$.seconds'),bonus_expires_ms=NEW.created_ms+86400000,revision=revision+1 WHERE id=NEW.device_id AND household_id=NEW.household_id AND NEW.kind='grant';
END;

CREATE TRIGGER IF NOT EXISTS redeem_installation AFTER UPDATE OF redeemed_ms ON installation_tickets
WHEN OLD.redeemed_ms IS NULL AND NEW.redeemed_ms IS NOT NULL BEGIN
 UPDATE devices SET token_hash=NEW.redeem_token_hash WHERE id=NEW.device_id AND enabled=1;
END;

CREATE TRIGGER IF NOT EXISTS revoke_sessions_on_password AFTER UPDATE OF password_json ON households BEGIN DELETE FROM sessions WHERE household_id=NEW.id; END;
