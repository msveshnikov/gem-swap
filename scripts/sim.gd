class_name Sim
extends RefCounted
## Level goals bookkeeping (shared by the game and the autoplayer) + a greedy autoplayer used to
## calibrate move counts and star scores (`-- --calibrate`).


class Goals extends RefCounted:
	var list: Array = []      # [{type, n, color, left}]
	var score := 0

	func setup(lv: Dictionary, m: Match3) -> void:
		list = []
		score = 0
		for g in lv.get("goals", []):
			var d: Dictionary = g.duplicate()
			match d.type:
				"score":
					d.left = int(d.n)
				"collect":
					d.left = int(d.n)
				"ice":
					d.n = m.count_ice()
					d.left = d.n
				"stone":
					d.n = m.count_stone()
					d.left = d.n
			list.append(d)

	func on_step(step: Dictionary, m: Match3) -> void:
		score += int(step.get("score", 0))
		var byc: Dictionary = step.get("gems_by_color", {})
		for g in list:
			match g.type:
				"collect":
					g.left = maxi(0, int(g.left) - int(byc.get(int(g.color), 0)))
				"score":
					g.left = maxi(0, int(g.n) - score)
				"ice":
					g.left = m.count_ice()
				"stone":
					g.left = m.count_stone()

	func done() -> bool:
		for g in list:
			if int(g.left) > 0:
				return false
		return true

	func has_type(t: String) -> bool:
		for g in list:
			if g.type == t:
				return true
		return false


static func stars_for(lv: Dictionary, score: int) -> int:
	var st: Array = lv.get("stars", [])
	if st.size() < 3:
		return 1
	if score >= int(st[2]):
		return 3
	if score >= int(st[1]):
		return 2
	return 1


## Plays one level with simple greedy choices. skill = chance of taking the best-looking move.
static func play(lv: Dictionary, seed_: int, skill := 0.7, moves_override := -1) -> Dictionary:
	var m := Match3.new()
	m.setup(lv, seed_)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 31 + 7
	var goals := Goals.new()
	goals.setup(lv, m)
	var moves: int = int(lv.moves) if moves_override < 0 else moves_override
	var used := 0
	while used < moves and not goals.done():
		var mv := m.find_moves()
		if mv.is_empty():
			m.shuffle_board()
			continue
		mv.sort_custom(func(a, b): return a[2] > b[2])
		var pick: Array = mv[0]
		if rng.randf() > skill:
			pick = mv[rng.randi_range(0, mini(mv.size() - 1, 6))]
		else:
			pick = _best_move(m, goals, mv)
		_resolve(m, goals, [pick[0], pick[1]], m.do_swap(pick[0], pick[1]))
		used += 1
	var win := goals.done()
	if win:
		var left := moves - used
		for k in mini(left, 15):
			var c := m.random_plain_cell()
			if c < 0:
				break
			m.sp[c] = Match3.SP_LINE_H if rng.randf() < 0.5 else Match3.SP_LINE_V
		for k in 40:
			var c := m.first_special()
			if c < 0:
				break
			_resolve(m, goals, [], {"fire": c})
	return {"win": win, "score": goals.score, "used": used}


## One-step lookahead: what does each swap actually clear, and how much of that helps the goals?
static func _best_move(m: Match3, goals: Goals, mv: Array) -> Array:
	var want := {}
	var need_ice := false
	var need_stone := false
	for g in goals.list:
		if g.type == "collect" and int(g.left) > 0:
			want[int(g.color)] = true
		elif g.type == "ice" and int(g.left) > 0:
			need_ice = true
		elif g.type == "stone" and int(g.left) > 0:
			need_stone = true
	var best: Array = mv[0]
	var best_v := -1.0
	for k in mini(mv.size(), 24):
		var cand: Array = mv[k]
		var c := m.clone()
		var st := c.resolve_step([cand[0], cand[1]], c.do_swap(cand[0], cand[1]), 1)
		if st.is_empty():
			continue
		var v := float(st.score) * 0.004
		v += st.made.size() * 3.0
		if need_ice:
			v += st.ice.size() * 4.0
		if need_stone:
			v += st.stones.size() * 5.0
		for col in st.gems_by_color:
			if want.has(int(col)):
				v += st.gems_by_color[col] * 1.5
		# lower moves leave the top for cascades
		v += float(int(cand[0]) / m.w) * 0.05
		if v > best_v:
			best_v = v
			best = cand
	return best


static func _resolve(m: Match3, goals: Goals, focus: Array, combo: Dictionary) -> void:
	var cascade := 1
	for guard in 60:
		var step := m.resolve_step(focus, combo, cascade)
		combo = {}
		focus = []
		if step.is_empty():
			break
		goals.on_step(step, m)
		m.gravity()
		cascade += 1
