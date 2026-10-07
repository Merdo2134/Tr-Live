-- 005: müzik çalar, oda sohbeti, özel mesaj, engelleme/şikâyet, oda ayarları, güvenlik duvarı kayıtları

-- ---------- Oda ayarları ----------
ALTER TABLE rooms
  ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS chat_enabled BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE room_members ADD COLUMN IF NOT EXISTS chat_muted_until TIMESTAMPTZ;

-- ---------- Müzik ----------
CREATE TABLE IF NOT EXISTS music_tracks(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(120) NOT NULL,
  artist VARCHAR(120),
  url TEXT NOT NULL,
  cover_url TEXT,
  duration_ms INT NOT NULL CHECK (duration_ms > 0 AND duration_ms <= 7200000),
  license_note TEXT NOT NULL,            -- telif/lisans kaydı zorunlu
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_music_tracks_active ON music_tracks(is_active, title);

CREATE TABLE IF NOT EXISTS room_music(
  room_id UUID PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  track_id UUID REFERENCES music_tracks(id),
  status VARCHAR(10) NOT NULL DEFAULT 'stopped' CHECK (status IN ('playing','paused','stopped')),
  position_ms INT NOT NULL DEFAULT 0 CHECK (position_ms >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  controlled_by UUID REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS room_music_queue(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  track_id UUID NOT NULL REFERENCES music_tracks(id),
  added_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_room_music_queue_room ON room_music_queue(room_id, created_at);

-- ---------- Oda sohbeti ----------
CREATE TABLE IF NOT EXISTS room_messages(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  body VARCHAR(300) NOT NULL,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_room_messages_room ON room_messages(room_id, created_at DESC);

-- ---------- Özel mesaj, gizlilik, engelleme ----------
ALTER TABLE users ADD COLUMN IF NOT EXISTS who_can_dm VARCHAR(10) NOT NULL DEFAULT 'everyone';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_who_can_dm_valid') THEN
    ALTER TABLE users ADD CONSTRAINT users_who_can_dm_valid CHECK (who_can_dm IN ('everyone','following','nobody'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS direct_messages(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES users(id),
  receiver_id UUID NOT NULL REFERENCES users(id),
  body VARCHAR(1000) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  CHECK (sender_id <> receiver_id)
);
CREATE INDEX IF NOT EXISTS idx_dm_pair ON direct_messages(sender_id, receiver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dm_receiver ON direct_messages(receiver_id, sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dm_unread ON direct_messages(receiver_id) WHERE read_at IS NULL;

CREATE TABLE IF NOT EXISTS user_blocks(
  blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id);

CREATE TABLE IF NOT EXISTS reports(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES users(id),
  kind VARCHAR(20) NOT NULL CHECK (kind IN ('user','room','room_message','dm')),
  target_user_id UUID REFERENCES users(id),
  room_id UUID REFERENCES rooms(id),
  message_id UUID,
  reason VARCHAR(30) NOT NULL,
  details VARCHAR(500),
  status VARCHAR(12) NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','dismissed')),
  resolved_by UUID REFERENCES users(id),
  resolved_note VARCHAR(300),
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status, created_at DESC);

-- ---------- Güvenlik duvarı ----------
CREATE TABLE IF NOT EXISTS firewall_blocks(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ip INET NOT NULL UNIQUE,
  reason VARCHAR(200),
  expires_at TIMESTAMPTZ,                 -- NULL = süresiz
  created_by UUID REFERENCES users(id),   -- NULL = otomatik
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS security_events(
  id BIGSERIAL PRIMARY KEY,
  event_type VARCHAR(40) NOT NULL,
  ip INET,
  user_id UUID,
  detail JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_security_events_time ON security_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_security_events_type ON security_events(event_type, created_at DESC);
