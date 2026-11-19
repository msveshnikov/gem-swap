class_name Fx
extends RefCounted
## Effect builders: particle bursts, beams, shockwaves, lightning, floating text, confetti.
## Everything is spawned into a layer node and frees itself.

static var star_tex: Texture2D
static var glow_tex: Texture2D
static var shard_tex: Texture2D
static var add_mat: CanvasItemMaterial


static func init() -> void:
	if star_tex:
		return
	add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# soft round glow
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	glow_tex = gt
	# four-point sparkle
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := absf(x - n * 0.5 + 0.5) / (n * 0.5)
			var dy := absf(y - n * 0.5 + 0.5) / (n * 0.5)
			var a := clampf(1.0 - (dx * 9.0 * dy + dx * 0.9 + dy * 0.9) * 0.9, 0.0, 1.0)
			a = maxf(a, clampf(1.0 - sqrt(dx * dx + dy * dy) * 3.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	star_tex = ImageTexture.create_from_image(img)
	# faceted shard (a little rhombus)
	var img2 := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := absf(x - 15.5) / 9.0 + absf(y - 15.5) / 15.0
			var shade := 1.0 if x < 16 else 0.7
			img2.set_pixel(x, y, Color(shade, shade, shade, 1.0 if d < 1.0 else 0.0))
	shard_tex = ImageTexture.create_from_image(img2)


static func _one_shot(layer: Node, pos: Vector2, tex: Texture2D, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = pos
	p.emitting = true
	layer.add_child(p)
	p.finished.connect(p.queue_free)
	return p


## Gem shatter: coloured shards fly out, white sparkles, a soft flash.
static func shatter(layer: Node, pos: Vector2, color: Color, cell: float, big := false) -> void:
	var s := _one_shot(layer, pos, shard_tex, 10 if not big else 18, 0.7)
	s.direction = Vector2(0, -1)
	s.spread = 180
	s.initial_velocity_min = cell * 2.5
	s.initial_velocity_max = cell * 6.0
	s.gravity = Vector2(0, cell * 14.0)
	s.angular_velocity_min = -720
	s.angular_velocity_max = 720
	s.angle_min = 0
	s.angle_max = 360
	s.scale_amount_min = cell / 32.0 * 0.18
	s.scale_amount_max = cell / 32.0 * 0.38
	s.color = color.lightened(0.15)
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 1, 1, 1))
	cr.set_color(1, Color(1, 1, 1, 0))
	s.color_ramp = cr
	var sp := _one_shot(layer, pos, star_tex, 6 if not big else 12, 0.55)
	sp.material = add_mat
	sp.spread = 180
	sp.initial_velocity_min = cell * 0.8
	sp.initial_velocity_max = cell * 3.0
	sp.gravity = Vector2.ZERO
	sp.damping_min = cell * 2.0
	sp.damping_max = cell * 4.0
	sp.scale_amount_min = cell / 64.0 * 0.3
	sp.scale_amount_max = cell / 64.0 * 0.8
	sp.color = color.lightened(0.5)
	sp.color_ramp = cr
	glow(layer, pos, color, cell * 1.6, 0.3)


static func glow(layer: Node, pos: Vector2, color: Color, diameter: float, dur: float) -> void:
	var g := Sprite2D.new()
	g.texture = glow_tex
	g.material = add_mat
	g.position = pos
	g.modulate = Color(color, 0.9)
	var s := diameter / 64.0
	g.scale = Vector2(s * 0.5, s * 0.5)
	layer.add_child(g)
	var t := g.create_tween()
	t.tween_property(g, "scale", Vector2(s, s), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(g, "modulate:a", 0.0, dur)
	t.tween_callback(g.queue_free)


## A beam across the board (line gem).
static func beam(layer: Node, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var b := Beam.new()
	b.a = from
	b.b = to
	b.col = color
	b.w = width
	b.material = add_mat
	layer.add_child(b)
	var sp := CPUParticles2D.new()
	sp.texture = star_tex
	sp.material = add_mat
	sp.amount = 26
	sp.lifetime = 0.6
	sp.one_shot = true
	sp.explosiveness = 0.9
	sp.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var mid := (from + to) * 0.5
	var half := (to - from) * 0.5
	sp.position = mid
	sp.emission_rect_extents = Vector2(absf(half.x) + 1, absf(half.y) + 1)
	sp.spread = 180
	sp.initial_velocity_min = width * 0.5
	sp.initial_velocity_max = width * 2.5
	sp.gravity = Vector2.ZERO
	sp.scale_amount_min = width / 64.0 * 0.4
	sp.scale_amount_max = width / 64.0 * 0.9
	sp.color = color.lightened(0.4)
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 1, 1, 1))
	cr.set_color(1, Color(1, 1, 1, 0))
	sp.color_ramp = cr
	sp.emitting = true
	sp.finished.connect(sp.queue_free)
	layer.add_child(sp)


class Beam extends Node2D:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var col := Color.WHITE
	var w := 40.0
	var k := 0.0

	func _ready() -> void:
		var t := create_tween()
		t.tween_property(self, "k", 1.0, 0.45)
		t.tween_callback(queue_free)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var grow := clampf(k / 0.25, 0.0, 1.0)
		var fade := 1.0 - clampf((k - 0.3) / 0.7, 0.0, 1.0)
		var mid := (a + b) * 0.5
		var pa := mid.lerp(a, grow)
		var pb := mid.lerp(b, grow)
		var ww := w * (0.5 + 0.7 * sin(minf(k, 0.5) * PI)) * fade
		draw_line(pa, pb, Color(col, 0.35 * fade), ww * 1.9, true)
		draw_line(pa, pb, Color(col.lightened(0.3), 0.7 * fade), ww * 0.9, true)
		draw_line(pa, pb, Color(1, 1, 1, fade), ww * 0.32, true)


## Expanding ring (bombs).
static func shockwave(layer: Node, pos: Vector2, color: Color, radius: float, dur := 0.5) -> void:
	var r := Ring.new()
	r.position = pos
	r.col = color
	r.max_r = radius
	r.dur = dur
	r.material = add_mat
	layer.add_child(r)


class Ring extends Node2D:
	var col := Color.WHITE
	var max_r := 100.0
	var dur := 0.5
	var k := 0.0

	func _ready() -> void:
		var t := create_tween()
		t.tween_property(self, "k", 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_callback(queue_free)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := max_r * k
		var a := 1.0 - k
		draw_circle(Vector2.ZERO, r, Color(col, 0.18 * a))
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(col.lightened(0.4), 0.9 * a), maxf(2.0, max_r * 0.12 * a), true)
		draw_arc(Vector2.ZERO, r * 0.8, 0, TAU, 64, Color(1, 1, 1, 0.6 * a), maxf(1.0, max_r * 0.04 * a), true)


## Jagged lightning bolt (prism).
static func lightning(layer: Node, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var l := Bolt.new()
	l.a = from
	l.b = to
	l.col = color
	l.w = width
	l.material = add_mat
	layer.add_child(l)


class Bolt extends Node2D:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var col := Color.WHITE
	var w := 6.0
	var life := 0.0
	var pts := PackedVector2Array()

	func _ready() -> void:
		_make()

	func _make() -> void:
		pts.clear()
		var n := 9
		var d := b - a
		var nrm := Vector2(-d.y, d.x).normalized()
		for i in n + 1:
			var f := float(i) / n
			var off := 0.0 if i == 0 or i == n else randf_range(-1, 1) * d.length() * 0.08
			pts.append(a + d * f + nrm * off)

	func _process(delta: float) -> void:
		life += delta
		if fmod(life, 0.05) < delta:
			_make()
		if life > 0.32:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var al := 1.0 - life / 0.32
		draw_polyline(pts, Color(col, 0.45 * al), w * 2.6, true)
		draw_polyline(pts, Color(1, 1, 1, al), w * 0.8, true)


## "+120" etc. rising and fading.
static func float_text(layer: Node, pos: Vector2, text: String, color: Color, size: int, dur := 0.9) -> Label:
	var l := UiKit.label(text, size, color, maxi(6, size / 5))
	l.position = pos - Vector2(200, size * 0.7)
	l.size = Vector2(400, size * 1.4)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.3, 0.3)
	layer.add_child(l)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "position:y", l.position.y - size * 1.2, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.6)
	t.tween_callback(l.queue_free)
	return l


