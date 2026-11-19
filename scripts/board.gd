class_name Board
extends Node2D
## The playfield: tiles, gems, ice, stones, input (swipe or tap-tap), and every animation of a move:
## swap, matches, specials, cascades, falling gems, shuffles, hints and the bonus finale.

signal move_made                         # a valid swap happened (costs a move)
signal scored(points: int, pos: Vector2, cascade: int)
signal gems_cleared(list: Array)         # [{color, pos}] in global coords
signal obstacles_changed
signal combo(n: int, pos: Vector2)
signal settled                           # the board is still and ready for input
signal special_made(kind: int)
signal shuffling

var m := Match3.new()
var cell := 80.0
var origin := Vector2.ZERO
var grid_size := Vector2.ZERO
var tint := Color(0.7, 0.5, 1.0)
var nodes := {}               # gem id -> Gem
var busy := false
var input_enabled := true
var sel := -1
var idle := 0.0
var hint_on: Array = []
var shown_ice := PackedInt32Array()
var shown_stone := PackedInt32Array()
var stone_nodes := {}         # cell -> StoneNode
var speed := 1.0              # autotest can speed things up
var cascade_max := 0

var tiles: Node2D
var clip: Control
var gem_layer: Node2D
var ice_layer: Node2D
var stone_layer: Node2D
var fx_layer: Node2D
var _press_cell := -1
var _press_pos := Vector2.ZERO
var _dragged := false


func _ready() -> void:
	Fx.init()
	tiles = Node2D.new()
	tiles.draw.connect(_draw_tiles)
	add_child(tiles)
	clip = Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	gem_layer = Node2D.new()
	clip.add_child(gem_layer)
	ice_layer = Node2D.new()
	ice_layer.draw.connect(_draw_ice)
	add_child(ice_layer)
	stone_layer = Node2D.new()
	add_child(stone_layer)
	fx_layer = Node2D.new()
	add_child(fx_layer)


# ================================================================== setup / layout

func load_level(lv: Dictionary, seed_ := -1) -> void:
	for n in nodes.values():
		n.queue_free()
	nodes.clear()
	for s in stone_nodes.values():
		s.queue_free()
	stone_nodes.clear()
	for c in fx_layer.get_children():
		c.queue_free()
	m = Match3.new()
	m.setup(lv, seed_)
	shown_ice = m.ice.duplicate()
	shown_stone = m.stone.duplicate()
	sel = -1
	busy = false
	idle = 0.0
	hint_on = []
	_layout_size()


## Fit the board into rect (in parent coordinates).
func fit(rect: Rect2) -> void:
	cell = floorf(minf(rect.size.x / m.w, rect.size.y / m.h))
	grid_size = Vector2(m.w, m.h) * cell
	position = rect.position + (rect.size - grid_size) * 0.5
	origin = Vector2.ZERO
	_layout_size()


func _layout_size() -> void:
	clip.position = Vector2(-cell * 0.3, 0)
	clip.size = Vector2(grid_size.x + cell * 0.6, grid_size.y + cell * 0.3)
	gem_layer.position = -clip.position
	for n in nodes.values():
		n.queue_free()
	nodes.clear()
	for i in m.w * m.h:
		if m.has_gem(i):
			_make_gem(i, m.ids[i], m.col[i], m.sp[i], cell_pos(i))
	for s in stone_nodes.values():
		s.queue_free()
	stone_nodes.clear()
	for i in m.w * m.h:
		if shown_stone[i] > 0:
			var sn := StoneNode.new()
			sn.hp = shown_stone[i]
			sn.max_hp = shown_stone[i]
			sn.size = cell
			sn.position = cell_pos(i)
			stone_layer.add_child(sn)
			stone_nodes[i] = sn
	tiles.queue_redraw()
	ice_layer.queue_redraw()


