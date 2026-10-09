-- 30 mikrofonlu oda modu (Yoho düzeni: 6 x 5)
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_seat_count_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_seat_count_check CHECK (seat_count IN (2, 4, 5, 6, 8, 9, 12, 15, 20, 30));
ALTER TABLE room_profiles DROP CONSTRAINT IF EXISTS room_profiles_seat_count_check;
ALTER TABLE room_profiles ADD CONSTRAINT room_profiles_seat_count_check CHECK (seat_count IN (2, 4, 5, 6, 8, 9, 12, 15, 20, 30));

-- "Mikrofonda olmak için istekte bulunmanız gerekiyor" modu: açıkken kullanıcılar mikrofona ancak yetkilinin davetiyle çıkar.
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS mic_request BOOLEAN NOT NULL DEFAULT FALSE;
