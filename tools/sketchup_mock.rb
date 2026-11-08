# encoding: UTF-8
#
# Minimalna atrapa Ruby API SketchUpa – pozwala uruchomić skrypt modelu poza
# SketchUpem (np. w CI), sprawdzić go i wyeksportować geometrię do JSON.
# Odwzorowuje tylko to, czego używa sketchup/dom_smart_comfort.rb.
# Wewnętrznie, jak SketchUp, pracuje w calach.

require 'json'

class Numeric
  def cm; to_f / 2.54; end
  def mm; to_f / 25.4; end
  def m; to_f / 0.0254; end
  def degrees; to_f * Math::PI / 180.0; end
end

module Geom
  TOL = 1e-6

  module Coords
    attr_accessor :x, :y, :z

    def set_xyz(args)
      args = args[0] if args.size == 1 && args[0].respond_to?(:to_a)
      a = args.to_a.map(&:to_f)
      @x = a[0] || 0.0
      @y = a[1] || 0.0
      @z = a[2] || 0.0
    end

    def to_a; [@x, @y, @z]; end
    def [](i); to_a[i]; end
  end

  class Vector3d
    include Coords
    def initialize(*args); set_xyz(args); end
    def dot(o); @x * o.x + @y * o.y + @z * o.z; end
    def cross(o); Vector3d.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x); end
    def *(o); o.is_a?(Numeric) ? Vector3d.new(@x * o, @y * o, @z * o) : cross(o); end
    def +(o); Vector3d.new(@x + o.x, @y + o.y, @z + o.z); end
    def -(o); Vector3d.new(@x - o.x, @y - o.y, @z - o.z); end
    def length; Math.sqrt(dot(self)); end
    def normalize; l = length; Vector3d.new(@x / l, @y / l, @z / l); end
    def reverse; Vector3d.new(-@x, -@y, -@z); end
    def valid?; length > TOL; end
  end

  class Point3d
    include Coords
    def initialize(*args); set_xyz(args); end

    def -(o)
      o.is_a?(Vector3d) ? Point3d.new(@x - o.x, @y - o.y, @z - o.z) : Vector3d.new(@x - o.x, @y - o.y, @z - o.z)
    end

    def +(v); Point3d.new(@x + v.x, @y + v.y, @z + v.z); end
    def distance(o); (self - o).length; end
    def transform(t); t * self; end
  end

  class Transformation
    attr_reader :m

    def initialize(arg = nil)
      @m = [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]
      return unless arg
      if arg.is_a?(Array) && arg.size == 4 && arg[0].is_a?(Array)
        @m = arg
      else
        p = arg.is_a?(Array) ? Point3d.new(arg) : arg
        @m[0][3] = p.x
        @m[1][3] = p.y
        @m[2][3] = p.z
      end
    end

    def self.axes(o, x, y, z)
      [x, y, z].each { |v| raise ArgumentError, 'axes: zero vector' unless v.valid? }
      new([[x.x, y.x, z.x, o.x], [x.y, y.y, z.y, o.y], [x.z, y.z, z.z, o.z], [0, 0, 0, 1.0]])
    end

    def self.translation(v); new(Point3d.new(v.x, v.y, v.z)); end

    def *(o)
      case o
      when Transformation
        r = Array.new(4) { Array.new(4, 0.0) }
        4.times { |i| 4.times { |j| r[i][j] = (0..3).sum { |k| @m[i][k] * o.m[k][j] } } }
        Transformation.new(r)
      when Point3d
        Point3d.new(*(0..2).map { |i| @m[i][0] * o.x + @m[i][1] * o.y + @m[i][2] * o.z + @m[i][3] })
      when Vector3d
        Vector3d.new(*(0..2).map { |i| @m[i][0] * o.x + @m[i][1] * o.y + @m[i][2] * o.z })
      when Array
        self * Point3d.new(o)
      end
    end

    def det3
      a = @m
      a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
        a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
        a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
    end
  end
end