## Drop-in intro: every gem falls into place, column by column.
func intro() -> void:
	busy = true
	for id in nodes:
		var g: Gem = nodes[id]
		var target := g.position
		g.position = target - Vector2(0, grid_size.y + cell)
		var x := g.cell % m.w
		var y := g.cell / m.w
		var t := g.create_tween()
		t.tween_interval((x * 0.035 + (m.h - y) * 0.03) / speed)
		t.tween_property(g, "position", target, 0.42 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(g.land.bind(0.8))
	await _wait(0.42 + m.w * 0.035 + m.h * 0.03 + 0.2)
	busy = false
	settled.emit()


func cell_pos(i: int) -> Vector2:
	return origin + Vector2(i % m.w + 0.5, i / m.w + 0.5) * cell


func cell_at(local: Vector2) -> int:
	var p := (local - origin) / cell
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	if not m.inside(x, y):
		return -1
	return m.idx(x, y)


func _make_gem(i: int, id: int, color: int, sp: int, pos: Vector2) -> Gem:
	var g := Gem.new()
	gem_layer.add_child(g)
	g.setup(color if color >= 0 else 0, sp, cell)
	g.cell = i
	g.position = pos
	nodes[id] = g
	return g


func gem_at(i: int) -> Gem:
	if i < 0 or not m.has_gem(i):
		return null
	return nodes.get(m.ids[i])


# ================================================================== drawing

func _draw_tiles() -> void:
	var r := cell * 0.16
	# dark glass panel behind the playable cells
	for i in m.w * m.h:
		if m.mask[i] == 0:
			continue
		var p := Vector2(i % m.w, i / m.w) * cell
		tiles.draw_rect(Rect2(p - Vector2(cell, cell) * 0.08, Vector2(cell, cell) * 1.16), Color(0.03, 0.02, 0.08, 0.62))
	for i in m.w * m.h:
		if m.mask[i] == 0:
			continue
		var x := i % m.w
		var y := i / m.w
		var p := Vector2(x, y) * cell
		var light := (x + y) % 2 == 0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.085 if light else 0.04)
		sb.set_corner_radius_all(int(r))
		sb.anti_aliasing = true
		tiles.draw_style_box(sb, Rect2(p + Vector2(2, 2), Vector2(cell - 4, cell - 4)))
		# glowing outline on the outer edges of the shape
		var edge_col := Color(tint.lightened(0.25), 0.75)
		var wdt := maxf(2.0, cell * 0.04)
		var o := cell * 0.08
		if y == 0 or m.mask[i - m.w] == 0:
			tiles.draw_line(p + Vector2(-o, -o), p + Vector2(cell + o, -o), edge_col, wdt, true)
		if y == m.h - 1 or m.mask[i + m.w] == 0:
			tiles.draw_line(p + Vector2(-o, cell + o), p + Vector2(cell + o, cell + o), edge_col, wdt, true)
		if x == 0 or m.mask[i - 1] == 0:
			tiles.draw_line(p + Vector2(-o, -o), p + Vector2(-o, cell + o), edge_col, wdt, true)
		if x == m.w - 1 or m.mask[i + 1] == 0:
			tiles.draw_line(p + Vector2(cell + o, -o), p + Vector2(cell + o, cell + o), edge_col, wdt, true)


func _draw_ice() -> void:
	for i in m.w * m.h:
		var n := shown_ice[i]
		if n <= 0:
			continue
		var p := Vector2(i % m.w, i / m.w) * cell
		var rc := Rect2(p + Vector2(3, 3), Vector2(cell - 6, cell - 6))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.65, 0.9, 1.0, 0.22 if n == 1 else 0.38)
		sb.border_color = Color(0.85, 0.97, 1.0, 0.75 if n == 1 else 0.95)
		sb.set_border_width_all(2 if n == 1 else 4)
		sb.set_corner_radius_all(int(cell * 0.14))
		sb.anti_aliasing = true
		ice_layer.draw_style_box(sb, rc)
		var hl := Color(1, 1, 1, 0.55)
		ice_layer.draw_line(rc.position + Vector2(cell * 0.15, cell * 0.42), rc.position + Vector2(cell * 0.42, cell * 0.15), hl, 3, true)
		ice_layer.draw_line(rc.position + Vector2(cell * 0.18, cell * 0.6), rc.position + Vector2(cell * 0.6, cell * 0.18), Color(1, 1, 1, 0.3), 2, true)
		if n >= 2:
			# frost corners
			for c: Vector2 in [rc.position, rc.position + Vector2(rc.size.x, 0), rc.end, rc.position + Vector2(0, rc.size.y)]:
				var dir: Vector2 = (rc.get_center() - c).normalized()
				for k in 3:
					var a := dir.rotated((k - 1) * 0.5)
					ice_layer.draw_line(c + dir * 4, c + dir * 4 + a * cell * 0.16, Color(1, 1, 1, 0.7), 2, true)


