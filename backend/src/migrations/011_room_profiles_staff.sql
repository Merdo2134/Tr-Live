-- Kalıcı oda: kullanıcı odasını bir kez kurar (ad, etiketler, koltuk düzeni, tema); "oda aç" bu bilgilerle tek adımda açar.
-- Her kullanıcının sesli ve görüntülü için ayrı birer kalıcı odası olabilir.
CREATE TABLE IF NOT EXISTS room_profiles (
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  room_type VARCHAR(20) NOT NULL CHECK (room_type IN ('audio', 'video')),
  name VARCHAR(120) NOT NULL,
  tags TEXT[] NOT NULL DEFAULT '{}',
  seat_count INT NOT NULL DEFAULT 8 CHECK (seat_count IN (2, 4, 5, 6, 8, 9, 12, 15, 20)),
  theme VARCHAR(20) NOT NULL DEFAULT 'default',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, room_type)
);

-- Oda yöneticileri (yardımcı sahip / moderatör) oda kapanıp yeniden açılınca korunur.
CREATE TABLE IF NOT EXISTS room_staff (
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  room_type VARCHAR(20) NOT NULL CHECK (room_type IN ('audio', 'video')),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL CHECK (role IN ('cohost', 'moderator')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, room_type, user_id)
);

-- Şu an açık olan odalardan profil üret (sahip başına tür başına en yeni oda).
INSERT INTO room_profiles (owner_id, room_type, name, tags, seat_count, theme)
SELECT DISTINCT ON (owner_id, room_type) owner_id, room_type, name, COALESCE(tags, '{}'), seat_count, theme
FROM rooms WHERE is_active = TRUE AND room_type IN ('audio', 'video')
ORDER BY owner_id, room_type, created_at DESC
ON CONFLICT DO NOTHING;
