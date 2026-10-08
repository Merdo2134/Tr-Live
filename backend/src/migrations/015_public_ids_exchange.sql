-- 015: Kullanıcı kimliği (public_id), kalıcı oda numarası (room_number), WIP 5 kırmızı isim.

-- Her kullanıcıya 8 haneli benzersiz görünür kimlik. Yönetici hesabında kimlik yerine "admin" yazar.
ALTER TABLE users ADD COLUMN IF NOT EXISTS public_id VARCHAR(20);
DO $$
DECLARE r RECORD; cand TEXT;
BEGIN
  FOR r IN SELECT id, username, system_role FROM users WHERE public_id IS NULL LOOP
    IF r.system_role = 'admin' THEN
      cand := r.username;
    ELSE
      LOOP
        cand := (10000000 + floor(random() * 90000000))::bigint::text;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM users WHERE public_id = cand);
      END LOOP;
    END IF;
    UPDATE users SET public_id = cand WHERE id = r.id;
  END LOOP;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_public_id ON users(public_id);

-- Her kalıcı odaya (sesli/görüntülü) değişmeyen 7 haneli oda numarası; açılan her oda bunu taşır.
ALTER TABLE room_profiles ADD COLUMN IF NOT EXISTS room_number VARCHAR(12);
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS room_number VARCHAR(12);
DO $$
DECLARE r RECORD; cand TEXT;
BEGIN
  FOR r IN SELECT owner_id, room_type FROM room_profiles WHERE room_number IS NULL LOOP
    LOOP
      cand := (1000000 + floor(random() * 9000000))::bigint::text;
      EXIT WHEN NOT EXISTS (SELECT 1 FROM room_profiles WHERE room_number = cand);
    END LOOP;
    UPDATE room_profiles SET room_number = cand WHERE owner_id = r.owner_id AND room_type = r.room_type;
  END LOOP;
  -- Profili olmayan eski odalara da numara verilir.
  UPDATE rooms o SET room_number = p.room_number FROM room_profiles p
   WHERE o.room_number IS NULL AND p.owner_id = o.owner_id AND p.room_type = o.room_type;
  FOR r IN SELECT id FROM rooms WHERE room_number IS NULL LOOP
    LOOP
      cand := (1000000 + floor(random() * 9000000))::bigint::text;
      EXIT WHEN NOT EXISTS (SELECT 1 FROM room_profiles WHERE room_number = cand) AND NOT EXISTS (SELECT 1 FROM rooms WHERE room_number = cand);
    END LOOP;
    UPDATE rooms SET room_number = cand WHERE id = r.id;
  END LOOP;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS idx_room_profiles_number ON room_profiles(room_number);
CREATE INDEX IF NOT EXISTS idx_rooms_number ON rooms(room_number);

-- WIP 5 renkli ismi kırmızı.
UPDATE wip_tiers SET features = features || '{"nameColor":"#FF2B2B"}'::jsonb WHERE level = 5;

-- Hesap yönetici yapıldığında kimlik otomatik olarak "admin" (doluysa kullanıcı adı) olur.
CREATE OR REPLACE FUNCTION trg_admin_public_id() RETURNS trigger AS $$
BEGIN
  IF NEW.system_role = 'admin' AND NEW.public_id IS DISTINCT FROM 'admin' AND NEW.public_id IS DISTINCT FROM NEW.username THEN
    IF NOT EXISTS (SELECT 1 FROM users WHERE public_id = 'admin' AND id <> NEW.id) THEN NEW.public_id := 'admin';
    ELSE NEW.public_id := NEW.username; END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS users_admin_public_id ON users;
CREATE TRIGGER users_admin_public_id BEFORE INSERT OR UPDATE OF system_role ON users
  FOR EACH ROW EXECUTE FUNCTION trg_admin_public_id();
-- Mevcut yöneticiler.
UPDATE users SET system_role = system_role WHERE system_role = 'admin';
