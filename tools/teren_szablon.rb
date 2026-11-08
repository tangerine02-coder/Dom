# encoding: UTF-8
#
# ============================================================================
#  Teren działki pod dom „Smart comfort+” i garaż – model 3D dla SketchUp
#  Wygenerowany z rzędnych wysokościowych z projektu zagospodarowania
#  terenu (PZT, skala 1:500). Plik powstaje automatycznie
#  (tools/teren_generuj.py) – dane terenu są zapisane niżej jako liczby.
# ----------------------------------------------------------------------------
#  JAK UŻYĆ: najlepiej w modelu domu – Okno → Konsola Ruby i wpisz
#        load 'C:/ścieżka/do/teren.rb'
#  Teren ma ten sam układ co model domu: dom stoi w punkcie (0,0,0),
#  garaż przylega do prawej ściany szczytowej (w skrypcie garażu ustaw
#  @pozycja = [1066.5, 0]). Wysokość z = 0 to poziom ±0,00 domu
#  (wartość w m n.p.m. wypisze się w konsoli). W skryptach domu i garażu
#  ustaw @teren = false, żeby nie dublować płaskiego trawnika.
# ============================================================================

module Teren

  # =============================== USTAWIENIA ===============================
  @warstwice = true   # warstwice co 0,5 m
  @granica   = true   # granica działki i znaki graniczne
  # ==========================================================================

  class << self
    attr_accessor :warstwice, :granica

    def build
      model = Sketchup.active_model
      dane!
      model.start_operation('Teren działki', true)
      begin
        mat = {}
        {
          'Działka'       => ['Teren – trawa (działka)',     [118, 158, 84]],
          'Otoczenie'     => ['Teren – otoczenie działki',   [168, 182, 128]],
          'Utwardzenia'   => ['Teren – kostka brukowa',      [150, 146, 140]],
          'Pod budynkami' => ['Teren – grunt pod budynkami', [140, 120, 96]],
          'Granica'       => ['Teren – granica działki',     [200, 30, 30]]
        }.each do |k, (n, rgb)|
          m = model.materials[n] || model.materials.add(n)
          m.color = Sketchup::Color.new(*rgb)
          mat[k] = m
        end
        tag = model.layers.add('Teren działki')
        root = model.active_entities.add_group
        root.name = 'Teren działki'
        root.layer = tag
        pts = @v.map { |x, y, z| Geom::Point3d.new(x.cm, y.cm, z.cm) }
        @t.each do |nazwa, tris|
          next if tris.empty?
          g = root.entities.add_group
          g.name = "Teren – #{nazwa.to_s.downcase}"
          g.material = mat[nazwa.to_s]
          tris.each do |a, b, c|
            f = g.entities.add_face(pts[a], pts[b], pts[c])
            f.reverse! if f && f.normal.z < 0
          end
          wygladz(g)
        end
        warstwice!(root) if @warstwice
        granica!(root, mat['Granica']) if @granica
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("Nie udało się zbudować terenu:\n#{e.message}")
        raise
      end
      puts "Gotowe: teren działki. Poziom ±0,00 domu = #{format('%.2f', @h0)} m n.p.m."
      root
    end

    # zmiękczenie krawędzi wewnątrz strefy – teren wygląda gładko
    def wygladz(g)
      return unless defined?(Sketchup::Edge)
      g.entities.grep(Sketchup::Edge).each do |e|
        next unless e.faces.size == 2
        e.soft = true
        e.smooth = true
      end
    end

    def warstwice!(root)
      g = root.entities.add_group
      g.name = 'Teren – warstwice co 0,5 m'
      @w.each do |x1, y1, z1, x2, y2, z2|
        g.entities.add_line(Geom::Point3d.new(x1.cm, y1.cm, (z1 + 2).cm), Geom::Point3d.new(x2.cm, y2.cm, (z2 + 2).cm))
      end
    end

    def granica!(root, mat)
      g = root.entities.add_group
      g.name = 'Teren – granica działki'
      g.material = mat
      n = @g.size
      n.times do |i|
        a = @g[i]
        b = @g[(i + 1) % n]
        g.entities.add_line(Geom::Point3d.new(a[0].cm, a[1].cm, (a[2] + 5).cm), Geom::Point3d.new(b[0].cm, b[1].cm, (b[2] + 5).cm))
        slupek(g.entities, a[0], a[1], a[2])
      end
    end

    # znak graniczny 12 x 12 cm, 15 cm ponad teren
    def slupek(ents, x, y, z)
      s = 6.0
      p = ->(dx, dy, dz) { Geom::Point3d.new((x + dx).cm, (y + dy).cm, (z + dz).cm) }
      c = Geom::Point3d.new(x.cm, y.cm, (z + 5).cm)
      [
        [p[-s, -s, -10], p[s, -s, -10], p[s, s, -10], p[-s, s, -10]],
        [p[-s, -s, 15], p[s, -s, 15], p[s, s, 15], p[-s, s, 15]],
        [p[-s, -s, -10], p[s, -s, -10], p[s, -s, 15], p[-s, -s, 15]],
        [p[s, -s, -10], p[s, s, -10], p[s, s, 15], p[s, -s, 15]],
        [p[s, s, -10], p[-s, s, -10], p[-s, s, 15], p[s, s, 15]],
        [p[-s, s, -10], p[-s, -s, -10], p[-s, -s, 15], p[-s, s, 15]]
      ].each do |q|
        f = ents.add_face(q)
        next unless f
        v = q[0] - c
        f.reverse! if f.normal.dot(v) < 0
      end
    end

    # ------------------------------------------------------------------------
    #  DANE TERENU (cm, układ modelu domu; @h0 – ±0,00 domu w m n.p.m.)
    # ------------------------------------------------------------------------
    def dane!
      # @@DANE@@
    end
  end
end

Teren.build
