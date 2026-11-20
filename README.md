# BIST Asistan

BIST hisselerini tarayan ve **sanal parayla** (gerçek işlem yok) al-sat deneyen asistan.

- `tarayici/calistir.py`: veriyi çeker, hesaplar, 3 stratejiyi ayrı sanal kasalarla paralel dener.
- GitHub Actions seans saatlerinde (hafta içi 10:00-18:00) her 15 dakikada çalıştırır, sonuçları `veri/` klasörüne yazar.
- `veri/durum.json`: uygulamanın okuduğu güncel durum. `veri/gecmis.json`: kasa grafiği.
- Fiyatlar ücretsiz kaynaktan (Yahoo Finance), genelde ~15 dakika gecikmeli.
- Her işlemde komisyon ve fiyat farkı hesaba katılır; her pozisyonda zarar kes vardır.
- Endeks 50 günlük ortalamanın altındaysa yeni alım yapılmaz.

Bu bir yatırım tavsiyesi değildir.