module Sketchup
  STATS = Hash.new(0)

  def self.version; '24.0.0 (mock)'; end

  class Color
    attr_reader :red, :green, :blue
    def initialize(r, g, b); @red = r; @green = g; @blue = b; end
    def to_a; [@red, @green, @blue]; end
  end

  class Entity
    def valid?; !@deleted; end
  end

  class Drawingelement < Entity
    attr_accessor :material, :layer
  end

  class Material
    attr_accessor :name, :alpha
    attr_reader :color
    def initialize(name); @name = name; @alpha = 1.0; @color = Color.new(255, 255, 255); end
    def color=(c); @color = c.is_a?(Array) ? Color.new(*c) : c; end
  end

  class Materials
    include Enumerable
    def initialize; @h = {}; end
    def [](n); @h[n]; end
    def add(n)
      n = "#{n}#{@h.size}" while @h[n]
      @h[n] = Material.new(n)
    end
    def each(&b); @h.values.each(&b); end
  end

  class Layer
    attr_accessor :name, :visible
    def initialize(n); @name = n; @visible = true; end
  end

  class Layers
    include Enumerable
    def initialize; @list = [Layer.new('Layer0')]; end
    def add(n); self[n] || (@list << Layer.new(n)).last; end
    def [](n); n.is_a?(Integer) ? @list[n] : @list.find { |l| l.name == n }; end
    def each(&b); @list.each(&b); end
  end

  # --------------------------------------------------------------------
  class Face < Drawingelement
    attr_accessor :back_material
    attr_reader :outer, :holes, :entities

    def initialize(ents, pts)
      @entities = ents
      @outer = pts
      @holes = []
    end

    def self.newell(pts)
      n = [0.0, 0.0, 0.0]
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.size]
        n[0] += (p.y - q.y) * (p.z + q.z)
        n[1] += (p.z - q.z) * (p.x + q.x)
        n[2] += (p.x - q.x) * (p.y + q.y)
      end
      Geom::Vector3d.new(*n)
    end

    def normal; Face.newell(@outer).normalize; end

    def reverse!
      @outer = @outer.reverse
      @holes = @holes.map(&:reverse)
      Sketchup::STATS[:reversed] += 1
      self
    end

    def erase!
      @deleted = true
      @entities.remove(self)
    end

    def plane_dist(p); normal.dot(p - @outer[0]); end
  end

  class Entities
    include Enumerable
    attr_reader :owner

    def initialize(owner = nil); @owner = owner; @items = []; end
    def each(&b); @items.dup.each(&b); end
    def remove(e); @items.delete(e); end
    def size; @items.size; end

    def add_face(*args)
      pts = (args.size == 1 && args[0].is_a?(Array) && !args[0][0].is_a?(Numeric) ? args[0] : args)
      pts = pts.map { |p| p.is_a?(Geom::Point3d) ? p : Geom::Point3d.new(p) }
      raise ArgumentError, 'add_face: za mało punktów' if pts.size < 3
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.size]
        raise ArgumentError, "add_face: zdublowane punkty #{p.to_a}" if p.distance(q) < 0.001
      end
      n = Face.newell(pts)
      raise ArgumentError, 'add_face: punkty współliniowe' if n.length < 1e-6
      nn = n.normalize
      pts.each do |p|
        raise ArgumentError, 'add_face: punkty niepłaskie' if nn.dot(p - pts[0]).abs > 0.001
      end
      f = Face.new(self, pts)
      # odwzorowanie zachowania SketchUpa: ściana narysowana wewnątrz innej
      # współpłaszczyznowej ściany tworzy w niej otwór (pętlę wewnętrzną)
      @items.each do |e|
        next unless e.is_a?(Face) && e.valid?
        next unless e.normal.dot(nn).abs > 1 - 1e-9 && e.plane_dist(pts[0]).abs < 1e-6
        next unless pts.all? { |p| Mock.point_in_poly?(p, e.outer, nn) }
        e.holes << pts
        Sketchup::STATS[:holes] += 1
        break
      end
      @items << f
      Sketchup::STATS[:faces] += 1
      f
    end

    def add_group
      g = Group.new
      @items << g
      g
    end

    def add_instance(defn, tr)
      i = ComponentInstance.new(defn, tr)
      @items << i
      i
    end

    def add_line(*_a); nil; end
  end

  class Group < Drawingelement
    attr_accessor :name, :transformation
    attr_reader :entities
    def initialize; @entities = Entities.new(self); @transformation = Geom::Transformation.new; @name = ''; end
  end

  class ComponentDefinition
    attr_accessor :name
    attr_reader :entities
    def initialize(n); @name = n; @entities = Entities.new(self); end
  end

  class DefinitionList
    include Enumerable
    def initialize; @list = []; end
    def add(n)
      base = n
      i = 1
      while @list.any? { |d| d.name == n }
        n = "#{base}##{i}"
        i += 1
      end
      (@list << ComponentDefinition.new(n)).last
    end
    def [](n); @list.find { |d| d.name == n }; end
    def each(&b); @list.each(&b); end
  end

  class ComponentInstance < Drawingelement
    attr_accessor :name, :transformation, :definition
    def initialize(d, t)
      raise ArgumentError, 'add_instance: brak definicji' unless d.is_a?(ComponentDefinition)
      raise ArgumentError, 'add_instance: transformacja odbijająca' if t.det3 < 0
      @definition = d
      @transformation = t
      @name = ''
    end
  end

  class Camera
    attr_accessor :eye, :target, :up, :perspective, :fov, :height
    def initialize(eye, target, up)
      @eye = eye; @target = target; @up = up; @perspective = true; @fov = 30.0
    end
  end

  class View
    attr_accessor :camera
  end

  class Page
    attr_reader :name, :camera, :hidden
    def initialize(n, cam, hidden); @name = n; @camera = cam; @hidden = hidden; end
  end

  class Pages
    include Enumerable
    attr_accessor :selected_page
    def initialize(model); @model = model; @list = []; end
    def add(n)
      cam = @model.active_view.camera
      p = Page.new(n, cam, @model.layers.reject(&:visible).map(&:name))
      @list << p
      p
    end
    def [](k); k.is_a?(Integer) ? @list[k] : @list.find { |p| p.name == k }; end
    def each(&b); @list.each(&b); end
    def size; @list.size; end
  end

  class Model
    attr_reader :entities, :materials, :layers, :definitions, :pages, :options, :active_view
    def initialize
      @entities = Entities.new(self)
      @materials = Materials.new
      @layers = Layers.new
      @definitions = DefinitionList.new
      @pages = Pages.new(self)
      @options = { 'UnitsOptions' => {} }
      @active_view = View.new
      @ops = []
    end
    def active_entities; @entities; end
    def start_operation(n, *_a); @ops << n; true; end
    def commit_operation; @ops.pop; true; end
    def abort_operation; @ops.pop; true; end
  end

  def self.active_model; @active_model ||= Model.new; end
