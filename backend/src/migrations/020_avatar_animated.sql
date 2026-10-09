-- 020: Hareketli profil fotoğrafı WIP 5 bitince eski sabit fotoğrafa döner.
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_animated BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS static_avatar_url TEXT;
