CREATE TABLE IF NOT EXISTS usage_samples (
 device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,event_id TEXT NOT NULL,
 day TEXT NOT NULL,app_package TEXT NOT NULL,seconds INTEGER NOT NULL,at_ms INTEGER NOT NULL,
 PRIMARY KEY(device_id,event_id)
) STRICT;
CREATE TRIGGER IF NOT EXISTS consume_usage_sample AFTER INSERT ON usage_samples BEGIN
 INSERT INTO daily_usage(device_id,day,app_package,seconds) VALUES(NEW.device_id,NEW.day,NEW.app_package,NEW.seconds)
 ON CONFLICT(device_id,day,app_package) DO UPDATE SET seconds=MIN(86400,seconds+excluded.seconds);
 UPDATE devices SET bonus_seconds=MAX(0,bonus_seconds-NEW.seconds) WHERE id=NEW.device_id AND NEW.at_ms>=bonus_expires_ms-86400000 AND NEW.at_ms<bonus_expires_ms;
END;
