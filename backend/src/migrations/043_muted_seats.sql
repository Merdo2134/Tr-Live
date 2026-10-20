-- v2.55.1: Koltuk susturma. Yetkili bir koltuğu susturunca oturan kişi koltukta kalır ama konuşamaz;
-- koltukta kırmızı "susturuldu" işareti görünür (boş koltukta da). Oda kapanınca sıfırlanır.
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS muted_seats INT[] NOT NULL DEFAULT '{}';
