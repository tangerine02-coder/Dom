#!/usr/bin/env bash
# Sprawdza skrypty SketchUpa (dom i garaż) na atrapie API i odtwarza pliki
# do importu: COLLADA (.dae), glTF (.glb) oraz OBJ (+ .mtl).
# Wymaga: ruby, python3, pip install mapbox_earcut numpy
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build inne_programy garaz/inne_programy

for w in antracyt braz; do
  # dom „Smart comfort+”
  ruby tools/run_mock.rb sketchup/dom_smart_comfort.rb "build/model_$w.json" "$w"
  python3 tools/export_model.py "build/model_$w.json" "sketchup/dom_smart_comfort_$w.dae" "build/mesh_$w.json"
  python3 tools/export_inne.py "build/mesh_$w.json" "inne_programy/dom_smart_comfort_$w"

  # garaż
  ruby tools/run_mock.rb garaz/sketchup/garaz.rb "build/garaz_model_$w.json" "$w"
  python3 tools/export_model.py "build/garaz_model_$w.json" "garaz/sketchup/garaz_$w.dae" "build/garaz_mesh_$w.json"
  python3 tools/export_inne.py "build/garaz_mesh_$w.json" "garaz/inne_programy/garaz_$w"
done
