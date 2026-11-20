import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kTaban =
    'https://raw.githubusercontent.com/elnino9000/Bist-asistan/main/veri/';
const double kSunucuPara = 100000.0;

const Map<String, String> kAdlar = {
  'trend': 'Trend takibi',
  'geri_donus': 'Geri dönüş',
  'kirilim': 'Kırılım',
};
const Map<String, Color> kRenkler = {
  'trend': Color(0xFF4FC3F7),
  'geri_donus': Color(0xFFFFB74D),
  'kirilim': Color(0xFFBA68C8),
};
const Color kYesil = Color(0xFF2ECC71);
const Color kKirmizi = Color(0xFFE74C3C);

void main() => runApp(const BistApp());

class BistApp extends StatelessWidget {
  const BistApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BIST Asistan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: kYesil, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0F151B),
        cardColor: const Color(0xFF18212A),
      ),
      home: const AnaSayfa(),
    );
  }
}

double _d(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

String sayi(double v, {int ondalik = 0}) {
  final negatif = v < 0;
  final s = v.abs().toStringAsFixed(ondalik);
  final parcalar = s.split('.');
  final tam = parcalar[0];
  final b = StringBuffer();
  for (int i = 0; i < tam.length; i++) {
    if (i > 0 && (tam.length - i) % 3 == 0) b.write('.');
    b.write(tam[i]);
  }
  final sonuc = ondalik > 0 ? '$b,${parcalar[1]}' : b.toString();
  return negatif ? '-$sonuc' : sonuc;
}

String tl(double v) => '${sayi(v)} ₺';
String yuzde(double v) => '${v >= 0 ? '+' : ''}${sayi(v, ondalik: 2)}%';
Color renk(double v) => v > 0 ? kYesil : (v < 0 ? kKirmizi : Colors.white70);

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  Map<String, dynamic>? durum;
  List<dynamic> gecmis = [];
  String? hata;
  bool yukleniyor = true;
  double para = 100000;
  int sekme = 0;

  @override
  void initState() {
    super.initState();
    _basla();
  }

  Future<void> _basla() async {
    final sp = await SharedPreferences.getInstance();
    para = sp.getDouble('para') ?? 100000;
    await _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      yukleniyor = true;
      hata = null;
    });
    try {
      final t = DateTime.now().millisecondsSinceEpoch;
      final r1 = await http
          .get(Uri.parse('${kTaban}durum.json?t=$t'))
          .timeout(const Duration(seconds: 20));
      if (r1.statusCode != 200) {
        throw Exception(
            'Henüz veri yok (kod ${r1.statusCode}). Seans saatinde tarama çalışınca dolar.');
      }
      durum = json.decode(utf8.decode(r1.bodyBytes)) as Map<String, dynamic>;
      try {
        final r2 = await http
            .get(Uri.parse('${kTaban}gecmis.json?t=$t'))
            .timeout(const Duration(seconds: 20));
        if (r2.statusCode == 200) {
          gecmis = json.decode(utf8.decode(r2.bodyBytes)) as List<dynamic>;
        }
      } catch (_) {}
    } catch (e) {
      hata = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => yukleniyor = false);
  }

  Future<void> _paraAyarla() async {
    final c = TextEditingController(text: para.toStringAsFixed(0));
    final yeni = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sanal paran'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Bu tutarla işlem yapmış gibi kâr/zarar hesaplanır. Gerçek para değildir.',
              style: TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                suffixText: '₺', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () {
                final v = double.tryParse(c.text.replaceAll('.', '').replaceAll(',', '.'));
                Navigator.pop(ctx, v);
              },
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (yeni != null && yeni > 0) {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('para', yeni);
      setState(() => para = yeni);
    }
  }

  double get olcek => para / kSunucuPara;

  List<Map<String, dynamic>> get stratejiler =>
      ((durum?['stratejiler'] ?? []) as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();

  @override
  Widget build(BuildContext context) {
    final sayfalar = <Widget>[
      _ozet(),
      _pozisyonlar(),
      _islemler(),
      _tarama(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('BIST Asistan'),
        backgroundColor: const Color(0xFF0F151B),
        actions: [
          TextButton.icon(
            onPressed: _paraAyarla,
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: Text(tl(para)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _yukle,
        child: yukleniyor && durum == null
            ? const Center(child: CircularProgressIndicator())
            : (durum == null
                ? ListView(children: [
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(hata ?? 'Veri alınamadı',
                            textAlign: TextAlign.center)),
                    const Center(child: Text('Yenilemek için aşağı çek')),
                  ])
                : sayfalar[sekme]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: sekme,
        onDestinationSelected: (i) => setState(() => sekme = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Özet'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Pozisyon'),
          NavigationDestination(icon: Icon(Icons.history), label: 'İşlemler'),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Tarama'),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ ÖZET
  Widget _ozet() {
    final d = durum!;
    final rejim = (d['rejim'] ?? {}) as Map<String, dynamic>;
    final ok = rejim['ok'] == true;
    final seans = d['seans_acik'] == true;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(seans ? Icons.circle : Icons.circle_outlined,
                    size: 12, color: seans ? kYesil : Colors.white54),
                const SizedBox(width: 8),
                Text(seans ? 'Seans açık' : 'Seans kapalı',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Güncelleme: ${d['guncelleme']}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60)),
              ]),
              const SizedBox(height: 10),
              Text(
                  'BIST 100: ${sayi(_d(rejim['endeks']), ondalik: 0)}  (${yuzde(_d(rejim['gunluk_degisim']))} bugün)',
                  style: TextStyle(color: renk(_d(rejim['gunluk_degisim'])))),
              const SizedBox(height: 4),
              Text(
                  ok
                      ? 'Piyasa güçlü: yeni alıma izin var'
                      : 'Piyasa zayıf: trend ve kırılım yeni alım yapmıyor',
                  style: TextStyle(color: ok ? kYesil : Colors.orangeAccent)),
              const SizedBox(height: 4),
              Text('${d['taranan']} hisse tarandı',
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        for (final s in stratejiler) _stratejiKarti(s),
        const SizedBox(height: 8),
        _grafikKarti(),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
              '${d['veri_notu'] ?? ''}\nBu bir yatırım tavsiyesi değildir.',
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _stratejiKarti(Map<String, dynamic> s) {
    final ad = s['ad'] as String;
    final ky = _d(s['kar_yuzde']);
    final toplam = para * (1 + ky / 100);
    final kar = toplam - para;
    final kazanma = s['kazanma_orani'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: kRenkler[ad] ?? Colors.grey, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(kAdlar[ad] ?? ad,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(yuzde(ky),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: renk(ky))),
          ]),
          const SizedBox(height: 6),
          Text(s['aciklama'] ?? '',
              style: const TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Toplam: ${tl(toplam)}'),
            Text('${kar >= 0 ? '+' : ''}${tl(kar)}',
                style: TextStyle(color: renk(kar), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(
              'Açık: ${(s['acik'] as List).length}  •  İşlem: ${s['islem_sayisi']}  •  Kazanma: ${kazanma == null ? '-' : '%${sayi(_d(kazanma), ondalik: 0)}'}',
              style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ]),
      ),
    );
  }

  Widget _grafikKarti() {
    if (gecmis.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('Grafik için birkaç tarama sonucu birikmeli.',
              style: TextStyle(color: Colors.white60)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kâr/zarar seyri (%)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(painter: GrafikCizer(gecmis)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: [
            for (final k in kAdlar.keys)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, color: kRenkler[k]),
                const SizedBox(width: 4),
                Text(kAdlar[k]!, style: const TextStyle(fontSize: 12)),
              ]),
          ]),
        ]),
      ),
    );
  }

  // ------------------------------------------------------ POZİSYONLAR
  Widget _pozisyonlar() {
    final satirlar = <Widget>[];
    for (final s in stratejiler) {
      final ad = s['ad'] as String;
      final acik = (s['acik'] as List).map((e) => e as Map<String, dynamic>).toList();
      satirlar.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
        child: Text(kAdlar[ad] ?? ad,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: kRenkler[ad] ?? Colors.white)),
      ));
      if (acik.isEmpty) {
        satirlar.add(const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Açık pozisyon yok', style: TextStyle(color: Colors.white54)),
        ));
      }
      for (final p in acik) {
        final adet = _d(p['adet']) * olcek;
        final kar = (_d(p['fiyat']) - _d(p['giris'])) * adet;
        final ky = _d(p['kar_yuzde']);
        satirlar.add(Card(
          child: ListTile(
            title: Text(p['sembol'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'Giriş ${sayi(_d(p['giris']), ondalik: 2)} → Şimdi ${sayi(_d(p['fiyat']), ondalik: 2)}\n${p['zaman']}'),
            isThreeLine: true,
            trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(yuzde(ky),
                      style: TextStyle(color: renk(ky), fontWeight: FontWeight.bold)),
                  Text('${kar >= 0 ? '+' : ''}${tl(kar)}',
                      style: TextStyle(color: renk(kar), fontSize: 12)),
                ]),
          ),
        ));
      }
    }
    return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: satirlar);
  }

  // --------------------------------------------------------- İŞLEMLER
  Widget _islemler() {
    final hepsi = <Map<String, dynamic>>[];
    for (final s in stratejiler) {
      for (final i in (s['son_islemler'] as List)) {
        final m = Map<String, dynamic>.from(i as Map);
        m['strateji'] = s['ad'];
        hepsi.add(m);
      }
    }
    hepsi.sort((a, b) =>
        (b['cikis_zaman'] as String).compareTo(a['cikis_zaman'] as String));
    if (hepsi.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text('Henüz kapanmış işlem yok.', textAlign: TextAlign.center),
          )
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        for (final i in hepsi)
          Card(
            child: ListTile(
              title: Text('${i['sembol']}  •  ${kAdlar[i['strateji']] ?? i['strateji']}'),
              subtitle: Text(
                  '${sayi(_d(i['giris']), ondalik: 2)} → ${sayi(_d(i['cikis']), ondalik: 2)}\n${i['cikis_zaman']}  •  ${i['neden']}'),
              isThreeLine: true,
              trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(yuzde(_d(i['kar_yuzde'])),
                        style: TextStyle(
                            color: renk(_d(i['kar_yuzde'])),
                            fontWeight: FontWeight.bold)),
                    Text(
                        '${_d(i['kar']) >= 0 ? '+' : ''}${tl(_d(i['kar']) * olcek)}',
                        style: TextStyle(
                            color: renk(_d(i['kar'])), fontSize: 12)),
                  ]),
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------- TARAMA
  Widget _tarama() {
    final liste = ((durum?['tarama'] ?? []) as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    if (liste.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text('Şu an hiçbir strateji kuralına uyan hisse yok.',
                textAlign: TextAlign.center),
          )
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
              'Kurallara uyan hisseler. Bu liste "al" demek değildir, sadece kural uyan hisseleri gösterir.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
        ),
        for (final t in liste)
          Card(
            child: ListTile(
              title: Text(t['sembol'],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  'RSI ${t['rsi'] == null ? '-' : sayi(_d(t['rsi']), ondalik: 0)}  •  Hacim ${sayi(_d(t['hacim_orani']), ondalik: 1)}x\n${(t['uyan'] as List).map((e) => kAdlar[e] ?? e).join(', ')}'),
              isThreeLine: true,
              trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(sayi(_d(t['fiyat']), ondalik: 2),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(yuzde(_d(t['gunluk_degisim'])),
                        style: TextStyle(
                            color: renk(_d(t['gunluk_degisim'])), fontSize: 12)),
                  ]),
            ),
          ),
      ],
    );
  }
}

