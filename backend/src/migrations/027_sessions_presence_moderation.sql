-- v2.36: cihaz oturumları (yenileme token'ı), çevrimiçi gizliliği, otomatik moderasyon,
-- uygulama hata kayıtları ve uzaktan ayarlar.

-- ---------- Cihaz oturumları ----------
-- Yenileme token'ının kendisi saklanmaz, yalnızca SHA-256 özeti. Her yenilemede token değişir (rotasyon);
-- bir önceki token kısa bir süre (ağ kopması nedeniyle yanıtın ulaşmadığı durum) kabul edilir, sonrasında
-- eski token'ın kullanılması çalıntı sayılır ve oturum kapatılır.
CREATE TABLE IF NOT EXISTS user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_hash CHAR(64) NOT NULL,
  prev_hash CHAR(64),
  rotated_at TIMESTAMPTZ,
  device_id VARCHAR(64),
  device_name VARCHAR(80),
  platform VARCHAR(20),
  app_version VARCHAR(20),
  emulator BOOLEAN NOT NULL DEFAULT FALSE,
  ip VARCHAR(64),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  revoke_reason VARCHAR(30),
  -- Eski tip (30 günlük) token'dan yükseltilen oturum: aynı token ikinci kez yükseltilemez.
  legacy_hash CHAR(64)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_refresh ON user_sessions(refresh_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_prev ON user_sessions(prev_hash) WHERE prev_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id, last_used_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_device ON user_sessions(device_id) WHERE device_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_legacy ON user_sessions(legacy_hash) WHERE legacy_hash IS NOT NULL;

-- ---------- Çevrimiçi durumu ----------
-- users.last_seen_at (004) artık gerçekten güncelleniyor. Kullanıcı isterse durumunu gizleyebilir.
ALTER TABLE users ADD COLUMN IF NOT EXISTS show_presence BOOLEAN NOT NULL DEFAULT TRUE;

-- ---------- Otomatik moderasyon ----------
-- Link/reklam/küfür/spam nedeniyle reddedilen her mesaj bir "ihlal" kaydıdır. Kısa sürede tekrarlanırsa
-- kullanıcı tüm sohbetlerde süreli olarak kısıtlanır (chat_restricted_until).
ALTER TABLE users ADD COLUMN IF NOT EXISTS chat_restricted_until TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS moderation_strikes (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind VARCHAR(20) NOT NULL,
  context VARCHAR(20) NOT NULL,
  sample VARCHAR(300),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_strikes_user ON moderation_strikes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_strikes_created ON moderation_strikes(created_at DESC);

-- ---------- Uygulama hata kayıtları ----------
CREATE TABLE IF NOT EXISTS client_errors (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  app_version VARCHAR(20),
  device VARCHAR(80),
  source VARCHAR(80) NOT NULL,
  message VARCHAR(1000) NOT NULL,
  stack VARCHAR(2000),
  occurred_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_client_errors_created ON client_errors(created_at DESC);

-- ---------- Uzaktan ayarlar ----------
CREATE TABLE IF NOT EXISTS app_config (
  key VARCHAR(40) PRIMARY KEY,
  value JSONB NOT NULL,
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Yönetim panelindeki günlük sayılar ve işlem kaydı için indeksler.
CREATE INDEX IF NOT EXISTS idx_users_created ON users(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at DESC) WHERE last_seen_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_created ON financial_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_media_created_by ON media_files(created_by) WHERE created_by IS NOT NULL;
-- Panel her 10 sn'de "bugünkü mesaj" sayar; tarih indeksi olmadan tüm tablo taranırdı.
CREATE INDEX IF NOT EXISTS idx_room_messages_created ON room_messages(created_at);
CREATE INDEX IF NOT EXISTS idx_direct_messages_created ON direct_messages(created_at);