end

module UI
  def self.messagebox(m); puts "[messagebox] #{m}"; end
end

module Mock
  module_function

  def point_in_poly?(p, poly, n)
    ax = [n.x.abs, n.y.abs, n.z.abs].each_with_index.max[1]
    i1, i2 = [[1, 2], [0, 2], [0, 1]][ax]
    px = p.to_a[i1]
    py = p.to_a[i2]
    q = poly.map { |v| [v.to_a[i1], v.to_a[i2]] }
    # na krawędzi = w środku
    q.each_with_index do |a, i|
      b = q[(i + 1) % q.size]
      cr = (b[0] - a[0]) * (py - a[1]) - (b[1] - a[1]) * (px - a[0])
      len = Math.hypot(b[0] - a[0], b[1] - a[1])
      next unless (cr / len).abs < 1e-6
      return true if px.between?([a[0], b[0]].min - 1e-6, [a[0], b[0]].max + 1e-6) &&
                     py.between?([a[1], b[1]].min - 1e-6, [a[1], b[1]].max + 1e-6)
    end
    inside = false
    j = q.size - 1
    q.each_with_index do |a, i|
      b = q[j]
      if (a[1] > py) != (b[1] > py) && px < (b[0] - a[0]) * (py - a[1]) / (b[1] - a[1]) + a[0]
        inside = !inside
      end
      j = i
    end
    inside
  end

  # Eksport całej sceny do JSON (współrzędne w cm, w układzie świata)
  def export(model, path)
    faces = []
    walk = lambda do |ents, tr, mat, layer, names|
      ents.each do |e|
        case e
        when Sketchup::Face
          next unless e.valid?
          loops = ([e.outer] + e.holes).map { |lp| lp.map { |p| (tr * p).to_a.map { |c| (c * 2.54).round(4) } } }
          faces << { 'loops' => loops, 'mat' => (e.material || mat)&.name,
                     'back' => e.back_material&.name, 'layer' => layer, 'path' => names.join(' / ') }
        when Sketchup::Group
          lay = e.layer ? e.layer.name : layer
          walk.call(e.entities, tr * e.transformation, e.material || mat, lay, names + [e.name])
        when Sketchup::ComponentInstance
          lay = e.layer ? e.layer.name : layer
          nm = e.name.to_s.empty? ? e.definition.name : "#{e.name} <#{e.definition.name}>"
          walk.call(e.definition.entities, tr * e.transformation, e.material || mat, lay, names + [nm])
        end
      end
    end
    walk.call(model.entities, Geom::Transformation.new, nil, 'Layer0', [])
    mats = model.materials.map { |m| [m.name, { 'rgb' => m.color.to_a, 'alpha' => m.alpha }] }.to_h
    pages = model.pages.map do |p|
      c = p.camera
      { 'name' => p.name, 'eye' => c.eye.to_a.map { |v| v * 2.54 }, 'target' => c.target.to_a.map { |v| v * 2.54 },
        'up' => c.up.to_a, 'perspective' => c.perspective, 'fov' => c.fov,
        'height' => c.height ? c.height * 2.54 : nil, 'hidden' => p.hidden }
    end
    File.write(path, JSON.generate({ 'faces' => faces, 'materials' => mats, 'pages' => pages }))
    faces.size
  end
end
