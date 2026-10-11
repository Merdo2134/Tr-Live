-- v2.41.0: Yoho tarzı mesajlar.
--  * Duyurular (Ekip / Etkinlik / Ödül) görsel ve bağlantı taşıyabilir (kart görünümü).
--  * Kart rozetleri türe göre ayrı sıfırlanır (bir kartı açmak diğerlerinin rozetini silmez).
--  * Özel mesajda fotoğraf gönderilebilir (metin boş olabilir).
-- Tekrar çalıştırılabilir.
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS link_url TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS inbox_seen JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS image_url TEXT;
CREATE INDEX IF NOT EXISTS idx_friend_requests_pending ON friend_requests(target_id, created_at DESC) WHERE status = 'pending';
