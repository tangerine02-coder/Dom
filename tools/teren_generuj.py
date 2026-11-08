#!/usr/bin/env python3
"""Generuje model terenu działki z rzędnych odczytanych z projektu
zagospodarowania terenu (PZT, skala 1:500) i zapisuje skrypt SketchUpa
teren/sketchup/teren.rb (w tym samym układzie i jednostkach co model domu).

Układ (m): x – wzdłuż kalenicy domu (od szczytu z oknem W1 w stronę garażu),
y – od elewacji frontowej (wejście) w stronę ogrodu, z – wysokość względem
±0,00 domu. Punkt (0,0) = narożnik domu (front, szczyt z W1).

Użycie:  python3 tools/teren_generuj.py
Wymaga:  pip install numpy scipy
"""
import json
import math

import numpy as np
from scipy.spatial import Delaunay

DANE = 'teren/dane/rzedne_pzt.json'   # [x, y, H m n.p.m., id punktu]
WYJSCIE = 'teren/sketchup/teren.rb'

# --- elementy odczytane z PZT (po przeliczeniu do układu domu) -------------
DZIALKA = [(-15.3, -15.8), (55.6, -14.0), (54.4, 30.8), (-15.3, 31.1)]   # dz. 188/2
BUDYNKI = [(0.0, 0.0), (16.665, 0.0), (16.665, 8.29), (0.0, 8.29)]       # dom + garaż
# platforma wyrównana do poziomu terenu z projektu domu (−0,29) wokół budynków i pod tarasem
PLATFORMA = [(-1.0, -1.15), (17.665, -1.15), (17.665, 9.44), (6.1, 9.44), (6.1, 11.4),
             (-1.9, 11.4), (-1.9, 5.4), (-1.0, 5.4)]
UTWARDZENIA = {
    'Taras': [(-1.9, 5.4), (0.0, 5.4), (0.0, 8.29), (6.1, 8.29), (6.1, 11.4), (-1.9, 11.4)],
    'Dojście do wejścia': [(4.1, -16.5), (5.9, -16.5), (5.9, -1.0), (4.1, -1.0)],
    'Podjazd do garażu': [(11.2, -16.5), (16.0, -16.5), (15.0, -1.0), (11.9, -1.0)],
}
MARGINES = 6.0     # ile metrów terenu pokazać poza granicą działki
TEREN_DOMU = -0.29  # poziom terenu przy budynku w projekcie domu (m)
H0_RECZNIE = None   # ±0,00 domu w m n.p.m., jeśli poda je projektant (np. 62.50)


def w_wielokacie(p, poly):
    x, y = p
    ins = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            ins = not ins
        j = i
    return ins


def zageszczone(poly, krok, zamkniety=True):
    out = []
    n = len(poly)
    for i in range(n if zamkniety else n - 1):
        a = np.array(poly[i], float)
        b = np.array(poly[(i + 1) % n], float)
        k = max(1, int(math.ceil(np.linalg.norm(b - a) / krok)))
        out += [tuple(a + (b - a) * j / k) for j in range(k)]
    return out


def odsuniety(poly, d):
    """odsunięcie wypukłego wielokąta (CCW) na zewnątrz o d"""
    n = len(poly)
    lines = []
    for i in range(n):
        a = np.array(poly[i], float)
        b = np.array(poly[(i + 1) % n], float)
        e = (b - a) / np.linalg.norm(b - a)
        nrm = np.array([e[1], -e[0]])
        lines.append((a + nrm * d, e))
    out = []
    for i in range(n):
        p, r = lines[i - 1]
        q, s = lines[i]
        cr = lambda a, b: a[0] * b[1] - a[1] * b[0]
        t = cr(q - p, s) / cr(r, s)
        out.append(tuple(p + r * t))
    return out


class Powierzchnia:
    """liniowa interpolacja na siatce trójkątów + IDW poza jej obrysem"""

    def __init__(self, xy, z):
        self.xy = np.asarray(xy, float)
        self.z = np.asarray(z, float)
        self.tri = Delaunay(self.xy)

    def __call__(self, p):
        p = np.asarray(p, float)
        s = self.tri.find_simplex(p)
        if s >= 0:
            T = self.tri.transform[s]
            b = T[:2] @ (p - T[2])
            bc = np.r_[b, 1 - b.sum()]
            return float((self.z[self.tri.simplices[s]] * bc).sum())
        d = np.linalg.norm(self.xy - p, axis=1)
        k = np.argsort(d)[:4]
        w = 1 / np.maximum(d[k], 0.1) ** 2
        return float((self.z[k] * w).sum() / w.sum())