class StoneNode extends Node2D:
	var hp := 1
	var max_hp := 1
	var size := 80.0
	var shake := 0.0

	func _draw() -> void:
		var tex: Texture2D = Game.stone_tex
		var s := size * 0.98 / tex.get_width()
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		draw_set_transform(off, 0, Vector2(s, s))
		var tint := Color(0.62, 0.58, 0.8) if hp >= 2 else Color(0.78, 0.74, 0.8)
		draw_texture(tex, -Vector2(tex.get_width(), tex.get_height()) * 0.5, tint)
		draw_set_transform(off, 0, Vector2.ONE)
		var r := size * 0.5
		if hp >= 2:
			# glowing rune band = extra layer
			draw_arc(Vector2.ZERO, r * 0.52, 0, TAU, 36, Color(0.7, 0.85, 1.0, 0.85), maxf(2.0, size * 0.05), true)
			for k in 4:
				var a := k * TAU / 4.0 + PI / 4
				draw_circle(Vector2(cos(a), sin(a)) * r * 0.52, size * 0.05, Color(0.9, 0.95, 1.0))
		if hp < max_hp or hp == 1 and max_hp == 1 and false:
			var c := Color(0.08, 0.05, 0.08, 0.9)
			draw_polyline(PackedVector2Array([Vector2(-r * 0.6, -r * 0.3), Vector2(-r * 0.2, -r * 0.05), Vector2(-r * 0.05, r * 0.4), Vector2(r * 0.3, r * 0.55)]), c, 3, true)
			draw_polyline(PackedVector2Array([Vector2(-r * 0.2, -r * 0.05), Vector2(r * 0.25, -r * 0.35), Vector2(r * 0.6, -r * 0.3)]), c, 3, true)

	func hit() -> void:
		hp -= 1
		var t := create_tween()
		t.tween_method(func(v): shake = v; queue_redraw(), size * 0.12, 0.0, 0.3)
		if hp <= 0:
			t.tween_property(self, "scale", Vector2(1.25, 1.25), 0.06)
			t.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
			t.tween_callback(queue_free)


