"""BIST tarayici + sanal al-sat simulasyonu.

Gercek para ile islem YAPMAZ. Fiyatlar Yahoo Finance'ten (genelde ~15 dk gecikmeli)
gelir; uc strateji ayri ayri sanal kasalarla paralel denenir.
Sadece standart kutuphane kullanir.
"""
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERI = os.path.join(KOK, "veri")
TR = timezone(timedelta(hours=3))

BASLANGIC_PARA = 100000.0
KOMISYON = 0.001      # alis ve satista binde 1
KAYMA = 0.001         # fiyat farki/gecikme payi, her yonde binde 1
MAX_POZISYON = 5
POZISYON_PAYI = 0.20  # baslangic kasanin %20'si
ENDEKS = "XU100.IS"


# ---------------------------------------------------------------- veri
HATALAR = {}


def indir(sembol):
    for deneme in range(4):
        host = "query1" if deneme % 2 == 0 else "query2"
        url = ("https://%s.finance.yahoo.com/v8/finance/chart/%s?range=1y&interval=1d" % (host, sembol))
        istek = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Accept": "application/json"})
        try:
            with urllib.request.urlopen(istek, timeout=20) as r:
                d = json.load(r)
            sonuc = d["chart"]["result"][0]
            q = sonuc["indicators"]["quote"][0]
            zaman = sonuc["timestamp"]
            fiyat = sonuc["meta"].get("regularMarketPrice")
            satirlar = []
            for t, o, h, l, c, v in zip(zaman, q["open"], q["high"], q["low"], q["close"], q["volume"]):
                if c is None or h is None or l is None:
                    continue
                gun = datetime.fromtimestamp(t, TR).strftime("%Y-%m-%d")
                satirlar.append({"gun": gun, "h": h, "l": l, "c": c, "v": v or 0})
            if len(satirlar) < 60 or not fiyat:
                return None
            return {"satirlar": satirlar, "fiyat": float(fiyat)}
        except Exception as e:
            HATALAR[sembol] = "%s: %s" % (type(e).__name__, e)
            time.sleep(2 + deneme * 2)
    return None


def hisseleri_oku():
    with open(os.path.join(KOK, "tarayici", "hisseler.txt"), encoding="utf-8") as f:
        return sorted(set(f.read().split()))


# ---------------------------------------------------------- gostergeler
def sma(x, n):
    return sum(x[-n:]) / n if len(x) >= n else None


def rsi(c, n=14):
    if len(c) < n + 1:
        return None
    kazan = kayip = 0.0
    for i in range(1, n + 1):
        d = c[i] - c[i - 1]
        kazan += max(d, 0)
        kayip += max(-d, 0)
    kazan /= n
    kayip /= n
    for i in range(n + 1, len(c)):
        d = c[i] - c[i - 1]
        kazan = (kazan * (n - 1) + max(d, 0)) / n
        kayip = (kayip * (n - 1) + max(-d, 0)) / n
    if kayip == 0:
        return 100.0
    return 100 - 100 / (1 + kazan / kayip)


def analiz(veri, bugun):
    """Bugunun yarim cubugunu atip tamamlanmis gunlerle gosterge hesaplar."""
    s = [x for x in veri["satirlar"] if x["gun"] < bugun]
    if len(s) < 60:
        return None
    c = [x["c"] for x in s]
    h = [x["h"] for x in s]
    v = [x["v"] for x in s]
    p = veri["fiyat"]
    sma20, sma50 = sma(c, 20), sma(c, 50)
    sma50_once = sum(c[-55:-5]) / 50 if len(c) >= 55 else None
    ort_hacim = sum(v[-20:]) / 20 if sum(v[-20:]) else 0
    return {
        "fiyat": p,
        "onceki_kapanis": c[-1],
        "gunluk_degisim": (p / c[-1] - 1) * 100,
        "sma20": sma20,
        "sma50": sma50,
        "sma50_yukseliyor": bool(sma50_once and sma50 > sma50_once),
        "rsi": rsi(c),
        "yuksek20": max(h[-20:]),
        "hacim_orani": (v[-1] / ort_hacim) if ort_hacim else 0,
        "getiri20": (p / c[-21] - 1) * 100 if len(c) > 21 else 0,
    }


