extends SceneTree

const TakState = preload("res://scripts/tak_state.gd")
const MctsBot = preload("res://scripts/mcts_bot.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	_test_openings()
	_test_opening_move_guard()
	_test_reserves()
	_test_stone_moves()
	_test_wall_rules()
	_test_topple()
	_test_topple_alternation()
	_test_topple_tower()
	_test_roads()
	_test_full_board_count()
	_test_clone()
	_test_fast_legal_check()
	_test_random_move_sampler()
	await _test_ui_flow()
	_test_spectate_bots()
	_test_rule_top_slide()
	_test_rule_wall_move()
	_test_stalemate_guard()
	_test_brains()
	await _test_hint_and_courtly()
	_test_mcts()
	print("RESULT=%d_passed,%d_failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("PASS %s" % name)
	else:
		failed += 1
		print("FAIL %s: %s" % [name, detail if not detail.is_empty() else "assertion failed"])

func _normal_state() -> TakState:
	var state: TakState = TakState.new()
	state.opening_done = PackedByteArray([1, 1])
	state.current = 0
	return state

func _put(state: TakState, cell: int, owner: int, piece: int) -> void:
	var height: int = int(state.heights[cell])
	state.cells[cell * TakState.MAX_STACK + height] = owner * 3 + piece
	state.heights[cell] = height + 1
	if height == 0:
		state._occupied_count += 1
	state._mark_road_masks_dirty()

func _move(from: int, direction: int) -> Dictionary:
	return {"kind": "move", "from": from, "carry": 1, "dir": direction, "drops": [1]}

func _invariants_hold(state: TakState) -> String:
	for cell: int in range(25):
		var height: int = int(state.heights[cell])
		if height == 0:
			continue
		for layer: int in range(height):
			var owner: int = state.piece_owner(cell, layer)
			var type: int = state.piece_type(cell, layer)
			if layer < height - 1:
				if type == TakState.WALL or type == TakState.CAPSTONE:
					return "buried blocker at cell %d layer %d" % [cell, layer]
				if owner == state.piece_owner(cell, layer + 1):
					return "same-color adjacency at cell %d layer %d" % [cell, layer]
			elif type == TakState.WALL and height > 1:
				return "wall above others at cell %d" % cell
	return ""

func _test_openings() -> void:
	var state: TakState = TakState.new()
	var first: Array[Dictionary] = state.legal_moves()
	var only_flats: bool = first.size() == 25
	for move: Dictionary in first:
		only_flats = only_flats and move["kind"] == "place" and move["piece_type"] == TakState.FLAT
	state.apply_move({"kind": "place", "cell": 12, "piece_type": TakState.FLAT})
	var first_piece_ok: bool = state.piece_owner(12) == 1 and state.current == 1
	state.apply_move({"kind": "place", "cell": 0, "piece_type": TakState.FLAT})
	var second_piece_ok: bool = state.piece_owner(0) == 0 and state.opening_done[0] == 1 and state.opening_done[1] == 1
	var normal: bool = false
	for move: Dictionary in state.legal_moves():
		if move["kind"] == "place" and move["piece_type"] == TakState.WALL:
			normal = true
	_check("opening P0 places only P1 flats", only_flats and first_piece_ok, "first move or ownership was wrong")
	_check("opening P1 places only P0 flats", second_piece_ok, "second opening was wrong")
	_check("normal turns allow chosen piece types", normal, "wall placement did not become available")

func _test_opening_move_guard() -> void:
	var state: TakState = TakState.new()
	state.opening_done = PackedByteArray([1, 0])
	state.current = 1
	_put(state, 12, 1, TakState.FLAT)
	_check("opening turn rejects movement", not state.is_legal(_move(12, 0)), "forced opening allowed a move")

func _test_reserves() -> void:
	var state: TakState = _normal_state()
	state.apply_move({"kind": "place", "cell": 0, "piece_type": TakState.FLAT})
	state.current = 0
	state.apply_move({"kind": "place", "cell": 1, "piece_type": TakState.WALL})
	state.current = 0
	state.apply_move({"kind": "place", "cell": 2, "piece_type": TakState.CAPSTONE})
	var counts_ok: bool = state.reserve_flats[0] == 19 and state.reserve_caps[0] == 0
	state.current = 0
	var second_cap: bool = state.is_legal({"kind": "place", "cell": 3, "piece_type": TakState.CAPSTONE})
	_check("place piece types decrement reserves", counts_ok, "unexpected reserve totals")
	_check("capstone reserve limited to one", not second_cap, "second capstone placement was accepted")

func _test_stone_moves() -> void:
	var state: TakState = _normal_state()
	state.current = 0
	_put(state, 12, 0, TakState.FLAT)
	_put(state, 13, 0, TakState.FLAT)
	_put(state, 7, 1, TakState.FLAT)
	_put(state, 17, 1, TakState.CAPSTONE)
	_put(state, 5, 0, TakState.FLAT)
	_put(state, 5, 1, TakState.FLAT)
	_check("single stone moves onto empty ground", state.is_legal(_move(12, 1)), "empty landing rejected")
	_check("no same-color stacking", not state.is_legal(_move(12, 0)), "own-color landing accepted")
	_check("stone may stack onto enemy flat", state.is_legal(_move(12, 3)), "enemy landing rejected")
	_check("nothing lands on enemy capstone", not state.is_legal(_move(12, 2)), "capstone landing accepted")
	_check("buried stone cannot be dug out", not state.is_legal(_move(5, 1)) and not state.is_legal(_move(5, 2)), "buried stone was movable")
	_check("stones move exactly one space", not state.is_legal({"kind": "move", "from": 12, "carry": 1, "dir": 0, "drops": [1, 1]}), "multi-space move accepted")
	var tower: TakState = _normal_state()
	tower.current = 0
	_put(tower, 12, 1, TakState.FLAT)
	_put(tower, 12, 0, TakState.FLAT)
	var move_kinds_from_tower: int = 0
	for m: Dictionary in tower.legal_moves():
		if m.get("kind") == "move" and int(m.get("from", -1)) == 12:
			move_kinds_from_tower += 1
	_check("towers have no move actions", move_kinds_from_tower == 0 and not tower.is_legal(_move(12, 1)), "tower offered a move")

func _test_wall_rules() -> void:
	var state: TakState = _normal_state()
	state.current = 1
	_put(state, 10, 1, TakState.FLAT)
	_put(state, 11, 0, TakState.WALL)
	_put(state, 14, 0, TakState.WALL)
	_check("nothing but a capstone enters a wall cell", not state.is_legal(_move(10, 0)), "flat entered a wall cell")
	var cap: TakState = _normal_state()
	cap.current = 0
	_put(cap, 10, 0, TakState.CAPSTONE)
	_put(cap, 11, 1, TakState.WALL)
	var move: Dictionary = _move(10, 0)
	var legal: bool = cap.is_legal(move)
	cap.apply_move(move)
	var toppled: bool = int(cap.heights[11]) == 2 and cap.piece_type(11, 0) == TakState.FLAT and cap.piece_owner(11, 0) == 1 and cap.piece_type(11, 1) == TakState.CAPSTONE
	_check("lone capstone flattens enemy wall and rests on it", legal and toppled, "capstone wall entry wrong")
	var own: TakState = _normal_state()
	own.current = 0
	_put(own, 10, 0, TakState.CAPSTONE)
	_put(own, 11, 0, TakState.WALL)
	_check("capstone may not flatten its owner's wall", not own.is_legal(_move(10, 0)), "capstone entered own-color wall")
	var own_wall: TakState = _normal_state()
	own_wall.current = 0
	_put(own_wall, 12, 0, TakState.WALL)
	_check("walls never move", not own_wall.is_legal(_move(12, 1)) and not own_wall.is_legal(_move(12, 0)), "wall was movable")

func _test_topple() -> void:
	var t: TakState = _normal_state()
	t.current = 0
	_put(t, 10, 0, TakState.FLAT)
	_put(t, 10, 1, TakState.FLAT)
	_put(t, 10, 0, TakState.CAPSTONE)
	var listed: bool = false
	for m: Dictionary in t.legal_moves():
		if m.get("kind") == "topple" and int(m.get("from", -1)) == 10 and int(m.get("dir", -1)) == 0:
			listed = true
	var legal: bool = t.is_legal({"kind": "topple", "from": 10, "dir": 0})
	t.apply_move({"kind": "topple", "from": 10, "dir": 0})
	var distributed: bool = int(t.heights[10]) == 0 and int(t.heights[11]) == 1 and t.piece_owner(11) == 0 and t.piece_owner(12) == 1 and t.piece_type(13) == TakState.CAPSTONE
	_check("tower topple distributes bottom to top", listed and legal and distributed, "topple distribution wrong")
	var tt: TakState = _normal_state()
	tt.current = 0
	for i: int in range(6):
		_put(tt, 12, i % 2, TakState.FLAT)
	var no_topple: bool = true
	for m: Dictionary in tt.legal_moves():
		if m.get("kind") == "topple" and int(m.get("from", -1)) == 12:
			no_topple = false
	_check("six-tall tower cannot topple off board", no_topple and tt.has_legal_move(), "impossible topple offered or tower locked entirely")

func _test_topple_alternation() -> void:
	var a: TakState = _normal_state()
	a.current = 0
	_put(a, 10, 1, TakState.FLAT)
	_put(a, 10, 0, TakState.FLAT)
	_put(a, 12, 0, TakState.FLAT)
	_check("falling stone may not land on same color", not a.is_legal({"kind": "topple", "from": 10, "dir": 0}), "topple landed same-color")
	var b: TakState = _normal_state()
	b.current = 0
	_put(b, 12, 1, TakState.FLAT)
	_put(b, 12, 0, TakState.FLAT)
	_put(b, 14, 1, TakState.WALL)
	_check("topple ray blocked by wall cell", not b.is_legal({"kind": "topple", "from": 12, "dir": 0}) and b.is_legal({"kind": "topple", "from": 12, "dir": 1}), "wall did not block ray")
	var c: TakState = _normal_state()
	c.current = 0
	_put(c, 10, 1, TakState.FLAT)
	_put(c, 10, 0, TakState.FLAT)
	_put(c, 12, 1, TakState.CAPSTONE)
	_check("topple ray blocked by capstone cell", not c.is_legal({"kind": "topple", "from": 10, "dir": 0}), "capstone did not block ray")
	var w: TakState = _normal_state()
	w.current = 0
	_put(w, 10, 0, TakState.FLAT)
	_put(w, 10, 1, TakState.WALL)
	_put(w, 10, 0, TakState.FLAT)
	_put(w, 12, 1, TakState.FLAT)
	_check("falling wall needs empty landing", w.topple_landing_cells(10, 0).is_empty(), "wall stone landed on occupied cell")

func _test_topple_tower() -> void:
	var rw: TakState = _normal_state()
	rw.current = 0
	for cell: int in [6, 7, 8, 9]:
		_put(rw, cell, 0, TakState.FLAT)
	_put(rw, 15, 1, TakState.FLAT)
	_put(rw, 15, 0, TakState.FLAT)
	rw.apply_move({"kind": "topple", "from": 15, "dir": 3})
	_check("topple completing a road wins", rw.over and rw.winner == 0, "road win via topple not detected")

func _test_roads() -> void:
	var horizontal: TakState = _normal_state()
	for x: int in range(5):
		_put(horizontal, 10 + x, 0, TakState.FLAT)
	var vertical: TakState = _normal_state()
	for y: int in range(5):
		_put(vertical, y * 5 + 2, 1, TakState.CAPSTONE)
	var broken: TakState = horizontal.clone()
	_put(broken, 12, 1, TakState.WALL)
	var diagonal: TakState = _normal_state()
	for index: int in range(5):
		_put(diagonal, index * 6, 0, TakState.FLAT)
	_check("horizontal Light road", horizontal.road_exists(0), "left-to-right chain not found")
	_check("vertical Dark road", vertical.road_exists(1), "top-to-bottom chain not found")
	_check("wall on top breaks road", not broken.road_exists(0), "buried road piece incorrectly counted")
	_check("diagonal chain is not a road", not diagonal.road_exists(0), "diagonal connectivity was accepted")
	var vlight: TakState = _normal_state()
	for y: int in range(5):
		_put(vlight, y * 5 + 2, 0, TakState.FLAT)
	var hdark: TakState = _normal_state()
	for x: int in range(5):
		_put(hdark, 10 + x, 1, TakState.FLAT)
	_check("side-based: Light vertical is NOT a road", not vlight.road_exists(0), "default rules let Light win vertically")
	_check("side-based: Dark horizontal is NOT a road", not hdark.road_exists(1), "default rules let Dark win horizontally")
	vlight.set_rules(true, false, true, false, false)
	hdark.set_rules(true, false, true, false, false)
	_check("bidirectional house rule enables either direction", vlight.road_exists(0) and hdark.road_exists(1), "bidirectional flag not applied")
	var wrow: TakState = _normal_state()
	wrow.set_rules(false, false, true, false, false)
	for x: int in range(5):
		_put(wrow, 10 + x, 0, TakState.FLAT if x != 2 else TakState.WALL)
	var wblock: TakState = wrow.clone()
	wblock.set_rules(true, false, true, false, false)
	_check("walls-in-road house rule counts own walls", wrow.road_exists(0) and not wblock.road_exists(0), "walls_block flag not applied to roads")
	var et: TakState = _normal_state()
	et.current = 0
	_put(et, 10, 0, TakState.FLAT)
	_put(et, 10, 1, TakState.FLAT)
	var et_on: TakState = et.clone()
	et_on.set_rules(true, true, false, false, false)
	var own_only: bool = et.topple_landing_cells(10, 0).is_empty()
	var enemy_top: bool = not et_on.topple_landing_cells(10, 0).is_empty()
	_check("enemy-top topple gated by house rule", own_only and enemy_top, "topple_enemy_top flag wrong")

func _filled_board(light_flats: int, dark_flats: int) -> TakState:
	var state: TakState = _normal_state()
	for cell: int in range(25):
		_put(state, cell, cell % 2, TakState.WALL)
	for cell: int in [0, 2, 4, 6, 8, 10]:
		if light_flats > 0:
			state.cells[cell * TakState.MAX_STACK] = TakState.FLAT
			light_flats -= 1
	for cell: int in [14, 16, 18, 20, 22]:
		if dark_flats > 0:
			state.cells[cell * TakState.MAX_STACK] = 3 + TakState.FLAT
			dark_flats -= 1
	return state

func _test_full_board_count() -> void:
	var win_state: TakState = _filled_board(4, 2)
	win_state.heights[24] = 0
	win_state._occupied_count = 24
	win_state.current = 0
	win_state.reserve_flats[0] = 1
	win_state.apply_move({"kind": "place", "cell": 24, "piece_type": TakState.WALL})
	var counted: bool = win_state.over and win_state.winner == 0
	var draw_state: TakState = _filled_board(3, 3)
	draw_state.heights[24] = 0
	draw_state._occupied_count = 24
	draw_state.current = 0
	draw_state.reserve_flats[0] = 1
	draw_state.apply_move({"kind": "place", "cell": 24, "piece_type": TakState.WALL})
	_check("full board adjudicates by top flats", counted, "flat-count winner was not selected")
	_check("full board equal count is draw", draw_state.over and draw_state.winner == 2, "equal flat count did not draw")

func _test_clone() -> void:
	var original: TakState = _normal_state()
	var copy: TakState = original.clone()
	copy.apply_move({"kind": "place", "cell": 0, "piece_type": TakState.FLAT})
	_check("clone mutates independently", int(original.heights[0]) == 0 and int(copy.heights[0]) == 1, "clone changed original state")

func _test_fast_legal_check() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1701
	var state: TakState = TakState.new()
	var agrees: bool = true
	for sample: int in range(50):
		agrees = agrees and (state.has_legal_move() == (not state.legal_moves().is_empty()))
		var moves: Array[Dictionary] = state.legal_moves()
		if moves.is_empty():
			state = TakState.new()
			continue
		state.apply_move(moves[rng.randi_range(0, moves.size() - 1)])
		if state.over:
			state = TakState.new()
	_check("fast legal check agrees on 50 states", agrees, "has_legal_move disagreed with move enumeration")

func _test_random_move_sampler() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 90210
	var state: TakState = TakState.new()
	var checked: int = 0
	var legal: bool = true
	var invariant_fail: String = ""
	for sample: int in range(300):
		if state.over:
			state = TakState.new()
		var move: Dictionary = state.random_move(rng)
		if move.is_empty():
			continue
		checked += 1
		if not state.is_legal(move):
			legal = false
			break
		state.apply_move(move)
		if invariant_fail.is_empty():
			invariant_fail = _invariants_hold(state)
	_check("random move sampler emits legal moves", checked > 0 and legal and invariant_fail.is_empty(), "sampler produced illegal move or broke invariants: %s" % invariant_fail)

func _test_spectate_bots() -> void:
	var problems: Array[String] = []
	var games_over: int = 0
	for game: int in range(3):
		var state: TakState = TakState.new()
		var bots: Array = [MctsBot.new(), MctsBot.new()]
		bots[0].budget_seconds = 0.12
		bots[1].budget_seconds = 0.12
		var turn: int = 0
		while not state.over and turn < 400:
			turn += 1
			var mover: int = state.current
			var before: int = state.turn_number
			var bot: MctsBot = bots[mover]
			bot.start_thinking(state)
			while not bot.is_done():
				bot.tick()
			var move: Dictionary = bot.get_move()
			if not state.is_legal(move):
				problems.append("game %d turn %d illegal move %s" % [game, turn, str(move)])
				break
			state.apply_move(move)
			if state.turn_number != before + 1:
				problems.append("game %d turn %d multi-move (turn_number %d -> %d)" % [game, turn, before, state.turn_number])
				break
			if not state.over and state.current == mover:
				problems.append("game %d turn %d turn did not pass" % [game, turn])
				break
			var violation: String = _invariants_hold(state)
			if not violation.is_empty():
				problems.append("game %d turn %d invariant: %s" % [game, turn, violation])
				break
		if state.over:
			games_over += 1
	_check("bot vs bot: 3 clean games, one action per turn, invariants hold", problems.is_empty() and games_over == 3, "%s" % str(problems.slice(0, 4)))

func _seeded_midgame_state() -> TakState:
	var state: TakState = TakState.new()
	state.apply_move({"kind": "place", "cell": 12, "piece_type": TakState.FLAT})
	state.apply_move({"kind": "place", "cell": 0, "piece_type": TakState.FLAT})
	for cell: int in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17]:
		state.apply_move({"kind": "place", "cell": cell, "piece_type": TakState.FLAT if cell % 2 == 0 else TakState.WALL})
	return state

func _test_rule_top_slide() -> void:
	var st: TakState = _normal_state()
	st.current = 0
	_put(st, 12, 1, TakState.FLAT)
	_put(st, 12, 0, TakState.FLAT)
	_check("top slide OFF by default: no peel", not st.is_legal({"kind": "peel", "from": 12, "dir": 0}), "peel offered by default")
	st.set_rules(false, false, false, true, false)
	var dest: int = st.peel_landing(12, 0)
	st.apply_move({"kind": "peel", "from": 12, "dir": 0})
	var ok: bool = dest == 13 and int(st.heights[12]) == 1 and st.piece_owner(12) == 1 and int(st.heights[13]) == 1 and st.piece_owner(13) == 0
	_check("top slide ON: top stone slides one space", ok, "peel move wrong")
	var t2: TakState = _normal_state()
	t2.current = 0
	t2.set_rules(false, false, false, true, false)
	_put(t2, 10, 1, TakState.FLAT)
	_put(t2, 10, 0, TakState.FLAT)
	_check("2-tall tower cannot topple with slide ON", t2.topple_landing_cells(10, 0).is_empty(), "2-tall topple allowed with slide rule")
	var peels: int = 0
	for m: Dictionary in t2.legal_moves():
		if str(m.get("kind", "")) == "peel":
			peels += 1
	_check("legal_moves enumerates peels", peels > 0, "peels missing from legal_moves")

func _test_rule_wall_move() -> void:
	var st: TakState = _normal_state()
	st.current = 0
	_put(st, 12, 0, TakState.WALL)
	_put(st, 13, 1, TakState.FLAT)
	_check("walls frozen by default", not st.is_legal({"kind": "move", "from": 12, "carry": 1, "dir": 0, "drops": [1]}), "wall moved without rule")
	st.set_rules(false, false, false, false, true)
	var onto_empty: bool = st.is_legal({"kind": "move", "from": 12, "carry": 1, "dir": 3, "drops": [1]})
	var onto_enemy: bool = st.is_legal({"kind": "move", "from": 12, "carry": 1, "dir": 0, "drops": [1]})
	st.apply_move({"kind": "move", "from": 12, "carry": 1, "dir": 0, "drops": [1]})
	var landed: bool = int(st.heights[13]) == 2 and st.piece_type(13) == TakState.WALL
	_check("moving walls slide onto empty and enemy flats", onto_empty and onto_enemy and landed and int(st.heights[12]) == 0, "wall move wrong")
	_check("wall cannot land on capstone or own top", not st.is_legal({"kind": "move", "from": 13, "carry": 1, "dir": 2, "drops": [1]}), "illegal wall landing accepted")

func _test_stalemate_guard() -> void:
	var st: TakState = _normal_state()
	st.set_rules(false, false, false, true, false)
	st.reserve_flats = PackedInt32Array([0, 0])
	st.reserve_caps = PackedInt32Array([0, 0])
	_put(st, 10, 0, TakState.FLAT)
	_put(st, 10, 1, TakState.FLAT)
	_put(st, 20, 1, TakState.FLAT)
	_put(st, 20, 0, TakState.FLAT)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var plies: int = 0
	while not st.over and plies < 300:
		var mv: Dictionary = st.random_move(rng)
		if mv.is_empty():
			break
		st.apply_move(mv)
		plies += 1
	_check("stalemate guard ends churn games by count", st.over and (plies <= 125 or st.winner >= 0), "churn did not terminate in %d plies" % plies)

func _test_brains() -> void:
	var brains = load("res://scripts/tak_brains.gd")
	var win_state: TakState = _normal_state()
	win_state.current = 0
	for cell: int in [6, 7, 8, 9]:
		_put(win_state, cell, 0, TakState.FLAT)
	for b: int in [1, 2, 3, 4]:
		var brain = brains.new()
		brain.set_brain(b)
		brain.budget_seconds = 0.4
		brain.start_thinking(win_state.clone())
		while not brain.is_done():
			brain.tick()
		var mv: Dictionary = brain.get_move()
		var sim: TakState = win_state.clone()
		var found_win: bool = brain != null and win_state.is_legal(mv)
		if found_win:
			sim.apply_move(mv)
			found_win = sim.over and sim.winner == 0
		_check("brain %s takes the immediate win" % str(brains.NAMES[b]), found_win, "move=%s" % str(mv))
	var threat: TakState = _normal_state()
	threat.current = 0
	for cell: int in [0, 5, 10, 15]:
		_put(threat, cell, 1, TakState.FLAT)
	_put(threat, 22, 0, TakState.FLAT)
	var dbrain = brains.new()
	dbrain.set_brain(1)
	dbrain.budget_seconds = 0.5
	dbrain.start_thinking(threat.clone())
	while not dbrain.is_done():
		dbrain.tick()
	var block_move: Dictionary = dbrain.get_move()
	var blocked: bool = threat.is_legal(block_move)
	if blocked:
		var after: TakState = threat.clone()
		after.apply_move(block_move)
		var opp: TakState = after.clone()
		opp.current = 1
		for om: Dictionary in opp.legal_moves():
			var chk: TakState = opp.clone()
			chk.apply_move(om)
			if chk.over and chk.winner == 1:
				blocked = false
				break
	_check("Defensive blocks the enemy road win", blocked, "move=%s" % str(block_move))
	var open_state: TakState = _normal_state()
	open_state.current = 0
	_put(open_state, 12, 0, TakState.FLAT)
	var obrain = brains.new()
	obrain.set_brain(2)
	obrain.budget_seconds = 0.5
	obrain.start_thinking(open_state.clone())
	while not obrain.is_done():
		obrain.tick()
	_check("Offensive plays a legal move on open board", open_state.is_legal(obrain.get_move()), "bad move")
	var rbrain = brains.new()
	rbrain.set_brain(0)
	rbrain.budget_seconds = 0.3
	rbrain.start_thinking(open_state.clone())
	while not rbrain.is_done():
		rbrain.tick()
	_check("Ralph brain delegates to MCTS legally", open_state.is_legal(rbrain.get_move()) and rbrain.playouts > 50, "ralph brain broken")

func _test_hint_and_courtly() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.mode = 2
	game._new_game()
	_check("new game restarts bots in spectate mode", game.bot_thinking, "bots did not start")
	game.bot_thinking = false
	game.state.over = true
	game.state.winner = 0
	game.spectate_wait = 5.0
	game._process(5.4)
	_check("spectate auto-restarts 5s after a win", not game.state.over and game.bot_thinking, "no auto-restart")
	game.bot_thinking = false
	game._request_hint(false)
	var loops: int = 0
	while game.hint_state == game.HINT_COMPUTE and loops < 2000:
		game._process_hint(0.02)
		loops += 1
	var resolved: bool = game.hint_state in [game.HINT_FLASH, game.HINT_SHOW, game.HINT_IDLE]
	_check("hint computes without hanging", resolved, "stuck in compute")
	var before_turn: int = game.state.turn_number
	var total: int = 0
	for h: int in game.state.heights:
		total += int(h)
	loops = 0
	while game.hint_state != game.HINT_IDLE and loops < 800:
		game._process_hint(0.05)
		loops += 1
	var t2: int = 0
	for h: int in game.state.heights:
		t2 += int(h)
	_check("hint performs then clears without playing", game.hint_state == game.HINT_IDLE and game.state.turn_number == before_turn and t2 == total, "hint disturbed the game")
	game._request_hint(true)
	game._request_hint(false)
	loops = 0
	while game.hint_state == game.HINT_COMPUTE and loops < 3000:
		game._process_hint(0.02)
		loops += 1
	_check("re-requesting hints mid-compute is safe", game.hint_state != game.HINT_COMPUTE, "double press hung")
	game._clear_hint()
	# courtly review scenario
	var g2 = load("res://scenes/Main.tscn").instantiate()
	root.add_child(g2)
	await process_frame
	g2.mode = 0
	var st: TakState = g2.state
	st.opening_done = PackedByteArray([1, 1])
	for cell: int in [1, 6, 11, 16, 21]:
		_put(st, cell, 1, TakState.FLAT)
	_put(st, 13, 0, TakState.FLAT)
	st.current = 1
	st.over = true
	st.winner = 1
	st.turn_number = 20
	var pre: TakState = st.clone()
	pre.over = false
	pre.winner = -1
	pre.current = 0
	pre.heights[21] = 0
	pre.cells[21 * TakState.MAX_STACK] = 0
	pre._occupied_count -= 1
	pre._mark_road_masks_dirty()
	g2.undo_states = [pre, st.clone()]
	g2.undo_actors = [0, 1]
	g2._courtly_review()
	var has_block: bool = 21 in g2.court_cells
	g2._undo()
	_check("courtly review highlights the missed block", has_block and not g2.court_label.text.is_empty(), "cells=%s" % str(g2.court_cells))
	_check("undo clears the review and resumes play", g2.court_cells.is_empty() and not g2.state.over, "undo did not restore play")
	g2.queue_free()
	game.queue_free()

func _test_mcts() -> void:
	var opening: TakState = TakState.new()
	opening.apply_move({"kind": "place", "cell": 12, "piece_type": TakState.FLAT})
	var bot: MctsBot = MctsBot.new()
	bot.budget_seconds = 0.5
	bot.start_thinking(opening)
	while not bot.is_done():
		bot.tick()
	var opening_move: Dictionary = bot.get_move()
	var opening_legal: bool = opening.is_legal(opening_move) and opening_move.get("kind") == "place" and opening_move.get("piece_type") == TakState.FLAT
	var state: TakState = _seeded_midgame_state()
	bot.budget_seconds = 0.5
	bot.start_thinking(state)
	while not bot.is_done():
		bot.tick()
	var midgame_move: Dictionary = bot.get_move()
	_check("MCTS returns legal P1 opening", opening_legal, "bot did not respect P1's forced opening")
	_check("MCTS returns legal move in midgame", state.is_legal(midgame_move), "bot move was illegal in midgame")
	var performance_state: TakState = _seeded_midgame_state()
	bot.budget_seconds = 1.0
	bot.start_thinking(performance_state)
	while not bot.is_done():
		bot.tick()
	_check("MCTS returns legal move in seeded midgame", performance_state.is_legal(bot.get_move()), "bot move was illegal in seeded midgame")
	_check("MCTS completes 600 playouts in one second", bot.playouts >= 600, "only %d playouts completed" % bot.playouts)
	print("MCTS_PLAYOUTS=%d" % bot.playouts)

func _test_ui_flow() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.mode = 1
	game._commit_move({"kind": "place", "cell": 10, "piece_type": TakState.FLAT})
	game._commit_move({"kind": "place", "cell": 11, "piece_type": TakState.FLAT})
	game._commit_move({"kind": "place", "cell": 12, "piece_type": TakState.FLAT})
	game._select_stack(10)
	var dest_shown: bool = 11 in game.legal_destinations and 15 in game.legal_destinations
	game._on_cell_clicked(15)
	var moved: bool = int(game.state.heights[15]) == 1 and int(game.state.heights[10]) == 0 and game.state.current == 0
	game._select_stack(12)
	var alternation_excluded: bool = 11 not in game.legal_destinations
	game._on_cell_clicked(11)
	var own_click_reselected: bool = int(game.state.heights[12]) == 1 and game.selected_from == 11
	game._clear_selection()
	var s: TakState = game.state
	_put(s, 5, 1, TakState.FLAT)
	_put(s, 5, 0, TakState.FLAT)
	game._select_stack(5)
	var topples_shown: bool = game.topple_options.has(6) and game.topple_options.has(7) and bool(game.topple_options[7]["last"])
	game._on_cell_clicked(6)
	var ray_click_toppled: bool = int(game.state.heights[5]) == 0 and int(game.state.heights[6]) == 1 and int(game.state.heights[7]) == 1
	game._new_game()
	var s2 = game.state
	s2.opening_done = PackedByteArray([1, 1])
	s2.current = 0
	for cell: int in [10, 11, 12, 13]:
		_put(s2, cell, 0, TakState.FLAT)
	game._commit_move({"kind": "place", "cell": 14, "piece_type": TakState.FLAT})
	var announced: bool = s2.over and s2.winner == 0 and "Light wins by road" in game.status_label.text
	game.queue_free()
	_check("UI one-click stone move onto neighbor", dest_shown and moved, "one-click stone move failed")
	_check("UI excludes same-color landings", alternation_excluded and own_click_reselected, "alternation not enforced in UI")
	_check("UI tower shows topple rays", topples_shown, "topple rays not shown on tower select")
	_check("UI ray click topples tower", ray_click_toppled, "ray click did not topple")
	_check("road win ends game and is announced", announced, "winning road did not stop/announce game")

