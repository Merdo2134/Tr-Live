-- WIP üyeliğinin verdiği görünüm öğelerini kullanıcı tek tek kapatabilir (Görünüm sayfası).
-- Anahtarlar: frame, chat_bubble, badge, entrance_effect, vehicle → true ise o öğe gösterilmez.
ALTER TABLE users ADD COLUMN IF NOT EXISTS wip_hidden JSONB NOT NULL DEFAULT '{}'::jsonb;
