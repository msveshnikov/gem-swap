class_name Match3
extends RefCounted
## Pure match-3 rules: grid, swaps, matches, special gems, ice, stones, gravity, moves, shuffles.
## No nodes here; every step returns plain dictionaries the board animates.

enum { SP_NONE, SP_LINE_H, SP_LINE_V, SP_BOMB, SP_PRISM }
const PRISM_COLOR := -2
const EMPTY := -1

var w := 8
var h := 8
var ncolors := 6
var colors: Array = [0, 1, 2, 3, 4, 5]   # gem kinds used on this board
var mask := PackedInt32Array()     # 1 = playable cell
var col := PackedInt32Array()      # gem colour (kind index into colors) / EMPTY / PRISM_COLOR
var sp := PackedInt32Array()       # special
var ids := PackedInt32Array()      # visual identity of the gem in each cell
var ice := PackedInt32Array()      # ice layers under the gem
var stone := PackedInt32Array()    # stone hit points (cell holds no gem while > 0)
var rng := RandomNumberGenerator.new()
var _next_id := 1


func setup(lv: Dictionary, seed_ := -1) -> void:
	w = int(lv.get("w", 8))
	h = int(lv.get("h", 8))
	colors = lv.get("colors", [0, 1, 2, 3, 4, 5]).duplicate()
	ncolors = colors.size()
	if seed_ >= 0:
		rng.seed = seed_
	else:
		rng.randomize()
	var n := w * h
	mask.resize(n); col.resize(n); sp.resize(n); ids.resize(n); ice.resize(n); stone.resize(n)
	mask.fill(1); col.fill(EMPTY); sp.fill(SP_NONE); ids.fill(0); ice.fill(0); stone.fill(0)
	# layout rows: '.' cell, ' ' or '#' hole, 'i' ice, 'I' double ice, 's' stone, 'S' double stone
	var rows: Array = lv.get("map", [])
	for y in mini(rows.size(), h):
		var r: String = rows[y]
		for x in mini(r.length(), w):
			var c := r[x]
			var i := y * w + x
			match c:
				" ", "#":
					mask[i] = 0
				"i":
					ice[i] = 1
				"I":
					ice[i] = 2
				"s":
					stone[i] = 1
				"S":
					stone[i] = 2
	fill_initial()


func clone() -> Match3:
	var c := Match3.new()
	c.w = w; c.h = h; c.ncolors = ncolors; c.colors = colors
	c.mask = mask.duplicate(); c.col = col.duplicate(); c.sp = sp.duplicate(); c.ids = ids.duplicate()
	c.ice = ice.duplicate(); c.stone = stone.duplicate()
	c.rng.seed = rng.randi()
	c._next_id = _next_id
	return c


func idx(x: int, y: int) -> int:
	return y * w + x


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


## Cell holds a gem that can move / match.
func has_gem(i: int) -> bool:
	return mask[i] == 1 and stone[i] == 0 and col[i] != EMPTY


func open_cell(i: int) -> bool:
	return mask[i] == 1 and stone[i] == 0


func new_id() -> int:
	_next_id += 1
	return _next_id


## Colours stored in the grid are gem kinds (Game.GEMS indices) taken from this level's set.
func random_color() -> int:
	return int(colors[rng.randi_range(0, ncolors - 1)])


func fill_initial() -> void:
	for attempt in 200:
		for y in h:
			for x in w:
				var i := idx(x, y)
				sp[i] = SP_NONE
				if not open_cell(i):
					col[i] = EMPTY
					continue
				var c := random_color()
				for k in 12:
					if not _would_match(x, y, c):
						break
					c = random_color()
				col[i] = c
				ids[i] = new_id()
		if find_moves().size() >= 3:
			return


func _would_match(x: int, y: int, c: int) -> bool:
	if x >= 2 and _c(x - 1, y) == c and _c(x - 2, y) == c:
		return true
	if y >= 2 and _c(x, y - 1) == c and _c(x, y - 2) == c:
		return true
	return false


func _c(x: int, y: int) -> int:
	if not inside(x, y):
		return EMPTY
	var i := idx(x, y)
	return col[i] if has_gem(i) else EMPTY


