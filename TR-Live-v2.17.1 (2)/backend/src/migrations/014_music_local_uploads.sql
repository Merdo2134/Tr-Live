-- 014: Kullanıcının telefonundan odaya çaldığı geçici parçalar.
-- is_temp parçalar ortak kütüphanede görünmez; yalnızca yüklendiği odada çalınabilir ve süresi dolunca silinir.
ALTER TABLE music_tracks
  ADD COLUMN IF NOT EXISTS is_temp BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS owner_room_id UUID REFERENCES rooms(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS size_bytes INT;
CREATE INDEX IF NOT EXISTS idx_music_tracks_temp ON music_tracks(is_temp, expires_at) WHERE is_temp;