class GrafikCizer extends CustomPainter {
  final List<dynamic> gecmis;
  GrafikCizer(this.gecmis);

  @override
  void paint(Canvas canvas, Size size) {
    final seriler = <String, List<double>>{};
    for (final k in kAdlar.keys) {
      seriler[k] = gecmis
          .map((e) => ((_d((e as Map)[k]) / kSunucuPara) - 1) * 100)
          .toList();
    }
    double mn = 0, mx = 0;
    for (final v in seriler.values) {
      for (final x in v) {
        if (x < mn) mn = x;
        if (x > mx) mx = x;
      }
    }
    if (mx - mn < 0.5) {
      mx += 0.25;
      mn -= 0.25;
    }
    final n = gecmis.length;
    double yAt(double v) => size.height - (v - mn) / (mx - mn) * size.height;
    final sifir = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, yAt(0)), Offset(size.width, yAt(0)), sifir);
    seriler.forEach((k, v) {
      final p = Paint()
        ..color = kRenkler[k] ?? Colors.grey
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final yol = Path();
      for (int i = 0; i < v.length; i++) {
        final x = n == 1 ? 0.0 : i / (n - 1) * size.width;
        final y = yAt(v[i]);
        if (i == 0) {
          yol.moveTo(x, y);
        } else {
          yol.lineTo(x, y);
        }
      }
      canvas.drawPath(yol, p);
    });
  }

  @override
  bool shouldRepaint(covariant GrafikCizer old) => old.gecmis != gecmis;
}