# ================================================================== matches

## Runs of >= 3 same colour. Returns [{cells: [i...], dir: "h"/"v"}].
func find_runs() -> Array:
	var runs: Array = []
	for y in h:
		var x := 0
		while x < w:
			var c := _c(x, y)
			var e := x + 1
			while e < w and c >= 0 and _c(e, y) == c:
				e += 1
			if c >= 0 and e - x >= 3:
				var cells: Array = []
				for k in range(x, e):
					cells.append(idx(k, y))
				runs.append({"cells": cells, "dir": "h", "color": c})
			x = e
	for x in w:
		var y := 0
		while y < h:
			var c := _c(x, y)
			var e := y + 1
			while e < h and c >= 0 and _c(x, e) == c:
				e += 1
			if c >= 0 and e - y >= 3:
				var cells: Array = []
				for k in range(y, e):
					cells.append(idx(x, k))
				runs.append({"cells": cells, "dir": "v", "color": c})
			y = e
	return runs


## Runs that share cells are merged into groups (L, T and + shapes).
func find_groups() -> Array:
	var runs := find_runs()
	var groups: Array = []
	var used := {}
	for r in runs.size():
		if used.has(r):
			continue
		var g := {"cells": {}, "runs": [], "color": runs[r].color}
		var stack := [r]
		used[r] = true
		while not stack.is_empty():
			var k: int = stack.pop_back()
			g.runs.append(runs[k])
			for c in runs[k].cells:
				g.cells[c] = true
			for j in runs.size():
				if used.has(j) or runs[j].color != runs[k].color:
					continue
				for c in runs[j].cells:
					if c in runs[k].cells:
						used[j] = true
						stack.append(j)
						break
		groups.append(g)
	return groups


## What special a group makes, and where. focus = cells the player just swapped (preferred spot).
func special_for(g: Dictionary, focus: Array) -> Dictionary:
	var longest := 0
	var has_h := false
	var has_v := false
	var long_run: Dictionary
	for r in g.runs:
		if r.cells.size() > longest:
			longest = r.cells.size()
			long_run = r
		if r.dir == "h":
			has_h = true
		else:
			has_v = true
	var kind := SP_NONE
	var at := -1
	if longest >= 5:
		kind = SP_PRISM
	elif has_h and has_v:
		kind = SP_BOMB
	elif longest == 4:
		kind = SP_LINE_H if long_run.dir == "h" else SP_LINE_V
	if kind == SP_NONE:
		return {}
	for f in focus:
		if g.cells.has(f):
			at = f
	if at < 0:
		if kind == SP_BOMB:
			# the crossing cell
			var cnt := {}
			for r in g.runs:
				for c in r.cells:
					cnt[c] = cnt.get(c, 0) + 1
			for c in cnt:
				if cnt[c] > 1:
					at = c
		if at < 0:
			at = long_run.cells[long_run.cells.size() / 2]
	return {"kind": kind, "at": at, "color": g.color}


# ================================================================== swaps

func adjacent(a: int, b: int) -> bool:
	var ax := a % w
	var ay := a / w
	var bx := b % w
	var by := b / w
	return absi(ax - bx) + absi(ay - by) == 1


func _swap_cells(a: int, b: int) -> void:
	var t := col[a]; col[a] = col[b]; col[b] = t
	t = sp[a]; sp[a] = sp[b]; sp[b] = t
	t = ids[a]; ids[a] = ids[b]; ids[b] = t


## True when swapping a and b does something (a match, or a special combo / prism).
func swap_is_valid(a: int, b: int) -> bool:
	if not (has_gem(a) and has_gem(b) and adjacent(a, b)):
		return false
	if sp[a] == SP_PRISM or sp[b] == SP_PRISM:
		return true
	if sp[a] != SP_NONE and sp[b] != SP_NONE:
		return true
	_swap_cells(a, b)
	var ok := _match_at(a) or _match_at(b)
	_swap_cells(a, b)
	return ok


