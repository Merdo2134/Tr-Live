-- Mağazaya "Oda Kartı" kategorisi (oda sahibinin takılı kartı, oda bilgisi kartının arka planı olur).
ALTER TABLE store_items DROP CONSTRAINT IF EXISTS store_items_category_check;
ALTER TABLE store_items ADD CONSTRAINT store_items_category_check
  CHECK (category IN ('frame','chat_bubble','entrance_effect','mini_card','mic_wave','vehicle','badge','room_card'));
