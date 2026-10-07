-- 007: Yardımcı admin, süreli ban, kilitli koltuklar
ALTER TABLE users ADD COLUMN IF NOT EXISTS banned_until TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS ban_reason TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS banned_by UUID REFERENCES users(id);
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS locked_seats INT[] NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS idx_users_banned_until ON users(banned_until) WHERE account_status = 'banned' AND banned_until IS NOT NULL;
