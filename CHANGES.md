## v2.57.0 — Müzik çalar, bildirimler, aile sohbeti (2. bölüm)
- Müzik çalar baştan: "Müzik" listesi (N PARÇA, arama, düzenle), "Telefondan Ekle" (telefondaki ses dosyaları otomatik
  taranır, Ekle / Eklendi, Tümünü ekle), "Şimdi Çalıyor" (dönen plak, ilerleme, önceki / oynat / sonraki, Karıştır /
  Tümü / Tek, ses düzeyi, kapatma). Listeden dokunulan şarkı odada çalar, bitince sıradaki kendiliğinden çalar.
  Odada alt çubuk; aşağı kaydırınca / küçültünce dönen plak balonu.
- Mesajlar: "Bildirimler" kartı (beğeni, yorum, takipçi, arkadaşlık, aile, arkadaş oda açtı) ve okunmamış rozeti.
  Anlar'da beğeni ve yorum bildirim olarak düşer.
- Aile Sohbeti: Mesajlar'da aile üyelerinin kendi arasında yazıştığı sohbet. Aile başkanı "Üyelere Bildirim / Davet"
  ile tüm üyelere bildirim gönderir (isterse açık odasına davet).
- Etkinlik Promosyonu duyuruları parlak çerçeveli, görselli kart; bağlantı "Hemen katıl" ile açılır.
- Çoklu hediye: mikten mike giden hediye, adet kadar (en çok 7) art arda uçan simge, "xN" yazısı ve parıltıyla gider.
- Kulaklık: kablolu / Bluetooth kulaklık takılıyken ses medya modunda çalışır (uğultu ve kesilme olmasın);
  kulaklık çıkınca otomatik normal moda döner. Bluetooth'ta konuşurken telefonun kendi mikrofonu kullanılır.
- apk_build.yml: müzik dosyası tarama izni ve Android 10 dosya erişimi eklendi (elle yüklenmeli).

## v2.56.0 — Oda düzeni, yeni logo (1. bölüm)
- Oda sahibi çıksa da içeride yardımcı sahip / moderatör varsa oda kapanmaz; son yönetici de çıkınca kapanır.
  Sahip "Odayı kapat" ile her zaman kapatabilir.
- Arka planda başka uygulamaya geçince mikrofon artık kapanmıyor (başka uygulamanın ses açması arama sanılıyordu).
- Sistem duyurusu ve oda duyurusu odaya ilk girişte 12 sn görünür, sonra kalkar.
- Oda ayarları: Odayı temizle, Sohbet yasağı, Oda kilitleme, Oda gizleme, Ses ve efektler, Müzik, Mikrofon modu, Tema,
  Odayı paylaş, Odayı kapat. Oda sesi düğmesi alt çubukta (oyunlar ayarlardaki Ludo'da).
- Sohbet yazı alanı koyu ve yuvarlak; uçan yazı anahtarı, emoji, renkli gönder düğmesi, 3 satıra kadar.
- Ses ve efektler: bir görsel ya da ses kapatılınca o an oynayan da hemen durur.
- Yeni logo: giriş sayfası ve uygulama simgesi (apk_build.yml güncellendi, elle yüklenmeli).

## v2.55.5 — Balon yerine sabit bildirim
- Uygulamadan çıkınca ekranda balon çıkmaz. Odadayken üstte sabit "… odasındasınız · dönmek için dokun" bildirimi
  durur; dokununca odaya dönülür. Tek izin: bildirim izni (Android'in kendi penceresi, bir kez). Balon izni sorulmaz.

## v2.55.4 — Daha az izin sorusu
- Odaya girerken yalnızca bir kez "Diğer uygulamaların üzerinde göster" (odaya dönme balonu) izni sorulur.
  Bildirim, pil ve telefon izinleri artık sorulmaz. Mikrofon izni yalnızca mikrofona ilk çıkışta istenir.

## v2.55.3 — Arka planda odadan düşme
- Arka plan servisi artık arka plandayken kapatılıp yeniden açılmıyor (Android 12+ buna izin vermediği için servis
  kapalı kalıyor, telefon uygulamanın internetini kesiyordu). Servis odaya girerken mümkünse mikrofon türüyle açılır;
  gerekirse yalnızca uygulama ekrandayken yeniden kurulur. Uygulamaya dönünce servis kapanmışsa yeniden açılır.
- Pil kısıtlaması kalkana kadar günde en fazla bir kez hatırlatılır.

## v2.55.2 — Yönetim: giriş bilgileri
- Yönetim → kullanıcı → "Giriş bilgileri / şifre" (yalnızca yönetici): kullanıcı adı, telefon numarası ve yeni şifre
  verilebilir. Şifre gösterilmez; değişince kullanıcının tüm oturumları kapanır. İşlem kayda geçer.

## v2.55.1 — Koltuk susturma
- Yetkili (oda sahibi, yardımcı sahip, moderatör) bir konuşanı "Sustur" deyince kişi koltuktan inmez; mikrofonu
  kapanır ve açamaz. Koltukta pembe "susturuldu" işareti görünür. Boş koltuk da susturulabilir (koltuk menüsü).
  "Sesi Aç" ile geri açılır. Koltuktan indirmek için "Koltuk" düğmesi aynı kaldı.

## v2.55.0 — Ekran, arama, sıralama listeleri
- Uygulama açıkken ekran kendiliğinden kapanmaz; uygulama yalnızca dikey çalışır (yan çevirince dönmez).
- Telefon araması: Android'in kendi arama durumu okunur (ilk odaya girişte "telefon durumu" izni istenir). Arama
  gelince oda sesi, oda müziği, hediye / araç sesleri ve mikrofon kapanır; arama bitince açılır.
- "Oda sesini kapat" artık oda müziğini ve hediye / araç seslerini de susturur (odadan çıkınca açılır).
- Etkinlikler, Zirve Listesi, Katkı Listesi ve Koruyucu Sıralaması kimse olmasa da ilk 10 satırı gösterir.
- GitHub: apk_build.yml güncellendi (MainActivity, READ_PHONE_STATE izni, dikey ekran). Elle yüklenmeli.

## v2.54.1 — Etkinlik sayımı
- Alınan hediyeye göre yarışan etkinliklerde (Kral, Kraliçe, Yıldızlar-Yayıncı) kendine gönderilen hediye de sayılır.
- Destekçi sıralamasında (Yıldızlar-Destekçi) yalnızca başkasına gönderilen hediye sayılır.

## v2.54.0 — Koyu tema, şanslı çanta, katkı listesi
- Beyaz sayfalar uygulamanın koyu lacivert renklerine geçti: kullanıcı profili, aile sayfaları (liste, üyeler, istekler,
  bilgileri düzenle, seviyeler, Coins ödülü, kurallar), En İyi Arkadaş / Kanka listesi, koruyucu kuralları, Zirve Listesi üst çubuğu.
- Aile: "Üye gözünden bak" kaldırıldı; "Coins ödüllerini görmek için tıklayın" balonu günde bir kez (6 sn) görünür.
- İlişki Duvarı: ilişki yokken çerçevenin daralıp sola kayması ve başlığın taşması düzeltildi.
- Etkinlik sayfası açıkken sıralama 10 saniyede bir kendiliğinden yenilenir.
- Şanslı çanta: odadaki açma kartı küçük kare (ekranın ortasında). Gönderme penceresi Figma'daki pembe perdeli tasarım:
  Şanslı / Süper sekmeleri, kırmızı zarflar, sarı Gönder düğmesi, ? ile kurallar.
- Oda Katkı Listesi Figma tasarımına geçti (TOP1/2/3 taçlı çerçeveler, bayraklar, elmaslı tutar). "Toplam" ömür boyu:
  oda kapanıp yeniden açılınca sıfırlanmaz (aynı sahibin aynı tür odalarının tümü). "24 Saat" son 24 saat.

## v2.53.0 — Aile, Zirve Listesi, Etkinlik sayfaları ve Şanslı çanta (Figma tasarımı)
- Kendi profiline dokununca herkesin gördüğü beyaz profil sayfası açılır; düzenleme sağ üstteki kalemden.
  Kapak fotoğrafı kırpma oranı yeni profile göre (375x343).
- Aile:
  - Seviyeler Demir, Bronz, Gümüş, Altın, Elmas (üye sınırı 150/200/300/450/650, yönetici 5/8/14/23/35), seviyeye
    özel başlık arka planı ve rozetler; seviye sayfaları (Ayrıcalıklar) ve "Hızlı bir şekilde nasıl yükseltilir?".
  - Aile sayfası: çerçeveli logo, ad, aile ID, katkı çubuğu, aile bildirimi, üyeler (rol etiketleriyle), aile odaları,
    "Üye gözünden bak" (başkan), Coins ödülü düğmesi.
  - Katılım başvuru ile; yöneticiler "Yeni istek" / İstekler'den kabul eder. İstek Ayarları: en düşük zenginlik
    seviyesi. Bilgileri Düzenle: kapak resmi, aile ismi (12), aile bildirimi (100). Aileyi Dağıt / Aileden Ayrıl.
  - Katkı değeri (🔥): günlük giriş 20, yükleme 1 Coin = 1, gönderilen hediye 1 Coin = 1, alınan hediye 1 Elmas = 1.
    Üyelerin bu haftaki katkısı listede.
  - Coins ödülü: haftalık katkı 800K / 1M / 5M olunca 2300 / 4500 / 25K Coin (aile başkanı alır). Başkan indirimi:
    kişisel harcamanın seviyeye göre %1-3'ü birikir (en az 10K harcamadan sonra alınır).
  - Aile kuralları (soru-cevap) ve görev tablosu.
- Zirve Listesi: Yayıncı, Destekçi, Yükleme (yeni), Ajans, Aile, CP; Günlük / Haftalık / Aylık; her sekme kendi
  renginde, taçlı çerçeveli ilk 3 kürsü, tutarlar gizli (7****5), altta kendi sıran, Kurallar.
- Etkinlik sayfaları: Haftalık Kral ve Kraliçe, Haftalık Yıldızlar (Yayıncı / Destekçi ve 4 hediye), Haftanın Çifti;
  Figma görselleri, geri sayım, Bu Hafta / Geçen Hafta, sıralama, altta kendi sıran, Kural ve Ödül sayfası.
- Şanslı çanta: Figma'daki pembe perdeli kart; AÇ / geri sayım, "xTutar Tebrikler!", "Üzgünüm, bu şanslı çanta zaten
  açılmış..."; odadaki çanta simgesi kırmızı zarf.
- Notlar: mevcut ailelerin seviyesi yeni eşiklere (1M/6M/20M/60M) göre yeniden hesaplanır. Kendine hediye aile
  katkısına ve başkan indirimine sayılmaz. Başkan indirimi küçük harcamalarda da (kuruş kuruş) birikir.

## v2.52.0 — Profil, İlişki Duvarı ve Koruyucu (Figma tasarımı)
- Kullanıcı profili Figma'daki beyaz tasarıma geçti: tam genişlik kapak, çerçeveli avatar, sağda koruyucu rozeti,
  madalyalar, Profil / Başarılar / Paylaşım / İlişkiler sekmeleri, aile kartı, Top Destekçiler, seviye kartları.
- İlişkiler: CP (tek), En İyi Arkadaş ve Kanka (birden çok). Davet Coin ile (CP 2500, En İyi Arkadaş 1500, Kanka 1000);
  24 saat içinde kabul edilmezse, reddedilir ya da geri çekilirse Coin iade edilir. Seviye şartı kalktı.
- İlişki Duvarı (profil → İlişkiler): CP sahnesi, En İyi Arkadaş ve Kanka kartları, "Diğerleri" listesi (kendi
  listende düzenle ile çıkarma), CP İptali penceresi, ilişkisi olmayanlarda "İlişki Kur".
- Yakınlık penceresi: özel mesajdaki kalp ya da profildeki "İlişki Kur" ile açılır; 5 seviye kalbi, görevler ve
  "İlişki Türünü Seç" (CP / En İyi Arkadaş / Kanka) penceresi.
- Koruyucu: 3000 Coin ile bir kullanıcının koruyucusu olunur. O kişiye gönderilen hediyelerde 1 Coin = 1 koruyucu
  puanı. Hediye gönderilmeyen haftanın ardından Pazartesi 00:00'da puan düşer (250+ ise %20, altında 50), sıfırlanınca
  koruyuculuk biter; ilk hafta muaf. Koruyucular sayfası, Koruyucu Ol penceresi, kurallar, Koruyuculuğum (Koruyucum /
  Koruduğum; düzenle ile Seç / Kaldır / Sonlandır), "Koruyucu kabul et" ayarı. Profilde ve odadaki mini kartta
  seçilen (yoksa en yüksek puanlı) koruyucu görünür.
- Figma'daki süs görselleri (kanat, şato, çerçeve süsleri, madalyalar, simgeler) uygulamaya eklendi.
- Figma görsellerini indiren iş akışı (figma_assets.yml) eklendi.
- Test: gizli kullanıcının kendini de gizli görmesine göre eski birim testi güncellendi.

## v2.51.7 — Telefon araması ve hediye penceresi
- Telefon araması: zil çalınca ve görüşme sürerken oda sesi, oda müziği ve mikrofon artık kesin kapanır; arama bitince
  geri açılır. (Önceki yöntem ses odağı sinyaline dayanıyordu; oda sesi odağı kendisi aldığı için çoğu telefonda sinyal
  gelmiyordu. Artık telefonun ses modu doğrudan okunuyor.)
- Hediye penceresinin yüksekliği içeriğe göre hesaplanır: alttaki boşluk kalktı, pencere daha kısa ve aşağıda;
  hediye kutuları biraz küçüldü.

## v2.51.6 — Hediye penceresi düzeni
- Hediye penceresi sabit yükseklikte: kaymaz; hediyeye dokununca alt satır aşağı inmez, Coin / adet / Gönder satırı
  her zaman görünür.
- Üstteki kişi satırı (avatarlar) ve alttaki Coin satırı küçültüldü; hediye ızgarası kalan alana sığar.
- "Toplam … Coin" satırı yalnızca birden çok kişi / adet seçiliyken yer kaplar.

## v2.51.5 — Uçan yazı sohbetin üstünde
- Uçan yazı (ve "Hoş geldin" selamı) artık sohbet bölümünün en üstünde kayan yazı olarak geçer: tek şeritte,
  arka arkaya sırayla (biri bitince sıradaki). Yazı geçerken sohbet bir satır aşağı kayar, mesajların üstüne binmez.

## v2.51.4 — Çoklu hediye arka arkaya
- 10'lu hediyenin animasyonu artık iç içe girmez: 10 kez arka arkaya oynar, her tekrar bir önceki bitince hemen başlar.

## v2.51.3 — Çoklu hediye animasyonu
- 10'lu atılan hediyenin tam ekran animasyonu 10 kez oynar (en fazla 10): her tekrar bir öncekinin bitmesini
  beklemeden ~0,45 sn arayla başlar (üst üste); aynı anda en fazla 3 katman. Ses yalnızca ilkinde çalar.
- Ortadaki şerit ve üst (global) şerit bir kez geçer, adet "x10" olarak yazar. Aynı odada üst şerit, ortadaki
  şerit bitince yarım saniye sonra geçer.

## v2.51.2 — Hediye şeritleri sırayla
- Hediyenin atıldığı odada ortadaki oda şeridi ile üst (global) şerit artık aynı anda çıkmaz: önce ortadaki şerit
  geçer, o bitince 1 sn sonra üst şerit bir kez geçer. Diğer odalarda üst şerit hemen geçer.

## v2.51.1 — Gizli kullanıcı ve hayalet mod tutarlılığı
- **Gizli kullanıcı:** açıkken kişi odada, sohbette ve listelerde kendini de "Gizli Kullanıcı" olarak görür
  (başkalarının gördüğüyle aynı). Başkasının profiline girince **ziyaretçi listesine düşmez**.
- **Hayalet mod (SWIP):** açıkken oda başlığında kendine "👻 Hayalet" işareti çıkar (mikrofona çıkınca kalkar,
  çünkü mikrofondaki herkes görünür). Açarken mod gerçekten etkinse ya da SWIP üyeliği yoksa uyarı verilir.
- Profil sayfası artık hayalet modun gerçekten etkin olup olmadığını (ghostActive) bildirir.

## v2.51.0 — Otomatik bildirimler: arkadaşlık, takip, arkadaş oda açtı
- **Arkadaşlık isteği** gelince ve isteğin **kabul edilince**, biri **seni takip edince**, **arkadaşın oda açınca**
  telefona bildirim düşer (aynı arkadaştan oda bildirimi 30 dakikada en fazla bir kez).
- Bildirime dokununca: oda bildirimi → doğrudan odaya girer; istek / takip → kişinin profili açılır.
- Uygulama açıkken ya da arka planda çalışırken anında; tamamen kapalıysa uygulama açılınca gösterilir (son 3 gün).
- **Profil → Ayarlar → Bildirimler:** üç tür ayrı ayrı kapatılabilir. Gizli kullanıcı / hayalet modda bildirim gitmez.
- Yeni migration: `039_user_notifications.sql` (30 günden eski bildirimler otomatik silinir).

## v2.50.2 — Global hediye şeridi
- Global şerit artık bir kez görünür (gönderende iki kez çıkıyordu): her duyuruya kimlik verildi, aynı duyuru
  tekrar gelirse uygulama göstermez.
- Şerit düzeni: "Gönderen <ad>" / "Alıcı <ad>" alt alta, sağda hediyenin görseli ve adedi (x5).

## v2.50.1 — Sesli MP4 hediyeler sesli oynar
- Sesli MP4 hediye animasyonları ve giriş efektleri artık sesiyle birlikte oynar (animasyon oynatıcısı yalnızca
  görüntüyü çiziyordu; ses aynı dosyadan ayrıca çalınır). Sessiz dosyalarda değişiklik yok.
- **Efekt ve ses → "Hediye ve araç sesleri"** ile kapatılabilir; telefon araması sürerken çalmaz.

## v2.50.0 — Telefon aramasında oda sesi kapanır, ayrı ayrı efekt ayarları
- **Telefon araması:** arama (zil dahil) gelince odadakilerin sesi ve mikrofonun otomatik kapanır, arama bitince
  eski hâline döner (WhatsApp vb. aramalarda da). Oda müziği de durup devam eder.
- **Efekt ve ses** (oda araçları): Hediye görsel efekti, Araç ve giriş efektleri (SWIP araçları gizlenemez),
  Hediye kanalı, Global bildirim ayrı ayrı açılıp kapatılır; ayarlar telefonda hatırlanır. Mikrofon gürültü
  engelleme aynı sayfada.

## v2.49.1 — Ses bağlantısı ve üst üste açılan sayfalar
- **Ses sunucusu (LiveKit):** sunucunun genel IP'si ayara sabit yazıldı (her açılışta dışarıdan aranmıyor);
  ayar değişince ses sunucusu kendiliğinden yeniden başlar.
- Ses bağlantısı kurulamazsa uygulama 2, 4, 8 sn sonra kendisi yeniden dener; ancak üçü de olmazsa uyarı çıkar.
- **Panel → "Ses sunucusu testi":** LiveKit, sertifika, portlar ve güvenlik duvarı 5 dakikada bir kontrol edilir (✅/❌).
- Aynı sayfa ya da aynı alt pencere art arda iki kez açılmaz (çift dokunma / yavaş yanıtta tekrar dokunma).
- Sunucu, GitHub'dan gelen her güncellemede artık gereksiz yere yeniden başlatılmıyor (yalnızca uygulama sunucusu
  kodu değiştiyse ya da panelden "Kaydet ve uygula" ile) — "sunucu yanıt vermedi" kesintileri azalır.

## v2.49.0 — Şanslı çanta düzenlemesi ve hızlandırma
- **Şanslı çanta:** oda içinde en üstte, oda elmasının altında. Açtığın çanta sana bir daha görünmez; çanta tamamen
  bitince herkesten kalkar. Aynı kişi üst üste çanta atabilir (birden çok çanta varsa sayısı yazar, sıradaki açılır).
  Ana sayfadaki oda kartında çanta simgesi büyüdü.
- **Daha hızlı sayfa geçişleri:** ağır Android geçişi (iki sayfayı büyütüp soldurma) yerine yalnızca yeni sayfanın
  sağdan kaydığı hafif geçiş.
- **Geri dönüşte takılma giderildi:** alt sayfadan dönünce (profil, gelir merkezi, mağaza…) sayfa baştan kurulmuyor ve
  dönen yükleme simgesi çıkmıyor; içerik ekranda kalır, yenileme geçiş bitince arka planda yapılır (27 ekran).
- Profil ve Gelir Merkezi'ndeki istekler sırayla değil aynı anda gönderilir; etkinlik sayfasında yalnızca geri sayım
  yazısı her saniye yenilenir.

## v2.48.1 — Etkinlik banner görselleri ve tonlarına göre sayfa tasarımı
- Ana sayfadaki etkinlik kartları artık özel banner görselleri: **Haftalık Kral ve Kraliçe**, **Haftanın Çifti**,
  **Haftalık Yıldızlar**; dokununca ilgili etkinlik sayfası açılır, şimdiki lider sağ altta yazar.
- Kral ve Kraliçe görselindeki tarih kutusu her hafta o haftanın başlangıç/bitiş tarihini gösterir.
- Etkinlik sayfalarının başında aynı görsel; renkler görsellere göre: Kral & Kraliçe mor-pembe + altın,
  Çift kahve-bordo + altın, Yıldızlar koyu kırmızı + altın. Sekmeler kaydırınca üstte sabit kalır.

## v2.48.0 — Haftalık etkinlikler: Çift, Kral & Kraliçe, Yıldız
- **Haftalık Çift:** onaylı CP çiftlerinin birbirine gönderdiği CP hediyelerinin Coin değeri; ilk 3 çiftin iki kişisine de ödül.
- **Kral & Kraliçe:** erkek / kadın kullanıcılar ayrı yarışır, hafta boyunca en çok hediye (Coin değeri) alanlar; ayrı ödüller.
- **Haftalık Yıldız:** yönetimin seçtiği 4 hediyenin her biri ayrı yarış; o hediyeden en çok gönderen (adet) kazanır; her birine ayrı ödül.
- Hafta Pazartesi 00:00 (Türkiye saati) başlar. Hafta bitince ilk 3'e ödüller (Coin, WIP üyeliği, çerçeve, rozet, araç,
  balon… ) otomatik verilir, kazananlara bildirim gider ve "Etkinlik" duyurusu yayınlanır.
