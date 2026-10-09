-- Rozet kategorisi ve "mağazada satılmasın, yalnızca yönetici versin" seçeneği.
ALTER TABLE store_items DROP CONSTRAINT IF EXISTS store_items_category_check;
ALTER TABLE store_items ADD CONSTRAINT store_items_category_check
  CHECK (category IN ('frame','chat_bubble','entrance_effect','mini_card','mic_wave','vehicle','badge'));
ALTER TABLE store_items ADD COLUMN IF NOT EXISTS for_sale BOOLEAN NOT NULL DEFAULT TRUE;
