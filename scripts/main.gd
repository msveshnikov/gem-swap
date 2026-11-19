extends Node2D
## Game flow: title -> world map -> level (or Blitz) -> win / lose. All UI is built in code (UiKit).

const BG_SHADER := preload("res://shaders/background.gdshader")
const BLITZ_TIME := 90.0
const HUMAN_BUFFER := 3     # calibration adds these moves on top of what the bot needs

var bg_layer: CanvasLayer
var bg: ColorRect
var bg_mat: ShaderMaterial
var ambient: CPUParticles2D
var deco: Node2D             # falling gems on the title screen
var board: Board
var ui: CanvasLayer
var root: Control
var fly_layer: Control       # gems flying to the goal counters, combo texts
var overlay: Control
var screen := ""
var world := -1
var browse_world := 0

var mode := "level"
var level_idx := 0
var level: Dictionary
var goals := Sim.Goals.new()
var moves_left := 0
var score := 0
var shown_score := 0.0
var time_left := BLITZ_TIME
var plus5_used := false
var ended := false
var playing := false

var lbl_moves: Label
var lbl_moves_cap: Label
var lbl_score: Label
var score_bar: ScoreBar
var goal_box: HBoxContainer
var goal_labels := {}        # goal index -> Label
var goal_icons := {}         # goal index -> Control
var goal_shown := {}         # goal index -> displayed number
var tip_pill: PanelContainer
var _log := PackedStringArray()
var _reset_armed := false
var _deco_timer := 0.0


func _ready() -> void:
	UiKit.init_theme()
	Fx.init()
	bg_layer = CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	bg = ColorRect.new()
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = BG_SHADER
	bg.material = bg_mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg)
	deco = Node2D.new()
	add_child(deco)
	board = Board.new()
	add_child(board)
	board.visible = false
	board.move_made.connect(_on_move)
	board.scored.connect(_on_scored)
	board.gems_cleared.connect(_on_cleared)
	board.obstacles_changed.connect(_refresh_goals)
	board.combo.connect(_on_combo)
	board.settled.connect(_on_settled)
	board.shuffling.connect(func(): toast(Game.tr_("no_moves")))
	ui = CanvasLayer.new()
	add_child(ui)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	if Game.has_arg("--calibrate"):
		_calibrate()
	elif Game.has_arg("--autotest"):
		_autotest()
	elif Game.has_arg("--level"):
		start_level(int(Game.arg_value("--level", "1")) - 1)
	elif Game.has_arg("--featurebg"):
		_feature_bg()
	elif Game.has_arg("--storeshots"):
		_shots()
	else:
		show_title()


func vsize() -> Vector2:
	return get_viewport().get_visible_rect().size


func landscape() -> bool:
	var s := vsize()
	return s.x > s.y * 1.05


func _on_resize() -> void:
	var s := vsize()
	bg.position = Vector2.ZERO
	bg.size = s
	bg_mat.set_shader_parameter("aspect", Vector2(s.x / s.y, 1.0))
	if ambient:
		_place_ambient()
	if screen == "game":
		_layout_game()
	elif screen != "":
		var sc := screen
		match sc:
			"title":
				show_title()
			"map":
				show_map(browse_world)


# ================================================================ world look

func set_world(w: int) -> void:
	w = w % Game.WORLDS.size()
	if w == world:
		return
	var info: Dictionary = Game.WORLDS[w]
	if world >= 0:
		var t := create_tween()
		t.tween_method(func(v): bg_mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.25)
		t.tween_callback(func(): bg_mat.set_shader_parameter("style", info.style))
		t.tween_method(func(v): bg_mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.35)
	else:
		bg_mat.set_shader_parameter("style", info.style)
	bg_mat.set_shader_parameter("tint", info.tint)
	world = w
	board.tint = info.tint
	_make_ambient(info.fx, info.tint)


func _make_ambient(kind: String, tint: Color) -> void:
	if ambient:
		ambient.queue_free()
	ambient = CPUParticles2D.new()
	ambient.material = Fx.add_mat
	ambient.texture = Fx.glow_tex
	ambient.amount = 40
	ambient.lifetime = 8.0
	ambient.preprocess = 8.0
	ambient.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ambient.gravity = Vector2.ZERO
	ambient.spread = 180
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	cr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	ambient.color_ramp = cr
	match kind:
		"sparkles", "stars":
			ambient.texture = Fx.star_tex
			ambient.color = Color(0.85, 0.8, 1.0) if kind == "sparkles" else Color(1, 0.9, 1.0)
			ambient.scale_amount_min = 0.15
			ambient.scale_amount_max = 0.45
			ambient.initial_velocity_min = 2
			ambient.initial_velocity_max = 12
			ambient.lifetime = 4.0
		"bubbles":
			ambient.color = Color(0.6, 1.0, 1.0, 0.7)
			ambient.direction = Vector2(0, -1)
			ambient.spread = 10
			ambient.initial_velocity_min = 30
			ambient.initial_velocity_max = 70
			ambient.scale_amount_min = 0.08
			ambient.scale_amount_max = 0.25
		"dust":
			ambient.color = Color(1.0, 0.8, 0.5, 0.6)
			ambient.direction = Vector2(1, -0.2)
			ambient.spread = 20
			ambient.initial_velocity_min = 15
			ambient.initial_velocity_max = 45
			ambient.scale_amount_min = 0.05
			ambient.scale_amount_max = 0.15
		"fireflies":
			ambient.color = Color(0.8, 1.0, 0.4)
			ambient.initial_velocity_min = 8
			ambient.initial_velocity_max = 25
			ambient.scale_amount_min = 0.12
			ambient.scale_amount_max = 0.3
			ambient.lifetime = 6.0
		"embers":
			ambient.color = Color(1.0, 0.55, 0.15)
			ambient.direction = Vector2(0, -1)
			ambient.spread = 25
			ambient.initial_velocity_min = 40
			ambient.initial_velocity_max = 110
			ambient.scale_amount_min = 0.06
			ambient.scale_amount_max = 0.16
			ambient.lifetime = 5.0
	bg_layer.add_child(ambient)
	_place_ambient()
	ambient.emitting = true


func _place_ambient() -> void:
	var s := vsize()
	ambient.position = s * 0.5
	ambient.emission_rect_extents = s * 0.5


# ================================================================ screens

func _clear_ui() -> void:
	for c in ui.get_children():
		c.queue_free()
	overlay = null
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	fly_layer = Control.new()
	fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fly_layer)


func _place(c: Control, preset: int, offset := Vector2.ZERO) -> void:
	root.add_child(c)
	c.reset_size()
	c.size = c.get_combined_minimum_size()
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.position += offset
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER]:
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		var w := maxf(c.size.x, c.get_combined_minimum_size().x)
		c.offset_left = -w * 0.5 + offset.x
		c.offset_right = w * 0.5 + offset.x
	if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_BOTTOM_RIGHT]:
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]:
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER]:
		c.grow_vertical = Control.GROW_DIRECTION_BOTH


