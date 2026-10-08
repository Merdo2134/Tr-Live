-- 016: Günlük görevler (XP, 7 günlük seri) ve Şanslı Çanta.
ALTER TABLE users ADD COLUMN IF NOT EXISTS xp BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS daily_progress(
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  task_key VARCHAR(30) NOT NULL,
  count INT NOT NULL DEFAULT 0,
  done BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (user_id, day, task_key)
);
CREATE TABLE IF NOT EXISTS daily_streak(
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  streak INT NOT NULL DEFAULT 0,
  last_day DATE
);

CREATE TABLE IF NOT EXISTS lucky_bags(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id),
  kind VARCHAR(10) NOT NULL CHECK (kind IN ('normal','super')),
  tier VARCHAR(10) NOT NULL,
  total_coins BIGINT NOT NULL CHECK (total_coins > 0),
  slots INT NOT NULL CHECK (slots > 0),
  amounts BIGINT[] NOT NULL,
  claimed_count INT NOT NULL DEFAULT 0,
  note VARCHAR(100),
  status VARCHAR(10) NOT NULL DEFAULT 'open' CHECK (status IN ('open','done','expired')),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_lucky_open ON lucky_bags(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_lucky_room ON lucky_bags(room_id, status);
CREATE TABLE IF NOT EXISTS lucky_bag_claims(
  bag_id UUID NOT NULL REFERENCES lucky_bags(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  amount BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (bag_id, user_id)
);
