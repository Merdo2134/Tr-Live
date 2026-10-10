-- v2.38: WIP 1–10 + SWIP (hayalet), şanslı hediye.

-- ---------- WIP kademeleri 1–10, SWIP = 11 ----------
ALTER TABLE wip_tiers DROP CONSTRAINT IF EXISTS wip_tiers_level_check;
ALTER TABLE user_wip DROP CONSTRAINT IF EXISTS user_wip_level_valid;
ALTER TABLE wip_plans DROP CONSTRAINT IF EXISTS wip_plans_level_valid;

-- Eski 5 kademe yeni 10 kademeye oransal taşınır (eski en üst = yeni en üst; ödenen ayrıcalık kaybolmaz):
-- 1→2, 2→4, 3→6, 4→8 (buzlu nick), 5→10 (ateşli nick). Eski paketler kapatılır; yeni fiyat tablosu aşağıda.
-- Yalnızca bir kez (henüz 5'ten büyük kademe yokken) yapılır: dosya tekrar çalışsa seviyeler yeniden katlanmaz.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM wip_tiers WHERE level > 5) THEN
    UPDATE user_wip SET level = level * 2 WHERE level BETWEEN 1 AND 5;
    UPDATE wip_plans SET is_active = FALSE WHERE level BETWEEN 1 AND 5;
  END IF;
END $$;

ALTER TABLE wip_tiers ADD CONSTRAINT wip_tiers_level_check CHECK (level BETWEEN 1 AND 11);
ALTER TABLE user_wip ADD CONSTRAINT user_wip_level_valid CHECK (level BETWEEN 1 AND 11);
ALTER TABLE wip_plans ADD CONSTRAINT wip_plans_level_valid CHECK (level BETWEEN 1 AND 11 AND duration_days > 0 AND price_coins >= 0);

-- Ayrıcalıklar birikimlidir (üst kademe alttakilerin hepsini içerir). Yönetim panelinden değiştirilebilir.
INSERT INTO wip_tiers(level, name, features) VALUES
  (1,  'WIP 1 · Bronz',     '{"nameColor":"#CD7F32","badge":"wip_1","maxRooms":1,"viewVisitors":false,"vipGifts":false,"muteImmunity":false,"kickImmunity":false,"profileEffect":false,"customRoomTheme":false,"invisibleVisit":false,"animatedAvatar":false,"ghostMode":false}'),
  (2,  'WIP 2 · Gümüş',     '{"nameColor":"#C0C0C0","badge":"wip_2","maxRooms":1,"viewVisitors":true,"vipGifts":false,"muteImmunity":false,"kickImmunity":false,"profileEffect":false,"customRoomTheme":false,"invisibleVisit":false,"animatedAvatar":false,"ghostMode":false}'),
  (3,  'WIP 3 · Altın',     '{"nameColor":"#FFD700","badge":"wip_3","maxRooms":1,"viewVisitors":true,"vipGifts":true,"muteImmunity":false,"kickImmunity":false,"profileEffect":false,"customRoomTheme":false,"invisibleVisit":false,"animatedAvatar":false,"ghostMode":false}'),
  (4,  'WIP 4 · Zümrüt',    '{"nameColor":"#2ECC71","badge":"wip_4","maxRooms":2,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":false,"profileEffect":false,"customRoomTheme":false,"invisibleVisit":false,"animatedAvatar":false,"ghostMode":false}'),
  (5,  'WIP 5 · Ametist',   '{"nameColor":"#B36BFF","badge":"wip_5","maxRooms":2,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":false,"profileEffect":true,"customRoomTheme":false,"invisibleVisit":false,"animatedAvatar":false,"ghostMode":false}'),
  (6,  'WIP 6 · Kraliyet',  '{"nameColor":"#FFC43D","badge":"wip_6","maxRooms":2,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":true,"profileEffect":true,"customRoomTheme":true,"invisibleVisit":false,"animatedAvatar":false,"ghostMode":false}'),
  (7,  'WIP 7 · Yeşim',     '{"nameColor":"#00E5A0","badge":"wip_7","maxRooms":3,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":true,"profileEffect":true,"customRoomTheme":true,"invisibleVisit":true,"animatedAvatar":false,"ghostMode":false}'),
  (8,  'WIP 8 · Buz',       '{"nameColor":"#80D8FF","badge":"wip_8","maxRooms":3,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":true,"profileEffect":true,"customRoomTheme":true,"invisibleVisit":true,"animatedAvatar":true,"ghostMode":false}'),
  (9,  'WIP 9 · Gökkuşağı', '{"nameColor":"#FF7AD9","badge":"wip_9","maxRooms":4,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":true,"profileEffect":true,"customRoomTheme":true,"invisibleVisit":true,"animatedAvatar":true,"ghostMode":false}'),
  (10, 'WIP 10 · Ateş',     '{"nameColor":"#FF2B2B","badge":"wip_10","maxRooms":5,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":true,"profileEffect":true,"customRoomTheme":true,"invisibleVisit":true,"animatedAvatar":true,"ghostMode":false}'),
  (11, 'SWIP · Hayalet',    '{"nameColor":"#C9B8FF","badge":"swip","maxRooms":5,"viewVisitors":true,"vipGifts":true,"muteImmunity":true,"kickImmunity":true,"profileEffect":true,"customRoomTheme":true,"invisibleVisit":true,"animatedAvatar":true,"ghostMode":true}')
ON CONFLICT (level) DO UPDATE SET name = EXCLUDED.name, features = EXCLUDED.features;

INSERT INTO wip_plans(name, level, duration_days, price_coins)
SELECT v.name, v.level, 30, v.price
FROM (VALUES
  ('WIP 1 · 30 gün', 1, 5000::bigint),
  ('WIP 2 · 30 gün', 2, 12000::bigint),
  ('WIP 3 · 30 gün', 3, 25000::bigint),
  ('WIP 4 · 30 gün', 4, 50000::bigint),
  ('WIP 5 · 30 gün', 5, 90000::bigint),
  ('WIP 6 · 30 gün', 6, 150000::bigint),
  ('WIP 7 · 30 gün', 7, 250000::bigint),
  ('WIP 8 · 30 gün', 8, 400000::bigint),
  ('WIP 9 · 30 gün', 9, 650000::bigint),
  ('WIP 10 · 30 gün', 10, 1000000::bigint),
  ('SWIP · 30 gün', 11, 2000000::bigint)
) AS v(name, level, price)
WHERE NOT EXISTS (SELECT 1 FROM wip_plans p WHERE p.level = v.level AND p.duration_days = 30 AND p.is_active = TRUE);

-- ---------- SWIP hayalet modu ----------
-- Kullanıcının açıp kapattığı tercih; yalnızca kademesinde ghostMode varken geçerlidir.
ALTER TABLE users ADD COLUMN IF NOT EXISTS ghost_mode BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_users_ghost ON users(id) WHERE ghost_mode;

-- Hayalet mod şu an etkin mi (tercih açık + aktif kademesi izin veriyor).
CREATE OR REPLACE FUNCTION is_ghost(uid UUID) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT COALESCE((
    SELECT u.ghost_mode AND COALESCE((wt.features->>'ghostMode')::boolean, FALSE)
    FROM users u
    JOIN user_wip uw ON uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW()
    JOIN wip_tiers wt ON wt.level = uw.level
    WHERE u.id = uid
  ), FALSE)
$$;

-- Şu an hayalet olan kullanıcılar (oda listelerinde toplu sayım için; satır başına is_ghost() çağırmaktan çok hızlı).
CREATE OR REPLACE VIEW active_ghosts AS
  SELECT u.id FROM users u
  JOIN user_wip uw ON uw.user_id = u.id AND uw.is_active = TRUE AND uw.expires_at > NOW()
  JOIN wip_tiers wt ON wt.level = uw.level
  WHERE u.ghost_mode AND COALESCE((wt.features->>'ghostMode')::boolean, FALSE);

-- ---------- Şanslı hediye ----------
ALTER TABLE gifts DROP CONSTRAINT IF EXISTS gifts_category_check;
ALTER TABLE gifts ADD CONSTRAINT gifts_category_check CHECK (category IN ('event', 'popular', 'private', 'vip', 'lucky'));

-- Alıcıya geçen Elmas (şanslı hediyede hediye değerinin bir payı). NULL = coin_amount ile aynı (normal hediye).
ALTER TABLE gift_transactions ADD COLUMN IF NOT EXISTS diamond_amount BIGINT;
ALTER TABLE gift_transactions DROP CONSTRAINT IF EXISTS gift_transactions_diamond_amount_check;
ALTER TABLE gift_transactions ADD CONSTRAINT gift_transactions_diamond_amount_check CHECK (diamond_amount IS NULL OR diamond_amount >= 0);

INSERT INTO gifts(name, coin_price, animation_format, has_alpha, category)
SELECT v.name, v.price, 'lottie', TRUE, 'lucky'
FROM (VALUES ('Şanslı Çan', 10::bigint), ('Şanslı Yonca', 100::bigint)) AS v(name, price)
WHERE NOT EXISTS (SELECT 1 FROM gifts g WHERE g.name = v.name);
