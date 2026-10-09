-- Güvenlik ve performans sağlamlaştırma (v2.34)

-- Yüklenen görsellerin sahibi: gönderilerde yalnızca kendi yüklediğin görsel kullanılabilir,
-- gönderi silinince yalnızca sahibinin dosyası silinir (başkasının avatarı/kapakları silinemez).
CREATE TABLE IF NOT EXISTS upload_owners (
  url TEXT PRIMARY KEY,
  owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sohbet susturması odadan çıkıp girince kaybolmasın.
CREATE TABLE IF NOT EXISTS room_mutes (
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  until TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (room_id, user_id)
);

-- Sıralama tabloları (son 24 saat / hafta) tüm hediye kayıtlarını taramasın.
CREATE INDEX IF NOT EXISTS idx_gift_tx_created ON gift_transactions(created_at DESC);
