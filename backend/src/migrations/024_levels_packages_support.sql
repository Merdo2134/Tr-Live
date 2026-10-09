-- 160 kademeli seviye: mevcut kullanıcıların seviyelerini yeni eğriye göre yeniden hesapla (L = floor((exp/2000)^0.4) + 1, en çok 160).
UPDATE users SET
  coin_level = LEAST(160, GREATEST(1, FLOOR(POWER(total_sent_coins::numeric / 2000.0, 0.4))::int + 1)),
  gift_level = LEAST(160, GREATEST(1, FLOOR(POWER(total_received_diamonds::numeric / 2000.0, 0.4))::int + 1));

-- Coin yükleme paketleri (Yükleme Merkezi)
CREATE TABLE IF NOT EXISTS coin_packages(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coins BIGINT NOT NULL CHECK (coins > 0),
  price_cents BIGINT NOT NULL CHECK (price_cents >= 0),
  currency VARCHAR(3) NOT NULL DEFAULT 'TRY',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0
);
INSERT INTO coin_packages(coins, price_cents, sort_order)
SELECT * FROM (VALUES (7000, 4299, 1), (35000, 21499, 2), (70500, 42999, 3)) AS v(coins, price_cents, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM coin_packages);

-- Müşteri hizmetleri sohbeti
CREATE TABLE IF NOT EXISTS support_messages(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_staff BOOLEAN NOT NULL DEFAULT FALSE,
  staff_id UUID REFERENCES users(id) ON DELETE SET NULL,
  category VARCHAR(40),
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_support_user ON support_messages(user_id, created_at DESC);