def main():
    pkt = json.load(open(DANE, encoding='utf-8'))
    xy = np.array([[p[0], p[1]] for p in pkt])
    H = np.array([p[2] for p in pkt])

    # poziom ±0,00: średni teren pod budynkami + 0,29 m (jak w projekcie domu)
    f0 = Powierzchnia(xy, H)
    gx, gy = np.meshgrid(np.arange(0.25, 16.665, 0.5), np.arange(0.25, 8.29, 0.5))
    h_sr = np.mean([f0((a, b)) for a, b in zip(gx.ravel(), gy.ravel())])
    H0 = H0_RECZNIE if H0_RECZNIE is not None else round(h_sr - TEREN_DOMU, 2)
    z_plat = H0 + TEREN_DOMU
    print(f'Średni teren pod budynkami: {h_sr:.2f} m n.p.m. -> ±0,00 = {H0:.2f} m n.p.m.')

    teren = odsuniety(DZIALKA, MARGINES)
    poza_plat = [not w_wielokacie(p, PLATFORMA) for p in xy]
    w_terenie = [w_wielokacie(p, teren) for p in xy]
    m = np.array(poza_plat) & np.array(w_terenie)
    pts = [tuple(p) for p in xy[m]]
    zz = list(H[m])
    # platforma
    plat = zageszczone(PLATFORMA, 0.5)
    for gxv in np.arange(-0.5, 17.5, 2.0):
        for gyv in np.arange(-0.5, 11.0, 2.0):
            if w_wielokacie((gxv, gyv), PLATFORMA):
                plat.append((gxv, gyv))
    pts += plat
    zz += [z_plat] * len(plat)
    f = Powierzchnia(pts, zz)

    # dodatkowe wierzchołki na granicach stref (ostre krawędzie stref)
    extra = zageszczone(DZIALKA, 1.0) + zageszczone(teren, 2.0) + zageszczone(BUDYNKI, 1.0)
    for poly in UTWARDZENIA.values():
        extra += zageszczone(poly, 0.5)
    for p in extra:
        if w_wielokacie(p, teren) or min(np.hypot(p[0] - q[0], p[1] - q[1]) for q in teren) < 1e-6 \
                or p in [tuple(q) for q in teren]:
            pts.append(p)
            zz.append(f(p) if not w_wielokacie(p, PLATFORMA) else z_plat)
    # usunięcie duplikatów
    uniq = {}
    for p, z in zip(pts, zz):
        uniq.setdefault((round(p[0], 3), round(p[1], 3)), z)
    P = np.array(list(uniq.keys()))
    Z = np.array(list(uniq.values()))
    tri = Delaunay(P)

    strefy = {'Pod budynkami': [], 'Utwardzenia': [], 'Działka': [], 'Otoczenie': []}
    for s in tri.simplices:
        c = P[s].mean(axis=0)
        if not w_wielokacie(c, teren):
            continue
        if w_wielokacie(c, BUDYNKI):
            k = 'Pod budynkami'
        elif w_wielokacie(c, DZIALKA) and any(w_wielokacie(c, u) for u in UTWARDZENIA.values()):
            k = 'Utwardzenia'
        elif w_wielokacie(c, DZIALKA):
            k = 'Działka'
        else:
            k = 'Otoczenie'
        strefy[k].append([int(i) for i in s])

    # warstwice co 0,5 m (wysokości bezwzględne)
    warstwice = []
    for s in tri.simplices:
        c = P[s].mean(axis=0)
        if not w_wielokacie(c, teren) or w_wielokacie(c, BUDYNKI):
            continue
        a = [(P[i][0], P[i][1], Z[i]) for i in s]
        lo, hi = min(p[2] for p in a), max(p[2] for p in a)
        for lev in np.arange(math.ceil(lo * 2) / 2, hi, 0.5):
            cut = []
            for i in range(3):
                p, q = a[i], a[(i + 1) % 3]
                if (p[2] - lev) * (q[2] - lev) < 0:
                    t = (lev - p[2]) / (q[2] - p[2])
                    cut.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, lev))
            if len(cut) == 2:
                warstwice.append(cut)

    cm = lambda v: round(v * 100, 1)
    V = [[cm(p[0]), cm(p[1]), cm(z - H0)] for p, z in zip(P, Z)]
    W = [[cm(c[0][0]), cm(c[0][1]), cm(c[0][2] - H0), cm(c[1][0]), cm(c[1][1]), cm(c[1][2] - H0)]
         for c in warstwice]
    G = [[cm(p[0]), cm(p[1]), cm(f(p) - H0)] for p in DZIALKA]
    print(f'Wierzchołków: {len(V)}, trójkątów: {sum(len(t) for t in strefy.values())}, '
          f'odcinków warstwic: {len(W)}')
    print('Rzędne terenu w obrębie działki: %.2f – %.2f m n.p.m.' % (H[np.array(w_terenie)].min(), H[np.array(w_terenie)].max()))

    szablon = open('tools/teren_szablon.rb', encoding='utf-8').read()
    dane = (f'      @h0 = {H0:.2f}\n'
            f'      @v = {json.dumps(V)}\n'
            f'      @t = {json.dumps(strefy, ensure_ascii=False)}\n'
            f'      @w = {json.dumps(W)}\n'
            f'      @g = {json.dumps(G)}\n')
    open(WYJSCIE, 'w', encoding='utf-8').write(szablon.replace('      # @@DANE@@\n', dane))
    print('Zapisano', WYJSCIE)


if __name__ == '__main__':
    main()
