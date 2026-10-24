-- Uygulamayla gelen hazır hediye / çerçeve paketleri: her öğe bir kez eklenir (yönetici silerse geri gelmez).
CREATE TABLE IF NOT EXISTS asset_seeds(
  key VARCHAR(80) PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
