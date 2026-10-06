-- Hediye paneli sekmeleri: Etkinlik / Popüler / Kişiye Özel / Vip.
ALTER TABLE gifts ADD COLUMN IF NOT EXISTS category VARCHAR(20) NOT NULL DEFAULT 'popular'
  CHECK (category IN ('event', 'popular', 'private', 'vip'));
UPDATE gifts SET category = 'vip' WHERE name = 'Crown' AND category = 'popular';
