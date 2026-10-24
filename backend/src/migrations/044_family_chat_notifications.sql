-- v2.57.0: Aile sohbeti (aile üyeleri kendi arasında) ve Mesajlar'daki "Bildirimler" alanı.
CREATE TABLE IF NOT EXISTS family_messages (
  id BIGSERIAL PRIMARY KEY,
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body VARCHAR(500) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_family_messages_family ON family_messages(family_id, id DESC);

-- Bildirimler sayfasında en son görülen bildirim (okunmamış sayısı için).
ALTER TABLE users ADD COLUMN IF NOT EXISTS notify_seen_id BIGINT NOT NULL DEFAULT 0;
-- Aile sohbetinde en son okunan mesaj.
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS chat_seen_id BIGINT NOT NULL DEFAULT 0;
