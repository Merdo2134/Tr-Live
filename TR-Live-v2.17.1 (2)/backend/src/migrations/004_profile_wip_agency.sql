-- 004: bütünlük kısıtları, zengin profil, 5 kademeli WIP, ajans/yayıncı sistemi

-- ---------- Kullanıcı profili ----------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS cover_url TEXT,
  ADD COLUMN IF NOT EXISTS gender VARCHAR(10),
  ADD COLUMN IF NOT EXISTS birth_date DATE,
  ADD COLUMN IF NOT EXISTS country VARCHAR(60),
  ADD COLUMN IF NOT EXISTS city VARCHAR(60),
  ADD COLUMN IF NOT EXISTS token_version INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_lower ON users(lower(username));

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_balances_nonneg') THEN
    ALTER TABLE users ADD CONSTRAINT users_balances_nonneg CHECK (coins >= 0 AND diamonds >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_gender_valid') THEN
    ALTER TABLE users ADD CONSTRAINT users_gender_valid CHECK (gender IS NULL OR gender IN ('male','female','other'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_status_valid') THEN
    ALTER TABLE users ADD CONSTRAINT users_status_valid CHECK (account_status IN ('active','banned','deleted'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_role_valid') THEN
    ALTER TABLE users ADD CONSTRAINT users_role_valid CHECK (system_role IN ('user','support','admin'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dealer_balance_nonneg') THEN
    ALTER TABLE dealer_accounts ADD CONSTRAINT dealer_balance_nonneg CHECK (coin_balance >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'room_members_role_valid') THEN
    ALTER TABLE room_members ADD CONSTRAINT room_members_role_valid CHECK (role IN ('user','moderator','cohost','owner'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS follows(
  follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followed_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(follower_id, followed_id),
  CHECK (follower_id <> followed_id)
);
CREATE INDEX IF NOT EXISTS idx_follows_followed ON follows(followed_id, created_at DESC);

CREATE TABLE IF NOT EXISTS profile_visitors(
  profile_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  visitor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  visit_count INT NOT NULL DEFAULT 1,
  last_visited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(profile_user_id, visitor_id),
  CHECK (profile_user_id <> visitor_id)
);
CREATE INDEX IF NOT EXISTS idx_profile_visitors_recent ON profile_visitors(profile_user_id, last_visited_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_user_created ON wallet_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_room_members_user ON room_members(user_id);
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;

-- ---------- WIP: 5 kademe ----------
CREATE TABLE IF NOT EXISTS wip_tiers(
  level INT PRIMARY KEY CHECK (level BETWEEN 1 AND 5),
  name VARCHAR(60) NOT NULL,
  features JSONB NOT NULL DEFAULT '{}'::jsonb
);

INSERT INTO wip_tiers(level, name, features) VALUES
  (1, 'WIP 1 · Bronz',  '{"nameColor":"#CD7F32","badge":"wip_1","maxRooms":1,"viewVisitors":false,"kickImmunity":false,"profileEffect":false}'),
  (2, 'WIP 2 · Gümüş',  '{"nameColor":"#C0C0C0","badge":"wip_2","maxRooms":2,"viewVisitors":true,"kickImmunity":false,"profileEffect":false}'),
  (3, 'WIP 3 · Altın',  '{"nameColor":"#FFD700","badge":"wip_3","maxRooms":2,"viewVisitors":true,"kickImmunity":true,"profileEffect":false}'),
  (4, 'WIP 4 · Platin', '{"nameColor":"#E5E4E2","badge":"wip_4","maxRooms":3,"viewVisitors":true,"kickImmunity":true,"profileEffect":true}'),
  (5, 'WIP 5 · Elmas',  '{"nameColor":"#B9F2FF","badge":"wip_5","maxRooms":5,"viewVisitors":true,"kickImmunity":true,"profileEffect":true}')
ON CONFLICT (level) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_wip_level_valid') THEN
    ALTER TABLE user_wip ADD CONSTRAINT user_wip_level_valid CHECK (level BETWEEN 1 AND 5);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'wip_plans_level_valid') THEN
    ALTER TABLE wip_plans ADD CONSTRAINT wip_plans_level_valid CHECK (level BETWEEN 1 AND 5 AND duration_days > 0 AND price_coins >= 0);
  END IF;
END $$;

INSERT INTO wip_plans(name, level, duration_days, price_coins)
SELECT v.name, v.level, 30, v.price
FROM (VALUES
  ('WIP 1 · 30 gün', 1, 5000::bigint),
  ('WIP 2 · 30 gün', 2, 15000::bigint),
  ('WIP 3 · 30 gün', 3, 40000::bigint),
  ('WIP 4 · 30 gün', 4, 100000::bigint),
  ('WIP 5 · 30 gün', 5, 250000::bigint)
) AS v(name, level, price)
WHERE NOT EXISTS (SELECT 1 FROM wip_plans p WHERE p.level = v.level AND p.duration_days = 30);

-- ---------- Aile ----------
ALTER TABLE families ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE families DROP CONSTRAINT IF EXISTS families_name_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_families_name_active ON families(lower(name)) WHERE is_active = TRUE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'family_members_role_valid') THEN
    ALTER TABLE family_members ADD CONSTRAINT family_members_role_valid CHECK (role IN ('owner','admin','member'));
  END IF;
END $$;

-- ---------- Ajans ve yayıncı ----------
CREATE TABLE IF NOT EXISTS agencies(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(80) NOT NULL,
  owner_id UUID NOT NULL REFERENCES users(id),
  logo_url TEXT,
  description TEXT,
  commission_bps INT NOT NULL DEFAULT 0 CHECK (commission_bps BETWEEN 0 AND 10000),
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','suspended','rejected')),
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_agencies_name_lower ON agencies(lower(name)) WHERE status <> 'rejected';
CREATE UNIQUE INDEX IF NOT EXISTS idx_agencies_owner ON agencies(owner_id) WHERE status <> 'rejected';

CREATE TABLE IF NOT EXISTS broadcasters(
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  agency_id UUID REFERENCES agencies(id) ON DELETE SET NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','suspended')),
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  joined_agency_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_broadcasters_agency ON broadcasters(agency_id);

CREATE TABLE IF NOT EXISTS agency_requests(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id UUID NOT NULL REFERENCES agencies(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  direction VARCHAR(10) NOT NULL CHECK (direction IN ('invite','apply')),
  status VARCHAR(12) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  responded_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_agency_requests_one_pending ON agency_requests(agency_id, user_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_agency_requests_user ON agency_requests(user_id, status);

CREATE TABLE IF NOT EXISTS agency_commissions(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id UUID NOT NULL REFERENCES agencies(id),
  broadcaster_id UUID NOT NULL REFERENCES users(id),
  gift_transaction_id UUID REFERENCES gift_transactions(id),
  diamond_amount BIGINT NOT NULL CHECK (diamond_amount > 0),
  period CHAR(7) NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'accrued' CHECK (status IN ('accrued','paid')),
  paid_at TIMESTAMPTZ,
  paid_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_agency_commissions_lookup ON agency_commissions(agency_id, period, status);
CREATE INDEX IF NOT EXISTS idx_agency_commissions_broadcaster ON agency_commissions(broadcaster_id, period);

CREATE TABLE IF NOT EXISTS broadcast_sessions(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  room_id UUID REFERENCES rooms(id),
  agency_id UUID REFERENCES agencies(id) ON DELETE SET NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_broadcast_sessions_user ON broadcast_sessions(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_broadcast_sessions_open ON broadcast_sessions(room_id) WHERE ended_at IS NULL;
