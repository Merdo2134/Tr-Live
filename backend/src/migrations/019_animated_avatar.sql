-- 019: WIP 5 özelliği — hareketli profil fotoğrafı (gif / animasyonlu webp).
UPDATE wip_tiers SET features = features || jsonb_build_object('animatedAvatar', level >= 5);
