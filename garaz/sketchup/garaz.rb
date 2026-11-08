# encoding: UTF-8
#
# ============================================================================
#  Garaż – budynek jednorodzinny, część gospodarczo-garażowa – model 3D
#  Skrypt dla SketchUp (Ruby Console). Wymiary wg projektu z 10.2026:
#  rzut parteru, rzut strychu, rzut dachu, przekrój A-A, elewacje,
#  zestawienie stolarki. Model samego garażu (bez domu).
# ----------------------------------------------------------------------------
#  JAK UŻYĆ
#   1. Otwórz SketchUp na komputerze (Pro / wersja próbna / Make 2017).
#   2. Okno (Window) → Konsola Ruby (Ruby Console).
#   3. Wpisz (ze swoją ścieżką do pliku) i naciśnij Enter:
#        load 'C:/Users/Ja/Pobrane/garaz.rb'
#   4. Model zbuduje się jako jedna grupa „Garaż”. Ctrl+Z cofa całość.
#
#  Jednostki: centymetry. Poziom ±0,00 = posadzka domu (jak w projekcie);
#  posadzka garażu −0,13, teren −0,29.
#  Oś X – wzdłuż kalenicy (od strony domu w stronę ściany szczytowej),
#  oś Y – od bramy garażowej w stronę ogrodu, oś Z – w górę.
# ============================================================================

