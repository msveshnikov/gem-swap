class_name Gem
extends Node2D
## One gem on the board: Blender-rendered sprite strip (8 light angles), shadow, special-gem effects,
## and its own little animations (glint, select pulse, land squash, wobble, pop).

const GEM_SHADER := preload("res://shaders/gem.gdshader")
const FRAMES := 8

var kind := 0           # gem kind (Game.GEMS index) or -2 prism
var special := 0        # Match3.SP_*
var cell := 0
var size := 80.0
var selected := false

var spr: Sprite2D
var shadow: Sprite2D
var mat: ShaderMaterial
var back: Node2D        # halo / rays behind the gem (additive)
var front: Node2D       # streaks / sparks above the gem (additive)
var _frame_f := 0.0
var _glint_left := 0.0
var _next_glint := 0.0
var _t := 0.0
var _hint_t := -1.0
var _base_scale := Vector2.ONE


func setup(k: int, s: int, cell_size: float) -> void:
	kind = k
	special = s
	size = cell_size
	if spr == null:
		_build()
	_apply()


func _build() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	back = Node2D.new()
	back.material = add
	back.draw.connect(_draw_back)
	add_child(back)
	shadow = Sprite2D.new()
	shadow.hframes = FRAMES
	shadow.modulate = Color(0, 0, 0, 0.38)
	add_child(shadow)
	spr = Sprite2D.new()
	spr.hframes = FRAMES
	mat = ShaderMaterial.new()
	mat.shader = GEM_SHADER
	spr.material = mat
	add_child(spr)
	front = Node2D.new()
	front.material = add
	front.draw.connect(_draw_front)
	add_child(front)
	_next_glint = randf_range(1.0, 7.0)
	_frame_f = randi_range(0, FRAMES - 1)


func _apply() -> void:
	var tex: Texture2D = Game.prism_tex if special == Match3.SP_PRISM else Game.gem_tex[kind]
	spr.texture = tex
	shadow.texture = tex
	var sc := size * 0.94 / float(tex.get_height())
	_base_scale = Vector2(sc, sc)
	spr.scale = _base_scale
	shadow.scale = _base_scale
	shadow.position = Vector2(size * 0.03, size * 0.07)
	mat.set_shader_parameter("rainbow", 1.0 if special == Match3.SP_PRISM else 0.0)
	_set_frame(int(_frame_f))
	back.queue_redraw()
	front.queue_redraw()


func color() -> Color:
	if special == Match3.SP_PRISM or kind < 0:
		return Color.WHITE
	return Game.GEMS[kind].color


func _set_frame(f: int) -> void:
	spr.frame = f % FRAMES
	shadow.frame = f % FRAMES


func _process(delta: float) -> void:
	_t += delta
	# glints: idle gems now and then flick through their light angles; selected / special ones keep turning
	if selected or special != Match3.SP_NONE:
		_frame_f += delta * (14.0 if selected else 7.0)
		_set_frame(int(_frame_f))
	elif _glint_left > 0.0:
		_glint_left -= delta
		_frame_f += delta * 22.0
		_set_frame(int(_frame_f))
		mat.set_shader_parameter("shine", 1.4 - _glint_left / 0.45 * 1.9)
		if _glint_left <= 0.0:
			mat.set_shader_parameter("shine", -1.0)
	else:
		_next_glint -= delta
		if _next_glint <= 0.0:
			_glint_left = 0.45
			_next_glint = randf_range(4.0, 11.0)
	if selected:
		var p := 1.0 + 0.09 + sin(_t * 9.0) * 0.04
		spr.scale = _base_scale * p
		shadow.scale = spr.scale
	if _hint_t >= 0.0:
		_hint_t += delta
		spr.rotation = sin(_hint_t * 18.0) * 0.18 * clampf(1.0 - fmod(_hint_t, 1.4) / 0.7, 0.0, 1.0)
		shadow.rotation = spr.rotation
	if special != Match3.SP_NONE:
		back.queue_redraw()
		front.queue_redraw()


func set_selected(v: bool) -> void:
	selected = v
	if not v:
		var t := create_tween()
		t.tween_property(spr, "scale", _base_scale, 0.15)
		t.parallel().tween_property(shadow, "scale", _base_scale, 0.15)
	back.queue_redraw()


func set_hint(on: bool) -> void:
	_hint_t = 0.0 if on else -1.0
	if not on:
		spr.rotation = 0
		shadow.rotation = 0


func flash(amount := 1.0, dur := 0.25) -> void:
	var t := create_tween()
	t.tween_method(func(v): mat.set_shader_parameter("flash", v), amount, 0.0, dur)


func shine_now() -> void:
	_glint_left = 0.45


## Landing squash after a fall.
func land(strength := 1.0) -> void:
	var t := create_tween()
	var s := strength
	t.tween_property(self, "scale", Vector2(1.0 + 0.16 * s, 1.0 - 0.18 * s), 0.07)
	t.tween_property(self, "scale", Vector2(1.0 - 0.06 * s, 1.0 + 0.08 * s), 0.09)
	t.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Turn into a special gem with a burst of light.