## Confetti rain over the whole screen.
static func confetti(layer: Node, rect: Rect2, amount := 120) -> void:
	var p := CPUParticles2D.new()
	p.texture = shard_tex
	p.amount = amount
	p.lifetime = 3.2
	p.one_shot = true
	p.explosiveness = 0.75
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.position = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 20)
	p.emission_rect_extents = Vector2(rect.size.x * 0.5, 10)
	p.direction = Vector2(0, 1)
	p.spread = 30
	p.initial_velocity_min = 80
	p.initial_velocity_max = 380
	p.gravity = Vector2(0, 420)
	p.angular_velocity_min = -500
	p.angular_velocity_max = 500
	p.angle_max = 360
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color("#ff2d55"), Color("#ffd51f"), Color("#22e06a"), Color("#2f7bff"), Color("#b04dff"), Color("#ff6fb5")])
	p.color_initial_ramp = g
	p.emitting = true
	p.finished.connect(p.queue_free)
	layer.add_child(p)


## Firework burst.
static func firework(layer: Node, pos: Vector2, color: Color) -> void:
	var p := _one_shot(layer, pos, star_tex, 48, 1.2)
	p.material = add_mat
	p.spread = 180
	p.initial_velocity_min = 180
	p.initial_velocity_max = 320
	p.gravity = Vector2(0, 160)
	p.damping_min = 120
	p.damping_max = 200
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.55
	p.color = color
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 1, 1, 1))
	cr.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = cr
	glow(layer, pos, color, 260, 0.5)