func show_title() -> void:
	screen = "title"
	playing = false
	board.visible = false
	board.input_enabled = false
	set_world(5 if world < 0 else world)
	_clear_ui()
	var s := vsize()
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(v)
	var logo := Logo.new()
	logo.custom_minimum_size = Vector2(minf(s.x, 720) * 0.92, 300)
	v.add_child(logo)
	var sub := UiKit.label(Game.tr_("subtitle"), 36, Color(1, 0.92, 0.75), 8)
	v.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 40)
	v.add_child(sp)
	var play := UiKit.button(Game.tr_("play"), Color(0.95, 0.35, 0.65), Vector2(440, 120), 54)
	play.pressed.connect(func():
		Sfx.start_music()
		start_level(clampi(int(Game.save.unlocked) - 1, 0, 9999)))
	_center(v, play)
	var lv := UiKit.button(Game.tr_("levels"), Color(0.45, 0.35, 0.95), Vector2(440, 100), 44)
	lv.pressed.connect(func():
		Sfx.start_music()
		show_map(Game.world_of(clampi(int(Game.save.unlocked) - 1, 0, 59))))
	_center(v, lv)
	var bz := UiKit.button(Game.tr_("blitz"), Color(1.0, 0.6, 0.15), Vector2(440, 100), 44)
	bz.pressed.connect(func():
		Sfx.start_music()
		start_blitz())
	_center(v, bz)
	var best := UiKit.label("%s: %d" % [Game.tr_("best"), int(Game.save.blitz_best)], 28, Color(1, 0.85, 0.5), 6)
	v.add_child(best)
	var gear := UiKit.IconButton.new("gear", Color(0.45, 0.35, 0.8), 92)
	gear.pressed.connect(_show_settings)
	_place(gear, Control.PRESET_TOP_RIGHT, Vector2(-24, 24))
	var stars := HBoxContainer.new()
	stars.add_child(UiKit.Star.new(44))
	stars.add_child(UiKit.label(" %d" % Game.total_stars(), 38, Color(1, 0.9, 0.5), 8))
	_place(stars, Control.PRESET_TOP_LEFT, Vector2(28, 36))
	for k in v.get_child_count():
		UiKit.pop_in(v.get_child(k), 0.05 * k)


func _center(v: VBoxContainer, c: Control) -> void:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(c)
	v.add_child(h)


func _process(delta: float) -> void:
	# title screen: gems drift down behind the logo
	if screen == "title" or screen == "map":
		_deco_timer -= delta
		if _deco_timer <= 0.0 and deco.get_child_count() < 26:
			_deco_timer = 0.35
			var g := Gem.new()
			deco.add_child(g)
			var s := vsize()
			var sz := randf_range(50, 110)
			g.setup(randi() % Game.GEMS.size(), Match3.SP_PRISM if randf() < 0.06 else 0, sz)
			g.modulate = Color(1, 1, 1, 0.55 if sz < 80 else 0.8)
			g.position = Vector2(randf_range(0, s.x), -80)
			g.z_index = -1
			var t := g.create_tween()
			var dur := randf_range(7, 13) * 110.0 / sz
			t.tween_property(g, "position:y", s.y + 100, dur)
			t.parallel().tween_property(g, "rotation", randf_range(-2, 2), dur)
			t.tween_callback(g.queue_free)
	elif deco.get_child_count() > 0:
		for c in deco.get_children():
			c.queue_free()
	if screen == "game" and playing:
		if shown_score < score:
			shown_score = minf(score, shown_score + maxf(20.0, (score - shown_score) * 6.0) * delta)
			lbl_score.text = str(int(shown_score))
			score_bar.value = shown_score
		if mode == "blitz" and not ended and overlay == null:
			if not board.busy or time_left > 0.0:
				time_left = maxf(0.0, time_left - delta)
			lbl_moves.text = str(int(ceil(time_left)))
			lbl_moves.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if time_left < 10 else Color.WHITE)
			if time_left <= 0.0 and not board.busy:
				_blitz_over()


# ================================================================ map

func show_map(w: int) -> void:
	screen = "map"
	playing = false
	board.visible = false
	board.input_enabled = false
	browse_world = clampi(w, 0, Game.WORLDS.size() - 1)
	set_world(browse_world)
	_clear_ui()
	var s := vsize()
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	var wl := UiKit.label("%s %d" % [Game.tr_("world"), browse_world + 1], 30, Color(1, 0.9, 0.7), 6)
	head.add_child(wl)
	var wn := UiKit.label(Game.world_name(browse_world), 58, Color.WHITE, 12, true)
	head.add_child(wn)
	_place(head, Control.PRESET_CENTER_TOP, Vector2(0, 40))
	var home := UiKit.IconButton.new("home", Color(0.45, 0.35, 0.8), 92)
	home.pressed.connect(show_title)
	_place(home, Control.PRESET_TOP_LEFT, Vector2(24, 24))
	var stars := HBoxContainer.new()
	stars.add_child(UiKit.Star.new(40))
	stars.add_child(UiKit.label(" %d" % Game.total_stars(), 34, Color(1, 0.9, 0.5), 8))
	_place(stars, Control.PRESET_TOP_RIGHT, Vector2(-28, 40))
	# level path
	var path := MapPath.new()
	path.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	path.offset_top = 0
	path.offset_bottom = 0
	path.tint = Game.WORLDS[browse_world].tint
	root.add_child(path)
	var pts := []
	var area := Rect2(Vector2(0, 230), Vector2(s.x, s.y - 440))
	for k in Game.PER_WORLD:
		var f := float(k) / (Game.PER_WORLD - 1)
		var y := area.end.y - f * area.size.y - 10
		var x := s.x * 0.5 + sin(f * PI * 2.6) * minf(s.x * 0.3, 260)
		pts.append(Vector2(x, y))
	path.points = pts
	for k in Game.PER_WORLD:
		var idx := browse_world * Game.PER_WORLD + k
		var node := _level_node(idx)
		root.add_child(node)
		node.position = pts[k] - node.custom_minimum_size * 0.5
		UiKit.pop_in(node, 0.03 * k)
	# world arrows
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 40)
	var prev := UiKit.IconButton.new("back", Color(0.45, 0.35, 0.8), 100)
	prev.disabled = browse_world == 0
	prev.pressed.connect(func(): show_map(browse_world - 1))
	bar.add_child(prev)
	var next := UiKit.IconButton.new("next", Color(0.45, 0.35, 0.8), 100)
	next.disabled = browse_world >= Game.WORLDS.size() - 1
	next.pressed.connect(func(): show_map(browse_world + 1))
	if Game.levels.size() > 0 and (browse_world + 1) * Game.PER_WORLD >= Game.levels.size():
		next.disabled = true
	bar.add_child(next)
	if browse_world == Game.WORLDS.size() - 1 and int(Game.save.unlocked) > Game.levels.size():
		var more := UiKit.button(Game.tr_("endless"), Color(0.95, 0.35, 0.65), Vector2(300, 100), 34)
		more.pressed.connect(func(): start_level(int(Game.save.unlocked) - 1))
		bar.add_child(more)
	_place(bar, Control.PRESET_CENTER_BOTTOM, Vector2(0, -40))


