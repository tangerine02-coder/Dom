# encoding: UTF-8
# Uruchamia skrypt modelu na atrapie API SketchUpa i zapisuje geometrię do JSON.
#   ruby tools/run_mock.rb [plik_wyjściowy.json] [antracyt|braz]
require_relative 'sketchup_mock'

out = ARGV[0] || File.join(__dir__, '..', 'build', 'model.json')
wariant = (ARGV[1] || 'antracyt').to_sym

# skrypt wywołuje DomSmartComfort.build na końcu – ustawiamy wariant przed
# wczytaniem przez podmianę ustawienia w kodzie źródłowym
src = File.read(File.join(__dir__, '..', 'sketchup', 'dom_smart_comfort.rb'), encoding: 'UTF-8')
src = src.sub(/@wariant\s*=\s*:\w+/, "@wariant      = :#{wariant}")
eval(src, TOPLEVEL_BINDING, 'dom_smart_comfort.rb')

require 'fileutils'
FileUtils.mkdir_p(File.dirname(out))
n = Mock.export(Sketchup.active_model, out)
puts "Ścian: #{n}, statystyki: #{Sketchup::STATS}"
puts "Definicje: #{Sketchup.active_model.definitions.map(&:name).join(', ')}"
puts "Sceny: #{Sketchup.active_model.pages.map(&:name).join(', ')}"
puts "Zapisano #{out}"
