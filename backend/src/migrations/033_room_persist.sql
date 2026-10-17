-- v2.42.0: Oda kapatılıp açılınca oda içindeki ayarlar ve oda elması korunur.
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS chat_enabled BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS theme_image_url TEXT;
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS scoreboard_enabled BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS mic_request BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS locked_seats INT[] NOT NULL DEFAULT '{}';
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS password_hash TEXT;
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS total_diamonds BIGINT NOT NULL DEFAULT 0;
-- Şu ana kadar bu sahibin bu türdeki odalarına gelen hediyeler (oda elması) bir kez hesaplanır.
UPDATE room_profiles p SET total_diamonds = COALESCE((
  SELECT SUM(COALESCE(gt.diamond_amount, gt.coin_amount)) FROM gift_transactions gt JOIN rooms r ON r.id = gt.room_id
  WHERE r.owner_id = p.owner_id AND r.room_type = p.room_type), 0);
-- Açık odaların ayarları profile kopyalanır.
UPDATE room_profiles p SET chat_enabled = r.chat_enabled, theme_image_url = r.theme_image_url, scoreboard_enabled = r.scoreboard_enabled,
  mic_request = r.mic_request, locked_seats = COALESCE(r.locked_seats, '{}'), password_hash = r.password_hash, is_hidden = r.is_hidden
FROM rooms r WHERE r.owner_id = p.owner_id AND r.room_type = p.room_type AND r.is_active = TRUE;
