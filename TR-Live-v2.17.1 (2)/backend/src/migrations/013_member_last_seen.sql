-- Oda üyesinin son görülme zamanı (uygulamadan gelen "yaşıyorum" sinyali). Temizleyici yalnızca uzun süredir sinyal vermeyenleri çıkarır.
ALTER TABLE room_members ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