func _level_node(idx: int) -> Control:
	var unlocked := idx < int(Game.save.unlocked)
	var current := idx == int(Game.save.unlocked) - 1
	var d := 108.0
	var b := Button.new()
	b.custom_minimum_size = Vector2(d, d)
	b.size = Vector2(d, d)
	var col: Color = Game.WORLDS[browse_world].tint
	if unlocked:
		UiKit.style_button(b, col.lerp(Color(0.9, 0.3, 0.6), 0.3) if current else col.darkened(0.15), int(d * 0.5))
	else:
		UiKit.style_button(b, Color(0.25, 0.22, 0.32), int(d * 0.5))
	UiKit.juice(b)
	b.text = str(idx + 1) if unlocked else ""
	b.add_theme_font_size_override("font_size", 42)
	if not unlocked:
		var lk := UiKit.Lock.new(44)
		lk.position = Vector2(d - 44, d - 44) * 0.5
		b.add_child(lk)
	else:
		var st := UiKit.star_row(Game.stars_of(idx), 30)
		st.position = Vector2(d * 0.5 - 48, d - 18)
		st.size = Vector2(96, 30)
		b.add_child(st)
	if current:
		var t := b.create_tween().set_loops()
		t.tween_property(b, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_SINE)
		t.tween_property(b, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	b.pressed.connect(func():
		if unlocked:
			start_level(idx)
		else:
			toast(Game.tr_("locked")))
	return b


class MapPath extends Control:
	var points: Array = []
	var tint := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var off := -position
		for k in points.size() - 1:
			var a: Vector2 = points[k] + off
			var b: Vector2 = points[k + 1] + off
			var n := int(a.distance_to(b) / 22.0)
			for i in n:
				var p := a.lerp(b, (i + 0.5) / n)
				draw_circle(p, 6, Color(tint.lightened(0.4), 0.55))


# ================================================================ game

func start_level(idx: int) -> void:
	mode = "level"
	level_idx = idx
	level = Game.get_level(idx)
	moves_left = int(level.moves)
	_start_common()
	set_world(Game.world_of(idx))
	_build_hud()
	_show_start_popup()


func start_blitz() -> void:
	mode = "blitz"
	level_idx = -1
	level = {"w": 8, "h": 8, "colors": [0, 2, 3, 4, 5, 6], "goals": [], "moves": 0, "map": []}
	time_left = BLITZ_TIME
	_start_common()
	set_world(randi() % Game.WORLDS.size())
	_build_hud()
	board.input_enabled = true
	playing = true
	await board.intro()


func _start_common() -> void:
	screen = "game"
	score = 0
	shown_score = 0
	plus5_used = false
	ended = false
	playing = false
	board.cascade_max = 0
	board.visible = true
	board.input_enabled = false
	board.load_level(level, int(Game.arg_value("--seed", "-1")))
	goals = Sim.Goals.new()
	goals.setup(level, board.m)


func _build_hud() -> void:
	_clear_ui()
	var s := vsize()
	var pause := UiKit.IconButton.new("pause", Color(0.45, 0.35, 0.8), 84)
	pause.pressed.connect(_show_pause)
	_place(pause, Control.PRESET_TOP_LEFT, Vector2(18, 18))
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -6)
	if mode == "blitz":
		title.add_child(UiKit.label(Game.tr_("blitz"), 44, Color.WHITE, 10, true))
		title.add_child(UiKit.label("%s: %d" % [Game.tr_("best"), int(Game.save.blitz_best)], 24, Color(1, 0.85, 0.6), 6))
	else:
		title.add_child(UiKit.label("%s %d" % [Game.tr_("level"), level_idx + 1], 44, Color.WHITE, 10, true))
		title.add_child(UiKit.label(Game.world_name(Game.world_of(level_idx)), 24, Color(1, 0.85, 0.6), 6))
	if landscape():
		_place(title, Control.PRESET_TOP_LEFT, Vector2(120, 12))
	else:
		_place(title, Control.PRESET_CENTER_TOP, Vector2(0, 14))
	# stats panel
	var panel := PanelContainer.new()
	var sb := UiKit.box(Color(0.06, 0.03, 0.14, 0.82), Color(world_tint().lightened(0.3), 0.8), 32, 3, 0.4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	panel.add_child(h)
	# moves / time
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", -8)
	lbl_moves_cap = UiKit.label(Game.tr_("time") if mode == "blitz" else Game.tr_("moves"), 22, Color(1, 0.85, 0.6), 5)
	mv.add_child(lbl_moves_cap)
	lbl_moves = UiKit.label(str(moves_left) if mode == "level" else str(int(time_left)), 64, Color.WHITE, 10)
	lbl_moves.custom_minimum_size = Vector2(110, 0)
	mv.add_child(lbl_moves)
	h.add_child(mv)
	# score
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 4)
	sv.add_child(UiKit.label(Game.tr_("score"), 22, Color(1, 0.85, 0.6), 5))
	lbl_score = UiKit.label("0", 44, Color(1, 0.95, 0.8), 8)
	sv.add_child(lbl_score)
	score_bar = ScoreBar.new()
	score_bar.custom_minimum_size = Vector2(160, 26)
	score_bar.stars = level.get("stars", [])
	if mode == "blitz":
		score_bar.stars = [5000, 15000, 30000]
	sv.add_child(score_bar)
	h.add_child(sv)
	# goals
	goal_box = HBoxContainer.new()
	goal_box.add_theme_constant_override("separation", 6)
	goal_labels.clear()
	goal_icons.clear()
	goal_shown.clear()
	for k in goals.list.size():
		var g: Dictionary = goals.list[k]
		if g.type == "score":
			continue
		var gv := VBoxContainer.new()
		gv.add_theme_constant_override("separation", -6)
		var icon: Control
		match g.type:
			"collect":
				icon = UiKit.GemIcon.new(int(g.color), 60)
			"ice":
				icon = ObstacleIcon.new("ice", 60)
			"stone":
				icon = ObstacleIcon.new("stone", 60)
		var ic := CenterContainer.new()
		ic.add_child(icon)
		gv.add_child(ic)
		var l := UiKit.label(str(g.left), 32, Color.WHITE, 7)
		gv.add_child(l)
		goal_box.add_child(gv)
		goal_labels[k] = l
		goal_icons[k] = icon
		goal_shown[k] = int(g.left)
	if goal_box.get_child_count() > 0:
		h.add_child(goal_box)
	if landscape():
		panel.custom_minimum_size = Vector2(minf(s.x * 0.36, 520), 0)
		_place(panel, Control.PRESET_CENTER_LEFT, Vector2(24, 0))
	else:
		panel.custom_minimum_size = Vector2(minf(s.x - 36, 700), 0)
		_place(panel, Control.PRESET_CENTER_TOP, Vector2(0, 112))
	UiKit.pop_in(panel, 0.05)
	tip_pill = UiKit.pill(28)
	tip_pill.visible = false
	tip_pill.custom_minimum_size = Vector2(minf(s.x - 60, 640), 0)
	_place(tip_pill, Control.PRESET_CENTER_BOTTOM, Vector2(0, -28))
	await get_tree().process_frame
	_layout_game()


func world_tint() -> Color:
	return Game.WORLDS[maxi(world, 0)].tint


func _layout_game() -> void:
	var s := vsize()
	var rect: Rect2
	if landscape():
		var left := minf(s.x * 0.36, 520) + 48
		rect = Rect2(Vector2(left, 30), Vector2(s.x - left - 30, s.y - 60))
	else:
		var top := 112.0 + 150.0
		rect = Rect2(Vector2(22, top + 14), Vector2(s.x - 44, s.y - top - 120))
	board.fit(rect)


