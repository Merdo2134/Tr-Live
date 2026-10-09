-- Arkadaşlık (karşılıklı onay) ve profil rozetleri için "en son baktığı an" sütunları.
CREATE TABLE IF NOT EXISTS friend_requests(
  requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  responded_at TIMESTAMPTZ,
  PRIMARY KEY(requester_id, target_id),
  CHECK (requester_id <> target_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_requests_target ON friend_requests(target_id, status);
CREATE INDEX IF NOT EXISTS idx_friend_requests_requester ON friend_requests(requester_id, status);

ALTER TABLE users ADD COLUMN IF NOT EXISTS visitors_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE users ADD COLUMN IF NOT EXISTS followers_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