- **Ana sayfa banner'ları:** açık etkinlikler için kartlar (şimdiki lider yazar); dokununca etkinlik sayfası: geri sayım,
  **Sıralama** (ilk 3 kürsü, ilk 50, kendi sıran, geçen haftanın kazananları), **Ödüller**, **Kurallar**.
  Yönetimden eklenen banner'ın bağlantısı varsa dokununca açılır.
- **Yönetim → Katalog → Haftalık etkinlikler:** etkinliği aç/kapat, Yıldız hediyelerini seç, her sıranın ödüllerini ekle/kaldır, kuralları düzenle.
- Yeni migration: `038_weekly_events.sql` (kurulduğu haftadan önceki hafta dağıtılmış sayılır).

## v2.47.0 — WIP öğeleri Görünüm'de, WIP araçları oynuyor
- **Görünüm sayfası:** WIP üyeliğinin verdiği araç, çerçeve, sohbet balonu, giriş efekti ve rozet ("WIP üyeliği"
  etiketiyle) ilgili sekmelerde listelenir; her biri ayrı ayrı **Kaldır / Etkinleştir** yapılabilir. Kaldırılan öğe
  odada, sohbette ve profilde görünmez. Yeni **Rozet** sekmesi. WIP öğeleri kodla çizilen önizlemeyle gösterilir.
- **WIP araçları** (Scooter → Hayalet UFO) artık odaya girişte oynar: araç renkli iz bırakarak geçer, altında kademe
  ve araç adı. Yönetim → Öğe ver → Araç sekmesinden WIP araçları ayrıca da verilebilir.
- Sıra: takılı mağaza aracı → WIP aracı → takılı özel giriş efekti → diğerleri.
- Yeni migration: `037_wip_hidden.sql`.

## v2.46.0 — Mağaza görünümleri çalışıyor, anında güncelleme, test örnekleri
- **Giriş aracı:** odaya giren kişi kendi aracını/giriş efektini de görür (önceden yalnızca diğerleri görüyordu;
  uygulama odaya bağlanmadan duyuru gittiği için kişiye hiç oynamıyordu). Uygulama kapanıp aynı odaya dönünce de oynar.
- **Sohbet balonu:** takılı mağaza balonu, odadaki mesajların arka planı olur.
- **Mikrofon dalgası:** konuşurken koltuktaki avatarın çevresinde nabız gibi oynar (yeşil halkanın yerine).
- **Profil Kartı** (eski adı Mini Kart): odada birine dokununca açılan kartın arka planı olur.
- **Oda Kartı** (yeni kategori): oda sahibinin takılı kartı, oda bilgisi kartının arka planı olur.
- Satın alınan / yöneticinin verdiği öğe, o türden takılı bir şey yoksa kendiliğinden takılır.
- **Anında değişim:** çerçeve, balon, mikrofon dalgası takıp çıkarınca ya da profil fotoğrafı değişince odadakiler
  çıkıp girmeden yeni görünümü görür.
- **Yönetim → Katalog → "Test örneklerini bana ekle ve tak":** araç, sohbet balonu, mikrofon dalgası, çerçeve,
  profil kartı ve oda kartı örneklerini (mağazada satılmaz) yöneticiye 30 günlüğüne verir ve takar.
- Yeni migration: `036_room_card.sql`.

## v2.45.0 — Kullanıcı adıyla kayıt geri geldi, ajans/yayıncı davet usulü
- **Giriş ekranı:** "Kullanıcı adı ile" düğmesi; kullanıcı adı + şifre ile hem giriş hem kayıt (görünen ad isteğe bağlı).
  Google, Facebook ve telefon seçenekleri aynen duruyor.
- **Ajans:** kullanıcılar artık kendileri ajans kuramaz. Yönetici, Yönetim → Ajans/Yayıncı → **"Ajans aç"** ile kişiyi
  ID ya da kullanıcı adıyla seçip ajans adını yazar; ajans doğrudan aktif açılır, kişi ajans sahibi olur ve profilinde
  **Ajans Merkezi** görünür.
- **Yayıncı:** "Yayıncı ol" başvurusu, ajans koduyla ve listeden başvuru kaldırıldı. Ajans sahibi, Ajans paneli →
  davet ile kişiyi **ID ya da kullanıcı adıyla** bulup davet eder; davet Mesajlar'a düşer, kabul edilince kişi onaylı
  yayıncı olur ve **Yayıncı Merkezi** görünür.