func _show_start_popup() -> void:
	board.input_enabled = false
	var p := _popup()
	var v: VBoxContainer = p.get_child(0)
	v.add_child(UiKit.label("%s %d" % [Game.tr_("level"), level_idx + 1], 56, Color.WHITE, 12, true))
	var ng = level.get("new_gem", null)
	if ng != null and not (int(ng) in Game.save.seen_gems):
		v.add_child(UiKit.label(Game.tr_("new_gem"), 34, Color(1, 0.85, 0.4), 8))
		var gi := UiKit.GemIcon.new(int(ng), 150, true)
		var cc := CenterContainer.new()
		cc.add_child(gi)
		v.add_child(cc)
		v.add_child(UiKit.label(Game.gem_name(int(ng)), 40, Game.GEMS[int(ng)].color.lightened(0.3), 9))
		Game.save.seen_gems.append(int(ng))
		Game.write_save()
		Sfx.play("powerup")
	v.add_child(UiKit.label(Game.tr_("goal"), 30, Color(1, 0.85, 0.6), 6))
	for g in goals.list:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		match g.type:
			"score":
				row.add_child(UiKit.Star.new(44))
				row.add_child(UiKit.label(Game.tr_("goal_score") % str(int(g.n)), 34, Color.WHITE, 7))
			"collect":
				row.add_child(UiKit.GemIcon.new(int(g.color), 56, true))
				row.add_child(UiKit.label("× %d" % int(g.n), 38, Color.WHITE, 8))
			"ice":
				row.add_child(ObstacleIcon.new("ice", 56))
				row.add_child(UiKit.label(Game.tr_("goal_ice"), 32, Color.WHITE, 7))
			"stone":
				row.add_child(ObstacleIcon.new("stone", 56))
				row.add_child(UiKit.label(Game.tr_("goal_stone"), 32, Color.WHITE, 7))
		v.add_child(row)
	v.add_child(UiKit.label("%s: %d" % [Game.tr_("moves"), moves_left], 32, Color(1, 0.9, 0.7), 7))
	var tut: String = level.get("tut", "")
	if tut != "":
		var tl := UiKit.label(Game.tr_("tip_" + tut), 28, Color(0.85, 0.95, 1.0), 6)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(520, 0)
		v.add_child(tl)
		if tut in ["line", "bomb", "prism", "combo"]:
			var demo := HBoxContainer.new()
			demo.alignment = BoxContainer.ALIGNMENT_CENTER
			var sp_kind: int = {"line": Match3.SP_LINE_H, "bomb": Match3.SP_BOMB, "prism": Match3.SP_PRISM, "combo": Match3.SP_BOMB}[tut]
			var demo_gem := DemoGem.new(sp_kind)
			demo.add_child(demo_gem)
			v.add_child(demo)
	var go := UiKit.button(Game.tr_("start"), Color(0.95, 0.35, 0.65), Vector2(360, 110), 48)
	go.pressed.connect(func():
		_close_overlay()
		_begin_play())
	_center(v, go)
	UiKit.pop_in(p, 0.0)


func _begin_play() -> void:
	await board.intro()
	board.input_enabled = true
	playing = true
	var tut: String = level.get("tut", "")
	if tut != "":
		tip(Game.tr_("tip_" + tut))


func tip(text: String) -> void:
	if tip_pill == null:
		return
	var l: Label = tip_pill.get_node("L")
	l.text = text
	tip_pill.visible = true
	tip_pill.modulate.a = 0.0
	var t := tip_pill.create_tween()
	t.tween_property(tip_pill, "modulate:a", 1.0, 0.3)
	t.tween_interval(6.0)
	t.tween_property(tip_pill, "modulate:a", 0.0, 0.6)
	t.tween_callback(func(): tip_pill.visible = false)


func toast(text: String) -> void:
	var p := UiKit.pill(32)
	p.get_node("L").text = text
	ui.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.modulate.a = 0.0
	var t := p.create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.2)
	t.tween_interval(1.6)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)


# ---------------------------------------------------------------- board events

func _on_move() -> void:
	if mode == "level":
		moves_left -= 1
		lbl_moves.text = str(moves_left)
		_bump(lbl_moves)
		lbl_moves.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if moves_left <= 3 else Color.WHITE)


func _on_scored(pts: int, _pos: Vector2, _cascade: int) -> void:
	score += pts
	goals.score = score
	for g in goals.list:
		if g.type == "score":
			g.left = maxi(0, int(g.n) - score)
	if mode == "blitz" and _cascade >= 3:
		time_left += 1.0


func _on_cleared(list: Array) -> void:
	var by_color := {}
	for e in list:
		by_color[e.color] = by_color.get(e.color, 0) + 1
	var flights := 0
	for k in goals.list.size():
		var g: Dictionary = goals.list[k]
		if g.type != "collect":
			continue
		var before := int(g.left)
		g.left = maxi(0, before - int(by_color.get(int(g.color), 0)))
		var need := before - int(g.left)
		for e in list:
			if need <= 0:
				break
			if int(e.color) != int(g.color):
				continue
			need -= 1
			if flights < 14:
				_fly_to_goal(k, int(g.color), e.pos, e.t + flights * 0.03)
				flights += 1
			else:
				goal_shown[k] = maxi(int(g.left), int(goal_shown[k]) - 1)
				goal_labels[k].text = str(goal_shown[k])
	_check_goal_marks()


func _fly_to_goal(k: int, color: int, from: Vector2, delay: float) -> void:
	var icon: Control = goal_icons.get(k)
	if icon == null:
		return
	var gi := UiKit.GemIcon.new(color, board.cell * 0.8)
	fly_layer.add_child(gi)
	gi.size = gi.custom_minimum_size
	gi.position = from - gi.size * 0.5
	gi.visible = false
	var to := icon.global_position + icon.size * 0.5 - gi.size * 0.5
	var mid := (gi.position + to) * 0.5 + Vector2(randf_range(-120, 120), -80)
	var t := gi.create_tween()
	t.tween_interval(delay + 0.12)
	t.tween_callback(func(): gi.visible = true)
	var start := gi.position
	t.tween_method(func(f: float):
		var a := start.lerp(mid, f)
		var b := mid.lerp(to, f)
		gi.position = a.lerp(b, f)
		gi.scale = Vector2.ONE * lerpf(1.0, 0.6, f), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		gi.queue_free()
		if goal_labels.has(k):
			goal_shown[k] = maxi(int(goals.list[k].left), int(goal_shown[k]) - 1)
			goal_labels[k].text = str(goal_shown[k]) if goal_shown[k] > 0 else "✓"
			_bump(icon)
			Sfx.play("pop", 1.0 + randf() * 0.3, -10.0))


func _refresh_goals() -> void:
	for k in goals.list.size():
		var g: Dictionary = goals.list[k]
		if g.type == "ice":
			g.left = board.m.count_ice()
		elif g.type == "stone":
			g.left = board.m.count_stone()
		else:
			continue
		var shown := 0
		for i in board.m.w * board.m.h:
			shown += board.shown_ice[i] if g.type == "ice" else board.shown_stone[i]
		if goal_labels.has(k) and goal_shown[k] != shown:
			goal_shown[k] = shown
			goal_labels[k].text = str(shown) if shown > 0 else "✓"
			_bump(goal_icons[k])


func _check_goal_marks() -> void:
	pass


func _bump(c: Control) -> void:
	if c == null:
		return
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(1.3, 1.3), 0.06)
	t.tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_combo(n: int, _pos: Vector2) -> void:
	var key := "combo%d" % mini(n, 6)
	var s := vsize()
	var cols := [Color(1, 0.9, 0.4), Color(0.5, 1, 0.7), Color(0.5, 0.85, 1), Color(1, 0.55, 0.9), Color(1, 0.6, 0.3)]
	var l := UiKit.label(Game.tr_(key), 58 + mini(n, 6) * 8, cols[mini(n, 6) - 2], 14, true)
	fly_layer.add_child(l)
	l.size = Vector2(s.x, 140)
	l.position = Vector2(0, board.position.y + board.grid_size.y * 0.42)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.2, 0.2)
	l.rotation = randf_range(-0.12, 0.12)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.45)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(l, "position:y", l.position.y - 60, 0.3)
	t.tween_callback(l.queue_free)
	if n >= 4:
		Sfx.play("bell", 1.0, -4.0)


func _on_settled() -> void:
	_refresh_goals()
	if screen != "game" or ended or not playing:
		return
	if mode == "blitz":
		return
	if goals.done():
		ended = true
		_finale()
	elif moves_left <= 0:
		ended = true
		board.input_enabled = false
		await get_tree().create_timer(0.4).timeout
		_show_lose()