# ------------------------------------------------------------ stratejiler
class Strateji:
    ad = ""
    aciklama = ""
    zarar_kes = 0.05

    def giris(self, a):
        """Giris uygunsa puan (>0), degilse None dondurur."""
        return None

    def cikis(self, poz, a, gun_sayisi):
        """Cikis nedeni (metin) ya da None."""
        return None


class Trend(Strateji):
    ad = "trend"
    aciklama = "Yukselen trendi takip eder: fiyat ortalamalarin ustunde, ortalama yukseliyor."
    zarar_kes = 0.06

    def giris(self, a):
        if a["rsi"] is None or not a["sma50"]:
            return None
        if (a["fiyat"] > a["sma20"] > a["sma50"] and a["sma50_yukseliyor"]
                and 50 <= a["rsi"] <= 70 and a["fiyat"] < a["sma20"] * 1.08):
            return a["getiri20"]
        return None

    def cikis(self, poz, a, gun_sayisi):
        if a["fiyat"] < a["sma20"] * 0.99:
            return "trend bozuldu"
        return None


class GeriDonus(Strateji):
    ad = "geri_donus"
    aciklama = "Asiri dusen hissede tepki yukselisi arar: RSI cok dusuk, uzun trend bozulmamis."
    zarar_kes = 0.05

    def giris(self, a):
        if a["rsi"] is None or not a["sma50"]:
            return None
        if a["rsi"] < 32 and a["fiyat"] > a["sma50"] * 0.85:
            return 40 - a["rsi"]
        return None

    def cikis(self, poz, a, gun_sayisi):
        if a["rsi"] is not None and a["rsi"] > 55:
            return "tepki tamamlandi"
        if a["fiyat"] >= poz["giris"] * 1.08:
            return "hedef kar"
        if gun_sayisi >= 10:
            return "sure doldu"
        return None


class Kirilim(Strateji):
    ad = "kirilim"
    aciklama = "20 gunluk zirveyi asan hisseyi izler; geri cekilince cikar."
    zarar_kes = 0.05

    def giris(self, a):
        if not a["sma50"]:
            return None
        if a["fiyat"] > a["yuksek20"] and a["sma50_yukseliyor"] and a["fiyat"] > a["sma50"]:
            return (a["fiyat"] / a["yuksek20"] - 1) * 100 + a["hacim_orani"]
        return None

    def cikis(self, poz, a, gun_sayisi):
        if a["fiyat"] <= poz["tepe"] * 0.95 and a["fiyat"] > poz["giris"] * 1.02:
            return "kar koruma (tepeden %5 geri cekilme)"
        return None


STRATEJILER = [Trend(), GeriDonus(), Kirilim()]


# ---------------------------------------------------------- simulasyon
def yeni_kasa():
    return {"nakit": BASLANGIC_PARA, "pozisyonlar": {}, "islemler": []}


def seans_acik(simdi):
    return simdi.weekday() < 5 and (10, 0) <= (simdi.hour, simdi.minute) < (18, 0)


def pozisyon_degeri(kasa, analizler):
    t = kasa["nakit"]
    for s, poz in kasa["pozisyonlar"].items():
        fiyat = analizler[s]["fiyat"] if s in analizler else poz["giris"]
        t += poz["adet"] * fiyat
    return t


def sat(kasa, s, poz, fiyat, neden, zaman):
    gelen = poz["adet"] * fiyat * (1 - KAYMA) * (1 - KOMISYON)
    kasa["nakit"] += gelen
    maliyet = poz["adet"] * poz["giris"]
    kasa["islemler"].append({
        "sembol": s, "adet": poz["adet"], "giris": round(poz["giris"], 2),
        "cikis": round(fiyat * (1 - KAYMA), 2), "giris_zaman": poz["zaman"],
        "cikis_zaman": zaman, "kar": round(gelen - maliyet, 2),
        "kar_yuzde": round((gelen / maliyet - 1) * 100, 2), "neden": neden,
    })
    del kasa["pozisyonlar"][s]


