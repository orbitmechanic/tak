extends SceneTree

var TakState = null
var game = null

func _initialize() -> void:
	TakState = load("res://scripts/tak_state.gd")
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	_run()

func _put(s: TakState, cell: int, owner: int, piece: int) -> void:
	var h: int = int(s.heights[cell])
	s.cells[cell * TakState.MAX_STACK + h] = owner * 3 + piece
	s.heights[cell] = h + 1
	if h == 0:
		s._occupied_count += 1
	s._mark_road_masks_dirty()

func _run() -> void:
	# E1: engine topple onto a TOWER [light flat, dark wall] with lone dark cap
	var s: TakState = TakState.new()
	s.opening_done = PackedByteArray([1, 1])
	s.current = 1
	_put(s, 11, 0, TakState.FLAT)
	_put(s, 11, 1, TakState.WALL)
	_put(s, 12, 1, TakState.CAPSTONE)
	var mv: Dictionary = {"kind": "move", "from": 12, "carry": 1, "dir": 1, "drops": [1]}
	print("E1 legality=%s" % str(s.is_legal(mv)))
	s.apply_move(mv)
	print("E1 result h=%d types=%d,%d,%d owners=%d,%d,%d (want h=3 wall-as-flat owner1 then cap)" % [
		int(s.heights[11]), s.piece_type(11, 0), s.piece_type(11, 1), s.piece_type(11, 2),
		s.piece_owner(11, 0), s.piece_owner(11, 1), s.piece_owner(11, 2)])
	await process_frame
	# UI: fresh game, P0 light lone cap at 12 adjacent to dark wall at 11
	game.hotseat = true
	var g: TakState = game.state
	g.opening_done = PackedByteArray([1, 1])
	g.current = 0
	_put(g, 11, 1, TakState.WALL)
	_put(g, 12, 0, TakState.CAPSTONE)
	g._mark_road_masks_dirty()
	game._select_stack(12)
	print("UI dests=%s carry=%d" % [str(game.legal_destinations), game.selected_carry])
	game._on_cell_clicked(11)
	print("UI after click h11=%d h12=%d top11=%d (want h11=2 h12=0 cap-on-flattened)" % [int(g.heights[11]), int(g.heights[12]), g.piece_type(11)])
	quit(0)
