-- 017: Oda kartı (duyuru, kapak fotoğrafı) ve süper çanta geri sayımı.
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS announcement VARCHAR(200);
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS cover_url TEXT;
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS announcement VARCHAR(200);
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS cover_url TEXT;
ALTER TABLE lucky_bags ADD COLUMN IF NOT EXISTS opens_at TIMESTAMPTZ;
UPDATE lucky_bags SET opens_at = created_at WHERE opens_at IS NULL;