def adim(strateji, kasa, analizler, rejim_ok, simdi):
    zaman = simdi.strftime("%Y-%m-%d %H:%M")
    # 1) tepe guncelle ve cikislar
    for s in list(kasa["pozisyonlar"].keys()):
        poz = kasa["pozisyonlar"][s]
        a = analizler.get(s)
        if not a:
            continue
        poz["tepe"] = max(poz["tepe"], a["fiyat"])
        gun = (simdi.date() - datetime.strptime(poz["zaman"][:10], "%Y-%m-%d").date()).days
        neden = None
        if a["fiyat"] <= poz["giris"] * (1 - strateji.zarar_kes):
            neden = "zarar kes"
        else:
            neden = strateji.cikis(poz, a, gun)
        if neden:
            sat(kasa, s, poz, a["fiyat"], neden, zaman)
    # 2) giris
    if not (rejim_ok and seans_acik(simdi)):
        return
    adaylar = []
    for s, a in analizler.items():
        if s in kasa["pozisyonlar"]:
            continue
        puan = strateji.giris(a)
        if puan is not None:
            adaylar.append((puan, s))
    adaylar.sort(reverse=True)
    for puan, s in adaylar:
        if len(kasa["pozisyonlar"]) >= MAX_POZISYON:
            break
        fiyat = analizler[s]["fiyat"] * (1 + KAYMA)
        butce = min(BASLANGIC_PARA * POZISYON_PAYI, kasa["nakit"])
        adet = int(butce / (fiyat * (1 + KOMISYON)))
        if adet < 1:
            continue
        kasa["nakit"] -= adet * fiyat * (1 + KOMISYON)
        kasa["pozisyonlar"][s] = {"adet": adet, "giris": fiyat, "tepe": fiyat, "zaman": zaman,
                                  "puan": round(puan, 2)}


def ozet(strateji, kasa, analizler):
    toplam = pozisyon_degeri(kasa, analizler)
    kapali = kasa["islemler"]
    kazanan = [x for x in kapali if x["kar"] > 0]
    acik = []
    for s, poz in kasa["pozisyonlar"].items():
        f = analizler[s]["fiyat"] if s in analizler else poz["giris"]
        acik.append({"sembol": s, "adet": poz["adet"], "giris": round(poz["giris"], 2),
                     "fiyat": round(f, 2), "kar_yuzde": round((f / poz["giris"] - 1) * 100, 2),
                     "zaman": poz["zaman"]})
    return {
        "ad": strateji.ad, "aciklama": strateji.aciklama, "zarar_kes_yuzde": strateji.zarar_kes * 100,
        "baslangic": BASLANGIC_PARA, "nakit": round(kasa["nakit"], 2), "toplam": round(toplam, 2),
        "kar": round(toplam - BASLANGIC_PARA, 2), "kar_yuzde": round((toplam / BASLANGIC_PARA - 1) * 100, 2),
        "islem_sayisi": len(kapali),
        "kazanma_orani": round(len(kazanan) / len(kapali) * 100, 1) if kapali else None,
        "acik": acik, "son_islemler": kapali[-15:][::-1],
    }


# ------------------------------------------------------------------ ana
def oku(ad, varsayilan):
    yol = os.path.join(VERI, ad)
    if os.path.exists(yol):
        with open(yol, encoding="utf-8") as f:
            return json.load(f)
    return varsayilan


def yaz(ad, veri):
    with open(os.path.join(VERI, ad), "w", encoding="utf-8") as f:
        json.dump(veri, f, ensure_ascii=False, indent=1)


