extends SceneTree

const TakState = preload("res://scripts/tak_state.gd")
const MctsBot = preload("res://scripts/mcts_bot.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	_test_openings()
	_test_opening_move_guard()
	_test_reserves()
	_test_move_generation()
	_test_wall_rules()
	_test_wall_carry()
	_test_topple()
	_test_roads()
	_test_full_board_count()
	_test_clone()
	_test_fast_legal_check()
	_test_random_move_sampler()
	await _test_ui_flow()
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

func _test_openings() -> void:
	var state: TakState = TakState.new()
	var first: Array[Dictionary] = state.legal_moves()
	var only_flats: bool = first.size() == 25
	for move: Dictionary in first:
		only_flats = only_flats and move["kind"] == "place" and move["piece_type"] == TakState.FLAT
	state.apply_move({"kind": "place", "cell": 12, "piece_type": TakState.FLAT})
	var first_piece_ok: bool = state.piece_owner(12) == 1 and state.current == 1
	var second: Array[Dictionary] = state.legal_moves()
	var second_only_flats: bool = second.size() == 24
	for move: Dictionary in second:
		second_only_flats = second_only_flats and move["kind"] == "place" and move["piece_type"] == TakState.FLAT
	state.apply_move({"kind": "place", "cell": 0, "piece_type": TakState.FLAT})
	var second_piece_ok: bool = state.piece_owner(0) == 0 and state.opening_done[0] == 1 and state.opening_done[1] == 1
	var normal: bool = false
	for move: Dictionary in state.legal_moves():
		if move["kind"] == "place" and move["piece_type"] == TakState.WALL:
			normal = true
			break
	_check("opening P0 places only P1 flats", only_flats and first_piece_ok, "first move or ownership was wrong")
	_check("opening P1 places only P0 flats", second_only_flats and second_piece_ok, "second opening was wrong")
	_check("normal turns allow chosen piece types", normal, "wall placement did not become available")

func _test_opening_move_guard() -> void:
	var state: TakState = TakState.new()
	state.opening_done = PackedByteArray([1, 0])
	state.current = 1
	_put(state, 12, 1, TakState.FLAT)
	var move: Dictionary = {"kind": "move", "from": 12, "carry": 1, "dir": 0, "drops": [1]}
	_check("opening turn rejects movement", not state.is_legal(move) and not state.path_legal(12, [1], 0), "forced opening allowed a move")

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

func _test_move_generation() -> void:
	var state: TakState = _normal_state()
	for index: int in range(6):
		_put(state, 10, 0, TakState.FLAT)
	var moves: Array[Dictionary] = state.legal_moves()
	var carry_five: bool = false
	for move: Dictionary in moves:
		if move["kind"] == "move" and move["from"] == 10 and move["carry"] == 5:
			carry_five = true
	var distributed: bool = state.path_legal(10, [1, 1, 1], 0)
	var empty_drops: bool = state.path_legal(10, [0, 0, 3], 0)
	var one_cell_all: bool = state.is_legal({"kind": "move", "from": 10, "carry": 5, "dir": 0, "drops": [5]})
	_check("stack of six generates carry five", carry_five, "maximum carry was not generated")
	_check("carry three can distribute across three cells", distributed, "legal drop distribution rejected")
	_check("zero drops on open cells are illegal", not empty_drops, "empty-cell pass-through was accepted")
	_check("single-cell move carries full stack portion", one_cell_all, "single destination carry rejected")

func _test_wall_rules() -> void:
	var state: TakState = _normal_state()
	_put(state, 10, 0, TakState.FLAT)
	_put(state, 11, 1, TakState.WALL)
	var blocked: bool = state.is_legal({"kind": "move", "from": 10, "carry": 1, "dir": 0, "drops": [1]})
	var pass_wall: bool = state.is_legal({"kind": "move", "from": 10, "carry": 1, "dir": 0, "drops": [0, 1]})
	var mid_path: TakState = _normal_state()
	_put(mid_path, 10, 0, TakState.FLAT)
	_put(mid_path, 10, 0, TakState.FLAT)
	_put(mid_path, 12, 1, TakState.WALL)
	var wall_on_second: bool = mid_path.is_legal({"kind": "move", "from": 10, "carry": 2, "dir": 0, "drops": [1, 1]})
	_check("wall blocks stacking and pass-through", not blocked and not pass_wall, "a wall cell was entered")
	_check("wall mid-path blocks carry", not wall_on_second, "movement passed through wall at path destination")

func _test_wall_carry() -> void:
	var state: TakState = _normal_state()
	_put(state, 10, 0, TakState.WALL)
	_put(state, 10, 0, TakState.FLAT)
	_put(state, 11, 1, TakState.FLAT)
	var occupied: bool = state.is_legal({"kind": "move", "from": 10, "carry": 2, "dir": 0, "drops": [2]})
	_check("wall bottom carry cannot enter occupied cells", not occupied, "wall carry stacked on a piece")
	var empty_cell: bool = state.is_legal({"kind": "move", "from": 10, "carry": 2, "dir": 2, "drops": [2]})
	_check("wall bottom carry enters empty cells", empty_cell, "wall carry could not reach empty square")

func _test_topple() -> void:
	var state: TakState = _normal_state()
	_put(state, 10, 0, TakState.CAPSTONE)
	_put(state, 11, 1, TakState.WALL)
	var move: Dictionary = {"kind": "move", "from": 10, "carry": 1, "dir": 0, "drops": [1]}
	var legal: bool = state.is_legal(move)
	state.apply_move(move)
	var toppled: bool = state.piece_type(11, 0) == TakState.FLAT and state.piece_owner(11, 0) == 1 and state.piece_type(11, 1) == TakState.CAPSTONE
	var stacked: TakState = _normal_state()
	_put(stacked, 10, 0, TakState.FLAT)
	_put(stacked, 10, 0, TakState.CAPSTONE)
	_put(stacked, 11, 1, TakState.WALL)
	var multi_topple: bool = stacked.is_legal({"kind": "move", "from": 10, "carry": 2, "dir": 0, "drops": [2]})
	_check("lone capstone topples and preserves wall owner", legal and toppled, "wall did not become its owner's flat under capstone")
	_check("multi-piece carry cannot topple wall", not multi_topple, "stacked carry toppled a wall")

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
	_check("vertical Light road also counts", vlight.road_exists(0), "either-direction rule not applied to Light")
	_check("horizontal Dark road also counts", hdark.road_exists(1), "either-direction rule not applied to Dark")
	var vw: TakState = _normal_state()
	vw.current = 0
	for y: int in range(4):
		_put(vw, y * 5 + 2, 0, TakState.FLAT)
	vw.apply_move({"kind": "place", "cell": 22, "piece_type": TakState.FLAT})
	_check("vertical Light road ends game", vw.over and vw.winner == 0, "vertical win not detected in apply_move")
	var hw: TakState = _normal_state()
	hw.current = 1
	for x: int in range(4):
		_put(hw, 5 + x, 1, TakState.FLAT)
	hw.apply_move({"kind": "place", "cell": 9, "piece_type": TakState.FLAT})
	_check("horizontal Dark road ends game", hw.over and hw.winner == 1, "horizontal win not detected for Dark")

func _filled_board(light_flats: int, dark_flats: int) -> TakState:
	var state: TakState = _normal_state()
	for cell: int in range(25):
		_put(state, cell, 0, TakState.WALL)
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
	win_state.reserve_flats[0] = 1
	win_state.apply_move({"kind": "place", "cell": 24, "piece_type": TakState.WALL})
	var counted: bool = win_state.over and win_state.winner == 0
	var draw_state: TakState = _filled_board(3, 3)
	draw_state.heights[24] = 0
	draw_state._occupied_count = 24
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
	_check("random move sampler emits legal moves", checked > 0 and legal, "sampled an illegal move")
	_check("random move sampler checked 300 positions", checked >= 250, "too many sampler calls returned empty")

func _test_ui_flow() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.hotseat = true
	game._commit_move({"kind": "place", "cell": 10, "piece_type": TakState.FLAT})
	game._commit_move({"kind": "place", "cell": 11, "piece_type": TakState.FLAT})
	game._commit_move({"kind": "place", "cell": 12, "piece_type": TakState.FLAT})
	game._select_stack(10)
	var dest_shown: bool = 11 in game.legal_destinations
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_LEFT
	key.pressed = true
	game._unhandled_input(key)
	var arrow_sets_direction: bool = game.selected_direction == 1
	game._on_cell_clicked(11)
	var moved_without_ray_direction: bool = int(game.state.heights[11]) == 2 and int(game.state.heights[10]) == 0
	game._new_game()
	var s = game.state
	s.opening_done = PackedByteArray([1, 1])
	s.current = 0
	for cell: int in [10, 11, 12, 13]:
		_put(s, cell, 0, TakState.FLAT)
	game._commit_move({"kind": "place", "cell": 14, "piece_type": TakState.FLAT})
	var announced: bool = s.over and s.winner == 0 and "Light wins by road" in game.status_label.text
	game.queue_free()
	_check("selecting stack highlights destinations", dest_shown, "no highlight after stack selection")
	_check("arrow key picks move direction", arrow_sets_direction, "left arrow did not select direction 1")
	_check("destination click works after stack select", moved_without_ray_direction, "clicking highlighted cell failed to move")
	_check("road win ends game and is announced", announced, "winning road did not stop/announce game")

func _seeded_midgame_state() -> TakState:
	var state: TakState = TakState.new()
	state.apply_move({"kind": "place", "cell": 12, "piece_type": TakState.FLAT})
	state.apply_move({"kind": "place", "cell": 0, "piece_type": TakState.FLAT})
	var wall_cells: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17]
	for cell: int in wall_cells:
		state.apply_move({"kind": "place", "cell": cell, "piece_type": TakState.WALL})
	return state

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
	var state: TakState = _normal_state()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2468
	for turn: int in range(4):
		var legal: Array[Dictionary] = state.legal_moves()
		state.apply_move(legal[rng.randi_range(0, legal.size() - 1)])
	bot.budget_seconds = 0.5
	bot.start_thinking(state)
	while not bot.is_done():
		bot.tick()
	var midgame_move: Dictionary = bot.get_move()
	_check("MCTS returns legal P1 opening", opening_legal, "bot did not respect P1's forced opening")
	_check("MCTS returns legal move after random turns", state.is_legal(midgame_move), "bot move was illegal in midgame")
	var performance_state: TakState = _seeded_midgame_state()
	bot.budget_seconds = 1.0
	var mcts_started: int = Time.get_ticks_usec()
	bot.start_thinking(performance_state)
	print("MCTS_START_MS=%.1f" % ((Time.get_ticks_usec() - mcts_started) / 1000.0))
	while not bot.is_done():
		bot.tick()
	_check("MCTS returns legal move in seeded midgame", performance_state.is_legal(bot.get_move()), "bot move was illegal in seeded midgame")
	_check("MCTS completes 600 playouts in one second", bot.playouts >= 600, "only %d playouts completed" % bot.playouts)
	print("MCTS_PLAYOUTS=%d" % bot.playouts)
