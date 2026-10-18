-- v2.52.0: İlişki Duvarı ve Koruyucu.
--  * İlişki türleri: CP (tek), En İyi Arkadaş ('friend', birden çok), Kanka (birden çok). Davet Coin ile gönderilir;
--    24 saat içinde kabul edilmezse (ya da reddedilir / geri çekilirse) Coin iade edilir.
--  * Koruyucu: bir kullanıcı Coin ile başka birinin koruyucusu olur; o kişiye gönderdiği hediyeler (1 Coin = 1 puan)
--    koruyucu puanı olur. Hediye gönderilmeyen haftanın ardından puan düşer, sıfırlanınca koruyuculuk biter.
-- Tekrar çalıştırılabilir.
ALTER TABLE cp_pairs DROP CONSTRAINT IF EXISTS cp_pairs_relation_check;
ALTER TABLE cp_pairs ADD CONSTRAINT cp_pairs_relation_check CHECK (relation IN ('none', 'friend', 'cp', 'kanka'));
ALTER TABLE cp_pairs DROP CONSTRAINT IF EXISTS cp_pairs_request_kind_check;
ALTER TABLE cp_pairs ADD CONSTRAINT cp_pairs_request_kind_check CHECK (request_kind IN ('friend', 'cp', 'kanka'));
-- Davet için alınan (iade edilecek) Coin.
ALTER TABLE cp_pairs ADD COLUMN IF NOT EXISTS request_cost BIGINT NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_cp_pairs_rel_a ON cp_pairs(user_a, relation) WHERE relation <> 'none';
CREATE INDEX IF NOT EXISTS idx_cp_pairs_rel_b ON cp_pairs(user_b, relation) WHERE relation <> 'none';

-- Koruyucu açık mı (kapalıysa kimse koruyucu olamaz, koruyucular sıralamalarda görünmez).
ALTER TABLE users ADD COLUMN IF NOT EXISTS guardian_enabled BOOLEAN NOT NULL DEFAULT TRUE;
-- Profilde gösterilecek koruyucu (profil sahibi seçer; boşsa en yüksek puanlı).
ALTER TABLE users ADD COLUMN IF NOT EXISTS guardian_shown_id UUID REFERENCES users(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS guardians (
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,     -- korunan kişi
  guardian_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- koruyucu
  points BIGINT NOT NULL DEFAULT 0,
  last_gift_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, guardian_id),
  CHECK (owner_id <> guardian_id)
);
CREATE INDEX IF NOT EXISTS idx_guardians_owner_points ON guardians(owner_id, points DESC);
CREATE INDEX IF NOT EXISTS idx_guardians_guardian ON guardians(guardian_id);

-- Haftalık puan düşüşünün hangi hafta için yapıldığı (her hafta bir kez).
CREATE TABLE IF NOT EXISTS guardian_decay_runs (
  week_start TIMESTAMPTZ PRIMARY KEY,
  done_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Özellik eklenmeden önceki haftalar düşüş yapılmış sayılır.
INSERT INTO guardian_decay_runs(week_start)
VALUES ((date_trunc('week', NOW() AT TIME ZONE 'Europe/Istanbul')) AT TIME ZONE 'Europe/Istanbul')
ON CONFLICT (week_start) DO NOTHING;
