-- v2.41.0: CP (yakınlık) sistemi.
--  * Her iki kişi arasında yakınlık puanı (exp): günlük ilk 10 özel mesaj 10'ar exp, aralarındaki hediyeler Coin
--    değeri kadar (CP hediyesi 1,5 kat). 5 kademe.
--  * 3. kademeden itibaren ilişki seçilebilir: Arkadaş ya da CP (karşı taraf onaylar). Bir kişinin tek CP'si olur.
-- Tekrar çalıştırılabilir.
CREATE TABLE IF NOT EXISTS cp_pairs (
  user_a UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exp BIGINT NOT NULL DEFAULT 0,
  relation VARCHAR(8) NOT NULL DEFAULT 'none' CHECK (relation IN ('none', 'friend', 'cp')),
  relation_since TIMESTAMPTZ,
  request_kind VARCHAR(8) CHECK (request_kind IN ('friend', 'cp')),
  request_from UUID REFERENCES users(id) ON DELETE SET NULL,
  request_at TIMESTAMPTZ,
  msg_day DATE,
  msg_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_a, user_b),
  CHECK (user_a < user_b)
);
CREATE INDEX IF NOT EXISTS idx_cp_pairs_b ON cp_pairs(user_b);
CREATE INDEX IF NOT EXISTS idx_cp_pairs_request ON cp_pairs(request_at DESC) WHERE request_kind IS NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS cp_partner_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- Hediye sekmesi: CP hediyeleri (yakınlığa 1,5 kat puan).
ALTER TABLE gifts DROP CONSTRAINT IF EXISTS gifts_category_check;
ALTER TABLE gifts ADD CONSTRAINT gifts_category_check CHECK (category IN ('event', 'popular', 'private', 'vip', 'lucky', 'cp'));
