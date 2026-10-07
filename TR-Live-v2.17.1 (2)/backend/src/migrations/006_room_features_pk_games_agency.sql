-- 006: Oda özellikleri (gizli oda, tema, sayı tahtası), PK, oda oyunları ve Yoho tarzı ajans / yayıncı maaş sistemi.

-- ---------- Oda: gizleme, davet kodu, tema, sayı tahtası ----------
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS join_code VARCHAR(8);
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS theme VARCHAR(20) NOT NULL DEFAULT 'default';
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS theme_image_url TEXT;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS scoreboard_enabled BOOLEAN NOT NULL DEFAULT TRUE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_join_code ON rooms(join_code) WHERE join_code IS NOT NULL AND is_active = TRUE;

-- Oda içinde kullanıcı başına alınan hediye toplamı (mikrofon koltuğu sayacı).
CREATE TABLE IF NOT EXISTS room_gift_totals(
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total_coins BIGINT NOT NULL DEFAULT 0 CHECK (total_coins >= 0),
  total_count BIGINT NOT NULL DEFAULT 0 CHECK (total_count >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (room_id, user_id)
);

-- WIP 4+ özel oda teması özelliği.
UPDATE wip_tiers SET features = features || jsonb_build_object('customRoomTheme', level >= 4)
WHERE NOT (features ? 'customRoomTheme');

-- ---------- Mikrofon oturumları (yayın saati hesabı) ----------
CREATE TABLE IF NOT EXISTS mic_sessions(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mic_sessions_open ON mic_sessions(user_id, room_id) WHERE ended_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_mic_sessions_user_time ON mic_sessions(user_id, started_at DESC);

-- ---------- PK ----------
CREATE TABLE IF NOT EXISTS pk_battles(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_a UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  room_b UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  host_a UUID NOT NULL REFERENCES users(id),
  host_b UUID NOT NULL REFERENCES users(id),
  status VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','finished','declined','cancelled')),
  duration_seconds INT NOT NULL CHECK (duration_seconds BETWEEN 60 AND 1800),
  score_a BIGINT NOT NULL DEFAULT 0 CHECK (score_a >= 0),
  score_b BIGINT NOT NULL DEFAULT 0 CHECK (score_b >= 0),
  winner_room UUID REFERENCES rooms(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  CHECK (room_a <> room_b)
);
CREATE INDEX IF NOT EXISTS idx_pk_open_a ON pk_battles(room_a) WHERE status IN ('pending','active');
CREATE INDEX IF NOT EXISTS idx_pk_open_b ON pk_battles(room_b) WHERE status IN ('pending','active');

CREATE TABLE IF NOT EXISTS pk_supporters(
  battle_id UUID NOT NULL REFERENCES pk_battles(id) ON DELETE CASCADE,
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  coins BIGINT NOT NULL DEFAULT 0 CHECK (coins >= 0),
  PRIMARY KEY (battle_id, user_id)
);

-- ---------- Oda oyunları (Ludo) ----------
CREATE TABLE IF NOT EXISTS room_games(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  game_type VARCHAR(20) NOT NULL DEFAULT 'ludo' CHECK (game_type IN ('ludo')),
  status VARCHAR(12) NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting','playing','finished','cancelled')),
  state JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID NOT NULL REFERENCES users(id),
  winner_id UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_room_games_open ON room_games(room_id) WHERE status IN ('waiting','playing');

CREATE TABLE IF NOT EXISTS room_game_players(
  game_id UUID NOT NULL REFERENCES room_games(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seat INT NOT NULL CHECK (seat BETWEEN 0 AND 3),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (game_id, user_id),
  UNIQUE (game_id, seat)
);

-- ---------- Ajans / yayıncı maaş sistemi ----------
ALTER TABLE gift_transactions ADD COLUMN IF NOT EXISTS receiver_agency_id UUID REFERENCES agencies(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_gift_tx_receiver_time ON gift_transactions(receiver_id, created_at);
CREATE INDEX IF NOT EXISTS idx_gift_tx_agency_time ON gift_transactions(receiver_agency_id, created_at) WHERE receiver_agency_id IS NOT NULL;

ALTER TABLE agencies ADD COLUMN IF NOT EXISTS agency_code VARCHAR(8);
CREATE UNIQUE INDEX IF NOT EXISTS idx_agencies_code ON agencies(agency_code) WHERE agency_code IS NOT NULL;
-- Ajansa özel sabit komisyon (baz puan). NULL ise genel kademeli tablo kullanılır.
ALTER TABLE agencies ADD COLUMN IF NOT EXISTS commission_override_bps INT CHECK (commission_override_bps IS NULL OR commission_override_bps BETWEEN 0 AND 10000);

ALTER TABLE broadcasters ADD COLUMN IF NOT EXISTS contract_tier INT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_status VARCHAR(12) NOT NULL DEFAULT 'none' CHECK (kyc_status IN ('none','pending','approved','rejected'));

-- Tek satırlık genel ayarlar.
CREATE TABLE IF NOT EXISTS agency_settings(
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  cycle VARCHAR(10) NOT NULL DEFAULT 'monthly' CHECK (cycle IN ('weekly','monthly')),
  penalty_bps INT NOT NULL DEFAULT 5000 CHECK (penalty_bps BETWEEN 0 AND 10000),
  require_official_events BOOLEAN NOT NULL DEFAULT FALSE,
  min_event_count INT NOT NULL DEFAULT 0 CHECK (min_event_count BETWEEN 0 AND 50),
  currency VARCHAR(3) NOT NULL DEFAULT 'USD',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO agency_settings(id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- Yayıncı maaş kademeleri. Değerler ÖRNEKTİR; yönetici panelinden değiştirilir.
CREATE TABLE IF NOT EXISTS host_salary_tiers(
  level INT PRIMARY KEY CHECK (level BETWEEN 1 AND 10),
  required_hours INT NOT NULL CHECK (required_hours >= 0),
  required_diamonds BIGINT NOT NULL CHECK (required_diamonds >= 0),
  salary_cents BIGINT NOT NULL CHECK (salary_cents >= 0)
);
INSERT INTO host_salary_tiers(level, required_hours, required_diamonds, salary_cents) VALUES
  (1, 20, 10000, 5000),
  (2, 28, 35000, 15000),
  (3, 40, 80000, 40000),
  (4, 60, 200000, 100000),
  (5, 80, 500000, 250000)
ON CONFLICT (level) DO NOTHING;

-- Ajans komisyon kademeleri (ekip Diamond toplamına göre). Değerler ÖRNEKTİR.
CREATE TABLE IF NOT EXISTS agency_commission_tiers(
  level INT PRIMARY KEY CHECK (level BETWEEN 1 AND 10),
  min_team_diamonds BIGINT NOT NULL CHECK (min_team_diamonds >= 0),
  commission_bps INT NOT NULL CHECK (commission_bps BETWEEN 0 AND 10000)
);
INSERT INTO agency_commission_tiers(level, min_team_diamonds, commission_bps) VALUES
  (1, 0, 2000),
  (2, 500000, 3000),
  (3, 2000000, 4000),
  (4, 5000000, 5000)
ON CONFLICT (level) DO NOTHING;

-- Resmi etkinlikler ve yayıncı katılımı.
CREATE TABLE IF NOT EXISTS official_events(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(120) NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS official_event_attendance(
  event_id UUID NOT NULL REFERENCES official_events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  marked_by UUID REFERENCES users(id),
  marked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (event_id, user_id)
);

-- Kapatılan dönemler ve hesap özetleri.
CREATE TABLE IF NOT EXISTS payout_periods(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_key VARCHAR(16) NOT NULL UNIQUE,
  cycle VARCHAR(10) NOT NULL CHECK (cycle IN ('weekly','monthly')),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  closed_by UUID REFERENCES users(id),
  closed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  config JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS host_statements(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id UUID NOT NULL REFERENCES payout_periods(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  agency_id UUID REFERENCES agencies(id) ON DELETE SET NULL,
  seconds BIGINT NOT NULL DEFAULT 0,
  diamonds BIGINT NOT NULL DEFAULT 0,
  tier_level INT,
  base_salary_cents BIGINT NOT NULL DEFAULT 0,
  penalty_applied BOOLEAN NOT NULL DEFAULT FALSE,
  salary_cents BIGINT NOT NULL DEFAULT 0,
  events_ok BOOLEAN NOT NULL DEFAULT TRUE,
  status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','void')),
  paid_at TIMESTAMPTZ,
  paid_by UUID REFERENCES users(id),
  UNIQUE (period_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_host_statements_user ON host_statements(user_id);

CREATE TABLE IF NOT EXISTS agency_statements(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id UUID NOT NULL REFERENCES payout_periods(id) ON DELETE CASCADE,
  agency_id UUID NOT NULL REFERENCES agencies(id),
  team_diamonds BIGINT NOT NULL DEFAULT 0,
  host_count INT NOT NULL DEFAULT 0,
  commission_bps INT NOT NULL DEFAULT 0,
  commission_diamonds BIGINT NOT NULL DEFAULT 0,
  status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','void')),
  paid_at TIMESTAMPTZ,
  paid_by UUID REFERENCES users(id),
  UNIQUE (period_id, agency_id)
);
CREATE INDEX IF NOT EXISTS idx_agency_statements_agency ON agency_statements(agency_id);