func _finale() -> void:
	board.input_enabled = false
	var s := vsize()
	_on_combo_text(Game.tr_("bonus"), Color(1, 0.85, 0.3))
	Sfx.play("complete")
	await get_tree().create_timer(0.8).timeout
	var left := moves_left
	await board.bonus_round(left, func(p: Vector2):
		moves_left = maxi(0, moves_left - 1)
		lbl_moves.text = str(moves_left)
		_bump(lbl_moves)
		var spark := UiKit.GemIcon.new(-1, 40)
		fly_layer.add_child(spark)
		var from := lbl_moves.global_position + lbl_moves.size * 0.5
		spark.position = from
		var t := spark.create_tween()
		t.tween_property(spark, "position", p - Vector2(20, 20), 0.25)
		t.tween_callback(spark.queue_free))
	await get_tree().create_timer(0.5).timeout
	_show_win()


func _on_combo_text(text: String, col: Color) -> void:
	var s := vsize()
	var l := UiKit.label(text, 96, col, 16, true)
	fly_layer.add_child(l)
	l.size = Vector2(s.x, 160)
	l.position = Vector2(0, s.y * 0.4)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.2, 0.2)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


# ---------------------------------------------------------------- end screens

func _popup() -> PanelContainer:
	_close_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var p := UiKit.panel(world_tint())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.add_child(p)
	overlay.add_child(cc)
	p.custom_minimum_size = Vector2(minf(vsize().x - 50, 620), 0)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	return p


func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


func _show_win() -> void:
	board.input_enabled = false
	var stars := Sim.stars_for(level, score)
	Game.record_win(level_idx, stars, score)
	Sfx.play("win")
	var s := vsize()
	Fx.confetti(fly_layer, Rect2(Vector2.ZERO, s), 140)
	for k in 5:
		var pos := Vector2(randf_range(s.x * 0.15, s.x * 0.85), randf_range(s.y * 0.15, s.y * 0.5))
		var col: Color = Game.GEMS[randi() % Game.GEMS.size()].color
		get_tree().create_timer(0.3 + k * 0.35).timeout.connect(func():
			if is_instance_valid(fly_layer):
				Fx.firework(fly_layer, pos, col)
				Sfx.play("firework", randf_range(0.9, 1.1), -6.0))
	var p := _popup()
	var v: VBoxContainer = p.get_child(0)
	v.add_child(UiKit.label(Game.tr_("win"), 58, Color(1, 0.9, 0.5), 12, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var st_nodes: Array = []
	for k in 3:
		var st := UiKit.Star.new(110 if k == 1 else 90, k < stars)
		st.modulate.a = 0.0
		row.add_child(st)
		st_nodes.append(st)
	v.add_child(row)
	var sc_l := UiKit.label("0", 64, Color.WHITE, 12)
	v.add_child(sc_l)
	var best := int(Game.save.best.get(str(level_idx), 0))
	if score >= best:
		v.add_child(UiKit.label(Game.tr_("new_best"), 30, Color(0.6, 1, 0.7), 7))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	var map := UiKit.IconButton.new("levels", Color(0.45, 0.35, 0.8), 104)
	map.pressed.connect(func(): show_map(Game.world_of(level_idx)))
	h.add_child(map)
	var again := UiKit.IconButton.new("restart", Color(0.45, 0.35, 0.8), 104)
	again.pressed.connect(func(): start_level(level_idx))
	h.add_child(again)
	var nx := UiKit.button(Game.tr_("next"), Color(0.95, 0.35, 0.65), Vector2(260, 104), 44)
	nx.pressed.connect(func(): start_level(level_idx + 1))
	h.add_child(nx)
	v.add_child(h)
	UiKit.pop_in(p)
	# stars pop one by one, score counts up
	var t := p.create_tween()
	t.tween_interval(0.5)
	for k in 3:
		var st: Control = st_nodes[k]
		var filled := k < stars
		t.tween_callback(func():
			st.pivot_offset = st.size * 0.5
			st.scale = Vector2(2.2, 2.2)
			var tt := st.create_tween()
			tt.tween_property(st, "modulate:a", 1.0, 0.1)
			tt.parallel().tween_property(st, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if filled:
				Sfx.play("star", 1.0 + k * 0.12)
				Fx.glow(fly_layer, st.global_position + st.size * 0.5, Color(1, 0.85, 0.3), 220, 0.5))
		t.tween_interval(0.35)
	t.parallel().tween_method(func(f: float): sc_l.text = str(int(score * f)), 0.0, 1.0, 1.2)


func _show_lose() -> void:
	board.input_enabled = false
	Sfx.play("fail")
	var p := _popup()
	var v: VBoxContainer = p.get_child(0)
	v.add_child(UiKit.label(Game.tr_("lose"), 58, Color(1, 0.6, 0.55), 12, true))
	v.add_child(UiKit.label(Game.tr_("lose_sub"), 32, Color.WHITE, 7))
	for k in goals.list.size():
		var g: Dictionary = goals.list[k]
		if int(g.left) <= 0:
			continue
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		match g.type:
			"collect":
				row.add_child(UiKit.GemIcon.new(int(g.color), 54))
			"ice":
				row.add_child(ObstacleIcon.new("ice", 54))
			"stone":
				row.add_child(ObstacleIcon.new("stone", 54))
			"score":
				row.add_child(UiKit.Star.new(44))
		row.add_child(UiKit.label("  %d" % int(g.left), 38, Color.WHITE, 8))
		v.add_child(row)
	if not plus5_used:
		var p5 := UiKit.button(Game.tr_("plus5"), Color(0.2, 0.75, 0.45), Vector2(360, 104), 44)
		p5.pressed.connect(func():
			plus5_used = true
			moves_left += 5
			lbl_moves.text = str(moves_left)
			lbl_moves.add_theme_color_override("font_color", Color.WHITE)
			ended = false
			_close_overlay()
			Sfx.play("powerup")
			board.input_enabled = true)
		_center(v, p5)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	var map := UiKit.IconButton.new("levels", Color(0.45, 0.35, 0.8), 104)
	map.pressed.connect(func(): show_map(Game.world_of(level_idx)))
	h.add_child(map)
	var again := UiKit.button(Game.tr_("retry"), Color(0.95, 0.35, 0.65), Vector2(280, 104), 44)
	again.pressed.connect(func(): start_level(level_idx))
	h.add_child(again)
	v.add_child(h)
	UiKit.pop_in(p)


func _blitz_over() -> void:
	ended = true
	board.input_enabled = false
	var rec := score > int(Game.save.blitz_best)
	if rec:
		Game.save.blitz_best = score
		Game.write_save()
	Sfx.play("win" if rec else "complete")
	var p := _popup()
	var v: VBoxContainer = p.get_child(0)
	v.add_child(UiKit.label(Game.tr_("time_up"), 58, Color(1, 0.9, 0.5), 12, true))
	v.add_child(UiKit.label(str(score), 72, Color.WHITE, 12))
	if rec:
		v.add_child(UiKit.label(Game.tr_("new_best"), 34, Color(0.6, 1, 0.7), 8))
		Fx.confetti(fly_layer, Rect2(Vector2.ZERO, vsize()), 120)
	else:
		v.add_child(UiKit.label("%s: %d" % [Game.tr_("best"), int(Game.save.blitz_best)], 32, Color(1, 0.85, 0.6), 7))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	var home := UiKit.IconButton.new("home", Color(0.45, 0.35, 0.8), 104)
	home.pressed.connect(show_title)
	h.add_child(home)
	var again := UiKit.button(Game.tr_("retry"), Color(0.95, 0.35, 0.65), Vector2(280, 104), 44)
	again.pressed.connect(start_blitz)
	h.add_child(again)
	v.add_child(h)
	UiKit.pop_in(p)


func _show_pause() -> void:
	if overlay:
		return
	board.input_enabled = false
	get_tree().paused = false
	var p := _popup()
	var v: VBoxContainer = p.get_child(0)
	v.add_child(UiKit.label(Game.tr_("pause"), 58, Color.WHITE, 12, true))
	var res := UiKit.button(Game.tr_("resume"), Color(0.95, 0.35, 0.65), Vector2(400, 104), 44)
	res.pressed.connect(func():
		_close_overlay()
		if not ended:
			board.input_enabled = true)
	_center(v, res)
	var rs := UiKit.button(Game.tr_("retry"), Color(0.45, 0.35, 0.95), Vector2(400, 96), 40)
	rs.pressed.connect(func():
		if mode == "blitz":
			start_blitz()
		else:
			start_level(level_idx))
	_center(v, rs)
	var mp := UiKit.button(Game.tr_("menu"), Color(0.45, 0.35, 0.95), Vector2(400, 96), 40)
	mp.pressed.connect(func():
		if mode == "blitz":
			show_title()
		else:
			show_map(Game.world_of(level_idx)))
	_center(v, mp)
	v.add_child(_sound_row())
	UiKit.pop_in(p)


func _sound_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	var snd := UiKit.IconButton.new("sound", Color(0.35, 0.3, 0.6), 96)
	snd.off = not Game.save.sound
	snd.pressed.connect(func():
		Game.save.sound = not Game.save.sound
		snd.off = not Game.save.sound
		snd.queue_redraw()
		Game.write_save())
	h.add_child(snd)
	var mus := UiKit.IconButton.new("music", Color(0.35, 0.3, 0.6), 96)
	mus.off = not Game.save.music
	mus.pressed.connect(func():
		Game.save.music = not Game.save.music
		mus.off = not Game.save.music
		mus.queue_redraw()
		Game.write_save()
		Sfx.start_music())
	h.add_child(mus)
	return h


func _show_settings() -> void:
	_reset_armed = false
	var p := _popup()
	var v: VBoxContainer = p.get_child(0)
	v.add_child(UiKit.label(Game.tr_("settings"), 58, Color.WHITE, 12, true))
	v.add_child(_sound_row())
	var lang := UiKit.button("English" if Game.save.lang == "ru" else "Русский", Color(0.45, 0.35, 0.95), Vector2(400, 96), 40)
	lang.pressed.connect(func():
		Game.save.lang = "en" if Game.save.lang == "ru" else "ru"
		Game.write_save()
		show_title())
	_center(v, lang)
	var reset := UiKit.button(Game.tr_("reset"), Color(0.6, 0.25, 0.3), Vector2(400, 86), 32)
	reset.pressed.connect(func():
		if not _reset_armed:
			_reset_armed = true
			toast(Game.tr_("reset_q"))
			return
		Game.save.unlocked = 1
		Game.save.stars = {}
		Game.save.best = {}
		Game.save.seen_gems = []
		Game.write_save()
		show_title())
	_center(v, reset)
	var priv := LinkButton.new()
	priv.text = Game.tr_("privacy")
	priv.add_theme_font_size_override("font_size", 26)
	priv.pressed.connect(func(): OS.shell_open("https://maxims.top/gems/privacy.html"))
	_center(v, priv)
	var cl := UiKit.button(Game.tr_("close"), Color(0.95, 0.35, 0.65), Vector2(300, 96), 40)
	cl.pressed.connect(_close_overlay)
	_center(v, cl)
	UiKit.pop_in(p)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			if overlay:
				if screen == "game" and not ended:
					_close_overlay()
					board.input_enabled = true
				elif screen == "title":
					_close_overlay()
			elif screen == "game":
				_show_pause()
			elif screen == "map":
				show_title()
		if event.keycode == KEY_H and screen == "game":
			board.show_hint()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen == "game" and overlay == null:
			_show_pause()
		elif screen == "map":
			show_title()
		elif screen == "title" and overlay == null:
			get_tree().quit()
		elif overlay:
			_close_overlay()
			if screen == "game" and not ended:
				board.input_enabled = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "game" and playing and not ended and overlay == null:
		_show_pause()


# ================================================================ small widgets

class ScoreBar extends Control:
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var stars: Array = []

	func _draw() -> void:
		var top := float(stars[2]) if stars.size() >= 3 else 10000.0
		var r := Rect2(Vector2(0, size.y * 0.25), Vector2(size.x, size.y * 0.5))
		draw_style_box(UiKit.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.25), int(r.size.y * 0.5), 2), r)
		var f := clampf(value / top, 0.0, 1.0)
		if f > 0.02:
			var fr := Rect2(r.position, Vector2(r.size.x * f, r.size.y))
			draw_style_box(UiKit.box(Color(1, 0.75, 0.2), Color(1, 0.9, 0.5), int(r.size.y * 0.5), 0), fr)
		for k in stars.size():
			var x := r.size.x * clampf(float(stars[k]) / top, 0.0, 1.0)
			var reached := value >= float(stars[k])
			_star(Vector2(clampf(x, 10, size.x - 10), size.y * 0.5), size.y * 0.55, Color(1, 0.85, 0.2) if reached else Color(0.45, 0.4, 0.55))

	func _star(c: Vector2, rr: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2.0 + k * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (rr if k % 2 == 0 else rr * 0.45))
		draw_colored_polygon(pts, col)


class ObstacleIcon extends Control:
	var kind := "ice"

	func _init(k: String, d := 56.0) -> void:
		kind = k
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var d := minf(size.x, size.y)
		var r := Rect2((size - Vector2(d, d)) * 0.5, Vector2(d, d))
		if kind == "ice":
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.65, 0.9, 1.0, 0.45)
			sb.border_color = Color(0.9, 0.98, 1.0, 0.95)
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(int(d * 0.18))
			draw_style_box(sb, r.grow(-4))
			draw_line(r.position + Vector2(d * 0.25, d * 0.5), r.position + Vector2(d * 0.5, d * 0.25), Color(1, 1, 1, 0.8), 3, true)
		else:
			var tex: Texture2D = Game.stone_tex
			draw_texture_rect(tex, r, false, Color(0.75, 0.7, 0.78))


