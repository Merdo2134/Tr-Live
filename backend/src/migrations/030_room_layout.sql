-- v2.40.0: "Yayın başlat" ekranı. Görüntülü odanın iki düzeni olur:
--   grid = Çoklu yayın (4/6/9/12 kişilik görüntü ızgarası)
--   live = Canlı yayın (yayıncı tam ekran, sağda küçük konuk pencereleri)
-- Sesli odalarda her zaman 'grid' kalır (koltuk düzeni seat_count ile belirlenir). Tekrar çalıştırılabilir.
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS layout VARCHAR(8) NOT NULL DEFAULT 'grid';
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS layout VARCHAR(8) NOT NULL DEFAULT 'grid';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rooms_layout_check') THEN
    ALTER TABLE rooms ADD CONSTRAINT rooms_layout_check CHECK (layout IN ('grid', 'live'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'room_profiles_layout_check') THEN
    ALTER TABLE room_profiles ADD CONSTRAINT room_profiles_layout_check CHECK (layout IN ('grid', 'live'));
  END IF;
END $$;
