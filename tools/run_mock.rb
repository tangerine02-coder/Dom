# encoding: UTF-8
# Uruchamia skrypt modelu na atrapie API SketchUpa i zapisuje geometrię do JSON.
#   ruby tools/run_mock.rb <skrypt.rb> <plik_wyjściowy.json> [antracyt|braz]
require_relative 'sketchup_mock'

skrypt = ARGV[0] || File.join(__dir__, '..', 'sketchup', 'dom_smart_comfort.rb')
out = ARGV[1] || File.join(__dir__, '..', 'build', 'model.json')
wariant = (ARGV[2] || 'antracyt').to_sym

# skrypt wywołuje budowę na końcu – wariant ustawiamy przez podmianę
# ustawienia w kodzie źródłowym przed wczytaniem
src = File.read(skrypt, encoding: 'UTF-8')
src = src.sub(/@wariant(\s*)=\s*:\w+/) { "@wariant#{Regexp.last_match(1)}= :#{wariant}" }
eval(src, TOPLEVEL_BINDING, File.basename(skrypt))

require 'fileutils'
FileUtils.mkdir_p(File.dirname(out))
n = Mock.export(Sketchup.active_model, out)
puts "Ścian: #{n}, statystyki: #{Sketchup::STATS}"
puts "Definicje: #{Sketchup.active_model.definitions.map(&:name).join(', ')}"
puts "Sceny: #{Sketchup.active_model.pages.map(&:name).join(', ')}"
puts "Zapisano #{out}"
