-- Hediye nerede oynar: 'full' tam ekran (varsayılan), 'seat' alıcının mikindeki dairede (yumurta, domates).
ALTER TABLE gifts ADD COLUMN IF NOT EXISTS play_mode VARCHAR(10) NOT NULL DEFAULT 'full';
ALTER TABLE gifts DROP CONSTRAINT IF EXISTS gifts_play_mode_check;
ALTER TABLE gifts ADD CONSTRAINT gifts_play_mode_check CHECK (play_mode IN ('full', 'seat'));
-- Hazır paket öğelerinin hangi sürümü kurulu (hediye / çerçeve). Yeni sürüm gelince yalnızca dosyalar yenilenir.
CREATE TABLE IF NOT EXISTS asset_items(
  key VARCHAR(80) PRIMARY KEY,
  kind VARCHAR(10) NOT NULL,
  ref_id UUID,
  version INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
