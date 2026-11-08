# encoding: UTF-8
#
# ============================================================================
#  Dom jednorodzinny „Smart comfort+” (SENDOM Domy Drewniane) – model 3D
#  Skrypt dla SketchUp (Ruby Console). Wymiary wg projektu z 01.2025:
#  rzuty parteru i poddasza, rzut dachu, przekroje A-A i B-B, elewacje,
#  zestawienie stolarki.
# ----------------------------------------------------------------------------
#  JAK UŻYĆ
#   1. Otwórz SketchUp (wersja desktopowa: Pro / Make 2017 / wersja próbna).
#   2. Okno (Window) → Konsola Ruby (Ruby Console).
#   3. Wpisz (podając swoją ścieżkę do pliku) i naciśnij Enter:
#        load 'C:/Users/Ja/Pobrane/dom_smart_comfort.rb'
#      (na Macu np. load '/Users/ja/Downloads/dom_smart_comfort.rb')
#   4. Model zbuduje się w kilka sekund jako jedna grupa „Dom Smart comfort+”.
#      Całość można cofnąć jednym Ctrl+Z.
#
#  Wariant kolorystyczny i inne opcje zmienisz w sekcji USTAWIENIA poniżej.
#  Jednostki: centymetry. Poziom ±0,00 = posadzka parteru.
#  Oś X – wzdłuż kalenicy (od ściany szczytowej z oknem W1),
#  oś Y – od elewacji frontowej (wejście) w stronę ogrodu, oś Z – w górę.
# ============================================================================