def main(indirici=indir, simdi=None):
    simdi = simdi or datetime.now(TR)
    bugun = simdi.strftime("%Y-%m-%d")
    hisseler = hisseleri_oku()
    with ThreadPoolExecutor(3) as ex:
        ham = list(ex.map(indirici, [h + ".IS" for h in hisseler] + [ENDEKS]))
    sozluk = dict(zip(hisseler + [ENDEKS], ham))
    endeks_ham = sozluk.pop(ENDEKS)
    analizler = {}
    for s, v in sozluk.items():
        if v:
            a = analiz(v, bugun)
            if a:
                analizler[s] = a
    alinamayan = [s for s in hisseler if s not in analizler]
    print("Hisse analiz edildi: %d, alinamayan: %d" % (len(analizler), len(alinamayan)))
    if len(analizler) < 20:
        print("Cok az veri geldi, kaynak calismiyor olabilir. Durum degistirilmedi.")
        yaz("hata.json", {"zaman": simdi.strftime("%Y-%m-%d %H:%M"), "alinan": len(analizler),
                         "alinamayan": alinamayan[:50],
                         "hatalar": dict(list(HATALAR.items())[:8])})
        sys.exit(1)
    # piyasa rejimi
    rejim = {"ok": True, "not": "endeks verisi yok, kontrol edilmedi"}
    if endeks_ham:
        ea = analiz(endeks_ham, bugun)
        if ea:
            rejim = {"ok": bool(ea["fiyat"] > ea["sma50"]), "endeks": round(ea["fiyat"], 1),
                     "sma50": round(ea["sma50"], 1), "gunluk_degisim": round(ea["gunluk_degisim"], 2),
                     "not": "Endeks 50 gunluk ortalamanin ustunde" if ea["fiyat"] > ea["sma50"]
                     else "Endeks 50 gunluk ortalamanin altinda: yeni alim yapilmaz"}
    sim = oku("sim.json", {"kasalar": {}})
    for st in STRATEJILER:
        sim["kasalar"].setdefault(st.ad, yeni_kasa())
        adim(st, sim["kasalar"][st.ad], analizler, rejim["ok"], simdi)
    yaz("sim.json", sim)
    ozetler = [ozet(st, sim["kasalar"][st.ad], analizler) for st in STRATEJILER]
    # tarama listesi: hangi hisse hangi stratejiye uyuyor
    tarama = []
    for s, a in analizler.items():
        uyan = [st.ad for st in STRATEJILER if st.giris(a) is not None]
        if uyan:
            tarama.append({"sembol": s, "fiyat": round(a["fiyat"], 2),
                           "gunluk_degisim": round(a["gunluk_degisim"], 2),
                           "rsi": round(a["rsi"], 1) if a["rsi"] else None,
                           "hacim_orani": round(a["hacim_orani"], 2), "uyan": uyan})
    tarama.sort(key=lambda x: (-len(x["uyan"]), -x["gunluk_degisim"]))
    durum = {
        "guncelleme": simdi.strftime("%Y-%m-%d %H:%M"), "seans_acik": seans_acik(simdi),
        "veri_notu": "Fiyatlar ucretsiz kaynaktan, genelde ~15 dk gecikmeli. Sanal para, gercek islem degil.",
        "taranan": len(analizler), "rejim": rejim, "stratejiler": ozetler, "tarama": tarama[:40],
    }
    yaz("durum.json", durum)
    # gecmis (grafik icin)
    gecmis = oku("gecmis.json", [])
    gecmis.append({"z": simdi.strftime("%Y-%m-%d %H:%M"),
                   **{o["ad"]: o["toplam"] for o in ozetler}})
    yaz("gecmis.json", gecmis[-3000:])
    for o in ozetler:
        print("%-11s toplam %.0f  kar %% %.2f  acik %d  islem %d" % (
            o["ad"], o["toplam"], o["kar_yuzde"], len(o["acik"]), o["islem_sayisi"]))


if __name__ == "__main__":
    main()
