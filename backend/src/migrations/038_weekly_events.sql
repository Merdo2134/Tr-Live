-- Haftalık etkinlikler: Haftalık Çift (CP hediyeleri), Kral / Kraliçe (en çok hediye alan erkek / kadın),
-- Haftalık Yıldız (seçilen 4 hediyenin her birinden en çok gönderen). Hafta: Pazartesi 00:00 (Türkiye saati).
-- Her etkinliğin ilk 3'üne yönetimden ayarlanan ödüller (Coin, WIP, çerçeve, rozet, araç…) otomatik verilir.
CREATE TABLE IF NOT EXISTS weekly_event_config (
  kind VARCHAR(10) PRIMARY KEY CHECK (kind IN ('couple', 'king', 'queen', 'star1', 'star2', 'star3', 'star4')),
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  gift_id UUID REFERENCES gifts(id) ON DELETE SET NULL, -- yalnızca Yıldız etkinlikleri
  rewards JSONB NOT NULL DEFAULT '{}'::jsonb,           -- {"1": [ödül...], "2": [...], "3": [...]}
  rules TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO weekly_event_config(kind, rewards) VALUES
  ('couple', '{"1":[{"type":"wip","level":3,"days":7}],"2":[{"type":"wip","level":2,"days":7}],"3":[{"type":"wip","level":1,"days":7}]}'),
  ('king',   '{"1":[{"type":"wip","level":3,"days":7}],"2":[{"type":"wip","level":2,"days":7}],"3":[{"type":"wip","level":1,"days":7}]}'),
  ('queen',  '{"1":[{"type":"wip","level":3,"days":7}],"2":[{"type":"wip","level":2,"days":7}],"3":[{"type":"wip","level":1,"days":7}]}'),
  ('star1',  '{"1":[{"type":"wip","level":2,"days":7}],"2":[{"type":"wip","level":1,"days":7}],"3":[{"type":"wip","level":1,"days":3}]}'),
  ('star2',  '{"1":[{"type":"wip","level":2,"days":7}],"2":[{"type":"wip","level":1,"days":7}],"3":[{"type":"wip","level":1,"days":3}]}'),
  ('star3',  '{"1":[{"type":"wip","level":2,"days":7}],"2":[{"type":"wip","level":1,"days":7}],"3":[{"type":"wip","level":1,"days":3}]}'),
  ('star4',  '{"1":[{"type":"wip","level":2,"days":7}],"2":[{"type":"wip","level":1,"days":7}],"3":[{"type":"wip","level":1,"days":3}]}')
ON CONFLICT (kind) DO NOTHING;

-- Kapanan haftalar (bir hafta yalnızca bir kez dağıtılır).
CREATE TABLE IF NOT EXISTS weekly_event_settlements (
  week_start TIMESTAMPTZ PRIMARY KEY,
  settled_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Kazananlar (geçmiş haftalar). Çift etkinliğinde partner_id dolu.
CREATE TABLE IF NOT EXISTS weekly_event_results (
  week_start TIMESTAMPTZ NOT NULL,
  kind VARCHAR(10) NOT NULL,
  rank INT NOT NULL CHECK (rank BETWEEN 1 AND 3),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  partner_id UUID REFERENCES users(id) ON DELETE SET NULL,
  score BIGINT NOT NULL,
  gift_id UUID REFERENCES gifts(id) ON DELETE SET NULL,
  rewards JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (week_start, kind, rank)
);
CREATE INDEX IF NOT EXISTS idx_weekly_event_results_user ON weekly_event_results(user_id);

-- Yıldız etkinliği sıralaması: belirli hediyenin haftalık gönderimleri.
CREATE INDEX IF NOT EXISTS idx_gift_tx_gift_time ON gift_transactions(gift_id, created_at);

-- Özellik eklenmeden önceki hafta dağıtılmış sayılır (ilk açılışta geçmiş haftaya habersiz ödül verilmesin).
INSERT INTO weekly_event_settlements(week_start)
VALUES ((date_trunc('week', NOW() AT TIME ZONE 'Europe/Istanbul') - INTERVAL '7 days') AT TIME ZONE 'Europe/Istanbul')
ON CONFLICT (week_start) DO NOTHING;