module DomSmartComfort

  # =============================== USTAWIENIA ===============================
  # Wariant elewacji (dwa warianty z projektu):
  #   :antracyt – deska elewacyjna i stolarka RAL 7016 (antracyt)
  #   :braz     – deska elewacyjna 1806 Nordika (brązowa), stolarka orzech
  @wariant      = :antracyt
  @teren        = true   # trawnik wokół domu
  @wnetrza      = true   # posadzki, strop, ściany działowe, schody, drzwi wewn.
  @fotowoltaika = true   # panele PV na połaci od strony ogrodu
  @sceny        = true   # gotowe sceny: widoki 3D, elewacje, rzuty
  # ==========================================================================

  class << self
    attr_accessor :wariant, :teren, :wnetrza, :fotowoltaika, :sceny

    # ------------------------------------------------------------------------
    #  GŁÓWNA PROCEDURA
    # ------------------------------------------------------------------------
    def build
      model = Sketchup.active_model
      @model = model
      @defs = {}
      wymiary!
      model.start_operation('Dom Smart comfort+', true)
      begin
        jednostki!
        materialy!
        tagi!
        root = model.active_entities.add_group
        root.name = 'Dom Smart comfort+'
        @root = root.entities

        teren! if @teren
        fundament!
        sciany_szczytowe!
        sciany_podluzne!
        dach!
        obrobki_blacharskie!
        elewacja_drewniana!
        zadaszenie_wejscia!
        detale_zewnetrzne!
        if @wnetrza
          posadzki_i_strop!
          sciany_dzialowe_parter!
          sciany_dzialowe_poddasze!
          schody!
          balustrada!
        end
        fotowoltaika! if @fotowoltaika
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("Nie udało się zbudować modelu:\n#{e.message}")
        raise
      end

      if @sceny
        begin
          sceny!
        rescue StandardError => e
          puts "Model gotowy, ale nie udało się utworzyć scen: #{e.message}"
        end
      end
      puts 'Gotowe: model domu „Smart comfort+” został zbudowany.'
      root
    end

    # ------------------------------------------------------------------------
    #  WYMIARY (cm) – odczytane z rysunków
    # ------------------------------------------------------------------------
    def wymiary!
      @L       = 1066.5  # długość całkowita (razem ze ścianami szczytowymi)
      @FIN     = 33.2    # grubość ściany szczytowej
      @D       = 829.0   # szerokość: lico ściany frontowej – lico ściany ogrodowej
      @WT      = 33.5    # grubość ścian podłużnych
      @FIN_OUT = 15.0    # wysunięcie ścian szczytowych przed lica ścian podłużnych
      @FIN_UP  = 15.0    # wysunięcie ścian szczytowych ponad pokrycie dachu
      @X0 = @FIN
      @X1 = @L - @FIN    # wnętrze 1000 cm
      @Y0 = @WT
      @Y1 = @D - @WT     # wnętrze 762 cm
      @RIDGE_Y = @D / 2.0

      a = 40.0 * Math::PI / 180.0  # kąt dachu 40° (84%)
      @TAN = Math.tan(a)
      @SIN = Math.sin(a)
      @COS = Math.cos(a)
      @Z_KALENICA = 691.0                          # +6,91
      @Z_OKAP     = @Z_KALENICA - @RIDGE_Y * @TAN  # ok. +3,43 w licu ściany
      @DACH_TV    = 37.0 / @COS                    # warstwy dachu 37 cm (w pionie)

      @Z_FUND     = -43.0  # spód płyty fundamentowej (-0,43)
      @Z_TEREN    = -29.0  # teren (-0,29)
      @Z_SUFIT    = 260.0  # sufit parteru (+2,60)
      @Z_PODDASZE = 294.0  # posadzka poddasza (+2,94)
      @Z_SCIANA   = 295.0  # góra ścian podłużnych (spód dachu w licu)
      @NADPROZE   = 221.0  # góra otworów okiennych i drzwiowych
      @OSADZENIE  = 8.0    # cofnięcie stolarki od lica elewacji
      @OP_S0      = 85.0   # odległość okna dachowego od okapu (po połaci)
    end

    # wysokość wierzchu pokrycia dachu nad punktem o współrzędnej y
    def dach_gora(y)
      @Z_OKAP + @TAN * [y, @D - y].min
    end

    def dach_dol(y)
      dach_gora(y) - @DACH_TV
    end

    # wierzch ściany szczytowej (płetwy)
    def plet(y)
      dach_gora(y) + @FIN_UP
    end

    # ------------------------------------------------------------------------
    #  MATERIAŁY, TAGI, JEDNOSTKI
    # ------------------------------------------------------------------------
    def jednostki!
      o = @model.options['UnitsOptions']
      o['LengthUnit'] = 3    # cm
      o['LengthFormat'] = 0  # dziesiętne
    rescue StandardError
      nil
    end

    def materialy!
      braz = (@wariant == :braz)
      @mat = {}
      kolory = {
        tynk:       ['Tynk silikonowy biały',           [243, 243, 239]],
        ral9005:    ['Blacha RAL 9005',                 [28, 28, 30]],
        pokrycie:   ['Blachodachówka modułowa RAL 9005', [34, 34, 37]],
        okno_dach:  ['Okno dachowe – rama',             [56, 62, 66]],
        stolarka:   braz ? ['Stolarka orzech', [92, 60, 36]] : ['Stolarka RAL 7016', [56, 62, 66]],
        deska:      braz ? ['Deska elewacyjna 1806 Nordika', [122, 84, 54]] : ['Deska elewacyjna RAL 7016', [64, 70, 76]],
        szklo:      ['Szkło',                           [150, 185, 205], 0.35],
        pv:         ['Panel fotowoltaiczny',            [26, 34, 51]],
        beton:      ['Beton',                           [165, 165, 160]],
        podloga:    ['Panele podłogowe',                [201, 169, 121]],
        sufit:      ['Płyta g-k biała',                 [248, 248, 246]],
        sciana_w:   ['Ściany wewnętrzne',               [246, 245, 241]],
        drzwi_w:    ['Drzwi wewnętrzne',                [236, 236, 232]],
        schody:     ['Schody – drewno',                 [176, 136, 88]],
        stal:       ['Stal nierdzewna',                 [176, 178, 180]],
        pompa:      ['Pompa ciepła – obudowa',          [214, 216, 218]],
        kostka:     ['Kostka betonowa',                 [140, 140, 136]],
        trawa:      ['Trawnik',                         [124, 160, 88]]
      }
      kolory.each do |key, (nazwa, rgb, alpha)|
        m = @model.materials[nazwa] || @model.materials.add(nazwa)
        m.color = Sketchup::Color.new(*rgb)
        m.alpha = alpha if alpha
        @mat[key] = m
      end
    end

    def tagi!
      nazwy = {
        teren:     'Teren',
        fund:      'Fundament',
        szczyt:    'Ściany szczytowe',
        zewn:      'Ściany zewnętrzne',
        dach:      'Dach',
        obrobki:   'Obróbki blacharskie',
        okna:      'Okna i drzwi zewnętrzne',
        okna_dach: 'Okna dachowe',
        deska:     'Elewacja – deska',
        detale:    'Detale zewnętrzne',
        pv:        'Fotowoltaika',
        parter:    'Parter – wnętrze',
        strop:     'Strop nad parterem',
        poddasze:  'Poddasze – wnętrze'
      }
      @tag = {}
      nazwy.each { |k, n| @tag[k] = @model.layers.add(n) }
    end

    # ------------------------------------------------------------------------
    #  NARZĘDZIA GEOMETRYCZNE (wszystko w cm)
    # ------------------------------------------------------------------------
    def p3(a)
      Geom::Point3d.new(a[0].to_f.cm, a[1].to_f.cm, a[2].to_f.cm)
    end

    def vadd(a, b) [a[0] + b[0], a[1] + b[1], a[2] + b[2]] end
    def vsub(a, b) [a[0] - b[0], a[1] - b[1], a[2] - b[2]] end
    def vmul(a, s) [a[0] * s, a[1] * s, a[2] * s] end
    def vdot(a, b) a[0] * b[0] + a[1] * b[1] + a[2] * b[2] end

    def vcross(a, b)
      [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    end

    def vnorm(a)
      l = Math.sqrt(vdot(a, a))
      [a[0] / l, a[1] / l, a[2] / l]
    end

    # wektor normalny wielokąta (metoda Newella) – wielokąt jest CCW względem niego
    def newell(poly)
      n = [0.0, 0.0, 0.0]
      poly.each_with_index do |p, i|
        q = poly[(i + 1) % poly.size]
        n[0] += (p[1] - q[1]) * (p[2] + q[2])
        n[1] += (p[2] - q[2]) * (p[0] + q[0])
        n[2] += (p[0] - q[0]) * (p[1] + q[1])
      end
      n
    end

    def oczysc(poly)
      out = []
      poly.each do |p|
        out << p if out.empty? || vdot(vsub(p, out[-1]), vsub(p, out[-1])) > 1e-4
      end
      out.pop if out.size > 1 && vdot(vsub(out[0], out[-1]), vsub(out[0], out[-1])) < 1e-4
      out
    end

    def orientuj(face, want)
      return unless face && face.valid?
      n = face.normal
      face.reverse! if n.x * want[0] + n.y * want[1] + n.z * want[2] < 0
    end

    # płaska ściana z otworami; want = kierunek, w który ma patrzeć lico
    def lico(ents, outer, holes, want)
      f = ents.add_face(outer.map { |p| p3(p) })
      holes.each do |h|
        hf = ents.add_face(h.map { |p| p3(p) })
        hf.erase! if hf && hf.valid? && hf != f
      end
      orientuj(f, want)
      f
    end

    # Bryła: płaski wielokąt `outer` (z otworami `holes`) wyciągnięty o wektor
    # `vec`. Zwraca lica: :cap0 (wielokąt wyjściowy), :cap1 (przesunięty),
    # :sides (boczne). Normalne skierowane na zewnątrz bryły.
    def bryla(ents, outer, holes, vec)
      outer = oczysc(outer)
      holes = holes.map { |h| oczysc(h) }
      n = vnorm(newell(outer))
      holes = holes.map { |h| vdot(newell(h), n) > 0 ? h.reverse : h }
      cap0 = lico(ents, outer, holes, vmul(vec, -1))
      cap1 = lico(ents, outer.map { |p| vadd(p, vec) },
                  holes.map { |h| h.map { |p| vadd(p, vec) } }, vec)
      sides = []
      ([outer] + holes).each do |loop|
        loop.each_with_index do |p, i|
          q = loop[(i + 1) % loop.size]
          f = ents.add_face(p3(p), p3(q), p3(vadd(q, vec)), p3(vadd(p, vec)))
          orientuj(f, vcross(vsub(q, p), n))
          sides << f
        end
      end
      { cap0: cap0, cap1: cap1, sides: sides }
    end

    def grupa(parent, nazwa, mat = nil, tag = nil)
      g = parent.add_group
      g.name = nazwa
      g.material = @mat[mat] if mat
      g.layer = @tag[tag] if tag
      g
    end

    def prostokat(u0, v0, u1, v1)
      [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]
    end

    def kostka(parent, nazwa, x0, y0, z0, x1, y1, z1, mat = nil, tag = nil)
      g = grupa(parent, nazwa, mat, tag)
      bryla(g.entities, [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]], [], [0, 0, z1 - z0])
      g
    end

    # Ściana w pionowej płaszczyźnie: punkt = origin + u*u_dir + v*Z,
    # grubość = wektor t_vec. Kontur i otwory podane w (u, v).
    def sciana(parent, nazwa, origin, u_dir, t_vec, kontur, otwory, mat, tag)
      g = grupa(parent, nazwa, mat, tag)
      map = ->(uv) { vadd(vadd(origin, vmul(u_dir, uv[0])), [0, 0, uv[1]]) }
      bryla(g.entities, kontur.map(&map), otwory.map { |h| h.map(&map) }, t_vec)
      g
    end

    # Wstawia komponent (okno/drzwi) w otwór ściany. Lokalnie: X w prawo
    # (patrząc od strony lica początkowego), Y w głąb muru, Z w górę.
    def wstaw(parent, defn, origin, u_dir, t_vec, u0, u1, v0, glebokosc, nazwa = nil)
      t = vnorm(t_vec)
      if vcross(u_dir, t)[2] > 0
        xa = u_dir
        o = vadd(origin, vmul(u_dir, u0))
      else
        xa = vmul(u_dir, -1)
        o = vadd(origin, vmul(u_dir, u1))
      end
      o = vadd(vadd(o, [0, 0, v0]), vmul(t, glebokosc))
      tr = Geom::Transformation.axes(p3(o), Geom::Vector3d.new(*xa),
                                     Geom::Vector3d.new(*t), Geom::Vector3d.new(0, 0, 1))
      inst = parent.add_instance(defn, tr)
      inst.name = nazwa if nazwa
      inst
    end

    # odsunięcie wypukłego wielokąta 2D (CCW) do środka o d
    def odsun(poly, d)
      n = poly.size
      linie = (0...n).map do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        dx = b[0] - a[0]
        dz = b[1] - a[1]
        l = Math.hypot(dx, dz)
        [[a[0] - dz / l * d, a[1] + dx / l * d], [dx, dz]]
      end
      (0...n).map do |i|
        p, r = linie[i - 1]
        q, s = linie[i]
        cr = r[0] * s[1] - r[1] * s[0]
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / cr
        [p[0] + r[0] * t, p[1] + r[1] * t]
      end
    end

    # ------------------------------------------------------------------------
    #  DEFINICJE KOMPONENTÓW (stolarka)
    # ------------------------------------------------------------------------
    # Okno: kontur ramy i szyby w lokalnej płaszczyźnie XZ, głębokość w +Y.
    def def_okna(nazwa, kontur, szyby, gl = 8.0)
      return @defs[nazwa] if @defs[nazwa]
      d = @model.definitions.add(nazwa)
      to3 = ->(p) { [p[0], 0, p[1]] }
      g = d.entities.add_group
      g.name = 'Rama'
      g.material = @mat[:stolarka]
      bryla(g.entities, kontur.map(&to3), szyby.map { |s| s.map(&to3) }, [0, gl, 0])
      gs = d.entities.add_group
      gs.name = 'Szyba'
      szyby.each do |s|
        f = gs.entities.add_face(s.map { |p| p3([p[0], gl / 2.0, p[1]]) })
        next unless f
        f.material = @mat[:szklo]
        f.back_material = @mat[:szklo]
      end
      @defs[nazwa] = d
    end

    # okno prostokątne: w, h = wymiar otworu w ścianie
    def okno_prost(nazwa, w, h, kwatery = 1)
      fr = 7.0
      k = prostokat(0.5, 0.5, w - 0.5, h - 0.5)
      x0 = 0.5 + fr
      x1 = w - 0.5 - fr
      z0 = 0.5 + fr
      z1 = h - 0.5 - fr
      szyby = if kwatery == 2
                m = w / 2.0
                [prostokat(x0, z0, m - 4, z1), prostokat(m + 4, z0, x1, z1)]
              else
                [prostokat(x0, z0, x1, z1)]
              end
      def_okna(nazwa, k, szyby)
    end

    # W2 – okno trapezowe w szczycie (górna krawędź równoległa do połaci)
    def otwor_w2(w, h)
      [[0, 0], [w, 0], [w, h], [0, h - w * @TAN]]
    end

    def okno_w2(w, h)
      k = odsun(otwor_w2(w, h), 0.5)
      def_okna('W2 witryna 160x185', k, [odsun(k, 7.0)])
    end

    # DZ – drzwi zewnętrzne wejściowe z lamelami
    def drzwi_dz
      nazwa = 'DZ drzwi zewnętrzne 90x210'
      return @defs[nazwa] if @defs[nazwa]
      w = 103.0
      h = @NADPROZE
      fr = 7.0
      gl = 8.0
      d = @model.definitions.add(nazwa)
      e = d.entities
      rama = [[0.5, 0], [0.5 + fr, 0], [0.5 + fr, h - 0.5 - fr], [w - 0.5 - fr, h - 0.5 - fr],
              [w - 0.5 - fr, 0], [w - 0.5, 0], [w - 0.5, h - 0.5], [0.5, h - 0.5]]
      g = e.add_group
      g.name = 'Ościeżnica'
      g.material = @mat[:stolarka]
      bryla(g.entities, rama.map { |p| [p[0], 0, p[1]] }, [], [0, gl, 0])
      x0 = 0.5 + fr
      x1 = w - 0.5 - fr
      z1 = h - 0.5 - fr
      s = grupa(e, 'Skrzydło', :stolarka)
      bryla(s.entities, [[x0, 1, 0.5], [x1, 1, 0.5], [x1, 1, z1], [x0, 1, z1]], [], [0, 6, 0])
      lam = grupa(e, 'Lamele', :deska)
      xl1 = x0 + 0.62 * (x1 - x0)
      z = 8.0
      while z + 5 <= z1 - 6
        bryla(lam.entities, [[x0 + 3, -0.5, z], [xl1, -0.5, z], [xl1, -0.5, z + 5], [x0 + 3, -0.5, z + 5]], [], [0, 1.5, 0])
        z += 9.0
      end
      k = grupa(e, 'Pochwyt', :stal)
      bryla(k.entities, [[x1 - 9, -4, 80], [x1 - 6, -4, 80], [x1 - 6, -4, 150], [x1 - 9, -4, 150]], [], [0, 5, 0])
      @defs[nazwa] = d
    end

    # D1 / D2 – drzwi wewnętrzne 80x200 (otwór 93x205), t = grubość ściany
    def drzwi_wewn(typ, t)
      nazwa = "#{typ} drzwi wewnętrzne 80x200 (ściana #{t.round(1)} cm)"
      return @defs[nazwa] if @defs[nazwa]
      w = 93.0
      h = 205.0
      fr = 6.0
      d = @model.definitions.add(nazwa)
      e = d.entities
      rama = [[0.5, 0], [0.5 + fr, 0], [0.5 + fr, h - 0.5 - fr], [w - 0.5 - fr, h - 0.5 - fr],
              [w - 0.5 - fr, 0], [w - 0.5, 0], [w - 0.5, h - 0.5], [0.5, h - 0.5]]
      g = grupa(e, 'Ościeżnica', :drzwi_w)
      bryla(g.entities, rama.map { |p| [p[0], -1, p[1]] }, [], [0, t + 2, 0])
      x0 = 0.5 + fr
      x1 = w - 0.5 - fr
      z1 = h - 0.5 - fr
      yc = t / 2.0
      s = grupa(e, 'Skrzydło', :drzwi_w)
      bryla(s.entities, [[x0, yc - 2, 1], [x1, yc - 2, 1], [x1, yc - 2, z1], [x0, yc - 2, z1]], [], [0, 4, 0])
      k = grupa(e, 'Klamka', :stal)
      bryla(k.entities, [[x1 - 14, yc - 7, 100], [x1 - 4, yc - 7, 100], [x1 - 4, yc - 7, 103], [x1 - 14, yc - 7, 103]], [], [0, 14, 0])
      @defs[nazwa] = d
    end

    # OP – okno dachowe 78x140. Lokalnie: X wzdłuż okapu, Y poziomo w stronę
    # kalenicy, Z w górę; początek = środek dolnej krawędzi na pokryciu.
    def okno_dachowe
      nazwa = 'OP okno dachowe 78x140'
      return @defs[nazwa] if @defs[nazwa]
      d = @model.definitions.add(nazwa)
      e = d.entities
      sl = ->(u, s, lift) { [u, s * @COS, s * @SIN + lift] }
      zew = [sl[-39, 0, 10], sl[39, 0, 10], sl[39, 140, 10], sl[-39, 140, 10]]
      wew = [sl[-31, 8, 10], sl[31, 8, 10], sl[31, 132, 10], sl[-31, 132, 10]]
      g = grupa(e, 'Rama i kołnierz', :okno_dach)
      bryla(g.entities, zew, [wew], [0, 0, -(10 + @DACH_TV + 3)])
      gs = grupa(e, 'Szyba')
      f = gs.entities.add_face([sl[-31, 8, 7], sl[31, 8, 7], sl[31, 132, 7], sl[-31, 132, 7]].map { |p| p3(p) })
      if f
        f.material = @mat[:szklo]
        f.back_material = @mat[:szklo]
      end
      @defs[nazwa] = d
    end

    # panel PV 1722 x 1134 mm
    def panel_pv
      nazwa = 'Panel PV 1722x1134'
      return @defs[nazwa] if @defs[nazwa]
      d = @model.definitions.add(nazwa)
      g = grupa(d.entities, 'Panel')
      r = bryla(g.entities, [[0, 0, 0], [113.4, 0, 0], [113.4, 172.2, 0], [0, 172.2, 0]], [], [0, 0, 3.5])
      r[:cap1].material = @mat[:pv]
      ([r[:cap0]] + r[:sides]).each { |f| f.material = @mat[:ral9005] if f }
      @defs[nazwa] = d
    end

    # ------------------------------------------------------------------------
    #  TEREN I FUNDAMENT
    # ------------------------------------------------------------------------
    def teren!
      g = grupa(@root, 'Teren', :trawa, :teren)
      z = @Z_TEREN
      f = g.entities.add_face([[-1500, -1500, z], [@L + 1500, -1500, z],
                               [@L + 1500, @D + 1500, z], [-1500, @D + 1500, z]].map { |p| p3(p) })
      orientuj(f, [0, 0, 1])
    end

    def fundament!
      kostka(@root, 'Płyta fundamentowa', 0, -@FIN_OUT, @Z_FUND, @L, @D + @FIN_OUT, -2, :beton, :fund)
    end

    # ------------------------------------------------------------------------
    #  ŚCIANY SZCZYTOWE („płetwy” wystające ponad dach i przed elewacje)
    # ------------------------------------------------------------------------
    def sciany_szczytowe!
      y_a = -@FIN_OUT
      y_b = @D + @FIN_OUT
      kontur = [[y_a, -2], [y_b, -2], [y_b, plet(y_b)], [@RIDGE_Y, plet(@RIDGE_Y)], [y_a, plet(y_a)]]

      # W1 (160x220) na parterze i W2 (160x185) na poddaszu – jedna oś
      w = 161.0
      u1 = @D + @FIN_OUT - 99.0 + 0.5  # rama 99 cm od tylnego narożnika ściany
      u0 = u1 - w
      w1 = prostokat(u0, 0, u1, @NADPROZE)
      w2 = otwor_w2(w, 186.0).map { |p| [u1 - p[0], @Z_PODDASZE + p[1]] }

      lewa = [0.0, 0.0, 0.0]
      sciana(@root, 'Ściana szczytowa lewa', lewa, [0, 1, 0], [@FIN, 0, 0], kontur, [w1, w2], :tynk, :szczyt)
      wstaw(@root, okno_prost('W1 witryna 160x220', w, @NADPROZE), lewa, [0, 1, 0], [@FIN, 0, 0],
            u0, u1, 0, @OSADZENIE, 'W1').layer = @tag[:okna]
      wstaw(@root, okno_w2(w, 186.0), lewa, [0, 1, 0], [@FIN, 0, 0],
            u0, u1, @Z_PODDASZE, @OSADZENIE, 'W2').layer = @tag[:okna]

      prawa = [@L, 0.0, 0.0]
      sciana(@root, 'Ściana szczytowa prawa', prawa, [0, 1, 0], [-@FIN, 0, 0], kontur, [], :tynk, :szczyt)
    end

    # ------------------------------------------------------------------------
    #  ŚCIANY PODŁUŻNE (frontowa z wejściem, ogrodowa z wyjściem na taras)
    # ------------------------------------------------------------------------
    def sciany_podluzne!
      kontur = prostokat(@X0, -2, @X1, @Z_SCIANA)

      # elewacja frontowa: O1, DZ, O2, O1 (położenie wg rzutu parteru)
      front = [
        [:o1, 132.2, 263.2, 90.0],
        [:dz, 437.5, 540.5, 0.0],
        [:o2, 680.9, 741.9, 90.0],
        [:o1, 832.4, 963.4, 90.0]
      ]
      o = [0.0, 0.0, 0.0]
      t = [0.0, @WT, 0.0]
      otw = front.map { |_, a, b, v| prostokat(a, v, b, @NADPROZE) }
      sciana(@root, 'Ściana frontowa', o, [1, 0, 0], t, kontur, otw, :tynk, :zewn)
      front.each do |typ, a, b, v|
        defn = case typ
               when :o1 then okno_prost('O1 okno 130x130', b - a, @NADPROZE - v)
               when :o2 then okno_prost('O2 okno 60x130', b - a, @NADPROZE - v)
               when :dz then drzwi_dz
               end
        inst = wstaw(@root, defn, o, [1, 0, 0], t, a, b, v, @OSADZENIE, typ.to_s.upcase)
        inst.layer = @tag[:okna]
        next if v <= 0
        # parapet zewnętrzny
        kostka(@root, "Parapet #{typ.to_s.upcase}", a - 2.5, -4, v - 3, b + 2.5, @OSADZENIE, v + 0.5, :ral9005, :obrobki)
      end

      # elewacja ogrodowa: Ot1 (HS 320x220) i Ot2 (drzwi 100x220)
      ogrod = [[:ot1, 84.5, 404.5], [:ot2, 714.5, 814.5]]
      o = [0.0, @D, 0.0]
      t = [0.0, -@WT, 0.0]
      otw = ogrod.map { |_, a, b| prostokat(a, 0, b, @NADPROZE) }
      sciana(@root, 'Ściana ogrodowa', o, [1, 0, 0], t, kontur, otw, :tynk, :zewn)
      ogrod.each do |typ, a, b|
        defn = if typ == :ot1
                 okno_prost('Ot1 okno przesuwne HS 320x220', b - a, @NADPROZE, 2)
               else
                 okno_prost('Ot2 drzwi balkonowe 100x220', b - a, @NADPROZE)
               end
        wstaw(@root, defn, o, [1, 0, 0], t, a, b, 0, @OSADZENIE, typ.to_s.capitalize).layer = @tag[:okna]
      end

      # nadścianki (ścianki kolankowe) – klin pod połacią
      [[0.0, @WT], [@D, @D - @WT]].each_with_index do |(yz, yw), i|
        g = grupa(@root, i.zero? ? 'Ścianka kolankowa frontowa' : 'Ścianka kolankowa ogrodowa', :tynk, :zewn)
        bryla(g.entities, [[@X0, yz, @Z_SCIANA], [@X0, yw, @Z_SCIANA], [@X0, yw, dach_dol(yw) + 1]], [], [@X1 - @X0, 0, 0])
      end
    end

    # ------------------------------------------------------------------------
    #  DACH (dwie połacie 40°, między ścianami szczytowymi) + okna dachowe
    # ------------------------------------------------------------------------
    def dach!
      smax = @RIDGE_Y / @COS
      okna = { przod: [187.2, 494.2, 801.2], tyl: [187.2, 801.2] }
      okna.each do |strona, xs|
        sl = if strona == :przod
               ->(x, s) { [x, s * @COS, @Z_OKAP + s * @SIN] }
             else
               ->(x, s) { [x, @D - s * @COS, @Z_OKAP + s * @SIN] }
             end
        kontur = [sl[@X0, 0], sl[@X1, 0], sl[@X1, smax], sl[@X0, smax]]
        s0 = @OP_S0
        otwory = xs.map do |x|
          [sl[x + 0.5, s0 + 0.5], sl[x + 77.5, s0 + 0.5], sl[x + 77.5, s0 + 139.5], sl[x + 0.5, s0 + 139.5]]
        end
        g = grupa(@root, strona == :przod ? 'Dach – połać frontowa' : 'Dach – połać ogrodowa', nil, :dach)
        r = bryla(g.entities, kontur, otwory, [0, 0, -@DACH_TV])
        r[:cap0].material = @mat[:pokrycie]
        r[:cap1].material = @mat[:sufit]
        r[:sides].each { |f| f.material = @mat[:sufit] if f }

        defn = okno_dachowe
        xs.each_with_index do |x, i|
          o = p3(sl[x + 39, s0])
          tr = if strona == :przod
                 Geom::Transformation.new(o)
               else
                 Geom::Transformation.axes(o, Geom::Vector3d.new(-1, 0, 0), Geom::Vector3d.new(0, -1, 0), Geom::Vector3d.new(0, 0, 1))
               end
          inst = @root.add_instance(defn, tr)
          inst.name = "OP #{strona == :przod ? 'front' : 'ogród'} #{i + 1}"
          inst.layer = @tag[:okna_dach]
        end
      end
    end

    # ------------------------------------------------------------------------
    #  OBRÓBKI BLACHARSKIE RAL 9005
    # ------------------------------------------------------------------------
    def obrobki_blacharskie!
      # pas okapowy z blachy na rąbek stojący (6)
      zd = dach_dol(0)
      [[-2.0, 0.0, -3.5, -2.0, 'frontowy'], [@D, @D + 2.0, @D + 2.0, @D + 3.5, 'ogrodowy']].each do |y0, y1, r0, r1, n|
        kostka(@root, "Pas okapowy #{n}", @X0, y0, zd, @X1, y1, @Z_OKAP, :ral9005, :obrobki)
        g = grupa(@root, "Rąbki pasa okapowego #{n}", :ral9005, :obrobki)
        krok = (@X1 - @X0) / 19.0
        (1..18).each do |i|
          x = @X0 + i * krok
          bryla(g.entities, [[x - 1, r0, zd], [x + 1, r0, zd], [x + 1, r1, zd], [x - 1, r1, zd]], [], [0, 0, @Z_OKAP - zd])
        end
      end

      # gąsior
      g = grupa(@root, 'Gąsior', :ral9005, :obrobki)
      ya = @RIDGE_Y - 20
      yb = @RIDGE_Y + 20
      bryla(g.entities, [[@X0, ya, dach_gora(ya)], [@X0, @RIDGE_Y, @Z_KALENICA], [@X0, yb, dach_gora(yb)],
                         [@X0, yb, dach_gora(yb) + 2.5], [@X0, @RIDGE_Y, @Z_KALENICA + 2.5], [@X0, ya, dach_gora(ya) + 2.5]],
            [], [@X1 - @X0, 0, 0])

      # opierzenie ścian szczytowych (5): czapa na „płetwie” + pasy poziome
      ya = -@FIN_OUT - 2
      yb = @D + @FIN_OUT + 2
      [[-1.5, 'lewej'], [@X1 - 1.5, 'prawej']].each do |x, n|
        g = grupa(@root, "Opierzenie ściany szczytowej #{n}", :ral9005, :obrobki)
        bryla(g.entities, [[x, ya, plet(ya)], [x, @RIDGE_Y, plet(@RIDGE_Y)], [x, yb, plet(yb)],
                           [x, yb, plet(yb) + 3], [x, @RIDGE_Y, plet(@RIDGE_Y) + 3], [x, ya, plet(ya) + 3]],
              [], [@FIN + 3, 0, 0])
      end
      yg = (543.0 - @FIN_UP - @Z_OKAP) / @TAN
      [[-2.0, 0.0, 'lewa'], [@L, @L + 2.0, 'prawa']].each do |x0, x1, n|
        kostka(@root, "Pas blachy na szczycie #{n} – dolny", x0, -@FIN_OUT, 287, x1, @D + @FIN_OUT, 290, :ral9005, :obrobki)
        kostka(@root, "Pas blachy na szczycie #{n} – górny", x0, yg, 540, x1, @D - yg, 543, :ral9005, :obrobki)
      end

      # rury spustowe Ø80
      [[@X0 + 6, -8.0], [@X1 - 6, -8.0], [@X0 + 6, @D + 8], [@X1 - 6, @D + 8]].each_with_index do |(cx, cy), i|
        g = grupa(@root, "Rura spustowa #{i + 1}", :ral9005, :obrobki)
        kolo = (0...12).map { |k| a = k * Math::PI / 6; [cx + 4 * Math.cos(a), cy + 4 * Math.sin(a), @Z_TEREN] }
        bryla(g.entities, kolo, [], [0, 0, zd - @Z_TEREN])
      end
    end

    # ------------------------------------------------------------------------
    #  DESKA ELEWACYJNA (2)
    # ------------------------------------------------------------------------
    def deski(g, x0, x1, z0, z1, ya, yb)
      szczelina = 1.5
      n = ((z1 - z0 + szczelina) / (12.5 + szczelina)).round
      h = (z1 - z0 - (n - 1) * szczelina) / n
      n.times do |i|
        za = z0 + i * (h + szczelina)
        bryla(g.entities, [[x0, ya, za], [x1, ya, za], [x1, yb, za], [x0, yb, za]], [], [0, 0, h])
      end
    end

    def elewacja_drewniana!
      g = grupa(@root, 'Deska elewacyjna – front', :deska, :deska)
      [[263.2, 362.0], [540.5, 680.9], [741.9, 832.4]].each { |a, b| deski(g, a, b, 90.0, @NADPROZE, -2.0, 0.0) }
      g = grupa(@root, 'Deska elewacyjna – ogród', :deska, :deska)
      deski(g, 404.5, 714.5, 0.0, @NADPROZE, @D, @D + 2.0)
    end

    # ------------------------------------------------------------------------
    #  ZADASZENIE WEJŚCIA, PODEST, POMPA CIEPŁA, CZERPNIA
    # ------------------------------------------------------------------------
    def zadaszenie_wejscia!
      kostka(@root, 'Podest wejściowy', 352, -100, @Z_TEREN, 580, 0, -4, :kostka, :detale)
      kostka(@root, 'Zadaszenie – ścianka boczna', 362, -74, -4, 376, 0, 256, :tynk, :detale)
      kostka(@root, 'Zadaszenie – daszek', 362, -74, 256, 566, 0, 273, :tynk, :detale)
      kostka(@root, 'Zadaszenie – obróbka', 361, -75, 273, 567, 0, 275, :ral9005, :obrobki)
    end

    def detale_zewnetrzne!
      g = grupa(@root, 'Pompa ciepła – jednostka zewnętrzna', nil, :detale)
      kostka(g.entities, 'Nóżka 1', -60, 52, @Z_TEREN, -30, 58, -5, :ral9005)
      kostka(g.entities, 'Nóżka 2', -60, 122, @Z_TEREN, -30, 128, -5, :ral9005)
      kostka(g.entities, 'Obudowa', -65, 45, -5, -25, 135, 70, :pompa)
      kostka(@root, 'Czerpnia / wyrzutnia', -2, 46, 259, 0, 62, 275, :ral9005, :detale)
    end

    # ------------------------------------------------------------------------
    #  WNĘTRZA
    # ------------------------------------------------------------------------
    # obrys stropu z otworem na schody (otwór dochodzi do ściany ogrodowej)
    def obrys_stropu(z)
      [[@X0, @Y0], [@X1, @Y0], [@X1, @Y1], [631.9, @Y1], [631.9, 566.8], [540.0, 566.8],
       [540.0, 704.8], [434.4, 704.8], [434.4, @Y1], [@X0, @Y1]].map { |x, y| [x, y, z] }
    end

    def posadzki_i_strop!
      kostka(@root, 'Posadzka parteru', @X0, @Y0, -2, @X1, @Y1, 0, :podloga, :parter)
      g = grupa(@root, 'Strop nad parterem', :sufit, :strop)
      bryla(g.entities, obrys_stropu(@Z_SUFIT), [], [0, 0, @Z_PODDASZE - 2 - @Z_SUFIT])
      g = grupa(@root, 'Posadzka poddasza', :podloga, :strop)
      bryla(g.entities, obrys_stropu(@Z_PODDASZE - 2), [], [0, 0, 2])
    end

    # ściana działowa z drzwiami; drzwi = [[typ, u0, u1], ...]
    def dzialowa(nazwa, origin, u_dir, grubosc, t_dir, kontur, drzwi, z0, tag)
      t_vec = vmul(t_dir, grubosc)
      otw = drzwi.map { |_, a, b| prostokat(a, z0, b, z0 + 205.0) }
      sciana(@root, nazwa, origin, u_dir, t_vec, kontur, otw, :sciana_w, tag)
      drzwi.each do |typ, a, b|
        wstaw(@root, drzwi_wewn(typ, grubosc), origin, u_dir, t_vec, a, b, z0, 0, typ).layer = @tag[tag]
      end
    end

    def sciany_dzialowe_parter!
      h = [-2.0, @Z_SUFIT]
      pr = ->(len) { prostokat(0, h[0], len, h[1]) }
      # ściana przy schodach (oddziela klatkę od pokoju 1)
      dzialowa('Parter – ściana przy schodach', [630.7, 443.1, 0], [0, 1, 0], 15.0, [1, 0, 0], pr[@Y1 - 443.1], [], 0, :parter)
      # pokój 1 – ściana od strony holu (drzwi D1)
      dzialowa('Parter – ściana pokoju 1', [645.7, 443.1, 0], [1, 0, 0], 15.1, [0, 1, 0], pr[@X1 - 645.7],
               [['D1', 3.3, 96.3]], 0, :parter)
      # pokój 2 / łazienka (drzwi D1 do pokoju 2)
      dzialowa('Parter – ściana pokoju 2', [787.4, @Y0, 0], [0, 1, 0], 15.0, [1, 0, 0], pr[443.1 - @Y0],
               [['D1', 300.0 - @Y0, 393.0 - @Y0]], 0, :parter)
      # wiatrołap + łazienka od strony holu (D1 do salonu, D2 do łazienki)
      dzialowa('Parter – ściana wiatrołapu i łazienki', [334.4, 279.9, 0], [1, 0, 0], 12.5, [0, 1, 0], pr[787.4 - 334.4],
               [['D1', 445.0 - 334.4, 538.0 - 334.4], ['D2', 647.7 - 334.4, 740.7 - 334.4]], 0, :parter)
      # wiatrołap | łazienka
      dzialowa('Parter – ściana wiatrołap/łazienka', [576.6, @Y0, 0], [0, 1, 0], 12.5, [1, 0, 0], pr[279.9 - @Y0], [], 0, :parter)
      # wiatrołap | kuchnia
      dzialowa('Parter – ściana wiatrołap/kuchnia', [334.4, @Y0, 0], [0, 1, 0], 12.5, [1, 0, 0], pr[279.9 - @Y0], [], 0, :parter)
    end

    def sciany_dzialowe_poddasze!
      zb = @Z_PODDASZE - 2
      dl = @Y1 - @Y0
      kontur = [[0, zb], [dl, zb], [dl, dach_dol(@Y1) + 1], [@RIDGE_Y - @Y0, dach_dol(@RIDGE_Y) + 1], [0, dach_dol(@Y0) + 1]]
      drzwi = [['D1', 396.0 - @Y0, 489.0 - @Y0]]
      dzialowa('Poddasze – ściana pokoju 2.4', [421.9, @Y0, 0], [0, 1, 0], 12.5, [1, 0, 0], kontur, drzwi, @Z_PODDASZE, :poddasze)
      dzialowa('Poddasze – ściana pokoju 2.3', [631.9, @Y0, 0], [0, 1, 0], 12.5, [1, 0, 0], kontur, drzwi, @Z_PODDASZE, :poddasze)
      zt = dach_dol(391.7) + 1
      dzialowa('Poddasze – ściana łazienki', [434.4, 379.2, 0], [1, 0, 0], 12.5, [0, 1, 0],
               prostokat(0, zb, 631.9 - 434.4, zt), [['D2', 2.0, 95.5]], @Z_PODDASZE, :poddasze)
    end

    # schody zabiegowe 16 x 18,4 cm: bieg wzdłuż ściany ogrodowej, 3 stopnie
    # zabiegowe w narożniku, bieg wzdłuż ściany pokoju 1 – wyjście na hol poddasza
    def schody!
      sg = grupa(@root, 'Schody', :schody, :parter)
      rise = @Z_PODDASZE / 16.0
      step = lambda do |k, poly|
        top = rise * k
        bot = [0.0, top - 30.0].max
        g = grupa(sg.entities, "Stopień #{k}")
        bryla(g.entities, poly.map { |x, y| [x, y, bot] }, [], [0, 0, top - bot])
      end
      ya = 704.8
      yb = @Y1
      xs = 540.0
      xe = 630.7
      (1..6).each do |k|
        x0 = xs - 23.0 * (7 - k)
        step.call(k, [[x0, ya], [x0 + 23, ya], [x0 + 23, yb], [x0, yb]])
      end
      xm = xs + (yb - ya) * Math.tan(30 * Math::PI / 180)
      ym = ya + (xe - xs) * Math.tan(30 * Math::PI / 180)
      step.call(7, [[xs, ya], [xs, yb], [xm, yb]])
      step.call(8, [[xs, ya], [xm, yb], [xe, yb], [xe, ym]])
      step.call(9, [[xs, ya], [xe, ym], [xe, ya]])
      (10..15).each do |k|
        y1 = ya - 23.0 * (k - 10)
        step.call(k, [[xs, y1 - 23], [xe, y1 - 23], [xe, y1], [xs, y1]])
      end
    end

    def balustrada!
      g = grupa(@root, 'Balustrada poddasza', :ral9005, :poddasze)
      z0 = @Z_PODDASZE
      z1 = z0 + 100
      kostka(g.entities, 'Pochwyt 1', 536, 566.8, z1 - 5, 540, 704.8, z1)
      kostka(g.entities, 'Pochwyt 2', 434.4, 700.8, z1 - 5, 536, 704.8, z1)
      sl = grupa(g.entities, 'Tralki')
      y = 572.0
      while y < 700
        bryla(sl.entities, [[537, y, z0], [539, y, z0], [539, y + 2, z0], [537, y + 2, z0]], [], [0, 0, z1 - 5 - z0])
        y += 11.0
      end
      x = 440.0
      while x < 530
        bryla(sl.entities, [[x, 701.8, z0], [x + 2, 701.8, z0], [x + 2, 703.8, z0], [x, 703.8, z0]], [], [0, 0, z1 - 5 - z0])
        x += 11.0
      end
    end

    # ------------------------------------------------------------------------
    #  FOTOWOLTAIKA – 12 paneli na połaci ogrodowej (wg rzutu dachu)
    # ------------------------------------------------------------------------
    def fotowoltaika!
      defn = panel_pv
      g = grupa(@root, 'Instalacja fotowoltaiczna', nil, :pv)
      kol1 = (0..3).map { |k| @X0 + 20.9 + k * 115.4 }
      kol2 = (0..3).map { |k| @X0 + 519.4 + k * 115.4 }
      dolny = [kol1[0], kol1[2], kol2[1], kol2[3]]  # rząd przy okapie (między oknami dachowymi)
      gorny = kol1 + kol2
      xa = Geom::Vector3d.new(-1, 0, 0)
      ya = Geom::Vector3d.new(0, -@COS, @SIN)
      za = Geom::Vector3d.new(0, @SIN, @COS)
      [[70.0, dolny], [244.2, gorny]].each do |s0, xs|
        xs.each do |x|
          o = [x + 113.4, @D - s0 * @COS + 12 * @SIN, @Z_OKAP + s0 * @SIN + 12 * @COS]
          g.entities.add_instance(defn, Geom::Transformation.axes(p3(o), xa, ya, za))
        end
      end
    end

    # ------------------------------------------------------------------------
    #  SCENY
    # ------------------------------------------------------------------------
    def sceny!
      pages = @model.pages
      view = @model.active_view
      cx = @L / 2.0
      cy = @D / 2.0
      warstwy = @model.layers

      dodaj = lambda do |nazwa, eye, target, up, persp, wys, ukryte|
        warstwy.each { |l| l.visible = true }
        ukryte.each { |k| @tag[k].visible = false }
        cam = Sketchup::Camera.new(p3(eye), p3(target), Geom::Vector3d.new(*up))
        cam.perspective = persp
        if persp
          cam.fov = 35.0
        else
          cam.height = wys.cm
        end
        view.camera = cam
        pages.add(nazwa)
      end

      z = [0, 0, 1]
      dodaj.call('Widok 3D – front', [cx - 1350, -1450, 760], [cx, cy, 260], z, true, nil, [])
      dodaj.call('Widok 3D – ogród', [cx + 1350, @D + 1450, 760], [cx, cy, 260], z, true, nil, [])
      dodaj.call('Elewacja frontowa', [cx, -4000, 330], [cx, 0, 330], z, false, 900, [])
      dodaj.call('Elewacja ogrodowa', [cx, @D + 4000, 330], [cx, @D, 330], z, false, 900, [])
      dodaj.call('Elewacja boczna (W1)', [-4000, cy, 330], [0, cy, 330], z, false, 900, [])
      ukryj_dach = %i[dach okna_dach pv obrobki]
      dodaj.call('Rzut parteru', [cx, cy, 4000], [cx, cy, 0], [0, 1, 0], false, 1100,
                 ukryj_dach + %i[strop poddasze])
      dodaj.call('Rzut poddasza', [cx, cy, 4000], [cx, cy, 0], [0, 1, 0], false, 1100, ukryj_dach)

      warstwy.each { |l| l.visible = true }
      pages.selected_page = pages['Widok 3D – front'] if pages['Widok 3D – front']
    end
  end
end

DomSmartComfort.build
