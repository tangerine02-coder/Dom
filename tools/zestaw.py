#!/usr/bin/env python3
"""Łączy dom, garaż (przy prawej ścianie szczytowej domu) i teren działki
w jeden plik .glb/.obj do oglądania całości (np. w Blenderze, 3dviewer.net).
Użycie: python3 tools/zestaw.py <wariant>"""
import json
import subprocess
import sys

w = sys.argv[1] if len(sys.argv) > 1 else 'antracyt'
dom = json.load(open(f'build/mesh_{w}.json', encoding='utf-8'))
gar = json.load(open(f'build/garaz_mesh_{w}.json', encoding='utf-8'))
ter = json.load(open('build/teren_mesh.json', encoding='utf-8'))
out = {'materials': {}, 'pages': [], 'parts': []}
for src, dx, pref in [(dom, 0.0, 'Dom'), (gar, 1066.5, 'Garaż'), (ter, 0.0, '')]:
    out['materials'].update(src['materials'])
    for p in src['parts']:
        if p['layer'] == 'Teren' and pref:   # płaski trawnik z modeli budynków
            continue
        pos = list(p['pos'])
        if dx:
            pos[0::3] = [round(v + dx, 2) for v in pos[0::3]]
        out['parts'].append({**p, 'node': f'{pref} – {p["node"]}' if pref else p['node'], 'pos': pos})
json.dump(out, open(f'build/zestaw_mesh_{w}.json', 'w', encoding='utf-8'), ensure_ascii=False)
subprocess.run(['python3', 'tools/export_inne.py', f'build/zestaw_mesh_{w}.json',
                f'teren/inne_programy/dom_garaz_teren_{w}'], check=True)