func _match_at(i: int) -> bool:
	var x := i % w
	var y := i / w
	var c := _c(x, y)
	if c < 0:
		return false
	var n := 1
	var k := x - 1
	while k >= 0 and _c(k, y) == c:
		n += 1; k -= 1
	k = x + 1
	while k < w and _c(k, y) == c:
		n += 1; k += 1
	if n >= 3:
		return true
	n = 1
	k = y - 1
	while k >= 0 and _c(x, k) == c:
		n += 1; k -= 1
	k = y + 1
	while k < h and _c(x, k) == c:
		n += 1; k += 1
	return n >= 3


## All valid swaps: [[a, b, score]] (score = rough value, used by hints and the autoplayer).
func find_moves() -> Array:
	var out: Array = []
	for y in h:
		for x in w:
			var a := idx(x, y)
			if not has_gem(a):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var bx: int = x + d.x
				var by: int = y + d.y
				if not inside(bx, by):
					continue
				var b := idx(bx, by)
				if swap_is_valid(a, b):
					out.append([a, b, _move_value(a, b)])
	return out


func _move_value(a: int, b: int) -> int:
	var v := 0
	if sp[a] != SP_NONE:
		v += 6 + sp[a] * 2
	if sp[b] != SP_NONE:
		v += 6 + sp[b] * 2
	_swap_cells(a, b)
	for i: int in [a, b]:
		var x := i % w
		var y := i / w
		var c := _c(x, y)
		if c < 0:
			continue
		var hn := 1
		var k := x - 1
		while k >= 0 and _c(k, y) == c:
			hn += 1; k -= 1
		k = x + 1
		while k < w and _c(k, y) == c:
			hn += 1; k += 1
		var vn := 1
		k = y - 1
		while k >= 0 and _c(x, k) == c:
			vn += 1; k -= 1
		k = y + 1
		while k < h and _c(x, k) == c:
			vn += 1; k += 1
		if hn >= 3:
			v += hn + (4 if hn >= 4 else 0) + (8 if hn >= 5 else 0)
		if vn >= 3:
			v += vn + (4 if vn >= 4 else 0) + (8 if vn >= 5 else 0)
		if hn >= 3 and vn >= 3:
			v += 6
		if ice[i] > 0:
			v += 2
	_swap_cells(a, b)
	return v


## Performs the swap in the model. Returns the "combo" activation for special + special or prism swaps,
## or {} when the swap should be resolved by ordinary matching.
func do_swap(a: int, b: int) -> Dictionary:
	_swap_cells(a, b)
	var sa := sp[a]
	var sb := sp[b]
	if sa == SP_PRISM or sb == SP_PRISM or (sa != SP_NONE and sb != SP_NONE):
		return {"a": a, "b": b}
	return {}


# ================================================================== resolving

