-- 008: favori yayıncılar, son girilen odalar, mikrofon sırası
CREATE TABLE IF NOT EXISTS favorite_hosts(
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  host_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id, host_id),
  CHECK (user_id <> host_id)
);
CREATE TABLE IF NOT EXISTS recent_rooms(
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  host_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  room_name VARCHAR(120),
  room_type VARCHAR(20),
  visited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id, host_id)
);
CREATE INDEX IF NOT EXISTS idx_recent_rooms_user ON recent_rooms(user_id, visited_at DESC);
CREATE TABLE IF NOT EXISTS room_mic_queue(
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(room_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_room_mic_queue_order ON room_mic_queue(room_id, created_at);
