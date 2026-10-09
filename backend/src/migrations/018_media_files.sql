-- 018: Yönetici yüklemeleri (hediye animasyonu, çerçeve) veritabanında saklanır; sunucu yeniden başlasa da kaybolmaz.
CREATE TABLE IF NOT EXISTS media_files(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind VARCHAR(20) NOT NULL,
  mime VARCHAR(60) NOT NULL,
  ext VARCHAR(8) NOT NULL,
  size_bytes INT NOT NULL,
  data BYTEA NOT NULL,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