## One resolution step. `focus` = swapped cells (for special placement), `combo` = forced activation from a
## special swap. Returns {} when nothing happens, else:
## {cleared: [{i, id, color, sp, t, by}], made: [{i, id, color, sp}], fx: [...], ice: [{i, left, t}],
##  stones: [{i, left, t}], score: int, gems_by_color: {color: n}}
func resolve_step(focus: Array, combo := {}, cascade := 1) -> Dictionary:
	var clear_t := {}       # cell -> time
	var by := {}            # cell -> reason
	var fx: Array = []
	var made: Array = []
	var activate: Array = []   # [cell, t, override]
	var match_cells := {}
	var score := 0
	var protect := {}       # cells that become a new special (not cleared)

	if combo.has("fire"):
		var fc: int = combo.fire
		clear_t[fc] = 0.0
		by[fc] = "blast"
		activate.append([fc, 0.0, sp[fc]])
	elif not combo.is_empty():
		_combo_activation(combo.a, combo.b, clear_t, by, fx, activate)
	else:
		var groups := find_groups()
		if groups.is_empty():
			return {}
		for g in groups:
			var s := special_for(g, focus)
			for c in g.cells:
				match_cells[c] = true
				if not clear_t.has(c):
					clear_t[c] = 0.0
					by[c] = "match"
			var n: int = g.cells.size()
			score += (n * 20 + maxi(0, n - 3) * 40) * cascade
			if not s.is_empty():
				protect[s.at] = s
			fx.append({"kind": "match", "cells": g.cells.keys(), "color": g.color, "t": 0.0, "n": n})
	# specials inside the cleared area go off (chain reaction)
	var queue: Array = []
	var forced := {}
	for a in activate:
		forced[a[0]] = true
	for c in clear_t.keys():
		if sp[c] != SP_NONE and not _in_combo(c, combo) and not forced.has(c):
			queue.append([c, clear_t[c]])
	queue.append_array(activate)
	var fired := {}
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var c: int = item[0]
		var t0: float = item[1]
		var key := str(c) if item.size() < 3 else "%d:%d" % [c, item[2]]
		if fired.has(key):
			continue
		fired[key] = true
		fired[str(c)] = true
		var kind := sp[c] if item.size() < 3 else int(item[2])
		var hits := _area(c, kind, t0, fx)
		score += 80 * cascade
		for hc in hits:
			var ht: float = hits[hc]
			if not clear_t.has(hc) or clear_t[hc] > ht:
				clear_t[hc] = ht
				by[hc] = "blast"
			if has_gem(hc) and sp[hc] != SP_NONE and not fired.has(str(hc)) and hc != c:
				queue.append([hc, ht + 0.05])
	# ice, stones
	var ice_ev: Array = []
	var stone_ev: Array = []
	var stone_hit := {}
	for c in clear_t:
		if mask[c] == 0:
			continue
		if stone[c] > 0:
			if not stone_hit.has(c):
				stone_hit[c] = clear_t[c]
			continue
		if ice[c] > 0 and col[c] != EMPTY:
			ice[c] -= 1
			ice_ev.append({"i": c, "left": ice[c], "t": clear_t[c]})
			score += 40
	for c in match_cells:
		for d: int in [-1, 1, -w, w]:
			var n2: int = c + d
			if n2 < 0 or n2 >= w * h:
				continue
			if absi(n2 % w - c % w) + absi(n2 / w - c / w) != 1:
				continue
			if stone[n2] > 0 and not stone_hit.has(n2):
				stone_hit[n2] = clear_t[c]
	for c in stone_hit:
		stone[c] -= 1
		stone_ev.append({"i": c, "left": stone[c], "t": stone_hit[c]})
		score += 60
	# clear gems
	var cleared: Array = []
	var by_color := {}
	for c in clear_t:
		if not has_gem(c):
			continue
		if protect.has(c):
			continue
		cleared.append({"i": c, "id": ids[c], "color": col[c], "sp": sp[c], "t": clear_t[c], "by": by[c]})
		if col[c] >= 0:
			by_color[col[c]] = by_color.get(col[c], 0) + 1
		score += 10 * cascade
		col[c] = EMPTY
		sp[c] = SP_NONE
		ids[c] = 0
	# new specials: the gem in that cell turns into the special (gets a new id)
	for at in protect:
		var s: Dictionary = protect[at]
		var old_id := ids[at]
		if col[at] != EMPTY and col[at] >= 0:
			by_color[col[at]] = by_color.get(col[at], 0) + 1
		col[at] = PRISM_COLOR if s.kind == SP_PRISM else int(s.color)
		sp[at] = s.kind
		ids[at] = new_id()
		made.append({"i": at, "id": ids[at], "old_id": old_id, "color": col[at], "sp": s.kind})
		score += 150 if s.kind == SP_PRISM else 60
	if cleared.is_empty() and made.is_empty() and ice_ev.is_empty() and stone_ev.is_empty():
		return {}
	return {"cleared": cleared, "made": made, "fx": fx, "ice": ice_ev, "stones": stone_ev,
		"score": score, "gems_by_color": by_color}


func _in_combo(c: int, combo: Dictionary) -> bool:
	return combo.has("a") and (c == combo.a or c == combo.b)


