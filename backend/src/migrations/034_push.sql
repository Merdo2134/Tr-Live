-- v2.42.0: Yönetim panelinden tüm kullanıcılara telefon bildirimi.
CREATE TABLE IF NOT EXISTS push_messages (
  id BIGSERIAL PRIMARY KEY,
  title VARCHAR(80) NOT NULL,
  body VARCHAR(300) NOT NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_push_messages_created ON push_messages(created_at DESC);