- Yayıncı olmayanlar Gelir Merkezi'nde **Canlı Kayıt** ve **Para Çekme**'yi görmez (Elmas Bozdurma herkese açık).
- **Ajans sahipleri de yayıncı olabilir:** Ajans Merkezi → "Ajansımda yayıncı ol" (ya da başka bir ajansın davetini kabul ederek).
- Yönetim hesabı ve yardımcı adminler de odada **Moderatör / Yardımcı sahip** yapılabilir (önceden "Yönetim hesabına
  komut uygulanamaz" hatası veriyordu). Atma, susturma gibi komutlara karşı dokunulmazlıkları sürüyor.

## v2.44.1 — Oracle Cloud'a taşıma paketi
- `deploy/oracle/`: tek sunucuda PostgreSQL + uygulama sunucusu + LiveKit + HTTPS (Caddy, sslip.io adresi) + yönetim
  paneli. Oracle'da sunucu açarken `cloud-init.sh` yapıştırılır, gerisi kendiliğinden kurulur (komut yok).
- **Panel** (`https://…/panel`): durum, ayarlar (Google/Facebook anahtarları, yöneticiler…), eski veritabanını tek
  tuşla aktarma, "şimdi güncelle". Sunucu GitHub'daki main dalını 5 dakikada bir kontrol edip kendini günceller.
- Günlük veritabanı yedeği (son 7 gün). Adım adım rehber: `deploy/oracle/KURULUM.md`.
- Sunucu, aynı makinedeki LiveKit'e iç adresten (`LIVEKIT_API_URL`) bağlanabilir.

## v2.44.0 — Google, Facebook ve telefon numarasıyla giriş
- **Giriş ekranı yenilendi:** "Google ile devam et", "Facebook ile devam et", "Telefon numarası ile". Yeni kayıt
  yalnızca bu üç yolla; kullanıcı adıyla kayıt kaldırıldı (eski hesaplar "Kullanıcı adıyla giriş" ile girmeye devam eder).
- **Google / Facebook:** giriş sayfası tarayıcıda açılır, onay verince uygulamaya dönülür ve giriş kendiliğinden
  tamamlanır (SDK yok, imza anahtarına bağlı değil). İlk girişte hesap açılır; kullanıcı adı otomatik verilir.
  Render'a `GOOGLE_CLIENT_ID/SECRET`, `FACEBOOK_APP_ID/SECRET`, `PUBLIC_BASE_URL` eklenince düğmeler görünür.
- **Telefon:** numara + şifre + görünen adla kayıt (SMS kodu yok); girişte telefon numarası ya da kullanıcı adı
  yazılabilir. Türkiye numaraları 0555…, 555…, +90… biçimlerinde kabul edilir; her numaraya tek hesap.
- Şifresi olmayan (Google/Facebook) hesaplar: "Şifre değiştir" ilk şifreyi belirler; "Hesabı sil" onayı için SİL yazılır.
  Silinen hesabın telefon ve Google/Facebook bağlantısı kaldırılır.
- Herkese açık **Gizlilik Politikası** (`/api/legal/privacy`) ve **Veri Silme** (`/api/legal/data-deletion`) sayfaları.
- Yeni tablo: `035_social_login.sql` (diğer migration'lar gibi sunucu güncellenirken uygulanır).

## v2.43.1 — Akış düzeni, global şerit yalnızca odalarda
- **Global hediye şeridi** yalnızca açık odalarda görünür (ana ekranda, profilde ve oda küçültülmüşken görünmez).
- **Akış gönderileri** ekranı kaplamıyor: solda fotoğraf, sağda ad + WIP ve seviye rozetleri, "+ Takip et",
  yazı, küçük görsel (dokununca tam ekran, yakınlaştırılabilir), zaman, beğeni / yorum / sil.

## v2.43.0 — Oda görünümü: hediye şeritleri, araçlar, giriş şeridi, uçan yazı, sohbet
1. **Global hediye şeridi** artık hediyenin atıldığı oda dahil her odada görünür; en üstten (durum çubuğunun altından)
   geçer ve küçültüldü. Oda içi hediye şeridi de aynı anda ortadan geçer.
2. **Oda hediye şeridi yeni tasarım:** gönderenin altın halkalı fotoğrafı, adı, "gönderdi → alan", alanın fotoğrafı,
   şeridin ucuna taşan parlayan hediye ikonu ve büyük "x adet/combo". Ekran genişliğine göre kendini ölçekler, uzun
   isimler kısaltılır.
3. **Araçlar paneli** tasarımdaki gibi: koyu panel, "İnteraktif Özellikler" kare kutular (PK, Ludo, Şanslı Çanta),
   "Temel Araçlar" küçük metalik yuvarlak düğmeler (satırda 4–6).
4. **Giriş şeridi** herkes için (WIP olmayanlar lacivert-gümüş, WIP'ler kademe renginde altın kenarlı): çerçeveli
   fotoğraf, WIP rozeti, gönderme/alma seviyesi, ad ve "odaya girdi". Kalabalık odada WIP girişleri öne geçer.
5. **Uçan yazı:** yazı alanındaki "Uçan" anahtarı açıkken mesaj odanın üstünden sağdan sola uçarak geçer (en fazla
   80 karakter). Ücreti yönetimden ayarlanır (varsayılan 99 Coin, 0 = ücretsiz).
6. **Sohbet satırı:** fotoğraf, ad, altında rozet sırası (WIP, taç/kalp seviyeleri, CP, "Doğrulanmış") ve balon.
   Girişler rozetli satır olarak; son 3 günde kayıt olanlar için "Bu kullanıcı yakın zamanda kayıt oldu" kartı ve
   "👏 Hoş geldiniz" düğmesi (selam sohbete yazılır ve uçan yazı olarak geçer, ücretsiz).
7. **Uygulama uyarı duyurusu:** odaya girince sohbetin en başında "TR Live Sistem Duyurusu" kartı (Yönetim → Uygulama
   ayarları → Oda'dan değiştirilir; boş bırakılırsa gösterilmez). Yayıncıyı takip etmeyenlere bir dakika sonra
   "Bu yayıncıyı takip edin" kartı çıkar (dokununca favorilere eklenir).
8. **Süper şanslı çanta kişi sayısı:** 50, 100, 150 veya 200 kişi seçilebilir.
9. **Çanta açma penceresi sadeleşti** (küçük kart); açınca "Açıldı! +X Coin" yazar ve pencere kendiliğinden kapanır.
10. **"Bu işlem hâlâ sürüyor" hatası:** yavaş bağlantıda çanta (ve diğer para işlemleri) gönderildiği halde bu hata
    çıkıyordu. Uygulama artık birkaç saniye bekleyip sonucu alır.

## v2.42.3 — Açılış çökmesi (shared_preferences) düzeltildi
- 16 Ekim'de yayınlanan `shared_preferences_android 2.5.0` yayın APK'sında açılışta `NoSuchMethodError
  SharedPreferencesApiRegistrar.getAll` hatası veriyordu (uygulama hiçbir kayıtlı veriyi okuyamıyordu). Bir önceki
  sorunsuz sürüme (2.4.28) sabitlendi.

## v2.42.2 — Açılışta logoda takılma düzeltmesi
- Bildirim izni penceresi uygulamanın ilk ekranı çizilmeden açılıyordu; bazı telefonlarda uygulama açılış logosunda
  takılı kalıyordu. Bildirim servisi artık ekran açıldıktan 4 sn sonra başlar.
- Açılıştaki hazırlık adımları (arka plan servisi, kayıtlı oturum) hata verse ya da gecikse de ekran yine açılır.

## v2.42.1 — APK derleme hatası düzeltildi
- APK derlemesi `workmanager` eklentisi yüzünden kırılıyordu (`WorkmanagerPlugin` bulunamadı: eklentinin yeni sürümü
  Kotlin derlemesini yeni Android Gradle'a bırakıyor). Eklenti kaldırıldı.
- Herkese telefon bildirimi: uygulama açıkken / arka plandayken soketten anında bildirim olarak düşer; uygulama tamamen
  kapalıyken gönderilenler uygulama açılınca ya da öne gelince bildirim olarak gösterilir (arka planda ~15 dk'lık
  kontrol artık yok).

## v2.42.0 — Büyük güncelleme: yönetim dokunulmazlığı, kalıcı oda, müzik, şanslı çanta, hediye, seviye görünümleri
1. **Yönetim dokunulmazlığı:** yönetim (admin) hesabına hiçbir komut uygulanamaz (başka admin dahil: ban, isim/foto,
   odada mikten alma, atma, engelleme, susturma, rol, koltuk kilidiyle indirme). Yardımcı admine yalnızca yönetim
   komut uygulayabilir.
2. **Oda kalıcı:** oda kapatılıp açılınca sohbet açık/kapalı, tema görseli, sayı tahtası, mikrofon isteği, kilitli
   koltuklar, şifre ve gizlilik aynı kalır. **Oda elması** artık sıfırlanmaz (odaya gelen tüm hediyeler; koltuk
   sayaçlarını sıfırlamak oda elmasını silmez).
3. **Müzik:** yeni çalar (plak görseli, büyük oynat düğmesi), "Çalma listesi / Müziklerim" sekmeleri. Telefondan bir
   kez seçilen şarkı uygulamanın kalıcı klasörüne kopyalanır, **Müziklerim**'de kalır; dokununca listeye eklenir.
   Oda içi müzik balonu dönen plak. **Gürültü engelleme** (Efekt ve Ses): mikrofonda çevre sesini azaltır.
   **Şanslı çanta:** yeni gönderim penceresi (kese kartları), odada ve oda kartında kese simgesi, açınca coin;
   gönderen de kendi çantasından alabilir; kim ne kadar aldıysa odanın ortasından geçen şeritte görünür.
4. **Ajans daveti:** ajans sahibinin daveti kullanıcının Mesajlar sayfasında "Ajans daveti" kartı olarak çıkar
   (bildirim gelir); oradan kabul/ret. Yayıncı olmayan kullanıcı da davet edilebilir, kabul edince ajansın yayıncısı olur.
5. **Yönetim → Öğe ver:** her WIP kademesinin çerçevesi, rozeti, sohbet balonu ve giriş efekti ayrı ayrı listede;
   verilen ve takılan öğe WIP üyeliği olmadan da görünür.
6–7. **Sohbet:** oda duyurusu sohbetin en başında sabit; odaya girenler "… odaya girdi" satırıyla görünür.
8. **Banner** artık dokunmadan da kendiliğinden döner.
9. **Mikrofon emojileri:** koltuktayken alt bardaki emoji → 3 hareketli emoji; koltuğunun üstünde birkaç saniye oynar.
10. **Hediye:** combo'da hızlı dokunuşlar kaybolmaz (sıraya alınır); sayfa/sekme değişince pencere boyu değişmez
   (her zaman 2 satır); şanslı hediye kazancı büyük çarpan ve coin ile gösterilir; mikten mike giden hediye ikonu daha
   yavaş; oda içi hediye şeridi odanın ortasında; global hediye şeridi kırmızı-altın bant tasarımında.
11. **Mikten mike geçiş hızlandı:** yeni koltuk hemen gösterilir; sunucu geçişte gereksiz işlemleri yapmaz.
12. **Herkese telefon bildirimi:** Yönetim → İçerik → "Telefon bildirimi · Herkese gönder". Uygulaması yüklü herkese
   bildirim olarak düşer: açık uygulamalara hemen, kapalı olanlara Android'in arka plan kontrolüyle en geç ~15 dk
   içinde (Firebase gerekmez). İlk açılışta bildirim izni istenir. **APK iş akışı güncellendi** (bildirim eklentisi
   için gerekli Android ayarı): `.github/workflows/apk_build.yml` elle yüklenmeli.
13. **Küçültülmüş oda** balonunda oda fotoğrafı döner.
14. **Seviye görünümleri:** taçlı etiketler = atış (gönderme) seviyesi, kalpli etiketler = alış seviyesi; seviye
   sayfasında büyük rozetler; CP seviye etiketleri (LV3–LV5).
- Düzeltmeler: kod analizindeki 2 uyarı (net_image.dart) giderildi; zip artık doğrudan proje kökünü içerir ("Zip ile
  güncelle" iş akışının beklediği yapı; v2.41.0 zip'i bu yüzden açılamamıştı). v2.41.0'daki CP sistemi bu sürüme dahildir.

## v2.41.0 — CP (yakınlık) sistemi
- **Yakınlık puanı (exp)** her iki kişi arasında birikir:
  - Özel mesaj: çift başına günde ilk 10 mesaj 10'ar exp (günde en fazla 100 exp; iki yönün toplamı).
  - Hediye: aralarında gönderilen hediyeler Coin değeri kadar exp. **CP hediyesi 1,5 kat** (hediye panelinde yeni
    "CP" sekmesi; yönetimde hediye eklerken sekme "CP" seçilir). Kendine hediye sayılmaz.
- **5 kademe:** 10.000 · 50.000 · 200.000 · 600.000 · 1.500.000 exp.
- **3. kademede ilişki seçimi:** profil kartında (odada kişiye dokununca ve profil sayfasında) "Yakınlık" bölümü:
  kalpler, ilerleme çubuğu, "Arkadaş olarak seç" / "CP olarak seç". Karşı taraf kabul eder (profil kartından ya da
  Mesajlar → Arkadaşlık isteği listesinden; bildirim ve rozet gelir). Herkesin tek CP'si olur; ilişki bitirilince
  puan korunur.
- **CP profilde:** CP eşi profil sayfasında ve odadaki profil kartında görünür. CP sıralaması artık onaylı çiftleri
  yakınlık puanına göre gösterir.
- **5. kademe oda efekti:** CP'ler sesli odada mikrofonda yan yana oturunca aralarında kalp atışı gibi büyüyüp küçülen
  bir kalp, ikisinin avatar dairesinin çevresinden de küçük kalpler çıkar. Koltuk düzeni değişmez, dokunmalar geçer.
- Sunucu: `cp_pairs` tablosu, `users.cp_partner_id`, `/api/cp/...` uçları, hediye sekmesi `cp`.

## v2.40.3 — Hızlandırma
- **Görseller telefonda saklanır:** avatarlar, oda kapakları, bannerlar, tema görselleri, hediye simgeleri ve mesaj
  fotoğrafları bir kez indirilir; uygulama her açıldığında yeniden indirilmez (sunucu ve internet yükü azalır, listeler
  daha hızlı dolar). Görseller ekranda çizilecekleri boyutta çözülür (büyük fotoğraflar belleği ve işlemciyi yormaz).
- **Oda açıkken ana sayfa arkada durur:** oda tam ekranken arkadaki ana sayfa çizilmez, animasyonları çalışmaz.
  Görünmeyen sekmelerin (Akış, Mesajlar, Profil…) animasyonları da durur.
- **Hareketli parçalar kendi katmanında:** koltuk çerçeveleri (SVGA/Lottie), WIP renkli adlar, giriş şeridi, araç,
  hediye şeridi ve uçan hediye, müzik balonu artık her karede odanın tamamını (arka plan, koltuklar, sohbet) yeniden
  çizdirmiyor. Oda arka plan görseli bir kez çizilir.
- **SVGA dosyaları arka planda açılır:** büyük hediye/çerçeve dosyası açılırken ekran donmaz; aynı dosya tekrar
  gelince yeniden indirilip açılmaz.
- **Ses sunucusu olayları:** oda yalnızca konuşan kişi, görüntü ya da bağlantı değişince yeniden çizilir (önceden
  bağlantı kalitesi bildirimlerinde de saniyede birkaç kez tüm oda yeniden çiziliyordu).
- **Sunucu:** veritabanı bağlantıları 10 sn yerine 5 dk açık tutulur. Az kullanıcıyla neredeyse her istek yeni SSL
  bağlantısı açıyor, her istekte fazladan ~0,3–1 sn bekletiyordu.

## v2.40.2 — Yayın başlat tasarımı, kırpma düzeltmesi, giriş efektleri
- **Yayın başlat ekranı yenilendi:** daha canlı mor → lacivert → turkuaz zemin (köşelerde yumuşak ışık), çerçeveli ve gölgeli oda fotoğrafı (sağ altta kamera rozeti), koyu ve kenarlı yazı kutuları, sesli odada duyuru kutusunda megafon simgesi. Mikrofon modlarında seçili kutu sarı çerçeve + parıltı + onay işareti, her kutuda kişi sayısı. Çoklu yayında kişi sayısı tek bir şerit içinde. Tür düğmeleri biraz daha aralıklı (yazılar artık birbirine değmez), seçili olan mor parıltılı. "… yayına başla" düğmesi turkuaz gölgeli. Ölçüler ekran genişliğine göre, küçük/büyük telefonda sınırlı.
- **Fotoğraf kırpma ekranı düzeltildi:** görsel ve çerçeve sağdan kesiliyordu; artık tüm ekranı kaplıyor.
- **WIP giriş efekti:** odaya girişte üstte kayan bantta artık araç yok; **fotoğrafın, adın (WIP renginde), WIP rozetin ve seviyen** görünür.
- **Araç giriş efekti ayrı:** mağazadan alınan araç yalnızca **odaya giriş efekti** olarak görünür: araç sağdan ekrana girer, ortada durur, sola çıkar; altında "Ad, Araç ile geldi". Takılı (seçili) giriş efekti öncelikli; yoksa araç, o da yoksa diğer giriş efekti.

## v2.40.1 — APK iş akışı
- APK derlemesi eski usulde: Actions → Build Android APK → Run workflow → Artifacts'tan zip. Sunucu adresi kutusu artık
  **https://tr-live-1.onrender.com** ile dolu gelir; zip yükleyince otomatik başlayan derleme de bu adresi kullanır
  (eskiden `api.example.com` ile bağlanamayan APK üretiyordu). APK zip içinde yeniden sıkıştırılmaz.
- İki eski kod analizi uyarısı giderildi (GitHub'daki "Mobile / analyze" kontrolü kırmızı çıkıyordu).

## v2.40.0 — Yayın başlat (Sesli · Canlı · Çoklu), Yoho mesajlar, fotoğraf kırpma, ana sayfa üst bar
Yayın başlat (Figma "Hillive")
- "Oda aç"a basınca yeni **Yayın başlat** ekranı: oda fotoğrafı (seçilmediyse profil fotoğrafın), yayın başlığı, **yayın isim kartı** (Sohbet · Eğlence · Müzik · Yarışma · Film · Oyun; açılır renkli çipler), altta **Çoklu Yayın · Canlı Yayın · Sesli Yayın** düğmeleri ve "… yayına başla".
- **Sesli:** oda duyurusu ve mikrofon modları (2 · 5 · 8 · 9 · 12 · 15 · 20 · 30; önizlemeler odadaki koltuk yerleşimiyle aynı). Sesli oda **bir kez** kurulur; sonra "Oda aç" doğrudan odana götürür.
- **Çoklu:** 4 · 6 · 9 · 12 kişilik görüntü ızgarası (4: yayıncı solda büyük; 6: yayıncı 2×2; 9: 3×3; 12: 4×3), yayıncının hücresinde kamera önizlemesi.
- **Canlı:** arkada tam ekran kamera önizlemesi. Odada yayıncı tam ekran, sağda en fazla 3 küçük konuk penceresi ("Konuk ol"), solda alttan sohbet.
- Görüntülü yayın açık değilse ekran her seferinde gelir (son bilgilerle dolu); açıksa doğrudan odana girersin. Sihirli değnek = oda teması. Güzellik filtresi henüz yok (düğme "yakında" der).
- Oda içinde: görüntülü odada kamerayı kapat/aç ve **kamerayı çevir** (koltuğuna dokun veya araçlar). Çoklu yayında "Yayın modu" 4/6/9/12 arasında değişir; canlı yayında konuk sayısı sabit.
- Oda kartında tür etiketi kendi renginde (ör. Eğlence pembe-mor).
- Sunucu: `rooms.layout` / `room_profiles.layout` ('grid' | 'live'), `POST /api/rooms` → `setup: true` ile kayıtlı oda bilgileri (ad, tür, duyuru, koltuk, düzen, tema) güncellenir; canlı yayında koltuk sayısı 4 (yayıncı + 3 konuk).

Fotoğraf boyutu ayarı
- Profil fotoğrafı (daire kılavuzlu kare), profil kapağı (profil sayfasındaki oran), oda fotoğrafı (kare) ve banner (3:1) seçilince **kırpma ekranı** açılır: sürükle, iki parmakla büyüt/küçült, "Kullan". Sonuç JPEG (veritabanında eskisinden ~5-10 kat az yer).

Ana sayfa
- Üst sekmeler **Popüler · Takip** (Yakında kalktı). Sağdaki ⋮ menüsü kalktı; gizli odaya kodla giriş ve kullanıcı arama, arama kutusunun sağında. Tavsiyeler / Yeni yayıncı çipleri kalktı.

Mesajlar (Yoho düzeni)
- **Mesajlar sayfası:** solda büyük "Mesajlar" başlığı, sağda arkadaş listesi; altında yana kayan kartlar **Arkadaşlık isteği · TR Live Ekibi · Etkinlik Promosyonu · Çevrimiçi Hizmet · Ödül Bildirimleri** (okunmamış rozetleriyle); altında sohbet listesi (büyük fotoğraf, ad ve rozetler, sağda saat: bugün 14:30 · "Dün 06:48" · eski "26-10-06", altında son mesaj). Üstteki uyarı şeridi ve Tümü/Özel Takip yok.
- **Oda içinde zarf düğmesi:** alttan açılan **"Sohbet"** penceresi (aynı kartlar ve liste). Sohbete dokununca sohbet tam ekran açılır, geri gelince pencere yerinde; oda arkada çalışmaya devam eder.
- **Sohbet ekranı:** ortada ad, sağda karşı tarafın fotoğrafı; tarih ayraçları; gelen mesaj solda gri, giden sağda yeşil baloncuk (fotoğraflarla); altta fotoğraf · "Bir şey söyle..." · emoji · gönder. **Fotoğraf gönderme** yeni. Mesaja uzun bas: kopyala / şikâyet et.
- **Arkadaşlık isteği:** yalnızca son 7×24 saatteki istekler (Kabul et / Reddet), boşsa el sallayan simge. Süresi dolan istek yeniden gönderilince tazelenir.
- **Ekip / Etkinlik / Ödül:** tarih ayraçlı akış; görselli duyurular kart (görsel + başlık + metin), görselsiz ekip mesajları baloncuk; bağlantı varsa "Görmek için tıklayın" (bağlantıyı kopyalar). Yönetici panelinde duyuruya görsel ve bağlantı eklenebilir. Rozetler kart başına ayrı sıfırlanır.
- **Çevrimiçi Müşteri Hizmetleri:** üstte "Müşteri Hizmetleri Merkezi · Hemen Yardım Al!" bandı, baloncuklu yazışma, yuvarlak yazı kutusu; sağ üstte konu seçimi.
- Henüz yok: sohbette hediye ve sesli mesaj, Yoho'daki sağ üst emoji düğmesi.

APK derleme
- "Build Android APK" iş akışında **Sunucu adresi** kutusu artık boş gelir; boş bırakılırsa depodaki `API_URL` değişkeni kullanılır. Eskiden kutuda `https://api.example.com` yazıyordu ve zip yükleyince otomatik başlayan derleme hiçbir sunucuya bağlanmayan APK üretiyordu. (`.github/workflows/apk_build.yml` elle yüklenmeli.)

## v2.39.2
- Veritabanı bağlantı havuzu 10'dan 5'e indi (Aiven Free toplam 20 bağlantı veriyor; Render güncelleme sırasında eski ve yeni sunucu birlikte açık kalınca sınır aşılıp "veritabanına bağlanamıyor" hatası çıkabiliyordu). `DATABASE_POOL_MAX` ile ayarlanır. Bağlantı 15 sn'de alınamazsa istek askıda kalmaz.
- Bağlantı hatası mesajında kısa hata kodu görünür (ör. "kod: 53300" = bağlantı sınırı, "28P01" = şifre yanlış).

## v2.39.1
- Sunucu veritabanına ulaşamadığında (şifre değişmiş, servis kapalı, adres yanlış, sertifika reddi) uygulama artık "Sunucu hatası" yerine "Sunucu şu an veritabanına bağlanamıyor" der; Render günlüğüne de sebep açıkça yazılır (`[veritabanı] ... veritabanı şifresi yanlış (DATABASE_URL içindeki şifre güncel mi?)`). `/health` bu durumda 503 döner.

## v2.39.0 — Yoho ile birebir düzen: oda ekranı ve ana sayfa
Ölçüler bu kez Yoho ile yan yana ekran görüntüsünden piksel piksel ölçüldü ve hesaplanan yerleşim Yoho görüntüsünün üstüne bindirilerek doğrulandı.

Oda ekranı
- **Üst satırlar Yoho gibi iki satır:** 1. satır oda kutusu (kapak + ad + ID) · ilk 3 izleyici · kişi sayısı · ••• · ⏻; 2. satır toplam elmas · favori ··· aile · taç. Eskiden 3 satırdı ve koltukları ~%10 aşağı itiyordu.
- **Koltuklar Yoho'nun yerinde:** 30 mikrofonda daire çapı, satır aralığı ve ilk satırın yeri Yoho ile aynı (önceki %1 daire büyütmesi Yoho'dan %9 büyük gösteriyordu, kaldırıldı).
- **Boyut artık hiç değişmez:** koltuk ölçüsü yalnızca ekran genişliğine bağlı. Mikrofona oturmak, izleyici gelmesi, aile/favori rozeti, klavye, ses hatası şeridi koltukları küçültmez/kaydırmaz. Başlık, koltuk adları ve alt bar telefonun yazı boyutu ayarından etkilenmez.
- **Çerçeve avatarın etrafına oturur:** takılı çerçeve koltuk kutusuna sıkıştırılmıyor; avatar çapının 1,6 katı, aynı merkezde (profil ile aynı oran). Oturan kişinin fotoğrafı artık küçük görünmez.
- Alt bar Yoho ölçüsünde (düğme ve hediye çapı, yükseklik). Şanslı çanta sağ altta (koltukların üstüne binmiyor). "•••" menüsü: paylaş, oda bilgisi, şikâyet, küçült.

Ana sayfa
- Ayrı üst çubuk kaldırıldı; Yoho gibi **İlgili · Sıcak · Yakında** yazı sekmeleri (seçili büyük ve kalın, altında çizgi), sağda sıralama tacı, arama, oda aç ve diğer.
- Banner 3:1, kenar boşlukları Yoho ölçüsünde. Sıcak sekmesinde **Tavsiyeler · Yeni yayıncı** süzgeçleri (son 30 günde açılan hesapların odaları).
- Oda kartları Yoho gibi: kare kapak, sol altta tür etiketi, sağ altta dinleyici sayısı ve üstünde üst üste binen üye fotoğrafları, oda adı kartın altında.
- Alt menü yalnızca simge (Yoho).
- Sunucu: oda listesinde `avatars` (en fazla 8; gizli kullanıcı ve hayalet dinleyici hariç) ve `fresh=1` süzgeci.

## v2.38.1 — Veritabanı taşıma
- Neon'un ücretsiz planı ayda 100 işlem saatiyle sınırlı; sürekli açık sunucumuzda ay ortasında bitiyor. Önerilen ücretsiz sağlayıcı: **Aiven Free PostgreSQL** (saat kotası yok). Adımlar: `docs/VERITABANI.md`.
- Sunucu artık bağlantı adresindeki `sslmode` parametresini yok sayıyor: Aiven/Supabase adresleri olduğu gibi yapıştırılabilir ("self-signed certificate" hatası olmaz). İsteğe bağlı `DATABASE_CA` ile tam sertifika doğrulaması.
- GitHub Actions'a **"Veritabanını taşı"** iş akışı: eski veritabanını yeni, boş veritabanına birebir kopyalar, her tablonun satır sayısını karşılaştırır, en büyük tabloları gösterir. Bağlantı adresleri GitHub secret olarak verilir.
- `ADMIN_USERNAMES` ortam değişkeni: sıfırdan kurulan veritabanında belirtilen kullanıcı adları yönetici yapılır.

## v2.38.0 — WIP 1–10 + SWIP (hayalet mod), şanslı hediye
- **WIP 1–10:** Yoho'daki VIP kademelerinin ayrıcalıkları 10 kademeye sıkıştırıldı (Yoho'nun en üst kademesi = WIP 10). Her kademenin kendi rengi, rozeti, **isim efekti** (renkli → parlayan → neon → altın/yeşim/buz/gökkuşağı parıltı → ateş), **sohbet balonu** (renk geçişli, kenar ışıklı, köşe süslü), **avatar çerçevesi** (WIP 6+ dönen, WIP 8+ yıldızlı; takılı mağaza çerçevesi varsa o görünür) ve **giriş aracı** (🛵 Scooter → 🐉 Ejderha) var.
- Ayrıcalıklar: ziyaretçileri görme (2), Vip hediyeler (3), susturulamaz (4), profil ışık efekti (5), odadan atılamaz + özel oda teması (6), gizli ziyaret (7), hareketli profil fotoğrafı (8), oda sayısı 1→5. Hepsi Panel > WIP kademelerinden değiştirilebilir.
- **SWIP (11. kademe):** WIP 10'un her şeyi + **hayalet mod** (Ayarlar > Hayalet mod): odaya giriş duyurulmaz, dinleyici listesinde, kişi sayısında, toplu hediye alıcılarında ve çevrimiçi göstergelerde görünmez; ziyaret iz bırakmaz, odadan çıkışı da duyurulmaz. Mikrofona çıkınca görünür, inince yeniden gizlenir; mod değişince odada ve çevrimiçi göstergelerde anında güncellenir.
- **WIP ekranı yenilendi:** kademe seçici, seçilen kademenin canlı önizlemesi (çerçeve, isim, balon, giriş aracı), kilitli/açık ayrıcalık ızgarası, paketler.
- Eski WIP üyelikleri oransal taşındı (1→2, 2→4, 3→6, 4→8, 5→10); süreler aynı. Yeni fiyatlar 30 gün: 5 bin → 1 milyon Coin, SWIP 2 milyon.
- **Şanslı hediye (Yoho çanı):** hediye penceresinde "Şanslı" sekmesi (Şanslı Çan, Şanslı Yonca). Her adet bir şans: x2–x500 kat Coin geri kazanma. Alıcıya hediye değerinin %10'u Elmas geçer. Büyük kazançlar (x100+) tüm uygulamaya duyurulur. Panel > Uygulama ayarları > Şanslı hediye: aç/kapa, geri dönüş oranı (varsayılan %70), alıcı payı, en fazla kazanç (toplam en fazla %95).
- Ajans/maaş, PK, sayı tahtası, aile puanı ve liderlik tablolarında alıcı tarafı artık alıcıya geçen Elmas'la hesaplanıyor (şanslı hediyede değerin tamamı değil, payı).
- Sunucu: migration 029; `is_ghost()` SQL işlevi ve `active_ghosts` görünümü (oda listelerinde hızlı sayım); `users.ghost_mode`, `gift_transactions.diamond_amount`; `lucky_gift_win` cüzdan türü ve global olayı; `GET /api/gifts` yanıtında `lucky`; hediye yanıtında/olayında `lucky`.

## v2.37.0 — Faz 2 (1. kısım): tekrar koruması, combo hediye, "yazıyor...", Coin geçmişi
- **Para işlemlerinde tekrar koruması:** hediye, mağaza, WIP, Elmas bozdurma, bayi satışı, şanslı çanta ve yönetici Coin düzeltmesi tek kullanımlık işlem anahtarıyla gider. Zayıf ağda istek iki kez ulaşsa (ya da uygulama zaman aşımından sonra kendiliğinden tekrar denese) Coin bir kez düşer. Ağ hatasından sonra aynı hediyeye tekrar basılırsa da aynı anahtar kullanılır.
- **Combo hediye (Yoho):** gönderimden sonra hediye penceresi açık kalır, 5 sn'lik geri sayımlı "COMBO xN" düğmesi aynı hediyeyi tek dokunuşla tekrar gönderir. Odadaki şerit yeni şerit açmak yerine büyüyen altın "xN" sayacıyla uzar. Hediye/adet/alıcı değişince combo biter.
- **"Yazıyor...":** arkadaşın yazarken sohbet başlığında ve mesaj listesinde görünür (yalnızca mesajlaşabilen arkadaşlar arasında, engelliyse gitmez).
- **Coin geçmişi:** Cüzdan ekranında tür süzgeçleri (Hediye, Yükleme, Bozdurma, Mağaza/WIP, Çanta) ve "Daha fazla göster" ile eski kayıtlar; tutarlar +/− işaretli.
- Sunucu: migration 028 (idempotency_keys), saatlik temizlik; `/api/me/wallet?group=&before=`; hediye yanıtında ve `room_gift` olayında `combo`; WebSocket `typing`.
- Bilinçli olarak eklenmedi: şanslı hediye (gönderenin rastgele Coin kazanması) — kumar sayılma ve Google Play riski. VIP 1–15 için kademe/fiyat/rozet kararı bekleniyor.

## v2.36.0 — Faz 1: oturumlar, çevrimiçi durumu, kalıcı medya, canlı panel, otomatik moderasyon
Belgeler
- `docs/` klasörü: MIMARI, EKONOMI, YETKILER, GUVENLIK, TEST_PLANI, YOL_HARITASI (elle) ve `docs/generated/` altında koddan üretilen veritabanı (74 tablo), API (258 uç) ve WebSocket (34 olay) belgeleri (`node backend/scripts/gen_docs.mjs`).

Oturum ve güvenlik
- Cihaz oturumları: 1 saatlik erişim token'ı + her kullanımda değişen yenileme token'ı (veritabanında yalnızca özeti). Uygulama süresi dolmadan kendiliğinden yeniler; internet yokken oturum kapanmaz.
- Çalıntı token tespiti: eski yenileme token'ı 15 dk ağ toleransından sonra tekrar kullanılırsa oturum kapanır. Giriş sürerken şifre değişirse/ban gelirse oturum açılmaz.
- Ayarlar > Oturumlarım: cihaz adı/modeli, sürüm, IP (maskeli), son etkinlik; tek cihazdan veya diğer tüm cihazlardan çıkış. Çıkışta sunucudaki oturum da kapanır.
- Şifre değişimi, ban, hesap silme tüm oturumları kapatır. Eski sürümden güncellenen uygulama yeniden giriş istemeden yeni oturuma geçer; eski APK'lar çalışmaya devam eder.
- Zorunlu güncelleme: Panel > Uygulama ayarları > en düşük sürüm. Altındaki uygulamalar "Güncelleme gerekli" ekranı görür (indirme bağlantısı kopyalanabilir). Yeni sürüm yayınlanınca bir kez "yeni sürüm var" bildirimi.
- Profil fotoğrafı/kapak artık dış adres olarak verilemez (yalnızca yükleme). Hesap silinince gönderiler gizlenir, yüklenen fotoğraflar silinir.

Çevrimiçi durumu
- Mesajlar listesinde çevrimiçi kişilerin avatarında yeşil nokta (canlı), sohbet başlığında "Çevrimiçi / Son görülme ... önce", kullanıcı profilinde çevrimiçi satırı.
- Özel mesajda "Görüldü".
- Ayarlar > "Çevrimiçi durumumu göster" (kapatılabilir). Gizli kullanıcı modu ve engellenen kişiler durumu göremez.

Kalıcı medya
- Profil fotoğrafı, kapak, gönderi görseli, oda kapağı ve banner'lar artık veritabanında: Render yeniden dağıtılınca görseller kaybolmuyor. Sık istenen küçük görseller sunucu belleğinde önbelleklenir; tarayıcı/uygulama önbelleği için ETag. Eski dosyalar silinirken yalnızca kullanıcının kendi yüklemesi silinir.

Otomatik moderasyon
- Link, site adresi, "nokta com" gibi gizlemeler, t.me/wa.me/discord ve "insta: @..." yönlendirmeleri; herkese açık alanlarda telefon numarası engellenir. "saat 10.30", "tamam.biz" gibi normal cümleler takılmaz.
- 10 dk içinde 3 ihlal → 15 dk tüm sohbetlerde kısıt; 24 saatte tekrarında süre ikiye katlanır (en fazla 24 sa). Değerler panelden değiştirilir. Ad, biyografi, oda adı/duyurusu, aile/ajans adında link ve telefon reddedilir.

Yönetim paneli
- Yeni "Panel" sekmesi (10 sn'de bir yenilenir): çevrimiçi kullanıcı, açık bağlantı, aktif oda, mikrofondaki kişi, açık oturum; bugünkü kayıt/aktif kullanıcı/hediye/mesaj/ihlal; sunucu sürümü, açık kalma süresi, CPU, bellek, veritabanı gecikmesi/boyutu/bağlantı havuzu, LiveKit durumu, açık şikâyet.
- Uygulama hata kayıtları (telefonlarda yakalanan hatalar otomatik gönderilir, en sık hatalar özeti), İşlem kaydı (yetkili işlemleri ve para hareketleri), Otomatik moderasyon listesi, Uygulama ayarları.
- Kullanıcı kartı: sohbet kısıtı koy/kaldır (yardımcı admin de), Cihazlar (oturumlar, emülatör işareti, aynı cihazı kullanan diğer hesaplar), Tüm oturumları kapat.

Sunucu
- Migration 027 (user_sessions, moderation_strikes, client_errors, app_config, users.show_presence / chat_restricted_until, panel indeksleri).
- Yeni uçlar: /api/auth/refresh, /api/auth/session, /api/auth/logout, /api/me/sessions…, /api/app/config, /api/client-errors, /api/admin/dashboard, /client-errors, /actions, /app-config, /moderation/strikes, /users/:id/chat-restriction, /users/:id/devices, /users/:id/sessions/revoke-all.
- Yeni WebSocket olayları: presence_watch → presence_state / presence, dm_read, chat_restricted.
- Testler: moderasyon/sürüm/cihaz birim testleri; oturum, moderasyon, çevrimiçi durumu ve panel için uçtan uca testler.

## v2.35.0
- Üst çubuk inceltildi; TRLive yazısı ve taç küçüldü; oda açma düğmesi yalnızca simge (yazı yok). Düğme yalnızca Sesli sekmesinde (mikrofon) ve Görüntülü sekmesinde (kamera) görünür; Akış, Mesajlar ve Profil'de yok.
- Mesajlar Yoho düzeninde: "Sohbet (okunmamış)" başlığı, Aile / Duyurular / Arkadaşlar düğmeleri, Arkadaşlık İsteği · Çevrimiçi Sohbet · Ajans Mesajı kartları, Tüm / Özel Takip (takip ettiklerin) sekmeleri, kart görünümlü sohbet listesi ve "1 Eki" tarih biçimi.
- Profil: üstteki fazla boşluk kaldırıldı (ikinci durum çubuğu boşluğu), simgeler çerçevenin sağ üstüne alındı; çerçeve fotoğrafın çapına göre (×1,6) — profil, kullanıcı profili ve seviye ekranında aynı oran; ad, ID, sayaçlar, kartlar ve menü yazıları küçültüldü.
- Mikrofon modu seçilince pencere kendiliğinden kapanır.
- Müzik yalnızca oda içinde: oda küçültülünce dışarıda ayrı müzik balonu çıkmaz; müzik çalıyorsa oda balonunda küçük nota görünür.

## v2.34.1
- Koltuk daireleri her mikrofon modunda ekran genişliğinin %1'i kadar büyütüldü (merkezler aynı, daire etrafına büyür); içindeki "+" simgesi eski boyutunda.

## v2.34.0 — Derin denetim: güvenlik, kararlılık, tasarım
Sunucu
- Başkasının yüklediği dosyayı silme açığı kapatıldı: gönderide yalnızca kendi yüklediğin görsel kullanılabilir; gönderi silinince yalnızca sahibinin dosyası silinir (upload_owners).
- Banlanan / hesabını silen kullanıcı tüm odalardan çıkarılır, ses-görüntü bağlantısı kesilir, sahibi olduğu oda kapanır. Silinen hesap adı çakışması giderildi.
- Gizli odanın üye/yönetici/katkı/PK bilgisi yalnızca odadakilere açık; gizli odalardan global hediye şeridi ve şans çantası duyurusu yayılmaz.
- Sohbet susturması odadan çıkıp girince kaybolmuyor (room_mutes). Moderatör, çevrimdışı yardımcı sahibi engelleyemez ve sahibin koyduğu engeli kaldıramaz.
- Maaş dönemleri çakışırsa (aylık + haftalık) kapatma reddedilir: aynı kazanç iki kez ödenmez.
- Tek bir kullanıcı adına yanlış şifre denenerek başkasının (ör. admin) hesabını kilitleme engellendi (kilit IP+kullanıcı bazlı).
- Yetki, büyük dosya gövdesi belleğe alınmadan önce denetlenir (müzik yükleme, oda kapağı). Profil/kapak yüklemeye sınır; eski hareketli avatar kaydı silinir.
- Zamanlayıcılar üst üste binmez (PK, müzik, oyun, oda temizliği); küfür filtresi ~25 kat hızlandı; sıralama sorgularına indeks; hediye sonrası hata parayı tekrar çektirmez; küçük doğrulama düzeltmeleri (limit, doğum tarihi, çanta türü, gizli yetkili adı, kullanıcı arama sınırı).
- Migration 026. Sözdizimi kontrolü tüm dosyalara genişletildi.

Mobil
- Çıkış yapınca açık/küçültülmüş oda kapanır, odadan düzgün çıkılır, müzik durur (önceden sonraki girişte eski oda açılıyordu).
- Ses (LiveKit) bağlantısı koparsa artan aralıklarla kendiliğinden yeniden kurulur.
- Soket yeniden bağlanınca / uygulama öne gelince oda durumu (koltuklar, kendi mikrofonun, sohbet, puanlar, PK, çantalar, müzik) sunucuyla eşitlenir; ölü bağlantı 70 sn'de fark edilir; geçici sunucu hatası artık oturumu kapatmaz.
- Kilitli/gizli odaya yeniden katılırken şifre/kod korunur. Odadan çıkış ağı beklemeden anında.
- Para işlemlerinde zaman aşımı mesajı "işlem gerçekleşmiş olabilir, kontrol et" der (körü körüne tekrar ettirmez).
- Müzik yarış durumları (geç gelen yanıt, odadan çıkınca yeniden başlama) giderildi. Arka plan servisi aç/kapat sırası düzeltildi.
- Hediye uçuşları/animasyonları oda küçültülmüşken birikmez; animasyon bitiş/hata bildirimleri bir kez ve doğru zamanda.
- Avatarlar gösterildiği boyutta çözülür (bellek). Sohbet, yukarı kaydırıp okurken aşağı zıplamaz. DM listesi her mesajda baştan yüklenmez.
- Akışta sayfa hatası sonsuz istek döngüsüne girmez; kısa ekranda hediye penceresi çökmesi giderildi; gizli mod anahtarı hata olursa geri döner.

Tasarım
- Bildirimler en üst katmanda (açık pencere/diyalog arkasında kalmaz), simgeli ve yumuşak geçişli. Silme/kapatma onayları kırmızı.
- Türkçe sistem metinleri (Geri, Kopyala/Yapıştır, tarih seçici). Kısa listelerde de aşağı çekip yenileme çalışır.
- Başlık yazısı 20 sp (uzun başlıklar kesilmez), kartlar arası boşluk, renk/boşluk/köşe ölçü tabloları (Gap, Rad, Pal.green/orange/gold), ortak EmptyState.
- Taşma düzeltmeleri (büyük yazı boyutunda bakiye, segmentler, çanta sayacı, mesaj kartları), podyum 🥉, "1,5K" Türkçe ondalık, Türkçe büyük harf (İ), kullanıcı profili yüklenirken de geri düğmesi, teknik hata metinleri kullanıcıya gösterilmez.
- APK derlemesi: Dart hatası varsa uzun derlemeyi beklemeden durur ve hatalı satırları özet sayfasında gösterir.

## v2.33.0 — Oda ekranı Yoho ölçüleriyle
- Koltuk yerleşimi Yoho ekran görüntülerinden ölçülen oranlarla her mod için ayrı: 2, 5, 8, 9, 12, 15, 20 ve yeni 30 mikrofon (6 x 5). Koltuklar başlığın altından sabit ölçüyle başlar; sohbet koltukların bittiği yerden akar. Boş koltuk: yarı saydam beyaz daire + ince çerçeve, altında numara.
- Mikrofonlar artık hiçbir durumda küçülmez: klavye açılınca oda kararır, mesajlar karartının üstünde görünür, beyaz yazı şeridi klavyenin üstündedir (Yoho). Hediye paneli koltukları sıkıştırmaz.
- Sohbet: renkli saydam balonlar (seviyeye göre lacivert/turkuaz/mavi/mor/pembe/altın), solda avatar, üstte ad ve seviye, altta balon; sistem mesajları sarı ("Oda sahibi yeni bir mikrofon moduna geçmiştir…").
- Alt bar Yoho düzeni: mikrofonda değilken "Selam..." kutusu + hediye, mesajlar, oyun, menü; mikrofondayken sohbet, mikrofon, emoji, hediye, mesajlar, oyun, menü. Ses aç/kapat, kamera, sıraya gir ve mikrofondan in oda araçlarına taşındı.
- Mikrofon modu penceresi Yoho gibi: beyaz pencere, mavi-mor başlık, ipuçları, önizlemeli 3 sütun, seçili yeşil çerçeve + tik, azaltırken "Tips" onayı, pencere açık kalır.
- Yeni: "Mikrofonda olmak için istekte bulunmanız gerekiyor" modu. Açıkken kullanıcı koltuğa dokununca istek gönderir; yetkililer "Mikrofon istekleri" listesinden onaylar (davet) veya reddeder.
- Sunucu: migration 025 (30 koltuk, rooms.mic_request), istek modu kontrolleri, DELETE /api/rooms/:id/mic/queue/:userId.

## v2.32.0
- Tüm uygulamada alt sistem çubuğu (Android gezinme çubuğu) payı: içerik artık çubuğun altında kalmıyor (Seviye Merkezi dahil tüm ekranlar).
- Hediye paneli açılınca sohbet ve alt bar gizlenir, sahne panelin üstüne sıkışır ve mikrofonlar küçülür; klavye açılınca da mikrofonlar küçülür.
- Oda sohbeti Yoho gibi şeffaf: balonlar saydam, üst kenarda solarak kaybolan kayar akış.

## v2.31.1
- WIP rozeti koltuk adlarından ve oda sohbetindeki adların yanından kaldırıldı (nick efekti kalır).
- Her koltuk modu (2, 4, 5, 6, 8, 9, 12, 15, 20) için ayrı, sabit koltuk ölçüsü tablosu; yükseklik yetmezse orantılı küçülür.

## v2.31.0
- Mikrofon modu penceresi açılmama hatası düzeltildi ("Cannot modify an unmodifiable list": sabit listeye sort uygulanıyordu).
- Koltuk adı: WIP rozeti küçük "W5" biçimine geçti, kesilme/taşma giderildi; ad satırı ölçüleri düzeltildi.
- Oda küçültme balonu ve müzik balonu: yumuşak sürükle-bırak ve kenara yapışma, kapatma (X) düğmesi büyütüldü ve tıklanabilir alana alındı. Oda küçültülünce müzik balonu da görünür kalır.
- Müzik sistemi yeniden yapıldı: tek çalma listesi. "Müzik ekle" ile telefondan bir veya birden çok şarkı seçilir, seçim sırasıyla listeye girer ve odada çalar (hiçbir şey çalmıyorsa ilk şarkı otomatik başlar). Telefonda ayrı dinleme/kitaplık kaldırıldı (iki yerden çalma sorunu bitti). Yetkililer için liste sınırı 40 şarkıya çıktı.
- Profil: Ayarlar en alta alındı (üstteki dişli kalktı). Kullanıcı profilinde kapak yüksekliği küçüldü.

## v2.30.1
- Derleme hatası düzeltildi (kullanıcı arama kutusu, common.dart: const InputDecoration).

## v2.30.0
- Güvenlik: yerleşik Türkçe/İngilizce küfür-hakaret filtresi (BANNED_WORDS boş olsa da çalışır; s1k, a.m.k, siiiik gibi yazım hilelerini yakalar, "sıkıntı" gibi masum sözleri geçirir). Sohbet, DM, biyografi, ad, oda adı, destek mesajı ve akışta geçerli.
- Güvenlik: şifre değiştirme ve hesap silme için kullanıcı başına hız sınırı (15 dakikada 5 deneme).
- Denetim notu: hediye/bakiye işlemleri zaten satır kilidiyle (FOR UPDATE) korunuyor.

## v2.29.0
- Seviye Merkezi: Yayıncı / Kullanıcı seviyesi geçişi, 160 kademeli seviye eğrisi, Mevcut/Gerekli Exp, Ayrıcalıklar tablosu (ödül sütunu henüz boş).
- Yükleme Merkezi (Coins; Gümüş yok): bakiye, coin paketleri (7.000 / 42,99₺ vb.), ödeme yöntemi listesi (ödeme altyapısı henüz bağlı değil uyarısı). Profildeki "Coins Yükleme" kartı buraya açılır.
- Müşteri Hizmetleri Merkezi: konu kutuları + çevrimiçi sohbet (yalnızca yazı). Profilin en üstündeki kulaklık simgesinden açılır.
- Yönetim paneli: "Destek" sekmesi (yönetici + yardımcı admin yanıtlar), "Coin paketleri", hediye / çerçeve / mağaza ürünü SİLME (geçmişte kullanıldıysa gizlenir).
- Hediye eklerken animasyon yüklenince ikon, animasyonun ilk karesinden otomatik PNG olarak oluşturulur (önizlemesi formda görünür; oda hediye panelinde de bu ikon kullanılır).
- WIP 5 adı ateşli git-gel, WIP 4 adı mavi buzlu hareketli renk (oda, koltuk, sohbet, profil).
- Sunucu: migration 024 (seviye yeniden hesap, coin_packages, support_messages), /api/support, /api/store/coin-packages, /api/me/levels.

## v2.28.1
- Yönetim paneli: kullanıcı ID (public ID), kullanıcı adı veya adla bulunur; sonuçta ve kartta ID görünür.
- "Öğe ver": kategori seç (Çerçeve, Rozet, Sohbet Balonu, Giriş Efekti, Mini Kart, Mikrofon Dalgası, Araç) → tüm öğeler önizlemeyle listelenir → seç, gün yaz (0 = süresiz) → Gönder. Elle anahtar yazmak kalktı.
- Mağaza ürünü eklerken "Mağazada satılsın" seçeneği ve Rozet kategorisi (rozetler yalnızca yönetici verir). "Mağaza ürünleri (aç/kapat)" listesi.
- Sunucu: migration 023, /api/admin/grantables, /api/admin/users/:id/grant.

## v2.28.0
- Mağaza (AVM): kategori çubuğu (Çerçeve, Sohbet Balonu, Özel Giriş, Mini Kart, Mikrofon Dalgası, Araç), Coins Mağazası, süre/fiyat, Önizleme, Satın al ve arkadaşa Gönder. Puan Mağazası "yakında".
- Görünüm (eski envanter): kategori çubuğu, Etkinleştir / Kaldır, son kullanma tarihi.
- Gelir Merkezi yeniden tasarlandı: mevcut elmas, Elmas Bozdurma, Para Çekme, son kazançlar, Canlı Kayıt.
- Yayın Özeti (aylık ay seçmeli + günlük), Canlı Yayın Geçmişi (video/sesli sekmeleri, sayfalı tablo), Para Çekme sayfası.
- Yönetim paneli: "Mağaza ürünü ekle" (yükleme + önizleme).
- Sunucu: migration 022 (store_items), /api/store, /api/admin/store/items, /api/me/earnings/summary ve /history.
- Not: sohbet balonu, mikrofon dalgası, mini kart ve araç ürünleri alınıp etkinleştirilebilir; uygulamada görsel etkileri sonraki sürümde.

## v2.27.0
- Profil ekranı Figma'ya göre yenilendi: ortalı çerçeveli avatar, kopyalanabilir ID, Takip edilen / Fanlar / Ziyaretçiler / Arkadaşlar sayaçları, Coins ve Gelir Merkezi kartları, Leveller · Aile · WIP · Görünüm kısayolları, Mağaza · Yayıncı Merkezi · Ajans Merkezi · Günlük Görevler listesi. Ayarlar sağ üstteki dişliye taşındı.
- Envanter adı "Görünüm" oldu. Aile ve Günlük Görevler profile taşındı (ana sayfa menüsünden ve oda araçlarından kaldırıldı).
- Mağaza sayfası eklendi (içerik sonra eklenecek).
- Yayıncı Merkezi (yayıncı olan/başvuracak herkes) ve Ajans Merkezi (yalnızca ajans sahibi) ayrıldı.
- Arkadaşlık sistemi: istek gönder / kabul / reddet / çıkar. Artık yalnızca arkadaşlar mesajlaşabilir.
- Kırmızı rozetler: yeni ziyaretçi, yeni fan, bekleyen arkadaş isteği (sayaçlarda ve alttaki Profil sekmesinde).
- Kullanıcı profili sekmeli: Profil · Başarılar (alınan hediyeler, madalyalar) · Paylaşım · İlişkiler; aile kartı, Top Destekçiler, kullanıcı/yayıncı seviye çubukları.
- Sunucu: migration 021 (friend_requests, visitors_seen_at, followers_seen_at), /api/friends, /api/me/badges, /api/me/seen.

## v2.26.3
- Müzik seçme yalnızca oda sahibi, yardımcı sahip ve moderatörde.

## v2.26.2
- Oda araçları yetkiye göre gizleniyor: sohbet yasağı, tema, mikrofon modu (sahip/yardımcı sahip); sohbet temizleme (yönetici); oda kilidi, gizleme, kapatma, PK (sahip); müzik (yönetici veya mikrofondakiler).

## v2.26.1
- Müzik Kütüphanesi kaldırıldı (uygulama + yönetim panelindeki "Müzik ekle"). Müzik çalar: Müziklerim (telefondan) | Sıra.

## v2.26.0
- Müzik paneli yenilendi: dönen plaklı çalar kartı, ses/ilerleme/kontroller üstte; sekmeler Telefonum | Kütüphane | Sıra; küçült oku.
- Müzik çalarken odada yuvarlak, sürüklenebilir müzik balonu (dönen kapak); dokununca panel açılır.
- Küçültülmüş oda artık yuvarlak, sürüklenebilir balon (kenara yapışır); X ile odadan çıkılır.

## v2.25.2
- Alıcı mikrofonda değil ama odadaysa hediye ikonu seyirci sayısı rozetine uçar.

## v2.25.1
- Hediye uçuşu 20 alıcıya kadar çıkarıldı (koltuk sayısı kadar).

## v2.25.0
- Hediye gönderilince hediyenin PNG ikonu gönderenden alıcı mikrofonlara uçar, ardından tam ekran animasyon oynar (Yoho tarzı).

# Değişiklik ve inceleme raporu

## v2.24.1
- WIP 5 (hareketli avatar özelliği) bitince hareketli profil fotoğrafı otomatik olarak önceki sabit fotoğrafa döner (dakikada bir kontrol; services/avatar_sweeper.js). Hareketli yüklenirken önceki sabit fotoğraf yedeklenir. Migration 020.

## v2.24.0 — WIP 5: hareketli profil fotoğrafı
- WIP 5 özelliği `animatedAvatar`: gif ve animasyonlu webp profil fotoğrafı (en çok 5 MB). Yalnızca WIP 5 yükleyebilir; sunucu 403 ile reddeder. Dosya olduğu gibi (yeniden sıkıştırılmadan) gönderilir, veritabanında saklanır.
- Profil düzenleme ekranında "Hareketli (WIP 5)" düğmesi. Avatar her yerde NetworkImage ile hareketli oynar.
- Migration 019. Yönetici WIP özellik düzenlemesinde `animatedAvatar` anahtarı kullanılabilir.

## v2.23.3
- Mikrofon Modu penceresi: araç penceresi kapandıktan 300 ms sonra, kök Navigator üzerinden açılır; açılamazsa hata mesajı gösterilir. Yetkisiz kullanıcıya uyarı pencerenin altında kalmaz.

## v2.23.2
- Mikrofon modu: seçim anında ekrana uygulanır; sunucu reddederse eski sayıya dönülür ve sunucunun hata mesajı pencerede gösterilir (sessiz başarısızlık kalmaz).

## v2.23.1 — Oda üst başlığı (Figma)
- İzleyici sayısı ve çıkış/küçült (X) düğmesi artık gerçekten en sağ üstte (oda kartı kalan alanı doldurur, kart solda).
- Ailesi olanlarda sağda aile kısayolu (logo + ad); dokununca Aile ekranı. Taç (katkı listesi) kısayolun hemen altında sağda.

## v2.23.0 — Koltukta çerçeve, renkli nick, yeni sahne hesabı
- Sunucu kullanıcı verisine `frameUrl` (takılı çerçeve) eklendi; koltukta avatarın üstünde hareketli çerçeve çizilir.
- Koltuk adı artık WIP renginde ve WIP rozetiyle görünür.
- Sahne düzeni yeniden hesaplanır: her satırın avatar boyutu satıra göre ayrı (üst oda sahibi/az koltuklu satır %20–35 büyük), tüm satırlar mevcut yüksekliğe sığar; 12+ koltukta sahne daha yüksek, sohbet daha kısa. Kaydırma yok.

## v2.22.4
- Hediyede animasyon dosyası tanımlı değilse oda içinde açık uyarı gösterilir (sessizce geçmez).

## v2.22.3
- Telefon belleğine indirme yalnızca hediyeler için. Çerçeveler ve giriş efektleri eskisi gibi doğrudan internetten oynar (AnimAsset cache: false).

## v2.22.2 — Telefon belleğine indirme
- Hediye animasyonları ve çerçeveler ilk kullanımda kullanıcının telefonuna (uygulama önbelleği) indirilir, sonra hep oradan oynar (services/media_cache.dart). Oda açılınca ve hediye paneli açılınca tüm hediyeler arka planda önceden indirilir. Önbellek 400 MB'ı geçerse en eski dosyalar silinir.
- Uygulama paketinde (APK) hiçbir hediye/çerçeve dosyası yoktur; hepsi yönetim panelinden eklenir.

## v2.22.1 — Yönetim panelinden önizlemeli ekleme
- Hediye ve çerçeve formunda dosya yüklenince canlı önizleme gösterilir (çerçeve avatar üstünde).
- Katalog → "Katalog listesi (önizleme)": tüm hediye/çerçeveler hareketli önizlemeyle, açma/kapama ve çerçeve için "Bana ver (dene)". Sunucu: GET /api/admin/catalog.
- Toplu hediye/çerçeve yükleme, telefondan dosya seçme, oynatma hatasında ekran uyarısı (v2.21.x) korunur.
- Pakete gömülü hazır içerik (v2.22.0) geri alındı; her şey yönetim panelinden eklenir.

## v2.21.3
- Katalog: "Toplu hediye yükle" ve "Toplu çerçeve yükle". Birden fazla dosya seçilir; ad dosya adından, fiyat/sekme tek seferde girilir; sonunda hangi dosyanın neden eklenmediği listelenir.

## v2.21.2
- svgaplayer_flutter paketi kaldırıldı (http sürümüyle çakışıp derlemeyi durduruyordu). SVGA 2.x için dış paketsiz kendi oynatıcımız eklendi (widgets/svga_lite.dart): görsel katmanlar, konum/ölçek/dönüş/saydamlık. Desteklenmeyen: vektör şekiller, matte maskesi, gömülü ses.

## v2.21.1
- Çerçeve olarak şeffaf mp4 (VAP) desteği; mp4 çerçeve ve avatar efekti döngüde oynar.
- Hareketli PNG (APNG) yüklemesi açık mesajla reddedilir (Flutter oynatamaz); webp/gif/svga kullanın.

## v2.21.0 — Hediye ve çerçeve dosyası yükleme
- Yönetici → Katalog: hediye ikonu/animasyonu ve avatar çerçevesi telefondan seçilip yüklenir (40 MB'a kadar). Dosyalar veritabanında saklanır (sunucu yenilense de kaybolmaz).
- Sunucu türü uzantıdan değil içinden anlar: svga 2.x, mp4, Lottie json (birleşik), webp, gif, png, jpg. PAG, WebM, svga 1.x ve görselleri dışarıda olan Lottie açık bir mesajla reddedilir.
- Yan yana şeffaf mp4'e eksik VAP ayar kutusu (vapc) otomatik eklenir; şeffaflık solda/sağda seçilebilir.
- Oynatıcı: svga (yeni paket svgaplayer_flutter), Lottie, VAP mp4, webp/gif/png. Avatar çerçeveleri hareketli (döngü) oynar. Giriş efekti de aynı oynatıcıyı kullanır.
- Migration 018 (media_files).

## v2.20.0 — Sabit koltuk sahnesi, yeni oda başlığı, çanta tasarımı
- **Koltuklar kaymaz (YoHo mantığı):** Sahne artık kaydırılmaz. Avatar boyutu, sahne yüksekliği ve genişliğine göre hesaplanır; her koltuk modu (2…20) ekrana sığar. 3 satıra kadar elmas rozeti, daha fazla satırda gizli. Az koltuklu üst satır Figma'daki gibi geniş aralıklı ortalanır. Hızlı dikey fling hâlâ odayı değiştirir; sahne oynamaz. İzleyiciler artık sahnede değil, üstteki izleyici sayısından açılan listede.
- **Oda başlığı (Figma):** kapak fotoğraflı oda rozeti + başlık + `ID:oda numarası`; sağ üstte izleyici sayısı ve en sağda çıkış X; alt satırda elmas toplamı, favori ve **taç = Katkı Listesi** (24 Saat / Toplam sekmeleri, ilk 3 kürsü, 4+ liste).
- **Oda kartı:** başlığa dokununca kapak, başlık, Oda Duyurusu, Oda İsim Kartı (renkli etiketler), yöneticiler. Oda sahibi/yardımcı **Düzenle** ile kapak resmi, başlık, duyuru, etiketler (en fazla 3) değiştirir, oda sahibi yönetici siler. Bilgiler kalıcı odaya da kaydedilir (migrasyon 017).
- **İzleyiciler** penceresi Figma'ya uygun yeniden tasarlandı.
- **Şanslı çanta:** Normal çanta süresiz/hemen açılır. Süper çanta Figma'daki pembe kartta 60 sn geri sayar, bitince **AÇ** olur (geri sayımda not sohbete yazılır), sonra 120 sn açılabilir. Odada sol üstte kırmızı zarf (rozet=açık çanta), oda listesinde 🧧 işareti. Süper çanta duyurusu ve global hediye şeridi artık sağdan sola kayan şerit olarak tüm odalarda ve ana ekranda görünür.
- **Giriş şeridi:** WIP giriş şeridi kendi girişinde de gösterilir.
- **Mikrofon modu:** seçim sonrası sunucudaki gerçek koltuk sayısı yeniden okunur ve üyeler yenilenir; liste Figma'daki gibi 2/5/8/9/12/15/20.
- Not: global hediye şeridi yalnızca alıcı başına en az `GLOBAL_GIFT_MIN_COINS` (varsayılan 1000) Coin'lik hediyelerde çıkar; küçük hediyelerde çıkmaz. Render ortam değişkeniyle değiştirilebilir.

## v2.19.0 — Günlük Görev ve Şanslı Çanta
- **Günlük Görev** (araçlar > Günlük Görev): 4 görev (odaya gir, mikrofona otur, 5 mesaj yaz, hediye gönder). Her görev 10 XP; günün tüm görevleri bitince seri ilerler, 1-6. günlerde +50 XP, **7. gün 1.000 Coin**. Gün aksatılırsa seri sıfırlanır. Gün, Türkiye saatine göre (gece 00:00) değişir.
- **Şanslı Çanta** (araçlar > Şanslı Çanta): Normal 3.000/6.000/9.000 Coin = 10/20/30 kişilik, 120 sn. **Süper** 30.000/60.000/90.000 Coin = 50 kişilik, 60 sn; gönderen not yazar, açmak isteyenler notu sohbete bir kez yazdıktan sonra açabilir; duyuru tüm odalarda altın şerit olarak görünür. Pay rastgele bölünür (herkese en az bir pay), kendi çantanı açamazsın, kişi başı bir kez. Süre dolunca dağıtılmayan Coin göndericiye iade edilir. Aynı anda tek açık çanta gönderilebilir.
- Ayarlar tek yerde: `backend/src/services/rewards_config.js`. Migrasyon 016. Cüzdan geçmişinde yeni işlem türleri.

## v2.18.1 — Derleme düzeltmesi
- `room_screen.dart` başlık satırında Favori düğmesinden sonra eksik virgül (Dart: "Expected 'else' or comma") giderildi.

## v2.18.0 — Sabit koltuk çerçevesi, kimlikler, elmas bozdurma, giriş şeridi
- **Koltuk kayması (YoHo gibi sabit):** Kayma/küçülmenin nedeni konuşma halkasının avatarın etrafına boşluk+çerçeve ekleyip hücreyi büyütmesiydi. Artık her koltuk sabit boyutlu bir çerçevedir (avatar yuvası, isim satırı, elmas rozeti yeri hep ayrılı); konuşma halkası aynı boyutlu saydam bir bindirmedir. Oturma/kalkma/konuşma hiçbir koltuğu oynatmaz. Avatar 56/48/40 dp, aralık 8 dp. Başlık ile mikrofonlar arasındaki boşluk daraltıldı.
- **Oda ayarları tek yerde:** Başlıktaki "Ayarlar" rozeti ve araçlardaki "Oda Ayarları" kaldırıldı; oda adına dokununca açılan pencerede (ad, etiket, yöneticiler + "Oda ayarları" satırı) toplandı.
- **Mikrofon modu:** 4 ve 6 koltuk seçenekleri eklendi (sunucu zaten destekliyordu); değişince yerel durum anında güncellenir ve üyeler yeniden yüklenir.
- **Koltuktan Kalk:** Mikrofondayken kendi koltuğuna dokununca Zula'daki gibi sayfa açılır (Koltuk #n • rol, Koltuğu sessize al, Koltuktan Kalk, İptal; üst satır profile gider).
- **Başlık:** Oda kapatma/çıkış X en sağ üstte; taç küçüldü (24); üye sayısı ikinci satıra taşındı.
- **Kimlikler:** Her kullanıcıya 8 haneli benzersiz ID (`publicId`); yönetici hesabında ID `admin`. Her kalıcı odaya 7 haneli değişmez oda numarası (`roomNumber`; oda temaları/ödülleri için). Mevcut kayıtlar migrasyon 015 ile doldurulur. Oda başlığında ve oda bilgisinde gösterilir.
- **Elmas bozdurma:** `POST /api/me/diamonds/exchange` — 5 Elmas = 1 Coin (5 ve katları), tek işlemde kilitli, cüzdan kaydı tutulur. Onaylı yayıncılar bozduramaz (maaş alır). Arayüz: Profil > Cüzdan ve Elmas Bozdurma.
- **Oda giriş efekti:** WIP 1–5 için ayrı tasarımlı, odanın ortasından geçen şerit (renk, parıltı, süre WIP ile artar; WIP 5 kırmızı-altın taçlı). Girişler sıraya alınır. WIP 5 renkli ismi kırmızı (#FF2B2B).
- Varsayımlar: oran 5 Elmas = 1 Coin; onaylı yayıncı bozdurmaz (kolay değiştirilir).

## v2.17.5 — APK derleme kökten düzeltme + tokensiz güncelleme
- **APK (checkReleaseAarMetadata):** `flutter_plugin_android_lifecycle` compileSdk 36 ister, `file_picker` ise android-34 ile derleniyordu. `apk_build.yml` artık `android/build.gradle(.kts)` başına tüm alt projeleri compileSdk 36'ya zorlayan bir blok ekliyor (tekrar çalışsa da bir kez eklenir). Böylece bu ve benzeri eklenti uyumsuzlukları kökten kapanır.
- **Güncelleme (token gerekmez):** yeni `.github/workflows/zip_ile_guncelle.yml`. Depoya GitHub sitesinden (Add file > Upload files) `TR-Live-v....zip` dosyasını ana dizine yüklemek yeter; iş akışı zip'i açar, projeyi birebir eşitler, zip'i siler ve APK derlemesini başlatır. `.github/workflows` klasörü GitHub kuralı gereği buradan güncellenemez; iş akışı dosyaları değiştiyse elle yüklenir.

## v2.17.3–2.17.4 — Yayıncı hedefi yalnızca yayıncı olduktan sonra
- **Kural:** Maaş hedefi (yayın süresi + Diamond) yalnızca **onaylı yayıncılar** için ve **yayıncı onayından sonraki** süre/hediyelerden hesaplanır. Ajansa katılma tarihi belirleyici değildir. Yayıncı olmayan kullanıcının hedefi/maaşı 0'dır; yalnızca Diamond'larını bozdurabilir.
- `hostMetrics` (hedef ekranı, ajans paneli, dönem kapanışı) buna göre düzeltildi; ajans e2e testi bu kurala göre yazıldı.
- Not: Diamond bozdurma (Diamond → Coin) özelliği henüz yok; oran belirlenince eklenecek.

## v2.17.2 — Derleme ve gizli oda düzeltmeleri
- **APK derleme hatası:** `NotificationVisibility` hem `flutter_foreground_task` hem `flutter_overlay_window` paketinde tanımlı olduğundan Dart "imported from both" hatası veriyordu (`background_service.dart`). Ön plan servisi paketinden bu ad gizlendi; balon için overlay paketininki kullanılıyor.
- **Gizli oda sızıntısı (sunucu):** `GET /api/rooms/:id` sorgusunda oda `is_hidden` alanı, sahibin `u.is_hidden` (gizli kullanıcı) alanıyla aynı adı taşıyordu; ikincisi birinciyi eziyor, gizli odanın ayrıntısı odada olmayan herkese açık dönüyordu. Oda alanı `room_hidden` takma adıyla alınıyor. (e2e testinde "expected 404, actual 200" hatasının nedeni buydu.)

## v2.17.1 — İzleyici kulübesi
- Oda başlığının sağında, odadaki en yüksek seviyeli ilk 3 kullanıcının üst üste binen altın çerçeveli avatarları görünür; dokununca üye listesi açılır.

## v2.17 — Oda içi ekran mekaniği (YoHo / Yalla ölçüleri)
- **Dikey bölünme:** üst başlık (~%15) · koltuk sahnesi (~%40) · canlı sohbet (~%35) · alt bar (~%10). Sahne ve sohbet oransal (flex 40 / 35) olduğundan her telefon boyunda aynı düzen korunur.
- **Klavye:** `resizeToAvoidBottomInset: false`; klavye açılınca koltuklar yukarı fırlamaz, yer sohbet bölgesinden alınır.
- **Koltuk ölçüleri:** ≤6 koltukta avatar 56dp, 8–9 koltukta 48dp, 12/15/20 koltukta 40dp (yazılar ve elmas rozeti de küçülür); koltuklar arası 8dp; avatarın çevresinde 3dp boşluk (konuşma/hediye halkası buraya oturur); uzun adlar `ellipsis` ile kesilir.
- **Hediye paneli:** alttan ekranın ~%45'ini kaplar, arkası kararmaz; koltuklar hediye seçerken de görünür.
- Not: Ölçüler kaynak olarak bir yapay zekâ özetine dayanır; telefonda görünce oranlar (%40/%35, avatar boyutları) tek satırlık değişiklikle ayarlanabilir.

## v2.16 — Telefondan müzik çalar
- **"Telefonum" sekmesi** (müzik panelinde): telefonun hafızasındaki mp3/m4a/aac/ogg/wav/flac dosyalarını seçip listeye ekler (sistem dosya seçici; ek izin gerekmez). Liste telefonda kalıcıdır, silinen dosyalar otomatik düşer. Arama, süre/boyut bilgisi, **telefonda dinle** (yalnızca kendin) ve listeden kaldırma var.
- **Odada çal:** yetkili (sahip / yardımcı / moderatör) şarkıyı tek dokunuşla odaya çalar; mikrofondaki kullanıcı sıraya ekler. Dosya sunucuya geçici yüklenir (en fazla 25 MB), odadaki herkes mevcut senkron müzik altyapısıyla aynı saniyede dinler; ilerleme çubuğu, duraklat, sonraki ve ses ayarı aynen çalışır.
- **Sunucu:** `POST /api/rooms/:id/music/upload` (ham ses; türü ilk baytlardan doğrular, kullanıcı başına 5 aktif parça, 10 yükleme/10 dk). Parçalar `is_temp` olarak işaretlenir, ortak kütüphanede görünmez, yalnızca yüklendiği odada çalınır, 12 saat sonra (çalmıyorsa/sırada değilse) dosyasıyla silinir. Migrasyon 014.
- **Sınır:** Telefonun sesini canlı olarak LiveKit'e aktarmak (Zula'daki "ses karıştırma") bu sürümde yok; bunun yerine dosya yüklenip herkeste senkron çalınır. Bu yöntem arka planda ve kötü ağda daha kararlıdır.

## v2.15 — Oda içi arayüz (Figma üst satır / alt satır)
- **Üst satır:** oda sahibinin avatarı + oda adı (dokununca oda bilgileri ve yöneticiler) + ID, dinleyici sayısı (dokununca üye listesi), X düğmesi. X → tam ekran **Küçült / Çıkış** seçimi.
- **İkinci satır:** odadaki toplam elmas sayacı, Favori (oda sahibine Ayarlar) rozeti, sağda altın taç (sıralamalar).
- **Sohbet:** kartlar halinde; avatar, ad, seviye rozeti, WIP. Yüksek seviyeli kullanıcıların mesajı mor / turuncu kart. Karta dokununca kullanıcı kartı açılır.
- **Alt satır:** 6 yuvarlak düğme: Sohbet (yazı alanını açar), Emoji, Oda sesi aç/kapat (yalnızca kendi cihazında), Mikrofon (konuşurken sustur/aç, uzun basınca mikrofondan in; mikrofonda değilken mikrofona çık / sıraya gir), Hediye, Oda araçları. Görüntülü odada kamera düğmesi de çıkar.
- Eski üst çubuk (AppBar) kaldırıldı; Odayı Kapat artık Oda araçlarında (yalnızca oda sahibi).

## v2.14.1 — "Oda bulunamadı" hatası
- **Neden:** Sunucu, odadaki kişinin canlı olup olmadığını yalnızca WebSocket aboneliğinden anlıyordu. Abonelik düşerse (ağ geçişi, sunucunun uyanması vb.) birkaç dakika sonra oda sahibi çıkarılıyor ve oda kapanıyordu; uygulama ise bunu öğrenemeyip kapalı odada kalıyor, her işlemde "Oda bulunamadı." diyordu.
- **Çözüm:** Uygulama odadayken her 25 sn'de HTTP "heartbeat" gönderir (`POST /api/rooms/:id/heartbeat`; `room_members.last_seen_at`, migrasyon 013). Temizleyici yalnızca WebSocket de heartbeat de uzun süredir yoksa çıkarır (üye 5 dk, oda sahibi 15 dk). Heartbeat oda kapanmışsa 404 döner; uygulama o zaman "Oda kapandı." deyip odadan çıkar, ölü odada takılmaz. Heartbeat aboneliği de yeniler.

## v2.14 — Arka planda çalışma, odadan düşmeme, yüzen balon, çökme koruması
- **Odadan düşme / oda kapanma nedeni bulundu ve düzeltildi:** uygulama arka plana alınınca telefon bağlantıyı kesiyordu; sunucudaki temizleyici üyeyi hemen odadan çıkarıyordu (oda sahibiyse oda kapanıyordu). Artık bağlantısı kopan üye hemen atılmaz: üye 5 dk, oda sahibi 15 dk beklenir; geri bağlanınca sayaç sıfırlanır (`ROOM_GRACE_SECONDS`, `ROOM_OWNER_GRACE_SECONDS`).
- **Arka planda çalışma:** odadayken bildirimli bir ön plan servisi çalışır (oda sesi kesilmez; mikrofondaysanız mikrofon da açık kalır). Pil kısıtlaması ve bildirim izni ilk odada sorulur.
- **Diğer uygulamaların üzerinde yüzen balon:** uygulamadan çıkınca ekranda mikrofon balonu kalır (sürüklenebilir); dokununca uygulamaya dönülür. "Diğer uygulamaların üzerinde göster" izni ilk odada sorulur; Profil > "Arka plan ve balon izinleri"nden tekrar istenebilir.
- **Geri dönünce:** bağlantı hemen yenilenir, üyeler ve sohbet güncellenir. Ağ kesintisinde oda açık kalır, 5 sn arayla yeniden denenir (yalnızca sunucu açıkça reddederse odadan çıkarılır).
- **Çökme koruması:** yakalanmamış hatalar uygulamayı kapatmaz, kayda geçer. Profil > "Hata kaydı"ndan görülüp kopyalanabilir.
- Derleme akışı Android manifestine servisleri ve izinleri ekler.

## v2.13 — Oda içi kullanıcı kartı
- Odada bir kullanıcıya dokununca Figma'daki gibi kart açılır: üstte taşan büyük avatar (dokununca tam profil), ad, seviye / hediye seviyesi / WIP / rol / aile rozetleri, kopyalanabilir kimlik, **Yakın Arkadaşlarım** (ona en çok hediye gönderen 5 kişi), **Madalyalar** (rozet envanteri), Etiketle (sohbete @ad yazar), Hediye Gönder, Takip Et.
- **Yetkiye göre görünür:** Yönetici (moderatör / yardımcı sahip ata, yetkiyi al — yalnızca oda sahibi ve yardımcı sahip), Mic Aç / Mic Kapat, Sohbet (10 dk / 1 saat / 1 gün sustur, kaldır), Koltuk (koltuktan indir ve kilitle), Odadan At — yalnızca hedeften üst yetkisi olana görünür. Normal kullanıcı bu düğmeleri hiç görmez. Sunucu aynı kuralları ayrıca denetler.
- Sol üstteki ünlem: Şikâyet et, Kullanıcıyı engelle, (yetkiliye) Bu odadan engelle.
- Sunucu: `GET /api/users/:id/card`.

## v2.12 — Boyut ve ölçü standartları
Android / Material 3 standartlarına göre düzenlendi:
- **Yazı ölçeği:** Material 3 tablosu (gövde 14/16, etiket 11-12, başlık 16-22 sp, satır yüksekliğiyle). 10 sp'lik küçük yazılar 11 sp'ye çıkarıldı.
- **Dokunma hedefi:** tüm düğmeler en az 48×48 dp (düğme yüksekliği 46 → 48).
- **Kontrast:** soluk yazı rengi WCAG AA (4.5:1) için açıldı; çok soluk `white38` yazılar `white54` oldu.
- **Pencere sınıfları:** compact < 600, medium 600-839, expanded 840-1199, large ≥ 1200 dp. Ekran kenar boşluğu 16 / 24 / 32 dp (ana sayfa ızgarası ve banner buna uyar). Oda kartı sütunları 2 / 3 / 4 / 5.
- **Sistem yazı boyutu:** kullanıcının ayarı 0.85–1.3 kat arasında uygulanır (önceden 1.25).

## v2.11 — Hediye paneli ve şeffaf MP4 hediye animasyonu
- **Yeni hediye paneli (Figma):** üstte mikrofondaki kişilerin avatarları (koltuk numarasıyla; seçili olan pembe halkalı), ok düğmesiyle odadaki herkesi göster; sekmeler Etkinlik / Popüler / Kişiye Özel / Vip; sayfalı 4'lü hediye ızgarası (seçili hediye pembe çerçeve); altta bakiye (cüzdana gider), adet seçici ve Gönder.
- **Alıcı seçimi:** tek kişi, birden çok kişi (HER birine seçilen adet gider, toplam = fiyat × adet × kişi), "Listele" menüsünden **Tüm Koltuk** (mikrofondakiler) ve **Tüm Oda** (kendin hariç, en fazla 50 kişi). Sunucu: `distribution: each | all_mic | all_room`.
- **Şeffaf MP4 hediye:** hediyeye animasyon adresi (.mp4) girilince odadaki herkeste tam ekran oynar. Format Tencent **VAP** (alfa kanallı H.264 MP4) olmalıdır; Lottie ve WebP/GIF de desteklenir. Animasyonlar sırayla oynar.
- **Hediye sekmesi:** `gifts.category` (migrasyon 012). Yönetici panelinde hediye eklerken sekme ve animasyon biçimi seçilir.
- Hediye listesi yanıtına `globalMinCoins` eklendi (dünya simgesi bu tutarın üstündeki hediyelerde görünür).

## v2.10 — Oda içi araçlar penceresi, mikrofon modu, koltuk yerleşimi
- **Oda araçları:** alt çubuktaki ⊞ düğmesi kayar pencere açar. İnteraktif Özellikler (PK, Oyunlar) ve Temel Araçlar: Yayını Paylaş (davet metnini kopyalar), Efekt ve Ses, Sohbet Yasağı/Açma, Müzik, Sohbet Temizleme, Oda Kilidi (şifre), Özel Temalar, Oda Gizleme, Mikrofon Modu, Oda Ayarları. Yetkisi olmayana uyarı verir.
- **Mikrofon Modu:** 2/5/8/9/12/15/20 mikrofon; seçince koltuk sayısı herkes için canlı değişir. Azaltınca taşan koltuktakiler dinleyiciye iner. `PATCH /api/rooms/:id {seatCount}` (oda sahibi / yardımcı sahip).
- **Koltuk yerleşimi** Figma'daki gibi: 5 → 1+4, 9 → 1+4+4, 12 → 2+5+5, 15 → 5×3, 20 → 5×4; kısa satırlar ortalanır.
- **Hata düzeltmesi:** oda sahibi başka koltuğa geçince kendi 0. koltuğuna geri dönemiyordu; artık dokunarak dönebilir.
- Henüz yok ("çok yakında" uyarısı verir): Günlük Görev, Şanslı Çanta.

## v2.9 — Kalıcı oda, şifresiz kurulum, yerleşim düzeltmesi
- **Yerleşim düzeltildi:** üst satır = TRLive tacı + oda aç düğmesi; alt satır = Sesli | Akış | Görüntülü | Mesajlar | Profil.
- **Oda bir kez kurulur:** ilk "Sesli oda aç / Görüntülü yayın aç"ta ad, etiket, koltuk düzeni ve tema sorulur. Sonraki açışlarda tek dokunuşla doğrudan odaya girilir; ad ve etiketler sabit kalır.
- **Şifre kurulumdan kaldırıldı;** yalnızca oda içindeki ayarlardan konur/kaldırılır.
- **Oda adına dokununca** "Oda bilgileri" açılır: sahip/yardımcı sahip ad ve etiketleri düzenler, herkes oda yöneticilerini görür.
- **Banner sonsuz döngü:** birden fazla banner hep ileri kayar; sonuncudan sonra yine ilkine geçer.
- Yöneticiler (yardımcı sahip, moderatör) oda kapanınca da korunur. Sunucu: `room_profiles`, `room_staff` (migrasyon 011), `GET /api/rooms/mine`, `GET /api/rooms/:id/managers`.

## v2.8 — Üst satır / alt satır düzeni
- **Üst satır:** Sesli | Akış | Görüntülü | Mesajlar | Profil. Alt menü kaldırıldı.
- **Alt satır:** altın taç + "TRLive" (sıralamaları açar) ve oda açma düğmesi. Sesli tarafta "Sesli oda aç", görüntülü tarafta "Görüntülü yayın aç".
- **Sıralamalar:** Günlük / Haftalık / Aylık × Yayıncı, Destekçi, Ajans, Aile, Oda, CP. Sunucu: `GET /api/leaderboards?type=receivers|senders|agencies|families|rooms|cp&period=daily|weekly|monthly`.
- Aile, favoriler, gizli odaya kodla giriş ve kullanıcı arama oda listesindeki ⋮ menüsünde.

## v2.6 — Figma (HİLLİVE) yerleşimine geçiş, 1. aşama
- Alt menü: Party | Keşfet | Giriş Sayfası | Mesajlar | Profil. Aile, liderlik, favoriler, kodla giriş ve kullanıcı arama "Giriş Sayfası"nda.
- Party ana sayfası: Takip / Popüler / Yakında sekmeleri, dikey görsel kartlar (tür rozeti, etiket, dinleyici sayısı, altında başlık).
- Yayın başlat: Sesli / Görüntülü seçimi tek pencerede.
- Giriş ekranı Figma düzenine yaklaştırıldı (taç + logo, hap butonlar). Renkler uygulamanın kendi temasıdır.
- Sunucu: `region=near` (aynı şehirdeki yayıncılar).

## v2.7 — Figma yerleşimi, 2. aşama
- **Keşfet gönderi akışı:** gönderi (yazı + görsel), beğeni, yorum, "Takip Edilen | Genel" sekmeleri; başkasının profilinde "Paylaşım" sekmesi. Uçlar: `GET/POST /api/posts`, `PUT /api/posts/image`, `DELETE /api/posts/:id`, `POST|DELETE /api/posts/:id/like`, `GET|POST /api/posts/:id/comments`. Gönderi sahibi veya yetkili (admin/yardımcı admin) siler.
- **Banner:** ana sayfanın üstünde kayan banner. Yönetici panelinde "Banner/Duyuru" sekmesinden yüklenir. Uçlar: `GET /api/banners`, `/api/admin/banners` (GET, PUT image, POST, PATCH, DELETE).
- **Mesajlar kartları:** Arkadaşlık isteği (yeni takipçiler), Ekip, Etkinlik duyurusu, Ödül bildirimleri; okunmamış rozetleri. Uçlar: `GET /api/announcements`, `GET /api/inbox-summary`, `POST /api/inbox-summary/seen`, `POST|DELETE /api/admin/announcements`.
- **Koltuk düzeni:** 4 ve 6 koltuk eklendi (migration 010); oda açarken düzen önizlemesi.
- Migration 009 (gönderi, banner, duyuru) ve 010 (koltuk düzenleri).

## v2.5 — Yeni tema ve duyarlı (responsive) ana sayfa
- Tüm uygulama tek renk kaynağına bağlandı: `mobile/lib/widgets/app_theme.dart` (koyu lacivert zemin, turkuaz vurgu, pembe CANLI rozeti, altın bildirim). Renk değiştirmek için yalnızca bu dosya düzenlenir.
- Ana sayfa yeniden tasarlandı: yuvarlak aksiyon düğmeleri, Trend / Arkadaşlar anahtarı, Global / Türkiye / Diğer bölge çipleri, görselli 2 sütunlu oda kartları.
- Duyarlılık: sütun sayısı ekran genişliğine göre (2–5), yazı ölçeği sınırlandı (0.85–1.25), geniş ekranda içerik ortalanır, oda koltuk ızgarası genişliğe uyar.
- Sunucu: `GET /api/rooms` artık `region` (`tr` | `other` | `friends`) kabul eder ve `themeImageUrl` döndürür.

## Orijinal kodda bulunan kritik hatalar (düzeltildi)
1. **Bakiye sızıntısı:** odaya giriş ve hediye şeridi olaylarında herkese Coin/Diamond bakiyesi yayınlanıyordu.
2. **`JWT_SECRET` yoksa üretimde bile `dev-only-change-me` kullanılıyordu.** Artık üretimde 32+ karakter zorunlu.
3. **Aile katılımı:** başka bir ailedeyken katılmak sessizce "başarılı" dönüyordu; sahip ayrılmayı denediğinde de sessiz başarı vardı. Aile üye sıralaması alfabetik (yanlış) yapılıyordu.
4. **Mikrofon sistemi yoktu:** koltuk alma/bırakma uç noktası olmadığı için "eşit/rastgele dağıtım" yalnızca oda sahibine çalışıyordu.
5. **Deadlock riski:** karşılıklı hediyelerde kilit sırası tutarsızdı. Artık tüm satırlar tek sorguda sıralı kilitleniyor.
6. **Giriş efekti** seçilen değil en yeni öğeyi kullanıyordu.
7. **Yetki:** `support` rolü Coin düzenleyebiliyordu; artık para/katalog işlemleri yalnızca `admin`.
8. **Girdi doğrulama:** `BigInt("0x10")` gibi girdiler kabul ediliyor, geçersiz UUID 500 hatası veriyordu, uzun alanlar DB hatasına düşüyordu.
9. **Kullanıcı adı** büyük/küçük harf duyarlıydı (`Ali` ≠ `ali`).
10. **Bayi sınırsız:** `commission_bps` kullanılmıyor, bayi sahibi kendi satışını yapamıyordu; katalog (hediye/çerçeve/efekt) için admin uç noktası yoktu.
11. **Çoklu cihaz/bağlantı:** WebSocket kaydı kullanıcı başına tek soketti, ölü bağlantılar temizlenmiyordu; odaya abonelik yetkisiz yapılabiliyordu.
12. **Operasyon:** migration çalışma dizinine bağlıydı, CI var olmayan `package-lock.json`'a dayanıyordu, Dockerfile root çalışıyordu, DB SSL zorla `rejectUnauthorized:false`'tı.
13. **Flutter:** çıkış yap ana ekranda `Navigator.pop` ile çöküyordu; hiçbir ekranda hata yönetimi yoktu; LiveKit hiç bağlanmıyordu (ses/görüntü yok); hediye gönderme arayüzü yoktu; global şerit hiç görünmüyordu; boş asset klasörleri git'te kaybolur ve derlemeyi bozar; `android/ios` klasörleri yoktu.

## v2.4 — roller ayrıldı
**Dört ayrı rol** (karıştırılmaz):
- **Admin (yönetici):** uygulama sahibi; admin panelindeki her şey.
- **Yardımcı admin:** yalnızca admin, admin panelinden (Yetkililer sekmesi) atar/alır. Yetkisi: kullanıcının **nickini** ve **profil fotoğrafını** değiştirmek/kaldırmak, **süreli veya süresiz ban** atmak/kaldırmak. Para, WIP, ajans, maaş, katalog, güvenlik, şikâyet ekranlarına giremez; admini ve diğer yardımcıları banlayamaz. (Sunucuda `staff_logic.js` içindeki izin listesiyle zorlanır.)
- **Oda sahibi:** yayını açan kişi.
- **Moderatör:** yalnızca oda sahibi (ve yardımcı sahip) atar. Yetkisi: sohbeti silme/temizleme, susturma, mikrofona davet, koltuk kilitleme/açma, koltuktan kaldırma, normal kullanıcıyı odadan atma/engelleme. Rol dağıtamaz, oda sahibine dokunamaz.
Ayrıca v2.4: **oda küçültme** (oda arka planda açık kalır, ses kesilmez; küçük çubuktan geri açılır/kapatılır), **yukarı/aşağı kaydırarak oda değiştirme** (oda sahibi hariç, şifreli odalar atlanır), **oda arama** (ad, yayıncı, etiket), **favori yayıncılar** ve **son girilen odalar** (★ ekranı; oda kapanınca silindiği için favori yayıncı bazlıdır), **mikrofon sırası** (boş koltuk yoksa "Sıraya gir"; koltuk boşalınca sıradaki davet alır, kabul ederse oturur). Migration 008.
Yeni: süreli ban (`banned_until`, süre dolunca otomatik açılır, giriş ekranında neden/bitiş gösterilir), kilitli koltuklar (`rooms.locked_seats`), mikrofon daveti (`mic_invite` olayı). Eski `/admin/users/:id/status` kaldırıldı → `/ban` ve `/unban`. Migration 007.

## v2.3 — yeni eklenenler
Gizli oda + davet kodu · oda temaları (WIP 4 özel görsel) · koltuk başına hediye sayacı · sohbet temizleme (sahip/moderatör) · PK karşılaşmaları ·
oda içi Ludo (sunucu-otoriter, bahissiz) · **ajans sistemi yeniden yazıldı:** ajans kodu, yayın saati takibi, maaş kademeleri, kesinti, kademeli komisyon,
resmi etkinlikler, dönem kapatma + hesap özetleri, KYC şartı · APK için `.github/workflows/apk_build.yml`.
Kendine hediye artık ajans/maaş, PK ve liderlik hesabına SAYILMAZ (suistimal önlemi); eski hediye-başı komisyon (`agency_commissions`) kullanımdan kalktı.
Okey yapılmadı (yalnızca Ludo).

## v2.2 — yeni eklenenler
Müzik çalar · oda içi yazılı sohbet · özel mesaj · oda etiketleri/şifre/ayarlar · engelleme/şikâyet/gizlilik · liderlik tabloları · **uygulama içi güvenlik duvarı** ·
Nginx/UFW/fail2ban/Docker Compose altyapısı · uçtan uca test paketi · GitHub Actions (backend + e2e + Flutter analiz).

## v2.1 — yeni eklenenler
Kendine hediye · WIP 5 kademe + satın alma · ajans/yayıncı sistemi (başvuru, davet, panel, komisyon, ödeme işaretleme) · zengin profil
(avatar/kapak yükleme, takip, ziyaretçi, çerçeve) · aile yönetimi · oda moderasyonu · bayi paneli · yönetim paneli · hesap silme ·
şifre değişince oturumları geçersiz kılma · cüzdan geçmişi · yasaklama.

## Doğrulama durumu (dürüst özet)
| Konu | Durum |
|---|---|
| Saf mantık + güvenlik duvarı ara katmanı (sahte istek/yanıtla) | 50 birim testi geçiyor (`npm test`) |
| Migrasyonlar 001–006 ve 006'daki ana SQL sorguları | Gerçek PostgreSQL 16'da elle çalıştırıldı, hata yok |
| Uçtan uca testler (`backend/e2e`, 19 senaryo) | **Yazıldı, çalıştırılmadı** — GitHub Actions'ta gerçek Postgres ile çalışır |
| Tüm backend modülleri import ediliyor, route'lar kayıt oluyor | Doğrulandı (sahte paketlerle) |
| İstemci ↔ sunucu uç nokta uyumu | 105 çağrı eşleştirildi |
| Dart sözdizimi (parantez/string), import'lar | Betikle tarandı |
| **SQL sorguları gerçek PostgreSQL'de** | **Çalıştırılmadı** |
| **Flutter derlemesi / LiveKit bağlantısı** | **Denenmedi** |

## Eksikler (mağaza ve gerçek kullanım öncesi)
Ayrıntılı ve öncelikli liste: [`docs/COMPARISON.md`](docs/COMPARISON.md). Başlıcalar: uygulama içi satın alma (Play/App Store) ·
telefon/Google/Apple girişi ve şifre sıfırlama · push bildirim · PK/oyunlar/karaoke · SVGA · web yönetim paneli ·
Redis/çoklu sunucu · ajans ödeme/maaş otomasyonu · yaş kapısı ve KVKK metinleri · token'ın `flutter_secure_storage` ile saklanması · yük testleri.

## v2.3.1
Yasaklı kelime denetimi artık yalnızca sohbet/DM'de değil; oda adı, kullanıcı adı/görünen ad, biyografi, aile adı ve ajans adında da uygulanır (`backend/src/safe_text.js`).