## A special swap (special + special, or prism + anything).
func _combo_activation(a: int, b: int, clear_t: Dictionary, by: Dictionary, fx: Array, activate: Array) -> void:
	var sa := sp[a]
	var sb := sp[b]
	# prism first
	if sa == SP_PRISM and sb == SP_PRISM:
		fx.append({"kind": "nova", "i": b, "t": 0.0})
		for c in w * h:
			if has_gem(c):
				clear_t[c] = 0.15 + _dist(c, b) * 0.04
				by[c] = "blast"
		return
	if sa == SP_PRISM or sb == SP_PRISM:
		var p := a if sa == SP_PRISM else b
		var o := b if p == a else a
		var target := col[o]
		var osp := sp[o]
		var targets: Array = []
		for c in w * h:
			if has_gem(c) and col[c] == target and c != p:
				targets.append(c)
		targets.shuffle()
		fx.append({"kind": "prism", "i": p, "targets": targets, "color": target, "t": 0.0, "convert": osp})
		clear_t[p] = 0.0
		by[p] = "blast"
		for k in targets.size():
			var c: int = targets[k]
			var t := 0.12 + k * 0.045
			if osp != SP_NONE:
				# every gem of that colour becomes the same special, then they all go off
				var kind := osp
				if osp == SP_LINE_H or osp == SP_LINE_V:
					kind = SP_LINE_H if rng.randf() < 0.5 else SP_LINE_V
				sp[c] = kind
				activate.append([c, t + 0.35, kind])
				clear_t[c] = t + 0.35
			else:
				clear_t[c] = t
			by[c] = "blast"
		return
	var lines := [SP_LINE_H, SP_LINE_V]
	clear_t[a] = 0.0
	clear_t[b] = 0.0
	by[a] = "blast"
	by[b] = "blast"
	if sa in lines and sb in lines:
		activate.append([b, 0.0, SP_LINE_H])
		activate.append([b, 0.0, SP_LINE_V])
		sp[a] = SP_NONE
		sp[b] = SP_NONE
	elif (sa in lines and sb == SP_BOMB) or (sb in lines and sa == SP_BOMB):
		sp[a] = SP_NONE
		sp[b] = SP_NONE
		fx.append({"kind": "bomb", "i": b, "t": 0.0, "r": 1, "big": false})
		var bx := b % w
		var by_ := b / w
		for d: int in [-1, 0, 1]:
			if inside(bx, by_ + d):
				activate.append([idx(bx, by_ + d), 0.08, SP_LINE_H])
			if inside(bx + d, by_):
				activate.append([idx(bx + d, by_), 0.08, SP_LINE_V])
	elif sa == SP_BOMB and sb == SP_BOMB:
		sp[a] = SP_NONE
		sp[b] = SP_NONE
		activate.append([b, 0.0, 10])   # 10 = mega bomb
	else:
		activate.append([a, 0.0, sa])
		activate.append([b, 0.05, sb])
		sp[a] = SP_NONE
		sp[b] = SP_NONE


func _dist(a: int, b: int) -> float:
	return Vector2(a % w, a / w).distance_to(Vector2(b % w, b / w))


## Cells hit by a special going off at c: {cell: time}.
func _area(c: int, kind: int, t0: float, fx: Array) -> Dictionary:
	var hits := {}
	var cx := c % w
	var cy := c / w
	match kind:
		SP_LINE_H:
			fx.append({"kind": "line_h", "i": c, "t": t0, "color": col[c]})
			for x in w:
				hits[idx(x, cy)] = t0 + absi(x - cx) * 0.035
		SP_LINE_V:
			fx.append({"kind": "line_v", "i": c, "t": t0, "color": col[c]})
			for y in h:
				hits[idx(cx, y)] = t0 + absi(y - cy) * 0.035
		SP_BOMB, 10:
			var r := 2 if kind == SP_BOMB else 4
			fx.append({"kind": "bomb", "i": c, "t": t0, "r": r, "big": kind == 10, "color": col[c]})
			for y in range(cy - r, cy + r + 1):
				for x in range(cx - r, cx + r + 1):
					if inside(x, y) and absi(x - cx) + absi(y - cy) <= r + (1 if kind == 10 else 0):
						hits[idx(x, y)] = t0 + 0.06 + (absi(x - cx) + absi(y - cy)) * 0.03
		SP_PRISM:
			# caught in a blast: takes out the most common colour
			var cnt := {}
			for k in w * h:
				if has_gem(k) and col[k] >= 0:
					cnt[col[k]] = cnt.get(col[k], 0) + 1
			var best := -1
			var bn := 0
			for k in cnt:
				if cnt[k] > bn:
					bn = cnt[k]
					best = k
			var targets: Array = []
			for k in w * h:
				if has_gem(k) and col[k] == best:
					targets.append(k)
			fx.append({"kind": "prism", "i": c, "targets": targets, "color": best, "t": t0, "convert": SP_NONE})
			for n in targets.size():
				hits[targets[n]] = t0 + 0.12 + n * 0.04
		_:
			pass
	hits[c] = t0
	return hits


