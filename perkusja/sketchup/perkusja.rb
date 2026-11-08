# encoding: UTF-8
#
# ============================================================================
#  Perkusja Mapex Mars MA529SF (Rock, 5 bębnów) – model 3D dla SketchUp
#  Rzeczywiste wymiary: stopa 22x18", tomy 10x7" i 12x8", floor tom 16x14",
#  werbel 14x6,5". Statywy i talerze ustawione jak na zdjęciu sklepowym
#  (talerze: hi-hat 14", crash 16", crash 18", ride 20" – rozmiary typowe).
# ----------------------------------------------------------------------------
#  JAK UŻYĆ: otwórz model domu w SketchUpie, Okno → Konsola Ruby i wpisz
#        load 'C:/ścieżka/do/perkusja.rb'
#  Perkusja pojawi się jako komponent „Perkusja Mapex Mars MA529SF”,
#  stojący na posadzce (z = 0), w miejscu podanym w @pozycja. Przesuniesz
#  ją narzędziem Przesuń (M), obrócisz narzędziem Obróć (Q).
#
#  Jednostki: centymetry (jak w modelu domu). Układ komponentu:
#  oś X – w prawo patrząc od miejsca perkusisty, oś Y – do przodu (w stronę
#  przedniego naciągu stopy), Z – w górę. Punkt (0,0,0) leży na podłodze
#  pod środkiem naciągu stopy od strony perkusisty.
# ============================================================================

