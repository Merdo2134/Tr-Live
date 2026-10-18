-- Kişiye özel telefon bildirimleri: arkadaşlık isteği, yeni takipçi, arkadaşın oda açması.
-- Uygulama açık/arka plandayken soketten anında, kapalıyken açılınca (son numaradan sonrakiler) gösterilir.
CREATE TABLE IF NOT EXISTS user_notifications (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind VARCHAR(20) NOT NULL,
  title VARCHAR(80) NOT NULL,
  body VARCHAR(300) NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_user_notifications_user ON user_notifications(user_id, id);
CREATE INDEX IF NOT EXISTS idx_user_notifications_created ON user_notifications(created_at);

-- Kullanıcının bildirim tercihleri: {"friend": false} gibi; anahtar yoksa açık sayılır.
ALTER TABLE users ADD COLUMN IF NOT EXISTS notify_prefs JSONB NOT NULL DEFAULT '{}'::jsonb;