# ================================================================== gravity

## Gems fall down their column (holes and stones are skipped, gems slide past them), new gems drop in.
## Returns {moves: [{id, from, to}], spawns: [{id, i, color, drop}]} (drop = how many cells above the top).
func gravity() -> Dictionary:
	var moves: Array = []
	var spawns: Array = []
	for x in w:
		var cells: Array = []
		for y in h:
			var i := idx(x, y)
			if open_cell(i):
				cells.append(i)
		var write := cells.size() - 1
		for r in range(cells.size() - 1, -1, -1):
			var i: int = cells[r]
			if col[i] != EMPTY:
				var dst: int = cells[write]
				if dst != i:
					col[dst] = col[i]; sp[dst] = sp[i]; ids[dst] = ids[i]
					col[i] = EMPTY; sp[i] = SP_NONE; ids[i] = 0
					moves.append({"id": ids[dst], "from": i, "to": dst})
				write -= 1
		var n := write + 1
		for r in range(write, -1, -1):
			var i: int = cells[r]
			col[i] = _spawn_color(i)
			sp[i] = SP_NONE
			ids[i] = new_id()
			spawns.append({"id": ids[i], "i": i, "color": col[i], "drop": n})
	return {"moves": moves, "spawns": spawns}


## New gems are random, with a light nudge away from instant triple matches so cascades feel earned.
func _spawn_color(i: int) -> int:
	var c := random_color()
	if rng.randf() < 0.55:
		var x := i % w
		var y := i / w
		for k in 4:
			if not _would_match_any(x, y, c):
				break
			c = random_color()
	return c


func _would_match_any(x: int, y: int, c: int) -> bool:
	var below := 0
	var k := y + 1
	while k < h and _c(x, k) == c:
		below += 1; k += 1
	return below >= 2


# ================================================================== shuffle / helpers

func shuffle_board() -> Array:
	var cells: Array = []
	for i in w * h:
		if has_gem(i) and sp[i] == SP_NONE:
			cells.append(i)
	var before := {}
	for i in cells:
		before[ids[i]] = i
	for attempt in 300:
		var pool: Array = []
		for i in cells:
			pool.append([col[i], ids[i]])
		pool.shuffle()
		for k in cells.size():
			col[cells[k]] = pool[k][0]
			ids[cells[k]] = pool[k][1]
		if find_groups().is_empty() and not find_moves().is_empty():
			break
		if attempt > 200:
			# recolour a few gems
			for i in cells:
				if rng.randf() < 0.3:
					col[i] = random_color()
	var moves: Array = []
	for i in cells:
		if before[ids[i]] != i:
			moves.append({"id": ids[i], "from": before[ids[i]], "to": i, "color": col[i]})
	return moves


func count_ice() -> int:
	var n := 0
	for i in w * h:
		n += ice[i]
	return n


func count_stone() -> int:
	var n := 0
	for i in w * h:
		n += stone[i]
	return n


## Put a special on a random plain gem (bonus round); returns the cell or -1.
func random_plain_cell() -> int:
	var cells: Array = []
	for i in w * h:
		if has_gem(i) and sp[i] == SP_NONE and col[i] >= 0:
			cells.append(i)
	if cells.is_empty():
		return -1
	return cells[rng.randi() % cells.size()]


func first_special() -> int:
	for i in w * h:
		if has_gem(i) and sp[i] != SP_NONE:
			return i
	return -1