## Shows a special gem on the tutorial popup.
class DemoGem extends Control:
	var g: Gem

	func _init(sp: int) -> void:
		custom_minimum_size = Vector2(120, 120)
		g = Gem.new()
		add_child(g)
		g.setup(4 if sp != Match3.SP_BOMB else 0, sp, 100)
		g.position = Vector2(60, 60)


## Title logo: each letter is its own gem-coloured glyph that bobs and glints.
class Logo extends Control:
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var txt := "Gem Swap"
		var f: Font = UiKit.font_title
		var fs := int(minf(size.x / 4.2, 170))
		var total := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := (size.x - total) * 0.5
		var base_y := size.y * 0.62
		var cols := [Color("#ff2d55"), Color("#ff8a1c"), Color("#ffd51f"), Color(0, 0, 0, 0), Color("#22e06a"), Color("#2f7bff"), Color("#b04dff"), Color("#ff6fb5")]
		for k in txt.length():
			var ch := txt[k]
			var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if ch != " ":
				var bob := sin(_t * 2.2 + k * 0.6) * fs * 0.05
				var p := Vector2(x, base_y + bob)
				var c: Color = cols[k]
				draw_string_outline(f, p + Vector2(0, fs * 0.06), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.16), Color(0.05, 0.0, 0.1, 0.8))
				draw_string_outline(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.1), c.darkened(0.45))
				draw_string(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c.lightened(0.15))
				# glint sweeping across the letters
				var sweep := fmod(_t * 0.6, 2.5) * total - total * 0.25
				var dist := absf((x - (size.x - total) * 0.5) - sweep)
				if dist < fs * 0.6:
					var a := 1.0 - dist / (fs * 0.6)
					draw_string(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a * 0.7))
				if k % 3 == 1:
					var tw := maxf(0.0, sin(_t * 3.0 + k * 1.7))
					Gem._star(self, p + Vector2(w * 0.8, -fs * 0.62), fs * 0.12 * tw, Color(1, 1, 1, 0.9 * tw))
			x += w


