#!/usr/bin/env python3
"""Zapisuje model w formatach dla innych darmowych programów 3D:
  * .glb  (glTF 2.0) – Blender, przeglądarki 3D online, Windows 3D Viewer…
  * .obj + .mtl      – FreeCAD, Sweet Home 3D, Blender i prawie każdy program 3D

Wejście: plik mesh_*.json z tools/export_model.py (współrzędne w cm, oś Z w górę).
Wyjście: metry, oś Y w górę (standard glTF i większości importerów OBJ).

Użycie:  python3 tools/export_inne.py build/mesh_antracyt.json inne_programy/dom_smart_comfort_antracyt
"""
import json
import os
import struct
import sys
from collections import defaultdict

import numpy as np


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def zamien(pos_cm):
    """cm, Z w górę  ->  m, Y w górę:  (x, y, z) -> (x, z, -y)"""
    p = np.asarray(pos_cm, dtype=np.float64).reshape(-1, 3) / 100.0
    return np.stack([p[:, 0], p[:, 2], -p[:, 1]], axis=1)


def normalne(p):
    t = p.reshape(-1, 3, 3)
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return np.repeat(n, 3, axis=0)


def main(src, base):
    data = json.load(open(src, encoding='utf-8'))
    mats = data['materials']
    by_node = defaultdict(lambda: defaultdict(list))
    for part in data['parts']:
        by_node[part['node']][part['mat']].append(zamien(part['pos']))
    os.makedirs(os.path.dirname(base) or '.', exist_ok=True)

    # ------------------------------------------------------------------ GLB
    mat_names = list(mats)
    gl_mats = []
    for n in mat_names:
        m = mats[n]
        a = m.get('alpha', 1.0) or 1.0
        gm = {'name': n, 'pbrMetallicRoughness': {
            'baseColorFactor': [srgb_to_linear(c) for c in m['rgb']] + [a],
            'metallicFactor': 0.0, 'roughnessFactor': 0.85}}
        if a < 1:
            gm['alphaMode'] = 'BLEND'
            gm['doubleSided'] = True
        gl_mats.append(gm)

    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def dodaj(arr, minmax=False):
        arr = np.ascontiguousarray(arr, dtype=np.float32)
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': arr.nbytes, 'target': 34962})
        blob.extend(arr.tobytes())
        acc = {'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(arr), 'type': 'VEC3'}
        if minmax:
            acc['min'] = arr.min(axis=0).tolist()
            acc['max'] = arr.max(axis=0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    for node, parts in by_node.items():
        prims = []
        for mat, chunks in parts.items():
            p = np.concatenate(chunks)
            prims.append({'attributes': {'POSITION': dodaj(p, True), 'NORMAL': dodaj(normalne(p))},
                          'material': mat_names.index(mat)})
        meshes.append({'name': node, 'primitives': prims})
        nodes.append({'name': node, 'mesh': len(meshes) - 1})
    nodes.append({'name': 'Dom Smart comfort+', 'children': list(range(len(nodes)))})
    gltf = {'asset': {'version': '2.0', 'generator': 'dom_smart_comfort.rb'},
            'scene': 0, 'scenes': [{'name': 'Dom Smart comfort+', 'nodes': [len(nodes) - 1]}],
            'nodes': nodes, 'meshes': meshes, 'materials': gl_mats,
            'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(blob)}]}
    js = json.dumps(gltf, ensure_ascii=False).encode('utf-8')
    js += b' ' * (-len(js) % 4)
    blob.extend(b'\0' * (-len(blob) % 4))
    glb = (struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
           + struct.pack('<II', len(js), 0x4E4F534A) + js
           + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob))
    open(base + '.glb', 'wb').write(glb)

    # ------------------------------------------------------------------ OBJ + MTL
    nazwa = lambda s: s.replace(' ', '_')
    mtl_file = os.path.basename(base) + '.mtl'
    with open(base + '.mtl', 'w', encoding='utf-8') as f:
        for n, m in mats.items():
            r, g, b = [c / 255.0 for c in m['rgb']]
            f.write(f'newmtl {nazwa(n)}\nKd {r:.4f} {g:.4f} {b:.4f}\nKa 0 0 0\n'
                    f'd {m.get("alpha", 1.0) or 1.0:.3f}\nillum 1\n\n')
    with open(base + '.obj', 'w', encoding='utf-8') as f:
        f.write('# Dom Smart comfort+ – metry, oś Y w górę\n')
        f.write(f'mtllib {mtl_file}\n')
        v = 0
        for node, parts in by_node.items():
            f.write(f'o {nazwa(node)}\n')
            for mat, chunks in parts.items():
                p = np.concatenate(chunks)
                f.write(f'usemtl {nazwa(mat)}\n')
                f.write(''.join(f'v {a:.4f} {b:.4f} {c:.4f}\n' for a, b, c in p))
                f.write(''.join(f'f {v + i + 1} {v + i + 2} {v + i + 3}\n' for i in range(0, len(p), 3)))
                v += len(p)
    print(f'Zapisano {base}.glb ({len(glb) / 1e6:.1f} MB) oraz {base}.obj/.mtl')


if __name__ == '__main__':
    main(*sys.argv[1:3])
