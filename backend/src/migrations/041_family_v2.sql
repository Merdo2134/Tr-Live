-- v2.53.0: Aile (Figma tasarımı).
--  * Seviyeler: Demir, Bronz, Gümüş, Altın, Elmas (üye ve yönetici sınırı seviyeye göre).
--  * Katılım başvuru ile: yönetici onaylar; "İstek Ayarları" ile en düşük zenginlik seviyesi.
--  * Katkı değeri (🔥): günlük giriş, yükleme, gönderilen ve alınan hediyeler. Üyenin haftalık katkısı tutulur.
--  * Haftalık Coins ödülü (aile başkanı alır) ve başkan indirimi (kişisel harcamanın yüzdesi).
-- Tekrar çalıştırılabilir.
ALTER TABLE families ADD COLUMN IF NOT EXISTS join_min_level INT NOT NULL DEFAULT 0;
ALTER TABLE families ADD COLUMN IF NOT EXISTS public_id VARCHAR(12);
-- leader_cashback: 1/10000 Coin biriminde (harcama x baz puan); alınırken 10000'e bölünür.
ALTER TABLE families ADD COLUMN IF NOT EXISTS leader_cashback BIGINT NOT NULL DEFAULT 0;
ALTER TABLE families ADD COLUMN IF NOT EXISTS leader_spent BIGINT NOT NULL DEFAULT 0;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS total_contrib BIGINT NOT NULL DEFAULT 0;

-- Aile kimliği (8 haneli), aile sayfasında "ID:" olarak görünür.
-- Benzersiz olsun diye sıra numarasından üretilir (rastgele çakışma dizini bozmasın).
UPDATE families f SET public_id = (10000000 + s.rn + COALESCE((SELECT MAX(public_id::bigint) - 10000000 FROM families WHERE public_id ~ '^[0-9]{8}$'), 0))::text
FROM (SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn FROM families WHERE public_id IS NULL) s
WHERE f.id = s.id;
CREATE UNIQUE INDEX IF NOT EXISTS idx_families_public_id ON families(public_id) WHERE public_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS family_join_requests (
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (family_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_family_join_requests_user ON family_join_requests(user_id);

-- Üyenin haftalık katkısı (hafta: Pazartesi 00:00 İstanbul).
CREATE TABLE IF NOT EXISTS family_contrib_weekly (
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  points BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (family_id, user_id, week_start)
);
CREATE INDEX IF NOT EXISTS idx_family_contrib_week ON family_contrib_weekly(family_id, week_start);

-- Günlük giriş katkısı (kişi başı günde bir kez).
CREATE TABLE IF NOT EXISTS family_daily_login (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  PRIMARY KEY (user_id, day)
);

-- Haftalık Coins ödülü: hangi kademe alındı.
CREATE TABLE IF NOT EXISTS family_week_rewards (
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  tier INT NOT NULL,
  claimed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  coins BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (family_id, week_start, tier)
);

-- Yeni seviye eşikleri (1M/6M/20M/60M): mevcut ailelerin seviyesi yeniden hesaplanır.
UPDATE families SET level = 1 + (total_points >= 1000000)::int + (total_points >= 6000000)::int
  + (total_points >= 20000000)::int + (total_points >= 60000000)::int;

-- Zirve Listesi "Yükleme" sekmesi için.
CREATE INDEX IF NOT EXISTS idx_wallet_type_created ON wallet_transactions(transaction_type, created_at);
