#!/usr/bin/env bash
# Sprawdza skrypt SketchUpa na atrapie API i odtwarza pliki COLLADA (.dae).
# Wymaga: ruby, python3, pip install mapbox_earcut numpy
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for w in antracyt braz; do
  ruby tools/run_mock.rb "build/model_$w.json" "$w"
  python3 tools/export_model.py "build/model_$w.json" "sketchup/dom_smart_comfort_$w.dae" "build/mesh_$w.json"
done
mkdir -p inne_programy
for w in antracyt braz; do
  python3 tools/export_inne.py "build/mesh_$w.json" "inne_programy/dom_smart_comfort_$w"
done
