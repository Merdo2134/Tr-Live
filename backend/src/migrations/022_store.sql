-- Mağaza ürünleri (Coins Mağazası). Çerçeve ve giriş efekti ürünleri mevcut kataloğa bağlanır.
CREATE TABLE IF NOT EXISTS store_items(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category VARCHAR(30) NOT NULL CHECK (category IN ('frame','chat_bubble','entrance_effect','mini_card','mic_wave','vehicle')),
  name VARCHAR(100) NOT NULL,
  image_url TEXT NOT NULL,
  ref_id UUID,
  price_coins BIGINT NOT NULL CHECK (price_coins >= 0),
  duration_days INT NOT NULL DEFAULT 14 CHECK (duration_days BETWEEN 1 AND 3650),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_store_items_cat ON store_items(category, is_active, sort_order, created_at DESC);
