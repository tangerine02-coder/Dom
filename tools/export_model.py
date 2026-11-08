#!/usr/bin/env python3
"""Sprawdza geometrię wyeksportowaną z atrapy SketchUpa i zapisuje:
  * plik COLLADA (.dae) do importu w SketchUpie / innych programach 3D,
  * plik JSON z trójkątami do podglądu w przeglądarce (three.js).

Użycie:  python3 tools/export_model.py build/model.json build/dom.dae build/mesh.json
Wymaga: pip install mapbox_earcut numpy
"""
import json
import sys
from collections import defaultdict
from xml.sax.saxutils import escape

import mapbox_earcut as earcut
import numpy as np


def newell(pts):
    n = np.zeros(3)
    for i in range(len(pts)):
        p, q = pts[i], pts[(i + 1) % len(pts)]
        n += [(p[1] - q[1]) * (p[2] + q[2]), (p[2] - q[2]) * (p[0] + q[0]), (p[0] - q[0]) * (p[1] + q[1])]
    return n / np.linalg.norm(n)


def triangulate(loops):
    """Zwraca listę trójkątów (indeksy do spłaszczonej listy punktów) i punkty."""
    pts = np.array([p for lp in loops for p in lp], dtype=float)
    n = newell(loops[0])
    # baza 2D w płaszczyźnie ściany, zgodna z normalną (CCW)
    a = np.array([1.0, 0, 0]) if abs(n[0]) < 0.9 else np.array([0, 1.0, 0])
    u = np.cross(n, a)
    u /= np.linalg.norm(u)
    v = np.cross(n, u)
    xy = np.stack([pts @ u, pts @ v], axis=1)
    rings = np.cumsum([len(lp) for lp in loops]).astype(np.uint32)
    idx = earcut.triangulate_float64(xy, rings).reshape(-1, 3)
    # earcut nie gwarantuje kierunku – wyrównujemy do normalnej
    out = []
    for t in idx:
        a_, b_, c_ = pts[t[0]], pts[t[1]], pts[t[2]]
        area2 = np.dot(np.cross(b_ - a_, c_ - a_), n)
        if abs(area2) < 1e-6:
            continue  # trójkąt zdegenerowany (punkty współliniowe)
        if area2 < 0:
            t = [t[0], t[2], t[1]]
        out.append(list(map(int, t)))
    return pts, out, n