# ================================================================== input

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or busy:
		if event is InputEventMouseButton and not event.pressed:
			_press_cell = -1
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var lp := to_local(event.position)
		if event.pressed:
			var c := cell_at(lp)
			if c < 0 or not m.has_gem(c):
				_select(-1)
				return
			_press_cell = c
			_press_pos = lp
			_dragged = false
			_touch()
			get_viewport().set_input_as_handled()
		else:
			if _press_cell >= 0 and not _dragged:
				_tap(_press_cell)
			_press_cell = -1
	elif event is InputEventMouseMotion and _press_cell >= 0 and not _dragged:
		var lp := to_local(event.position)
		var d := lp - _press_pos
		if d.length() > cell * 0.32:
			_dragged = true
			var dir := Vector2i(signi(int(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, signi(int(d.y)))
			var x := _press_cell % m.w + dir.x
			var y := _press_cell / m.w + dir.y
			var from := _press_cell
			_press_cell = -1
			_select(-1)
			if m.inside(x, y):
				try_swap(from, m.idx(x, y))


func _tap(c: int) -> void:
	if sel < 0:
		_select(c)
		Sfx.play("select", 1.0, -6.0)
	elif sel == c:
		_select(-1)
	elif m.adjacent(sel, c):
		var a := sel
		_select(-1)
		try_swap(a, c)
	else:
		_select(c)
		Sfx.play("select", 1.0, -6.0)


func _select(c: int) -> void:
	if sel >= 0:
		var g := gem_at(sel)
		if g:
			g.set_selected(false)
	sel = c
	if c >= 0:
		var g := gem_at(c)
		if g:
			g.set_selected(true)


func _touch() -> void:
	idle = 0.0
	_clear_hint()


func _process(delta: float) -> void:
	if busy or not input_enabled:
		idle = 0.0
		return
	idle += delta
	if idle > 5.0 and hint_on.is_empty():
		show_hint()


func show_hint() -> void:
	var mv := m.find_moves()
	if mv.is_empty():
		return
	mv.sort_custom(func(a, b): return a[2] > b[2])
	var best: Array = mv[randi() % mini(3, mv.size())]
	hint_on = [best[0], best[1]]
	for c in hint_on:
		var g := gem_at(c)
		if g:
			g.set_hint(true)


func _clear_hint() -> void:
	for c in hint_on:
		var g := gem_at(c)
		if g:
			g.set_hint(false)
	hint_on = []


# ================================================================== moves

func _wait(t: float) -> void:
	if t <= 0.0:
		return
	await get_tree().create_timer(t / speed, false).timeout


func _at(t: float, f: Callable) -> void:
	if t <= 0.001:
		f.call()
	else:
		get_tree().create_timer(t / speed, false).timeout.connect(f)


func try_swap(a: int, b: int) -> void:
	if busy:
		return
	_touch()
	var ga := gem_at(a)
	var gb := gem_at(b)
	if ga == null or gb == null:
		return
	busy = true
	var pa := cell_pos(a)
	var pb := cell_pos(b)
	ga.z_index = 2
	if not m.swap_is_valid(a, b):
		Sfx.play("swap", 1.1, -5.0)
		var t := create_tween()
		t.tween_property(ga, "position", pb, 0.14 / speed).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(gb, "position", pa, 0.14 / speed).set_trans(Tween.TRANS_QUAD)
		t.tween_callback(func(): Sfx.play("error", 1.0, -6.0))
		t.tween_property(ga, "position", pa, 0.2 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(gb, "position", pb, 0.2 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await t.finished
		ga.z_index = 0
		busy = false
		return
	Sfx.play("swap", 1.0, -3.0)
	var t2 := create_tween()
	t2.tween_property(ga, "position", pb, 0.16 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t2.parallel().tween_property(gb, "position", pa, 0.16 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t2.parallel().tween_property(ga, "scale", Vector2(1.15, 1.15), 0.08 / speed)
	t2.chain().tween_property(ga, "scale", Vector2.ONE, 0.08 / speed)
	await t2.finished
	ga.z_index = 0
	ga.cell = b
	gb.cell = a
	var combo_info := m.do_swap(a, b)
	move_made.emit()
	await resolve([a, b], combo_info)


## Resolve everything until the board is still. Also used by the bonus finale (combo = {"fire": cell}).
func resolve(focus: Array, combo_info := {}) -> void:
	busy = true
	var cascade := 1
	while true:
		var step := m.resolve_step(focus, combo_info, cascade)
		combo_info = {}
		if step.is_empty():
			break
		await _animate_step(step, cascade)
		var g := m.gravity()
		await _animate_gravity(g)
		cascade += 1
		focus = []
	cascade_max = maxi(cascade_max, cascade - 1)
	if m.find_moves().is_empty():
		await do_shuffle()
	busy = false
	idle = 0.0
	settled.emit()


func do_shuffle() -> void:
	shuffling.emit()
	await _wait(0.6)
	Sfx.play("shuffle")
	var moves := m.shuffle_board()
	var center := grid_size * 0.5
	for mv in moves:
		var g: Gem = nodes.get(mv.id)
		if g == null:
			continue
		g.cell = mv.to
		var t := g.create_tween()
		t.tween_property(g, "position", center + (g.position - center) * 0.2, 0.3 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(g, "position", cell_pos(mv.to), 0.4 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _wait(0.8)


func _animate_step(step: Dictionary, cascade: int) -> void:
	var maxt := 0.0
	var made_at := {}
	for mk in step.made:
		made_at[mk.i] = mk
	var merge_target := {}
	var match_center := Vector2.ZERO
	var match_n := 0
	var biggest := 0
	for f in step.fx:
		match f.kind:
			"match":
				for c in f.cells:
					match_center += cell_pos(c)
					match_n += 1
					if made_at.has(c):
						for c2 in f.cells:
							merge_target[c2] = c
				biggest = maxi(biggest, f.n)
			"line_h", "line_v":
				var p := cell_pos(f.i)
				var col := _fx_color(f.get("color", -1))
				var a := Vector2(origin.x - cell * 0.3, p.y) if f.kind == "line_h" else Vector2(p.x, origin.y - cell * 0.3)
				var b := Vector2(origin.x + grid_size.x + cell * 0.3, p.y) if f.kind == "line_h" else Vector2(p.x, origin.y + grid_size.y + cell * 0.3)
				_at(f.t, func(): Fx.beam(fx_layer, a, b, col, cell * 0.8); Sfx.play("line", randf_range(0.95, 1.1), -2.0); _shake(cell * 0.06))
				maxt = maxf(maxt, f.t + 0.3)
			"bomb":
				var p := cell_pos(f.i)
				var col := _fx_color(f.get("color", -1))
				var rr: float = cell * (float(f.r) + 0.8)
				_at(f.t, func():
					Fx.shockwave(fx_layer, p, col, rr, 0.55)
					Fx.glow(fx_layer, p, col, rr * 2.0, 0.4)
					Sfx.play("bomb", randf_range(0.9, 1.05), 0.0)
					_shake(cell * (0.22 if f.big else 0.14)))
				maxt = maxf(maxt, f.t + 0.35)
			"prism":
				var p := cell_pos(f.i)
				var col := _fx_color(f.color)
				_at(f.t, func(): Sfx.play("prism"); Fx.glow(fx_layer, p, Color.WHITE, cell * 3.0, 0.6))
				var k := 0
				for c in f.targets:
					var tp := cell_pos(c)
					var tt: float = f.t + 0.1 + k * 0.045
					_at(tt, func(): Fx.lightning(fx_layer, p, tp, col, cell * 0.08); if k % 3 == 0: Sfx.play("zap", randf_range(0.9, 1.4), -8.0))
					if f.get("convert", 0) != 0:
						var g := gem_at(c)
						if g:
							var conv: int = f.convert
							_at(tt + 0.05, func(): if is_instance_valid(g): g.become(-1, conv))
					k += 1
				maxt = maxf(maxt, f.t + 0.1 + k * 0.045 + 0.2)
			"nova":
				var p := cell_pos(f.i)
				_at(0.0, func():
					Fx.shockwave(fx_layer, p, Color.WHITE, grid_size.length(), 0.9)
					Sfx.play("prism", 0.8)
					Sfx.play("bomb", 0.7)
					_shake(cell * 0.3))
	# gems leaving the board
	var gone: Array = []
	for cl in step.cleared:
		var g: Gem = nodes.get(cl.id)
		nodes.erase(cl.id)
		if g == null:
			continue
		var t: float = cl.t
		var pos := cell_pos(cl.i)
		var gc := g.color()
		if cl.by == "match" and merge_target.has(cl.i) and merge_target[cl.i] != cl.i:
			g.merge_into(cell_pos(merge_target[cl.i]), t / speed)
		else:
			g.pop(t / speed)
			var big: bool = cl.sp != 0
			_at(t + 0.08, func(): Fx.shatter(fx_layer, pos, gc, cell, big))
		maxt = maxf(maxt, t)
		if cl.color >= 0:
			gone.append({"color": cl.color, "pos": to_global(pos), "t": t})
	# new specials
	for mk in step.made:
		var g: Gem = nodes.get(mk.old_id)
		if g:
			nodes.erase(mk.old_id)
		else:
			g = _make_gem(mk.i, mk.id, maxi(mk.color, 0), Match3.SP_NONE, cell_pos(mk.i))
		nodes[mk.id] = g
		g.cell = mk.i
		var kind: int = mk.color
		var spk: int = mk.sp
		_at(0.14, func(): g.become(kind, spk); Sfx.play("special"); Fx.glow(fx_layer, g.position, g.color(), cell * 2.5, 0.5))
		special_made.emit(spk)
		maxt = maxf(maxt, 0.3)
	# obstacles
	for e in step.ice:
		var c: int = e.i
		var left: int = e.left
		_at(e.t + 0.05, func():
			shown_ice[c] = left
			ice_layer.queue_redraw()
			Fx.shatter(fx_layer, cell_pos(c), Color(0.75, 0.95, 1.0), cell, false)
			Sfx.play("crack", randf_range(0.9, 1.2), -4.0)
			obstacles_changed.emit())
	for e in step.stones:
		var c: int = e.i
		var left: int = e.left
		_at(e.t + 0.05, func():
			shown_stone[c] = left
			var sn: StoneNode = stone_nodes.get(c)
			if sn:
				sn.hit()
				if left <= 0:
					stone_nodes.erase(c)
			Fx.shatter(fx_layer, cell_pos(c), Color(0.6, 0.55, 0.6), cell, left <= 0)
			Sfx.play("stone", randf_range(0.85, 1.1), -1.0)
			obstacles_changed.emit())
	# sound + score
	var chime := clampi(cascade - 1 + (1 if biggest >= 4 else 0), 0, 9)
	if match_n > 0:
		Sfx.play("chime%d" % chime, 1.0, -2.0)
		Sfx.play("match", randf_range(0.95, 1.1), -8.0)
	var center := match_center / maxf(1, match_n) if match_n > 0 else grid_size * 0.5
	var pts: int = step.score
	_at(0.1, func(): Fx.float_text(fx_layer, center, "+%d" % pts, Color(1, 0.95, 0.7) if cascade < 3 else Color(1, 0.75, 0.3), int(cell * (0.42 + minf(cascade, 5) * 0.06))))
	scored.emit(pts, to_global(center), cascade)
	if not gone.is_empty():
		gems_cleared.emit(gone)
	if cascade >= 2:
		combo.emit(cascade, to_global(center))
	await _wait(maxt + 0.26)


func _fx_color(c: int) -> Color:
	if c is int and c >= 0 and c < Game.GEMS.size():
		return Game.GEMS[c].color
	return Color(1, 1, 1)


func _animate_gravity(g: Dictionary) -> void:
	var longest := 0.0
	for mv in g.moves:
		var gem: Gem = nodes.get(mv.id)
		if gem == null:
			continue
		gem.cell = mv.to
		var target := cell_pos(mv.to)
		var dist := (target.y - gem.position.y) / cell
		var dur := 0.09 + sqrt(maxf(dist, 0.1)) * 0.085
		var t := gem.create_tween()
		t.tween_property(gem, "position", target, dur / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(gem.land.bind(clampf(dist * 0.3, 0.3, 1.0)))
		longest = maxf(longest, dur)
	for s in g.spawns:
		var target := cell_pos(s.i)
		var x: int = s.i % m.w
		var start := Vector2(target.x, cell_pos(x).y - cell * 0.5 - (float(s.drop) - float(s.i / m.w)) * cell + (target.y - cell_pos(x).y) * 0.0)
		# start above the top so the column falls as one block
		start.y = target.y - float(s.drop) * cell - cell * 0.4
		var gem := _make_gem(s.i, s.id, s.color, Match3.SP_NONE, start)
		var dist := (target.y - start.y) / cell
		var dur := 0.09 + sqrt(dist) * 0.085
		var delay := x * 0.012
		var t := gem.create_tween()
		t.tween_interval(delay / speed)
		t.tween_property(gem, "position", target, dur / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(gem.land.bind(0.7))
		longest = maxf(longest, dur + delay)
	if longest > 0.0:
		_at(longest * 0.85, func(): Sfx.play("land", randf_range(0.9, 1.15), -12.0))
	await _wait(longest + 0.06)


func _shake(amount: float) -> void:
	var base := position
	if has_meta("base_pos"):
		base = get_meta("base_pos")
	else:
		set_meta("base_pos", base)
	var t := create_tween()
	for k in 6:
		t.tween_property(self, "position", base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * (1.0 - k / 6.0), 0.035)
	t.tween_property(self, "position", base, 0.04)
	t.tween_callback(func(): remove_meta("base_pos"))


# ================================================================== bonus finale

## Remaining moves become line gems that go off one after another, then every special left fires.
func bonus_round(moves_left: int, on_spark: Callable) -> void:
	busy = true
	var n := mini(moves_left, 15)
	for k in n:
		var c := m.random_plain_cell()
		if c < 0:
			break
		m.sp[c] = Match3.SP_LINE_H if randf() < 0.5 else Match3.SP_LINE_V
		var g := gem_at(c)
		if g:
			on_spark.call(to_global(cell_pos(c)))
			g.become(m.col[c], m.sp[c])
			Sfx.play("special", 1.0 + k * 0.04, -4.0)
		await _wait(0.12)
	await _wait(0.3)
	for k in 40:
		var c := m.first_special()
		if c < 0:
			break
		await resolve([], {"fire": c})
		busy = true
	busy = false
