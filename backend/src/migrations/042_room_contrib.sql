-- v2.54.0: Oda katkı listesi (Toplam) aynı sahibin aynı tür odalarının hepsinden hesaplanır.
CREATE INDEX IF NOT EXISTS idx_rooms_owner_type ON rooms(owner_id, room_type);