def main(src, dae_path, mesh_path):
    data = json.load(open(src, encoding='utf-8'))
    faces = data['faces']
    mats = data['materials']

    tris_by = defaultdict(list)  # (węzeł, materiał) -> trójkąty [[p,p,p],...]
    groups = defaultdict(list)   # ścieżka grupy -> trójkąty (do kontroli objętości)
    loops_by = defaultdict(list)  # ścieżka grupy -> pętle wielokątów (do kontroli domknięcia)
    problems = []
    for f in faces:
        pts, tris, n = triangulate(f['loops'])
        loops_by[f['path']].extend(f['loops'])
        node = f['path'].split(' / ')[1] if ' / ' in f['path'] else f['path']
        mat = f['mat'] or 'Domyślny'
        for t in tris:
            tri = [pts[i].tolist() for i in t]
            tris_by[(node, mat, f['layer'])].append(tri)
            groups[f['path']].append(tri)
            if f.get('back'):
                tris_by[(node, f['back'], f['layer'])].append([tri[0], tri[2], tri[1]])

    if any(k[1] == 'Domyślny' for k in tris_by):
        mats['Domyślny'] = {'rgb': [200, 200, 200], 'alpha': 1.0}

    # kontrola: każda bryła zamknięta (każda krawędź raz w każdą stronę) i
    # z normalnymi na zewnątrz (dodatnia objętość)
    open_ok = ('Szyba', 'Teren')
    checked = 0
    for path, tris in groups.items():
        if any(path.endswith(s) for s in open_ok):
            continue
        key = lambda p: tuple(round(c, 3) for c in p)
        edges = defaultdict(int)
        vol = 0.0
        for a, b, c in tris:
            A, B, C = map(np.array, (a, b, c))
            vol += np.dot(A, np.cross(B, C)) / 6.0
        for lp in loops_by[path]:
            for i in range(len(lp)):
                edges[(key(lp[i]), key(lp[(i + 1) % len(lp)]))] += 1
        bad = [e for e, k in edges.items() if k != 1 or edges.get((e[1], e[0]), 0) != 1]
        checked += 1
        if bad or vol <= 0:
            problems.append(f'{path}: krawędzie_niedomknięte={len(bad)} objętość={vol / 1e6:.4f} m3')
    print(f'Sprawdzono brył: {checked}, problemów: {len(problems)}')
    for p in problems[:40]:
        print('  !', p)

    # ------------------------------------------------------------ JSON (three.js)
    mesh = {'materials': mats, 'pages': data['pages'], 'parts': []}
    for (node, mat, layer), tris in tris_by.items():
        arr = np.array(tris, dtype=float).reshape(-1, 3)
        mesh['parts'].append({'node': node, 'mat': mat, 'layer': layer,
                              'pos': [round(float(v), 2) for v in arr.flatten()]})
    json.dump(mesh, open(mesh_path, 'w', encoding='utf-8'), ensure_ascii=False)

    # ------------------------------------------------------------ COLLADA
    mat_ids = {name: f'mat{i}' for i, name in enumerate(list(mats) + ['Domyślny'])}

    def mid(s):
        return mat_ids.setdefault(s, f'mat{len(mat_ids)}')

    lib_fx, lib_mat, lib_geo, nodes = [], [], [], []
    fmt = lambda a: ' '.join(f'{v:.3f}' for v in a)
    for name, m in mats.items():
        r, g, b = [c / 255.0 for c in m['rgb']]
        a = m.get('alpha', 1.0) or 1.0
        lib_fx.append(
            f'<effect id="{mid(name)}-fx"><profile_COMMON><technique sid="common"><lambert>'
            f'<diffuse><color>{r:.4f} {g:.4f} {b:.4f} 1</color></diffuse>'
            f'<transparent opaque="A_ONE"><color>0 0 0 {a:.3f}</color></transparent>'
            f'<transparency><float>1</float></transparency>'
            f'</lambert></technique></profile_COMMON></effect>')
        lib_mat.append(f'<material id="{mid(name)}" name="{escape(name)}">'
                       f'<instance_effect url="#{mid(name)}-fx"/></material>')
    by_node = defaultdict(list)
    for (node, mat, layer), tris in tris_by.items():
        by_node[node].append((mat, tris))
    for gi, (node, parts) in enumerate(by_node.items()):
        gid = f'geom{gi}'
        pos, nor, prims = [], [], []
        base = 0
        for mat, tris in parts:
            idx = []
            for tri in tris:
                A, B, C = map(np.array, tri)
                nn = np.cross(B - A, C - A)
                nn = nn / (np.linalg.norm(nn) or 1)
                for p in tri:
                    pos.extend(p)
                    nor.extend(nn.tolist())
                    idx.append(base)
                    base += 1
            prims.append(f'<triangles material="{mid(mat)}" count="{len(tris)}">'
                         f'<input semantic="VERTEX" source="#{gid}-v" offset="0"/>'
                         f'<input semantic="NORMAL" source="#{gid}-n" offset="0"/>'
                         f'<p>{" ".join(map(str, idx))}</p></triangles>')
        def src(sid, arr):
            return (f'<source id="{sid}"><float_array id="{sid}-a" count="{len(arr)}">{fmt(arr)}</float_array>'
                    f'<technique_common><accessor source="#{sid}-a" count="{len(arr) // 3}" stride="3">'
                    '<param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/>'
                    '</accessor></technique_common></source>')
        lib_geo.append(
            f'<geometry id="{gid}" name="{escape(node)}"><mesh>' + src(f'{gid}-p', pos) + src(f'{gid}-n', nor)
            + f'<vertices id="{gid}-v"><input semantic="POSITION" source="#{gid}-p"/></vertices>'
            + ''.join(prims) + '</mesh></geometry>')
        binds = ''.join(f'<instance_material symbol="{mid(m)}" target="#{mid(m)}"/>' for m, _ in parts)
        nodes.append(f'<node id="node{gi}" name="{escape(node)}"><instance_geometry url="#{gid}">'
                     f'<bind_material><technique_common>{binds}</technique_common></bind_material>'
                     f'</instance_geometry></node>')
    dae = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">'
           '<asset><contributor><authoring_tool>dom_smart_comfort.rb</authoring_tool></contributor>'
           '<unit name="centimeter" meter="0.01"/><up_axis>Z_UP</up_axis></asset>'
           f'<library_effects>{"".join(lib_fx)}</library_effects>'
           f'<library_materials>{"".join(lib_mat)}</library_materials>'
           f'<library_geometries>{"".join(lib_geo)}</library_geometries>'
           '<library_visual_scenes><visual_scene id="scene" name="Dom Smart comfort+">'
           '<node id="dom" name="Dom Smart comfort+">' + ''.join(nodes) + '</node>'
           '</visual_scene></library_visual_scenes>'
           '<scene><instance_visual_scene url="#scene"/></scene></COLLADA>\n')
    open(dae_path, 'w', encoding='utf-8').write(dae)
    print(f'Zapisano {dae_path} ({len(dae) / 1e6:.1f} MB) i {mesh_path}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:4]))