# ================================================================ calibration

func _calibrate() -> void:
	var out: Array = []
	var only := int(Game.arg_value("--only", "0"))
	var runs := int(Game.arg_value("--runs", "30"))
	for i in Game.levels.size():
		var lv: Dictionary = Game.levels[i].duplicate(true)
		if only > 0 and i + 1 != only:
			out.append(lv)
			continue
		lv.moves = maxi(10, int(lv.moves) - HUMAN_BUFFER)
		var w := i / Game.PER_WORLD
		var target := 0.85 - w * 0.05 - (i % Game.PER_WORLD) * 0.008
		var res := {}
		for it in 8:
			res = _sim_level(lv, runs)
			if res.rate < target - 0.08 and lv.moves < 40:
				lv.moves = int(lv.moves) + (2 if res.rate > target - 0.3 else 4)
			elif res.rate > target + 0.12 and lv.moves > 14:
				lv.moves = int(lv.moves) - 2
			else:
				break
		var scores: Array = res.scores
		scores.sort()
		var s1 := 0
		for g in lv.goals:
			if g.type == "score":
				s1 = int(g.n)
		var p50 := int(scores[int(scores.size() * 0.45)]) if not scores.is_empty() else 3000
		var p85 := int(scores[int(scores.size() * 0.85)]) if not scores.is_empty() else 6000
		var s2 := maxi(s1 + 500, int(round(p50 / 500.0) * 500))
		var s3 := maxi(s2 + 1000, int(round(p85 / 500.0) * 500))
		lv.stars = [s1, s2, s3]
		lv.moves = int(lv.moves) + HUMAN_BUFFER
		out.append(lv)
		print("L%02d moves %d win %.2f (target %.2f) stars %s" % [i + 1, lv.moves, res.rate, target, str(lv.stars)])
	var f := FileAccess.open(Game.LEVELS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("CALIBRATION DONE")
	get_tree().quit(0)


func _sim_level(lv: Dictionary, runs: int) -> Dictionary:
	var wins := 0
	var scores: Array = []
	for r in runs:
		var res := Sim.play(lv, 1000 + r, 0.75)
		if res.win:
			wins += 1
			scores.append(res.score)
	return {"rate": float(wins) / runs, "scores": scores}


# ================================================================ autotest

var _fails := 0


func _check(ok: bool, what: String) -> void:
	var line := ("ok   " if ok else "FAIL ") + what
	print(line)
	_log.append(line)
	if not ok:
		_fails += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var pre := "land_" if landscape() else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/game"))
	img.save_png("res://renders/game/%s%s.png" % [pre, name])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_settled(limit := 20.0) -> void:
	var t := 0.0
	while (board.busy or not playing) and t < limit:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	await get_tree().create_timer(0.15).timeout


## Test input arrives in window pixels; convert from canvas coordinates (the window is scaled by the stretch mode).
func _win(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _press_at(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _win(p)
	e.global_position = e.position
	Input.parse_input_event(e)


func _drag(a: Vector2, b: Vector2) -> void:
	_press_at(a, true)
	await get_tree().process_frame
	for k in 4:
		var e := InputEventMouseMotion.new()
		e.position = _win(a.lerp(b, (k + 1) / 4.0))
		e.global_position = e.position
		Input.parse_input_event(e)
		await get_tree().process_frame
	_press_at(b, false)
	await get_tree().process_frame


func _logic_tests() -> void:
	# a hand-made board: verify specials are created and fire
	var m := Match3.new()
	m.setup({"w": 6, "h": 6, "colors": [0, 1, 2, 3], "map": []}, 5)
	_check(m.find_groups().is_empty(), "initial board has no matches")
	_check(not m.find_moves().is_empty(), "initial board has moves")
	var pat := [
		"012301",
		"123012",
		"000210",   # row 2: three 0s at x=0..2 + a 0 at x=3 after swap -> line
		"301230",
		"012301",
		"230123"]
	for y in 6:
		for x in 6:
			m.col[m.idx(x, y)] = int(pat[y][x])
			m.sp[m.idx(x, y)] = 0
	# put a 0 above (3,2)'s neighbour: swap (3,1)=0? set (3,3)=0 and swap it up into (3,2)
	m.col[m.idx(3, 3)] = 0
	m.col[m.idx(3, 2)] = 2
	_check(m.swap_is_valid(m.idx(3, 2), m.idx(3, 3)), "swap making 4 in a row is valid")
	m.do_swap(m.idx(3, 2), m.idx(3, 3))
	var st := m.resolve_step([m.idx(3, 2), m.idx(3, 3)])
	_check(st.made.size() == 1 and st.made[0].sp == Match3.SP_LINE_H, "4 in a row makes a line gem")
	_check(st.cleared.size() == 3, "the other 3 gems are cleared (got %d)" % st.cleared.size())
	var g := m.gravity()
	var full := true
	for i in 36:
		if m.col[i] == Match3.EMPTY:
			full = false
	_check(full, "gravity refills every cell")
	# fire the line gem
	var lc := m.first_special()
	var st2 := m.resolve_step([], {"fire": lc})
	_check(st2.cleared.size() >= 6, "line gem clears its row (%d)" % st2.cleared.size())
	m.gravity()
	# prism + gem clears that colour
	var m2 := Match3.new()
	m2.setup({"w": 7, "h": 7, "colors": [0, 1, 2, 3, 4], "map": []}, 9)
	m2.sp[m2.idx(3, 3)] = Match3.SP_PRISM
	m2.col[m2.idx(3, 3)] = Match3.PRISM_COLOR
	var target := m2.col[m2.idx(4, 3)]
	var n := 0
	for i in 49:
		if m2.col[i] == target:
			n += 1
	_check(m2.swap_is_valid(m2.idx(3, 3), m2.idx(4, 3)), "prism swap is always valid")
	var combo := m2.do_swap(m2.idx(3, 3), m2.idx(4, 3))
	var st3 := m2.resolve_step([], combo)
	_check(st3.cleared.size() >= n, "prism clears every gem of the colour (%d of %d)" % [st3.cleared.size(), n])
	# stones and ice
	var m3 := Match3.new()
	m3.setup({"w": 8, "h": 8, "colors": [0, 1, 2], "map": ["........", "........", "...ss...", "..iiii..", "........", "........", "........", "........"]}, 3)
	_check(m3.count_stone() == 2 and m3.count_ice() == 4, "map parses ice and stones")
	var played := 0
	for k in 60:
		var mv := m3.find_moves()
		if mv.is_empty():
			m3.shuffle_board()
			continue
		mv.sort_custom(func(a, b): return a[2] > b[2])
		var cmb := m3.do_swap(mv[0][0], mv[0][1])
		var foc := [mv[0][0], mv[0][1]]
		for z in 30:
			var s := m3.resolve_step(foc, cmb)
			cmb = {}
			foc = []
			if s.is_empty():
				break
			m3.gravity()
		played += 1
	_check(m3.count_ice() < 4, "playing breaks ice (%d left)" % m3.count_ice())
	# autoplayer sanity on the first levels
	var r := Sim.play(Game.levels[0], 1)
	_check(r.score > 0, "autoplayer scores on level 1 (%d, win %s)" % [r.score, str(r.win)])
	# every level loads with moves available
	var bad := 0
	for i in Game.levels.size():
		var mm := Match3.new()
		mm.setup(Game.levels[i], i)
		if mm.find_moves().is_empty() or not mm.find_groups().is_empty():
			bad += 1
	_check(bad == 0, "all %d levels start with moves and no matches" % Game.levels.size())


func _autotest() -> void:
	await get_tree().process_frame
	_logic_tests()
	show_title()
	await _wait(1.5)
	await _shot("01_title")
	_show_settings()
	await _wait(0.5)
	await _shot("02_settings")
	_close_overlay()
	for w in Game.WORLDS.size():
		show_map(w)
		await _wait(1.0)
		await _shot("03_map_%d" % w)
	Game.save.unlocked = 999
	start_level(0)
	await _wait(0.8)
	await _shot("04_start_popup")
	_close_overlay()
	_begin_play()
	await _wait_settled()
	await _shot("05_level1")
	# real input: drag a valid move
	var mv := board.m.find_moves()
	_check(not mv.is_empty(), "level 1 has a move")
	var before := moves_left
	var a := board.to_global(board.cell_pos(mv[0][0]))
	var b := board.to_global(board.cell_pos(mv[0][1]))
	await _drag(a, b)
	await _wait(0.25)
	await _shot("06_after_swap")
	await _wait_settled()
	_check(moves_left == before - 1, "a drag swap costs one move (%d -> %d)" % [before, moves_left])
	_check(score > 0, "the match scored (%d)" % score)
	# invalid swap by taps does not cost a move
	var inv := _find_invalid_pair()
	if inv.size() == 2:
		var mb := moves_left
		_press_at(board.to_global(board.cell_pos(inv[0])), true)
		_press_at(board.to_global(board.cell_pos(inv[0])), false)
		await get_tree().process_frame
		_press_at(board.to_global(board.cell_pos(inv[1])), true)
		_press_at(board.to_global(board.cell_pos(inv[1])), false)
		await _wait(0.6)
		_check(moves_left == mb, "an invalid tap swap is refused")
	# specials on the board, then combos (goal pushed out of reach so the level doesn't end by itself)
	for g in goals.list:
		if g.type == "score":
			g.n = 99999999
			g.left = 99999999
	await _special_demo()
	# win flow
	for g in goals.list:
		g.left = 0
	ended = true
	await _finale()
	await _wait(2.0)
	await _shot("10_win")
	_check(Game.stars_of(0) >= 1, "win records stars")
	# lose flow
	start_level(14)
	await _wait(0.5)
	_close_overlay()
	await _begin_play()
	await _wait_settled()
	await _shot("11_ice_level")
	moves_left = 0
	_on_settled()
	await _wait(1.0)
	await _shot("12_lose")
	# stones
	start_level(30)
	await _wait(0.6)
	await _shot("13_new_gem_popup")
	_close_overlay()
	await _begin_play()
	await _wait_settled()
	await _shot("14_stone_level")
	# a later shaped level of each world
	for w: int in [2, 4, 5]:
		start_level(w * 10 + 8)
		_close_overlay()
		await _begin_play()
		await _wait_settled()
		await _shot("15_world_%d" % w)
	# blitz
	start_blitz()
	await _wait(2.0)
	var mv2 := board.m.find_moves()
	if not mv2.is_empty():
		board.try_swap(mv2[0][0], mv2[0][1])
	await _wait(0.8)
	await _shot("16_blitz")
	time_left = 0.0
	await _wait(1.5)
	await _shot("17_blitz_over")
	_show_pause()
	await _wait(0.4)
	_close_overlay()
	print("AUTOTEST DONE fails=%d" % _fails)
	_log.append("AUTOTEST DONE fails=%d" % _fails)
	var f := FileAccess.open("res://renders/autotest.log", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit(_fails)


func _find_invalid_pair() -> Array:
	var m := board.m
	for i in m.w * m.h:
		var j := i + 1
		if i % m.w == m.w - 1 or not m.has_gem(i) or not m.has_gem(j):
			continue
		if not m.swap_is_valid(i, j):
			return [i, j]
	return []


func _special_demo() -> void:
	var m := board.m
	# plant specials and swap them so every effect plays at least once
	var cells: Array = []
	for i in m.w * m.h:
		if m.has_gem(i) and i % m.w < m.w - 1 and m.has_gem(i + 1) and i / m.w > 1:
			cells.append(i)
	var demos := [[Match3.SP_LINE_H, Match3.SP_LINE_V, "07_line_cross"], [Match3.SP_BOMB, Match3.SP_BOMB, "08_bombs"], [Match3.SP_PRISM, Match3.SP_NONE, "09_prism"]]
	for d in demos:
		if cells.is_empty():
			break
		var c: int = cells[(cells.size() / 2 + randi() % 5) % cells.size()]
		if not (m.has_gem(c) and m.has_gem(c + 1)):
			continue
		for pair in [[c, d[0]], [c + 1, d[1]]]:
			var cc: int = pair[0]
			var spk: int = pair[1]
			m.sp[cc] = spk
			if spk == Match3.SP_PRISM:
				m.col[cc] = Match3.PRISM_COLOR
			var g := board.gem_at(cc)
			if g:
				g.become(m.col[cc], spk)
		await _wait(0.6)
		board.try_swap(c, c + 1)
		await _wait(0.45)
		await _shot(d[2])
		await _wait_settled()
	_check(not board.busy, "board settles after special combos")


func _store_shot(n: int, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/play/raw"))
	img.save_png("res://renders/play/raw/%s_%d_%s.png" % [Game.lang(), n, name])


func _feature_bg() -> void:
	screen = "title"
	set_world(int(Game.arg_value("--world", "0")))
	_clear_ui()
	await _wait(3.5)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/play/raw"))
	get_viewport().get_texture().get_image().save_png("res://renders/play/raw/feature_bg.png")
	get_tree().quit()


## Google Play / README screenshots (run at 1080x1920): `-- --storeshots --lang ru`.
func _shots() -> void:
	Game.save.unlocked = 999
	Game.save.stars = {}
	for k in 24:
		Game.save.stars[str(k)] = 3 if k % 4 != 1 else 2
	show_title()
	await _wait(2.5)
	await _store_shot(1, "title")
	var demo := [[7, "line"], [26, "prism"], [16, "ice"], [33, "stone"], [52, "bomb"]]
	var n := 2
	for d in demo:
		start_level(d[0])
		_close_overlay()
		await _begin_play()
		await _wait_settled()
		for k in 2:
			var mv := board.m.find_moves()
			if mv.is_empty():
				break
			mv.sort_custom(func(x, y): return x[2] > y[2])
			board.try_swap(mv[0][0], mv[0][1])
			await _wait_settled()
		# plant a special pair and catch the effect mid-flight
		var m := board.m
		var c := m.idx(m.w / 2 - 1, m.h / 2)
		if m.has_gem(c) and m.has_gem(c + 1):
			var kinds: Array = {"line": [Match3.SP_LINE_H, Match3.SP_LINE_V], "prism": [Match3.SP_PRISM, Match3.SP_NONE],
				"ice": [Match3.SP_BOMB, Match3.SP_LINE_V], "stone": [Match3.SP_LINE_H, Match3.SP_BOMB], "bomb": [Match3.SP_BOMB, Match3.SP_BOMB]}[d[1]]
			for q in 2:
				var cc: int = c + q
				m.sp[cc] = kinds[q]
				if kinds[q] == Match3.SP_PRISM:
					m.col[cc] = Match3.PRISM_COLOR
				var g := board.gem_at(cc)
				if g:
					g.become(m.col[cc], kinds[q])
			await _wait(0.7)
			board.try_swap(c, c + 1)
			await _wait(0.5 if d[1] != "prism" else 0.75)
		await _store_shot(n, d[1])
		n += 1
		await _wait_settled()
	show_map(2)
	await _wait(1.5)
	await _store_shot(n, "map")
	n += 1
	start_level(4)
	_close_overlay()
	await _begin_play()
	await _wait_settled()
	score = 6200
	for g in goals.list:
		g.left = 0
	ended = true
	_show_win()
	await _wait(2.4)
	await _store_shot(n, "win")
	get_tree().quit()
