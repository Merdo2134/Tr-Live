-- Çoklu yayın düzenleri: 4 ve 6 koltuk eklendi.
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_seat_count_check;
ALTER TABLE rooms ADD CONSTRAINT rooms_seat_count_check CHECK (seat_count IN (2, 4, 5, 6, 8, 9, 12, 15, 20));
