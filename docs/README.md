# TR Live — Dokümanlar

Bu klasör uygulamanın "önce doküman" kaynağıdır. İki tür belge var:

| Belge | Ne anlatır | Nasıl güncellenir |
|---|---|---|
| [MIMARI.md](MIMARI.md) | Sistem bileşenleri, istek akışı, gerçek zamanlı katman, dosya yapısı | Elle |
| [VERITABANI.md](VERITABANI.md) | Ücretsiz veritabanı seçimi, Neon → Aiven geçişi, veritabanı ayarları | Elle |
| [EKONOMI.md](EKONOMI.md) | Coin / Elmas akışı, hediye, bozdurma, bayi, ajans maaşı, şanslı çanta, şanslı hediye, WIP kademeleri | Elle |
| [YETKILER.md](YETKILER.md) | Rol ve yetki tablosu (sistem, oda, aile, ajans, bayi) | Elle |
| [GUVENLIK.md](GUVENLIK.md) | Mevcut güvenlik katmanları ve açık kalanlar | Elle |
| [TEST_PLANI.md](TEST_PLANI.md) | Otomatik testler + cihazda elle kontrol listesi | Elle |
| [YOL_HARITASI.md](YOL_HARITASI.md) | Eksikler, öncelik sırası, ek iyileştirme fikirleri | Elle |
| [generated/database.md](generated/database.md) | Tüm tablolar, sütunlar, kısıtlar, indeksler | **Otomatik** |
| [generated/api.md](generated/api.md) | Tüm REST uçları, yetki ve hız sınırları | **Otomatik** |
| [generated/realtime.md](generated/realtime.md) | WebSocket olayları | **Otomatik** |

Otomatik belgeler koddan üretilir; elle düzenlenmez:

```bash
cd backend && node scripts/gen_docs.mjs
```

Eski notlar: [../docs.md](../docs.md) (API özeti), [COMPARISON.md](COMPARISON.md) (Yoho/Bigo karşılaştırması), [GITHUB.md](GITHUB.md), [figma_notlari.md](figma_notlari.md).