func become(new_kind: int, sp: int) -> void:
	kind = new_kind if new_kind >= 0 else kind
	special = sp
	_apply()
	flash(1.0, 0.5)
	scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Clear animation: flash, swell, spin away.
func pop(delay := 0.0) -> void:
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(func(): flash(1.0, 0.18))
	t.tween_property(self, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2(0.0, 0.0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "rotation", randf_range(-0.8, 0.8), 0.16)
	t.tween_callback(queue_free)


## Matched into a new special: slide into it and vanish.
func merge_into(target: Vector2, delay := 0.0) -> void:
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(func(): flash(0.8, 0.15))
	t.tween_property(self, "position", target, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "scale", Vector2(0.4, 0.4), 0.16)
	t.tween_callback(queue_free)


# ------------------------------------------------------------------ special effects

func _draw_back() -> void:
	var r := size * 0.5
	if selected:
		back.draw_circle(Vector2.ZERO, r * 0.95, Color(color(), 0.18))
		back.draw_arc(Vector2.ZERO, r * 0.9, 0, TAU, 40, Color(color().lightened(0.4), 0.55), 3.0, true)
	match special:
		Match3.SP_BOMB:
			var pulse := 0.5 + 0.5 * sin(_t * 6.0)
			for k in 4:
				back.draw_circle(Vector2.ZERO, r * (0.55 + k * 0.14 + pulse * 0.06), Color(color(), 0.10 - k * 0.02))
			back.draw_arc(Vector2.ZERO, r * (0.78 + pulse * 0.08), 0, TAU, 40, Color(color().lightened(0.5), 0.5), 2.5, true)
		Match3.SP_PRISM:
			for k in 8:
				var a := _t * 0.9 + k * TAU / 8.0
				var c := Color.from_hsv(fmod(k / 8.0 + _t * 0.1, 1.0), 0.7, 1.0, 0.28)
				var d1 := Vector2(cos(a - 0.12), sin(a - 0.12))
				var d2 := Vector2(cos(a + 0.12), sin(a + 0.12))
				back.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, d1 * r * 1.05, d2 * r * 1.05]), c)
			back.draw_circle(Vector2.ZERO, r * 0.7, Color(1, 1, 1, 0.12))
		Match3.SP_LINE_H, Match3.SP_LINE_V:
			var horiz := special == Match3.SP_LINE_H
			var dir := Vector2(1, 0) if horiz else Vector2(0, 1)
			var nrm := Vector2(-dir.y, dir.x)
			var glow := Color(color(), 0.22 + 0.1 * sin(_t * 8.0))
			back.draw_colored_polygon(PackedVector2Array([-dir * r * 1.0 - nrm * r * 0.32, dir * r * 1.0 - nrm * r * 0.32,
				dir * r * 1.0 + nrm * r * 0.32, -dir * r * 1.0 + nrm * r * 0.32]), glow)


func _draw_front() -> void:
	var r := size * 0.5
	match special:
		Match3.SP_LINE_H, Match3.SP_LINE_V:
			var horiz := special == Match3.SP_LINE_H
			var dir := Vector2(1, 0) if horiz else Vector2(0, 1)
			var nrm := Vector2(-dir.y, dir.x)
			var c := Color(1, 1, 1, 0.85)
			front.draw_line(-dir * r * 0.62, dir * r * 0.62, Color(color().lightened(0.6), 0.75), maxf(2.0, r * 0.07), true)
			for side: float in [-1.0, 1.0]:
				for k in 2:
					var ph := fmod(_t * 1.6 + k * 0.5, 1.0)
					var tip := dir * side * r * (0.35 + ph * 0.55)
					var a := Color(c, (1.0 - ph) * 0.9)
					front.draw_polyline(PackedVector2Array([tip - dir * side * r * 0.2 + nrm * r * 0.2, tip, tip - dir * side * r * 0.2 - nrm * r * 0.2]), a, maxf(2.5, r * 0.08), true)
		Match3.SP_BOMB:
			for k in 3:
				var a := _t * 3.0 + k * TAU / 3.0
				var p := Vector2(cos(a), sin(a) * 0.55) * r * 0.78
				front.draw_circle(p, r * 0.09, Color(1, 1, 1, 0.9))
				front.draw_circle(p, r * 0.18, Color(color(), 0.35))
			front.draw_circle(Vector2(-r * 0.18, -r * 0.2), r * 0.08 * (0.7 + 0.3 * sin(_t * 10.0)), Color(1, 1, 0.9, 0.9))
		Match3.SP_PRISM:
			var tw := 0.5 + 0.5 * sin(_t * 5.0)
			_star(front, Vector2(r * 0.3, -r * 0.35), r * 0.22 * tw, Color(1, 1, 1, 0.9))
			_star(front, Vector2(-r * 0.35, r * 0.25), r * 0.15 * (1.0 - tw), Color(1, 1, 1, 0.8))


static func _star(ci: CanvasItem, p: Vector2, s: float, c: Color) -> void:
	if s < 0.5:
		return
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.22, -s * 0.22), p + Vector2(s, 0), p + Vector2(s * 0.22, s * 0.22),
		p + Vector2(0, s), p + Vector2(-s * 0.22, s * 0.22), p + Vector2(-s, 0), p + Vector2(-s * 0.22, -s * 0.22)]), c)