module Garaz

  # =============================== USTAWIENIA ===============================
  # Wariant kolorystyczny:
  #   :antracyt – deska i stolarka RAL 7016 (jak w projekcie garażu)
  #   :braz     – deska 1806 Nordika, stolarka orzech (jak brązowy wariant domu)
  @wariant = :antracyt
  @teren   = true   # trawnik wokół budynku
  @wnetrza = true   # posadzka, strop, ściany działowe, drzwi wewnętrzne
  @sceny   = true   # gotowe sceny: widoki 3D, elewacje, rzuty
  # ==========================================================================

  class << self
    attr_accessor :wariant, :teren, :wnetrza, :sceny

    # ------------------------------------------------------------------------
    #  GŁÓWNA PROCEDURA
    # ------------------------------------------------------------------------
    def build
      model = Sketchup.active_model
      @model = model
      @defs = {}
      wymiary!
      model.start_operation('Garaż', true)
      begin
        jednostki!
        materialy!
        tagi!
        root = model.active_entities.add_group
        root.name = 'Garaż – część gospodarczo-garażowa'
        @root = root.entities

        teren! if @teren
        fundament_i_cokol!
        sciany_szczytowe!
        sciany_podluzne!
        dach!
        obrobki_blacharskie!
        elewacja_drewniana!
        detale_zewnetrzne!
        if @wnetrza
          posadzka_i_strop!
          sciany_dzialowe!
        end
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
      puts 'Gotowe: model garażu został zbudowany.'
      root
    end

    # ------------------------------------------------------------------------
    #  WYMIARY (cm) – odczytane z rysunków
    # ------------------------------------------------------------------------
    def wymiary!
      @L       = 600.0  # szerokość całkowita (z prawą ścianą szczytową)
      @D       = 829.0  # głębokość: lico ściany frontowej – lico ściany ogrodowej
      @WT      = 21.0   # grubość ścian zewnętrznych
      @WL      = 16.0   # lewa ściana (w projekcie przylega do domu)
      @XF      = 579.0  # wewnętrzne lico prawej ściany szczytowej
      @FIN_OUT = 15.0   # wysunięcie ściany szczytowej przed elewacje
      @FIN_UP  = 12.0   # wysunięcie ściany szczytowej ponad pokrycie (+6,42)
      @RIDGE_Y = @D / 2.0

      a = 40.0 * Math::PI / 180.0  # dach 40°
      @TAN = Math.tan(a)
      @SIN = Math.sin(a)
      @COS = Math.cos(a)
      @Z_KALENICA = 630.0                          # +6,30
      @Z_OKAP     = @Z_KALENICA - @RIDGE_Y * @TAN  # ok. +2,82 w licu ściany
      @DACH_TV    = 25.0 / @COS                    # warstwy dachu ok. 25 cm

      @Z_FUND     = -44.0  # spód płyty z izolacją
      @Z_PLYTA    = -15.0  # wierzch płyty fundamentowej
      @Z_POSADZKA = -13.0  # posadzka garażu (−0,13)
      @Z_TEREN    = -29.0  # teren (−0,29)
      @Z_SUFIT    = 247.0  # sufit (+2,47)
      @Z_STRYCH   = 274.0  # podłoga strychu (+2,74)
      @Z_PAS      = 212.0  # dół pasa blachy = góra bramy (+2,12)
      @Z_PARAPET  = 66.5   # dół otworów okiennych (okno 80 cm nad posadzką)
      @Z_NADPROZE = 199.5  # góra otworów okiennych (otwór 133 cm)
      @Z_DRZWI    = 202.0  # góra otworu drzwi D1 (otwór 215 cm)
      @OSADZENIE  = 8.0    # cofnięcie stolarki od lica elewacji
    end

    def dach_gora(y)
      @Z_OKAP + @TAN * [y, @D - y].min
    end

    def dach_dol(y)
      dach_gora(y) - @DACH_TV
    end

    def plet(y)
      dach_gora(y) + @FIN_UP
    end

    # ------------------------------------------------------------------------
    #  MATERIAŁY, TAGI, JEDNOSTKI
    # ------------------------------------------------------------------------
    def jednostki!
      o = @model.options['UnitsOptions']
      o['LengthUnit'] = 3
      o['LengthFormat'] = 0
    rescue StandardError
      nil
    end

    def materialy!
      braz = (@wariant == :braz)
      @mat = {}
      kolory = {
        tynk:      ['Tynk silikonowy biały',            [243, 243, 239]],
        cokol:     ['Tynk mozaikowy grafitowy',         [74, 77, 80]],
        ral9005:   ['Blacha RAL 9005',                  [28, 28, 30]],
        pokrycie:  ['Blachodachówka modułowa RAL 9005', [34, 34, 37]],
        okno_dach: ['Okno dachowe – rama',              [56, 62, 66]],
        stolarka:  braz ? ['Stolarka orzech', [92, 60, 36]] : ['Stolarka RAL 7016', [56, 62, 66]],
        deska:     braz ? ['Deska elewacyjna 1806 Nordika', [122, 84, 54]] : ['Deska elewacyjna RAL 7016', [64, 70, 76]],
        szklo:     ['Szkło',                            [150, 185, 205], 0.35],
        beton:     ['Beton',                            [165, 165, 160]],
        gres:      ['Płytki gresowe',                   [158, 154, 146]],
        deski:     ['Deski podłogowe',                  [196, 160, 110]],
        sufit:     ['Płyta g-k biała',                  [248, 248, 246]],
        sciana_w:  ['Ściany wewnętrzne',                [246, 245, 241]],
        drzwi_w:   ['Drzwi wewnętrzne',                 [236, 236, 232]],
        stal:      ['Stal nierdzewna',                  [176, 178, 180]],
        kostka:    ['Kostka betonowa',                  [140, 140, 136]],
        trawa:     ['Trawnik',                          [124, 160, 88]]
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
        fund:      'Fundament i cokół',
        szczyt:    'Ściany szczytowe',
        zewn:      'Ściany zewnętrzne',
        dach:      'Dach',
        obrobki:   'Obróbki blacharskie',
        okna:      'Okna, drzwi i brama',
        okna_dach: 'Okna dachowe',
        deska:     'Elewacja – deska',
        detale:    'Detale zewnętrzne',
        parter:    'Parter – wnętrze',
        strop:     'Strop i strych'
      }
      @tag = {}
      nazwy.each { |k, n| @tag[k] = @model.layers.add(n) }
    end

    # ------------------------------------------------------------------------
    #  NARZĘDZIA GEOMETRYCZNE (wszystko w cm) – jak w skrypcie domu
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

    def lico(ents, outer, holes, want)
      f = ents.add_face(outer.map { |p| p3(p) })
      holes.each do |h|
        hf = ents.add_face(h.map { |p| p3(p) })
        hf.erase! if hf && hf.valid? && hf != f
      end
      orientuj(f, want)
      f
    end

    # bryła: płaski wielokąt z otworami wyciągnięty o wektor vec
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

    def walec(parent, nazwa, cx, cy, r, z0, z1, mat = nil, tag = nil)
      g = grupa(parent, nazwa, mat, tag)
      kolo = (0...12).map { |k| a = k * Math::PI / 6; [cx + r * Math.cos(a), cy + r * Math.sin(a), z0] }
      bryla(g.entities, kolo, [], [0, 0, z1 - z0])
      g
    end

    def sciana(parent, nazwa, origin, u_dir, t_vec, kontur, otwory, mat, tag)
      g = grupa(parent, nazwa, mat, tag)
      map = ->(uv) { vadd(vadd(origin, vmul(u_dir, uv[0])), [0, 0, uv[1]]) }
      bryla(g.entities, kontur.map(&map), otwory.map { |h| h.map(&map) }, t_vec)
      g
    end

    # wstawia komponent w otwór: lokalnie X w prawo (od strony lica
    # początkowego), Y w głąb muru, Z w górę
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

    # ------------------------------------------------------------------------
    #  DEFINICJE KOMPONENTÓW (stolarka)
    # ------------------------------------------------------------------------
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
    def okno_prost(nazwa, w, h)
      fr = 7.0
      def_okna(nazwa, prostokat(0.5, 0.5, w - 0.5, h - 0.5),
               [prostokat(0.5 + fr, 0.5 + fr, w - 0.5 - fr, h - 0.5 - fr)])
    end

    def rama_u(w, h, fr)
      [[0.5, 0], [0.5 + fr, 0], [0.5 + fr, h - 0.5 - fr], [w - 0.5 - fr, h - 0.5 - fr],
       [w - 0.5 - fr, 0], [w - 0.5, 0], [w - 0.5, h - 0.5], [0.5, h - 0.5]]
    end

    # D1 – drzwi zewnętrzne pełne 90x210 (otwór 105x215), zawiasy lewe
    def drzwi_d1(w, h)
      nazwa = 'D1 drzwi zewnętrzne 90x210'
      return @defs[nazwa] if @defs[nazwa]
      fr = 7.0
      d = @model.definitions.add(nazwa)
      e = d.entities
      g = grupa(e, 'Ościeżnica', :stolarka)
      bryla(g.entities, rama_u(w, h, fr).map { |p| [p[0], 0, p[1]] }, [], [0, 8, 0])
      x0 = 0.5 + fr
      x1 = w - 0.5 - fr
      z1 = h - 0.5 - fr
      s = grupa(e, 'Skrzydło', :stolarka)
      bryla(s.entities, [[x0, 1, 0.5], [x1, 1, 0.5], [x1, 1, z1], [x0, 1, z1]], [], [0, 6, 0])
      k = grupa(e, 'Klamka', :stal)
      bryla(k.entities, [[x0 + 5, -5, 100], [x0 + 19, -5, 100], [x0 + 19, -5, 103], [x0 + 5, -5, 103]], [], [0, 6, 0])
      @defs[nazwa] = d
    end

    # D2 – drzwi wewnętrzne 80x200 (otwór 93x208), t = grubość ściany
    def drzwi_wewn(t)
      nazwa = "D2 drzwi wewnętrzne 80x200 (ściana #{t.round(1)} cm)"
      return @defs[nazwa] if @defs[nazwa]
      w = 93.0
      h = 208.0
      fr = 6.0
      d = @model.definitions.add(nazwa)
      e = d.entities
      g = grupa(e, 'Ościeżnica', :drzwi_w)
      bryla(g.entities, rama_u(w, h, fr).map { |p| [p[0], -1, p[1]] }, [], [0, t + 2, 0])
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

    # BG – brama segmentowa 400x225 montowana za otworem (od środka)
    def brama_bg(w, h)
      nazwa = 'BG brama garażowa segmentowa 400x225'
      return @defs[nazwa] if @defs[nazwa]
      d = @model.definitions.add(nazwa)
      e = d.entities
      g = grupa(e, 'Panele', :stolarka)
      bryla(g.entities, [[-5, 0, 0], [w + 5, 0, 0], [w + 5, 0, h + 5], [-5, 0, h + 5]], [], [0, 4, 0])
      lin = grupa(e, 'Przetłoczenia', :ral9005)
      (1..3).each do |i|
        z = h * i / 4.0
        bryla(lin.entities, [[0.5, -0.6, z - 0.75], [w - 0.5, -0.6, z - 0.75], [w - 0.5, -0.6, z + 0.75], [0.5, -0.6, z + 0.75]], [], [0, 0.6, 0])
      end
      @defs[nazwa] = d
    end

    # OP – okno dachowe; lokalnie X wzdłuż okapu, Y poziomo do kalenicy
    def okno_dachowe(w, h)
      nazwa = "OP okno dachowe #{w.round}x#{h.round}"
      return @defs[nazwa] if @defs[nazwa]
      d = @model.definitions.add(nazwa)
      e = d.entities
      sl = ->(u, s, lift) { [u, s * @COS, s * @SIN + lift] }
      hw = w / 2.0
      zew = [sl[-hw, 0, 10], sl[hw, 0, 10], sl[hw, h, 10], sl[-hw, h, 10]]
      wew = [sl[-hw + 8, 8, 10], sl[hw - 8, 8, 10], sl[hw - 8, h - 8, 10], sl[-hw + 8, h - 8, 10]]
      g = grupa(e, 'Rama i kołnierz', :okno_dach)
      bryla(g.entities, zew, [wew], [0, 0, -(10 + @DACH_TV + 3)])
      gs = grupa(e, 'Szyba')
      f = gs.entities.add_face([sl[-hw + 8, 8, 7], sl[hw - 8, 8, 7], sl[hw - 8, h - 8, 7], sl[-hw + 8, h - 8, 7]].map { |p| p3(p) })
      if f
        f.material = @mat[:szklo]
        f.back_material = @mat[:szklo]
      end
      @defs[nazwa] = d
    end

    # ------------------------------------------------------------------------
    #  TEREN, FUNDAMENT, COKÓŁ
    # ------------------------------------------------------------------------
    def teren!
      g = grupa(@root, 'Teren', :trawa, :teren)
      z = @Z_TEREN
      f = g.entities.add_face([[-1200, -1500, z], [@L + 1200, -1500, z],
                               [@L + 1200, @D + 1500, z], [-1200, @D + 1500, z]].map { |p| p3(p) })
      orientuj(f, [0, 0, 1])
    end

    def fundament_i_cokol!
      kostka(@root, 'Płyta fundamentowa', 0, 0, @Z_FUND, @L, @D, @Z_PLYTA, :beton, :fund)
      kostka(@root, 'Płyta pod ścianą szczytową', @XF, -@FIN_OUT, @Z_FUND, @L, @D + @FIN_OUT, @Z_PLYTA, :beton, :fund)

      # cokół – tynk mozaikowy grafitowy (3), od terenu do ok. −0,02
      g = grupa(@root, 'Cokół – tynk mozaikowy', :cokol, :fund)
      t = 1.5
      z0 = @Z_TEREN
      z1 = -2.0
      fo = @FIN_OUT
      [
        ['front 1',             -t, -t, 89.0, 0],
        ['front 2',             487.0, -t, @XF, 0],
        ['szczyt – bok przód',  @XF - t, -fo - t, @XF, 0],
        ['szczyt – czoło przód', @XF - t, -fo - t, @L + t, -fo],
        ['szczyt – bok',        @L, -fo - t, @L + t, @D + fo + t],
        ['szczyt – czoło tył',  @XF - t, @D + fo, @L + t, @D + fo + t],
        ['szczyt – bok tył',    @XF - t, @D, @XF, @D + fo + t],
        ['ogród 1',             152.5, @D, @XF, @D + t],
        ['ogród 2',             -t, @D, 47.5, @D + t],
        ['bok lewy',            -t, -t, 0, @D + t]
      ].each { |n, x0, y0, x1, y1| kostka(g.entities, "Cokół #{n}", x0, y0, z0, x1, y1, z1) }
    end

    # ------------------------------------------------------------------------
    #  ŚCIANY SZCZYTOWE
    # ------------------------------------------------------------------------
    def sciany_szczytowe!
      # prawa – „płetwa” wysunięta 15 cm przed elewacje i 12 cm ponad dach
      ya = -@FIN_OUT
      yb = @D + @FIN_OUT
      kontur = [[ya, @Z_PLYTA], [yb, @Z_PLYTA], [yb, plet(yb)], [@RIDGE_Y, plet(@RIDGE_Y)], [ya, plet(ya)]]
      sciana(@root, 'Ściana szczytowa prawa', [@L, 0, 0], [0, 1, 0], [-(@L - @XF), 0, 0], kontur, [], :tynk, :szczyt)

      # lewa – w projekcie przylega do domu; między ścianami podłużnymi,
      # zakończona pod połacią
      y0 = @WT
      y1 = @D - @WT
      kontur = [[y0, @Z_PLYTA], [y1, @Z_PLYTA], [y1, dach_dol(y1)], [@RIDGE_Y, dach_dol(@RIDGE_Y)], [y0, dach_dol(y0)]]
      sciana(@root, 'Ściana szczytowa lewa (od strony domu)', [0, 0, 0], [0, 1, 0], [@WL, 0, 0], kontur, [], :tynk, :szczyt)
    end

    # ------------------------------------------------------------------------
    #  ŚCIANY PODŁUŻNE: frontowa z bramą, ogrodowa z oknami i drzwiami
    # ------------------------------------------------------------------------
    def sciany_podluzne!
      zg = dach_dol(0)  # spód połaci w licu ściany
      kontur = prostokat(0, @Z_PLYTA, @XF, zg)

      # front – brama BG 400x225 (otwór 89 cm od lewego narożnika)
      o = [0.0, 0.0, 0.0]
      t = [0.0, @WT, 0.0]
      bg = [89.0, 487.0, @Z_POSADZKA, @Z_PAS]
      sciana(@root, 'Ściana frontowa', o, [1, 0, 0], t, kontur, [prostokat(bg[0], bg[2], bg[1], bg[3])], :tynk, :zewn)
      wstaw(@root, brama_bg(bg[1] - bg[0], bg[3] - bg[2]), o, [1, 0, 0], t, bg[0], bg[1], bg[2], @WT, 'BG').layer = @tag[:okna]

      # ogród – D1, O2, O1 (otwory wg zestawienia, osie wg rzutu)
      ogrod = [
        [:d1, 47.5, 152.5, @Z_POSADZKA, @Z_DRZWI],
        [:o2, 198.5, 281.5, @Z_PARAPET, @Z_NADPROZE],
        [:o1, 423.5, 526.5, @Z_PARAPET, @Z_NADPROZE]
      ]
      o = [0.0, @D, 0.0]
      t = [0.0, -@WT, 0.0]
      sciana(@root, 'Ściana ogrodowa', o, [1, 0, 0], t, kontur,
             ogrod.map { |_, a, b, v0, v1| prostokat(a, v0, b, v1) }, :tynk, :zewn)
      ogrod.each do |typ, a, b, v0, v1|
        defn = case typ
               when :d1 then drzwi_d1(b - a, v1 - v0)
               when :o2 then okno_prost('O2 okno 80x130', b - a, v1 - v0)
               when :o1 then okno_prost('O1 okno 100x130', b - a, v1 - v0)
               end
        wstaw(@root, defn, o, [1, 0, 0], t, a, b, v0, @OSADZENIE, typ.to_s.upcase).layer = @tag[:okna]
        next if typ == :d1
        kostka(@root, "Parapet #{typ.to_s.upcase}", a - 2.5, @D - @OSADZENIE, v0 - 3, b + 2.5, @D + 4, v0 + 0.5, :ral9005, :obrobki)
      end

      # wieniec / klin pod połacią (góra ścian zewnętrznych ok. +2,80)
      [[0.0, @WT, 'frontowej'], [@D, @D - @WT, 'ogrodowej']].each do |yz, yw, n|
        g = grupa(@root, "Klin ściany #{n} pod dachem", :tynk, :zewn)
        bryla(g.entities, [[0, yz, zg], [0, yw, zg], [0, yw, dach_dol(yw)]], [], [@XF, 0, 0])
      end
    end

    # ------------------------------------------------------------------------
    #  DACH – dwie połacie 40° od lewego lica do ściany szczytowej
    # ------------------------------------------------------------------------
    def dach!
      smax = @RIDGE_Y / @COS
      op_w = 78.0
      op_h = 148.0
      op_s0 = 132.0 / @COS  # wg rzutu dachu: 132 cm (w rzucie) od lica ściany
      { przod: [], tyl: [202.0] }.each do |strona, xs|
        sl = if strona == :przod
               ->(x, s) { [x, s * @COS, @Z_OKAP + s * @SIN] }
             else
               ->(x, s) { [x, @D - s * @COS, @Z_OKAP + s * @SIN] }
             end
        kontur = [sl[0, 0], sl[@XF, 0], sl[@XF, smax], sl[0, smax]]
        otwory = xs.map do |x|
          [sl[x + 0.5, op_s0 + 0.5], sl[x + op_w - 0.5, op_s0 + 0.5],
           sl[x + op_w - 0.5, op_s0 + op_h - 0.5], sl[x + 0.5, op_s0 + op_h - 0.5]]
        end
        g = grupa(@root, strona == :przod ? 'Dach – połać frontowa' : 'Dach – połać ogrodowa', nil, :dach)
        r = bryla(g.entities, kontur, otwory, [0, 0, -@DACH_TV])
        r[:cap0].material = @mat[:pokrycie]
        r[:cap1].material = @mat[:sufit]
        r[:sides].each { |f| f.material = @mat[:pokrycie] if f }

        xs.each do |x|
          o = p3(sl[x + op_w / 2, op_s0])
          tr = Geom::Transformation.axes(o, Geom::Vector3d.new(-1, 0, 0), Geom::Vector3d.new(0, -1, 0), Geom::Vector3d.new(0, 0, 1))
          inst = @root.add_instance(okno_dachowe(op_w, op_h), tr)
          inst.name = 'OP'
          inst.layer = @tag[:okna_dach]
        end
      end
    end

    # ------------------------------------------------------------------------
    #  OBRÓBKI BLACHARSKIE, RYNNY, RURY SPUSTOWE (RAL 9005)
    # ------------------------------------------------------------------------
    def obrobki_blacharskie!
      # pas z blachy na rąbek stojący (6) – od góry bramy do okapu
      [[-2.0, 0.0, -3.5, -2.0, 'frontowy'], [@D, @D + 2.0, @D + 2.0, @D + 3.5, 'ogrodowy']].each do |y0, y1, r0, r1, n|
        kostka(@root, "Pas blachy #{n}", 0, y0, @Z_PAS, @XF, y1, @Z_OKAP, :ral9005, :obrobki)
        g = grupa(@root, "Rąbki pasa #{n}", :ral9005, :obrobki)
        krok = @XF / 11.0
        (1..10).each do |i|
          x = i * krok
          bryla(g.entities, [[x - 1, r0, @Z_PAS], [x + 1, r0, @Z_PAS], [x + 1, r1, @Z_PAS], [x - 1, r1, @Z_PAS]], [], [0, 0, @Z_OKAP - @Z_PAS])
        end
      end

      # gąsior
      g = grupa(@root, 'Gąsior', :ral9005, :obrobki)
      ya = @RIDGE_Y - 20
      yb = @RIDGE_Y + 20
      bryla(g.entities, [[0, ya, dach_gora(ya)], [0, @RIDGE_Y, @Z_KALENICA], [0, yb, dach_gora(yb)],
                         [0, yb, dach_gora(yb) + 2.5], [0, @RIDGE_Y, @Z_KALENICA + 2.5], [0, ya, dach_gora(ya) + 2.5]],
            [], [@XF, 0, 0])

      # czapa na ścianie szczytowej (w rzucie dachu 31 cm szerokości)
      ya = -@FIN_OUT - 1
      yb = @D + @FIN_OUT + 1
      g = grupa(@root, 'Opierzenie ściany szczytowej', :ral9005, :obrobki)
      bryla(g.entities, [[@XF - 6, ya, plet(ya)], [@XF - 6, @RIDGE_Y, plet(@RIDGE_Y)], [@XF - 6, yb, plet(yb)],
                         [@XF - 6, yb, plet(yb) + 3], [@XF - 6, @RIDGE_Y, plet(@RIDGE_Y) + 3], [@XF - 6, ya, plet(ya) + 3]],
            [], [(@L - @XF) + 10, 0, 0])

      # pasy blachy na elewacji bocznej (6)
      yg = (463.0 - @FIN_UP - @Z_OKAP) / @TAN
      kostka(@root, 'Pas blachy na szczycie – dolny', @L, -@FIN_OUT, @Z_PAS - 2, @L + 2, @D + @FIN_OUT, @Z_PAS + 1, :ral9005, :obrobki)
      kostka(@root, 'Pas blachy na szczycie – górny', @L, yg, 460, @L + 2, @D - yg, 463, :ral9005, :obrobki)

      # rynny stalowe Ø120 i rury spustowe Ø90 przy ścianie szczytowej
      zr = @Z_OKAP - 4
      [[-8.0, 'frontowa'], [@D + 8, 'ogrodowa']].each do |cy, n|
        g = grupa(@root, "Rynna #{n} Ø120", :ral9005, :obrobki)
        pol = (0..12).map { |k| a = Math::PI * k / 12; [0.0, cy + 6 * Math.cos(a), zr - 6 * Math.sin(a)] }
        bryla(g.entities, pol, [], [@XF, 0, 0])
        walec(@root, "Rura spustowa #{n} Ø90", @XF - 7, cy, 4.5, @Z_TEREN, zr - 4, :ral9005, :obrobki)
      end
    end

    # ------------------------------------------------------------------------
    #  DESKA ELEWACYJNA (2) – między oknami i drzwiami od strony ogrodu
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
      g = grupa(@root, 'Deska elewacyjna – ogród', :deska, :deska)
      [[152.5, 198.5], [281.5, 423.5]].each { |a, b| deski(g, a, b, @Z_PARAPET, @Z_NADPROZE, @D, @D + 2.0) }
    end

    # ------------------------------------------------------------------------
    #  PODJAZD, PODEST, WYWIEWKA
    # ------------------------------------------------------------------------
    def detale_zewnetrzne!
      g = grupa(@root, 'Podjazd przed bramą (spadek 8%)', :kostka, :detale)
      bryla(g.entities, [[30, 0, @Z_TEREN], [30, 0, -13.5], [30, -140, -13.5 - 140 * 0.08], [30, -140, @Z_TEREN]],
            [], [500, 0, 0])
      kostka(@root, 'Odwodnienie liniowe', 33, -14, -15, 527, -2, -13.4, :ral9005, :detale)
      kostka(@root, 'Podest przy drzwiach D1', 30, @D, @Z_TEREN, 176, @D + 116, -15, :kostka, :detale)

      # wywiewka grawitacyjna na połaci ogrodowej przy kalenicy
      y = @D - 345.0
      z = dach_gora(y)
      walec(@root, 'Wywiewka – rura', 541, y, 7.5, z - 8, z + 45, :ral9005, :detale)
      walec(@root, 'Wywiewka – daszek', 541, y, 11, z + 45, z + 52, :ral9005, :detale)
    end

    # ------------------------------------------------------------------------
    #  WNĘTRZE
    # ------------------------------------------------------------------------
    def posadzka_i_strop!
      kostka(@root, 'Posadzka – płytki gresowe', @WL, @WT, @Z_PLYTA, @XF, @D - @WT, @Z_POSADZKA, :gres, :parter)
      obrys = ->(z) { [[@WL, @WT, z], [@XF, @WT, z], [@XF, @D - @WT, z], [@WL, @D - @WT, z]] }
      wlaz = ->(z) { [[141, 449, z], [281, 449, z], [281, 519, z], [141, 519, z]] }
      g = grupa(@root, 'Strop nad parterem', :sufit, :strop)
      bryla(g.entities, obrys[@Z_SUFIT], [wlaz[@Z_SUFIT]], [0, 0, @Z_STRYCH - 3.2 - @Z_SUFIT])
      g = grupa(@root, 'Podłoga strychu – deski', :deski, :strop)
      bryla(g.entities, obrys[@Z_STRYCH - 3.2], [wlaz[@Z_STRYCH - 3.2]], [0, 0, 3.2])
      kostka(@root, 'Podciąg Pd-1', @WL, @RIDGE_Y - 7, @Z_SUFIT - 20, @XF, @RIDGE_Y + 7, @Z_SUFIT, :sufit, :parter)
      kostka(@root, 'Właz na strych (schody strychowe 70x140)', 142, 450, @Z_SUFIT, 280, 518, @Z_SUFIT + 3, :drzwi_w, :parter)
    end

    def dzialowa(nazwa, origin, u_dir, grubosc, t_dir, dlugosc, drzwi)
      t_vec = vmul(t_dir, grubosc)
      otw = drzwi.map { |a, b| prostokat(a, @Z_POSADZKA, b, @Z_POSADZKA + 208.0) }
      sciana(@root, nazwa, origin, u_dir, t_vec, prostokat(0, @Z_PLYTA, dlugosc, @Z_SUFIT), otw, :sciana_w, :parter)
      drzwi.each do |a, b|
        wstaw(@root, drzwi_wewn(grubosc), origin, u_dir, t_vec, a, b, @Z_POSADZKA, 0, 'D2').layer = @tag[:parter]
      end
    end

    def sciany_dzialowe!
      # garaż (0.1) | pomieszczenia gospodarcze – drzwi D2 z garażu do 0.2
      dzialowa('Ściana garaż / pom. gospodarcze', [@WL, 546.0, 0], [1, 0, 0], 12.0, [0, 1, 0], @XF - @WL,
               [[45.0 - @WL, 138.0 - @WL]])
      # pom. gosp. 0.2 | 0.3 – drzwi D2
      dzialowa('Ściana pom. gospodarcze 0.2 / 0.3', [290.0, 558.0, 0], [0, 1, 0], 12.0, [1, 0, 0], @D - @WT - 558.0,
               [[685.0 - 558.0, 778.0 - 558.0]])
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
      dodaj.call('Widok 3D – front', [cx + 1050, -1100, 620], [cx, cy, 220], z, true, nil, [])
      dodaj.call('Widok 3D – ogród', [cx + 1050, @D + 1100, 620], [cx, cy, 220], z, true, nil, [])
      dodaj.call('Elewacja frontowa', [cx, -4000, 310], [cx, 0, 310], z, false, 800, [])
      dodaj.call('Elewacja ogrodowa', [cx, @D + 4000, 310], [cx, @D, 310], z, false, 800, [])
      dodaj.call('Elewacja boczna prawa', [@L + 4000, cy, 310], [@L, cy, 310], z, false, 800, [])
      ukryj_dach = %i[dach okna_dach obrobki]
      dodaj.call('Rzut parteru', [cx, cy, 4000], [cx, cy, 0], [0, 1, 0], false, 1000, ukryj_dach + %i[strop])
      dodaj.call('Rzut strychu', [cx, cy, 4000], [cx, cy, 0], [0, 1, 0], false, 1000, ukryj_dach)

      warstwy.each { |l| l.visible = true }
      pages.selected_page = pages['Widok 3D – front'] if pages['Widok 3D – front']
    end
  end
end

Garaz.build
