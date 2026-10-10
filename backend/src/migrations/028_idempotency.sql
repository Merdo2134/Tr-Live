-- v2.37: para işlemlerinde tekrar koruması (idempotency).
-- Uygulama her "Gönder / Satın al" dokunuşu için tek bir anahtar üretir; zayıf ağda istek iki kez gitse
-- (ya da zaman aşımından sonra otomatik tekrar denense) sunucu işlemi bir kez yapar, ikincisinde ilk sonucu döndürür.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key VARCHAR(64) NOT NULL,
  endpoint VARCHAR(60) NOT NULL,
  status_code INT,
  response JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, key)
);
CREATE INDEX IF NOT EXISTS idx_idempotency_created ON idempotency_keys(created_at);