module Perkusja

  # =============================== USTAWIENIA ===============================
  @talerze  = true    # talerze (hi-hat, 2 x crash, ride)
  @statywy  = true    # statywy, stopa (pedał), mocowanie tomów
  @stolek   = true    # stołek perkusisty (nie wchodzi w skład zestawu)
  # gdzie postawić perkusję w modelu: [x, y] w cm i obrót w stopniach.
  # Przykład dla domu „Smart comfort+”: [830, 640, 0] – pokój 1 na parterze
  @pozycja  = [0.0, 0.0, 0.0]
  # ==========================================================================

  class << self
    attr_accessor :talerze, :statywy, :stolek, :pozycja

    def build
      model = Sketchup.active_model
      @model = model
      model.start_operation('Perkusja Mapex Mars', true)
      begin
        materialy!
        tagi!
        defn = model.definitions.add('Perkusja Mapex Mars MA529SF')
        @e = defn.entities
        bebny!
        hardware! if @statywy
        talerze! if @talerze
        stolek! if @stolek
        x, y, kat = @pozycja
        a = kat.to_f * Math::PI / 180.0
        tr = Geom::Transformation.axes(p3([x, y, 0]), Geom::Vector3d.new(Math.cos(a), Math.sin(a), 0),
                                       Geom::Vector3d.new(-Math.sin(a), Math.cos(a), 0), Geom::Vector3d.new(0, 0, 1))
        inst = model.active_entities.add_instance(defn, tr)
        inst.name = 'Perkusja'
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("Nie udało się zbudować perkusji:\n#{e.message}")
        raise
      end
      puts 'Gotowe: perkusja Mapex Mars MA529SF została dodana do modelu.'
      inst
    end

    # ------------------------------------------------------------------------
    def materialy!
      @mat = {}
      {
        korpus:   ['Perkusja – korpus, brokat (wg zdjęcia)', [70, 104, 112]],
        naciag:   ['Perkusja – naciąg biały',                [238, 236, 228]],
        rezonans: ['Perkusja – naciąg rezonansowy',          [214, 200, 176]],
        chrom:    ['Perkusja – chrom',                       [205, 207, 210]],
        talerz:   ['Perkusja – brąz talerzy',                [196, 156, 78]],
        czarny:   ['Perkusja – czarny',                      [30, 30, 32]]
      }.each do |k, (n, rgb)|
        m = @model.materials[n] || @model.materials.add(n)
        m.color = Sketchup::Color.new(*rgb)
        @mat[k] = m
      end
    end

    def tagi!
      @tag = {}
      { bebny: 'Perkusja – bębny', hardware: 'Perkusja – statywy i stopa',
        talerze: 'Perkusja – talerze', stolek: 'Perkusja – stołek' }.each { |k, n| @tag[k] = @model.layers.add(n) }
    end

    # ------------------------------------------------------------------------
    #  GEOMETRIA (cm) – te same narzędzia co w modelu domu
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

    def bryla(ents, outer, holes, vec)
      n = vnorm(newell(outer))
      holes = holes.map { |h| vdot(newell(h), n) > 0 ? h.reverse : h }
      cap0 = lico(ents, outer, holes, vmul(vec, -1))
      cap1 = lico(ents, outer.map { |p| vadd(p, vec) }, holes.map { |h| h.map { |p| vadd(p, vec) } }, vec)
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

    # dwa wektory prostopadłe do osi d
    def baza(d)
      a = d[0].abs < 0.9 ? [1.0, 0, 0] : [0, 1.0, 0]
      u = vnorm(vcross(d, a))
      [u, vcross(d, u)]
    end

    def okrag(c, d, r, n)
      u, v = baza(d)
      (0...n).map do |k|
        t = 2 * Math::PI * k / n
        vadd(c, vadd(vmul(u, r * Math.cos(t)), vmul(v, r * Math.sin(t))))
      end
    end

    # walec od punktu p0 do p1 o promieniu r
    def pret(parent, nazwa, p0, p1, r, mat = nil, n = 10)
      d = vsub(p1, p0)
      g = grupa(parent, nazwa, mat)
      bryla(g.entities, okrag(p0, vnorm(d), r, n), [], d)
      g
    end

    def kier(x, y, z)
      vnorm([x, y, z])
    end

    def rad(st)
      st * Math::PI / 180.0
    end

    # ------------------------------------------------------------------------
    #  BĘBNY
    # ------------------------------------------------------------------------
    # c0 – środek naciągu dolnego/rezonansowego, os – kierunek do naciągu
    # górnego (bijącego), wymiary w calach
    def beben(nazwa, c0, os, cale_d, cale_h, lugi, obrecz = :chrom)
      r = cale_d * 2.54 / 2
      h = cale_h * 2.54
      g = grupa(@e, nazwa, nil, :bebny)
      e = g.entities
      s = grupa(e, 'Korpus', :korpus)
      res = bryla(s.entities, okrag(c0, os, r, 32), [], vmul(os, h))
      res[:cap0].material = @mat[:rezonans]
      res[:cap1].material = @mat[:naciag]
      [[-1.2, 1.8, 'dolna'], [h - 1.8, h + 1.2, 'górna']].each do |a, b, n|
        c = vadd(c0, vmul(os, a))
        o = grupa(e, "Obręcz #{n}", obrecz)
        bryla(o.entities, okrag(c, os, r + 0.9, 32), [okrag(c, os, r - 0.25, 32)], vmul(os, b - a))
      end
      l = grupa(e, 'Stroiki', :chrom)
      u, v = baza(os)
      dl = [h * 0.3, 5.0].min
      lugi.times do |k|
        t = 2 * Math::PI * (k + 0.5) / lugi
        p = vadd(c0, vmul(vadd(vmul(u, Math.cos(t)), vmul(v, Math.sin(t))), r + 0.9))
        [2.5, h - 2.5 - dl].each do |a|
          bryla(l.entities, okrag(vadd(p, vmul(os, a)), os, 0.9, 6), [], vmul(os, dl))
        end
      end
      { c0: c0, os: os, r: r, h: h, gora: vadd(c0, vmul(os, h)) }
    end

    def bebny!
      # stopa 22x18" – leży na obręczach, naciąg bijący od strony perkusisty
      zc = 22 * 2.54 / 2 + 0.9
      @stopa = beben('Stopa 22x18"', [0, 18 * 2.54, zc], [0, -1, 0], 22, 18, 8, :korpus)
      # werbel 14x6,5" – po lewej, lekko pochylony do perkusisty
      os = kier(0, -Math.sin(rad(4)), Math.cos(rad(4)))
      @werbel = beben('Werbel 14x6,5"', [-30, -22, 50], os, 14, 6.5, 10)
      # tomy na stopie: 10x7" i 12x8"
      os = kier(Math.sin(rad(8)), -Math.sin(rad(15)), Math.cos(rad(15)))
      @tom10 = beben('Tom 10x7"', vsub([-15, 14, 85], vmul(os, 7 * 2.54)), os, 10, 7, 6)
      os = kier(-Math.sin(rad(8)), -Math.sin(rad(15)), Math.cos(rad(15)))
      @tom12 = beben('Tom 12x8"', vsub([17, 16, 86], vmul(os, 8 * 2.54)), os, 12, 8, 6)
      # floor tom 16x14" – po prawej, na trzech nogach
      os = kier(0, -Math.sin(rad(3)), Math.cos(rad(3)))
      @floor = beben('Floor tom 16x14"', vsub([50, -12, 62], vmul(os, 14 * 2.54)), os, 16, 14, 8)

      # nogi floor toma
      g = grupa(@e, 'Nogi floor toma', :chrom, :bebny)
      c = @floor[:c0]
      r = @floor[:r]
      [200, 320, 80].each_with_index do |st, i|
        t = rad(st)
        gora = [c[0] + (r + 1.5) * Math.cos(t), c[1] + (r + 1.5) * Math.sin(t), 54]
        dol = [c[0] + (r + 8) * Math.cos(t), c[1] + (r + 8) * Math.sin(t), 1.5]
        pret(g.entities, "Noga #{i + 1}", gora, dol, 0.65)
        pret(g.entities, "Stopka #{i + 1}", vsub(dol, [0, 0, 1.5]), vadd(dol, [0, 0, 1]), 1.2, :czarny)
      end
    end

    # ------------------------------------------------------------------------
    #  STATYWY, STOPA, MOCOWANIE TOMÓW
    # ------------------------------------------------------------------------
    def trojnog(nazwa, cx, cy, z_gora, z_nogi, promien, faza = 90)
      g = grupa(@e, nazwa, :chrom, :hardware)
      e = g.entities
      pret(e, 'Rura', [cx, cy, z_nogi - 6], [cx, cy, z_gora], 1.2)
      3.times do |k|
        t = rad(faza + 120 * k)
        stopa = [cx + promien * Math.cos(t), cy + promien * Math.sin(t), 1.0]
        pret(e, "Noga #{k + 1}", [cx, cy, z_nogi], stopa, 0.7)
        pret(e, "Stopka #{k + 1}", vsub(stopa, [0, 0, 1]), vadd(stopa, [0, 0, 1.5]), 1.3, :czarny)
      end
      g
    end

    def plyta(parent, nazwa, p0, p1, szer, grub, mat)
      d = vsub(p1, p0)
      w = vnorm(vcross(d, [0, 0, 1]))
      w = [1.0, 0, 0] if w.any?(&:nan?)
      n = vnorm(vcross(w, d))
      h = vmul(w, szer / 2.0)
      g = grupa(parent, nazwa, mat)
      bryla(g.entities, [vsub(p0, h), vadd(p0, h), vadd(p1, h), vsub(p1, h)], [], vmul(n, grub))
      g
    end

    def hardware!
      # stopa (pedał) przy naciągu stopy
      g = grupa(@e, 'Stopa (pedał)', :chrom, :hardware)
      e = g.entities
      plyta(e, 'Podstawa', [0, -32, 0], [0, -1, 0], 12, 1.2, :czarny)
      plyta(e, 'Płyta pedału', [0, -28, 2.5], [0, -5, 9], 9, 1.2, :czarny)
      pret(e, 'Słupek lewy', [-5.5, -3, 0], [-5.5, -3, 18], 0.8)
      pret(e, 'Słupek prawy', [5.5, -3, 0], [5.5, -3, 18], 0.8)
      pret(e, 'Oś', [-5.5, -3, 17], [5.5, -3, 17], 0.6)
      pret(e, 'Trzon bijaka', [0, -3, 17], [0, -3.8, 31], 0.4)
      pret(e, 'Bijak', [0, -6, 30], [0, -3.6, 30], 3.0, :czarny, 14)

      # ostrogi stopy
      [-1, 1].each do |sx|
        gora = [sx * 27.0, 36.0, 24.0]
        dol = [sx * 40.0, 52.0, 1.0]
        pret(e, sx < 0 ? 'Ostroga lewa' : 'Ostroga prawa', gora, dol, 0.8)
        pret(e, sx < 0 ? 'Stopka ostrogi lewej' : 'Stopka ostrogi prawej', vsub(dol, [0, 0, 1]), vadd(dol, [0, 0, 1.5]), 1.3, :czarny)
      end

      # mocowanie tomów na stopie
      top = [0, 21, 72]
      pret(e, 'Uchwyt tomów', [0, 23, 55.5], top, 1.3)
      [[@tom10, 1], [@tom12, -1]].each do |t, s|
        cel = vadd(vadd(t[:c0], vmul(t[:os], 4)), [s * t[:r], 0, 0])
        pret(e, 'Ramię tomu', top, cel, 0.9)
      end

      # statyw werbla z koszem
      w = @werbel[:c0]
      trojnog('Statyw werbla', w[0], w[1], 48, 22, 26)
      g = grupa(@e, 'Kosz werbla', :chrom, :hardware)
      3.times do |k|
        t = rad(30 + 120 * k)
        pret(g.entities, "Ramię #{k + 1}", [w[0], w[1], 47], [w[0] + 15 * Math.cos(t), w[1] + 15 * Math.sin(t), 49.2], 0.5)
      end

      # statyw hi-hatu z pedałem
      trojnog('Statyw hi-hat', -62, -12, 89, 28, 28, 270)
      g = grupa(@e, 'Hi-hat – pedał i drążek', :chrom, :hardware)
      plyta(g.entities, 'Płyta pedału hi-hat', [-62, -42, 2.5], [-62, -16, 9], 9, 1.2, :czarny)
      pret(g.entities, 'Drążek', [-62, -12, 89], [-62, -12, 100], 0.4)
    end

    # ------------------------------------------------------------------------
    #  TALERZE
    # ------------------------------------------------------------------------
    def talerz(nazwa, c, n, cale)
      r = cale * 2.54 / 2
      g = grupa(@e, nazwa, :talerz, :talerze)
      d = grupa(g.entities, 'Talerz', nil)
      bryla(d.entities, okrag(vsub(c, vmul(n, 0.2)), n, r, 40), [], vmul(n, 0.4))
      b = grupa(g.entities, 'Kopułka', nil)
      bryla(b.entities, okrag(vadd(c, vmul(n, 0.2)), n, 6, 20), [], vmul(n, 2.3))
      g
    end

    def statyw_talerza(nazwa, cx, cy, z_rury, c, n, faza)
      trojnog(nazwa, cx, cy, z_rury, z_rury - 55, 30, faza)
      g = grupa(@e, "#{nazwa} – ramię", :chrom, :hardware)
      pret(g.entities, 'Ramię', [cx, cy, z_rury], vsub(c, vmul(n, 3)), 0.9)
      pret(g.entities, 'Trzpień', vsub(c, vmul(n, 3)), vadd(c, vmul(n, 3.5)), 0.4)
    end

    def talerze!
      # hi-hat 14"
      talerz('Hi-hat 14" – dolny', [-62, -12, 85], [0, 0, 1], 14)
      talerz('Hi-hat 14" – górny', [-62, -12, 88.5], [0, 0, 1], 14)
      # crash 16" po lewej
      n = kier(0.3, -0.35, 1)
      talerz('Crash 16"', [-42, 22, 140], n, 16)
      statyw_talerza('Statyw crash 16"', -72, 28, 112, [-42, 22, 140], n, 90) if @statywy
      # crash 18" nad tomami
      n = kier(0, -0.4, 1)
      talerz('Crash 18"', [8, 44, 155], n, 18)
      statyw_talerza('Statyw crash 18"', -8, 72, 124, [8, 44, 155], n, 90) if @statywy
      # ride 20" po prawej
      n = kier(-0.25, -0.35, 1)
      talerz('Ride 20"', [58, 18, 118], n, 20)
      statyw_talerza('Statyw ride 20"', 80, 32, 98, [58, 18, 118], n, 90) if @statywy
    end

    # ------------------------------------------------------------------------
    def stolek!
      g = grupa(@e, 'Stołek perkusisty', :czarny, :stolek)
      pret(g.entities, 'Siedzisko', [-5, -65, 50], [-5, -65, 57], 18, nil, 24)
      pret(g.entities, 'Kolumna', [-5, -65, 22], [-5, -65, 50], 1.6, :chrom)
      3.times do |k|
        t = rad(90 + 120 * k)
        stopa = [-5 + 26 * Math.cos(t), -65 + 26 * Math.sin(t), 1.0]
        pret(g.entities, "Noga #{k + 1}", [-5, -65, 24], stopa, 0.8, :chrom)
        pret(g.entities, "Stopka #{k + 1}", vsub(stopa, [0, 0, 1]), vadd(stopa, [0, 0, 1.5]), 1.4)
      end
    end
  end
end

Perkusja.build
