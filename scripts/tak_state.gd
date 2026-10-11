class_name TakState
extends RefCounted

const BOARD_SIZE: int = 5
const CELL_COUNT: int = 25
const MAX_STACK: int = 50
const FLAT: int = 0
const WALL: int = 1
const CAPSTONE: int = 2
const BOARD_MASK: int = (1 << CELL_COUNT) - 1
const LEFT_EDGE_MASK: int = 1082401
const RIGHT_EDGE_MASK: int = 17318416
const TOP_EDGE_MASK: int = 31
const BOTTOM_EDGE_MASK: int = 32505856

var cells: PackedInt32Array = PackedInt32Array()
var heights: PackedByteArray = PackedByteArray()
var reserve_flats: PackedInt32Array = PackedInt32Array([21, 21])
var reserve_caps: PackedInt32Array = PackedInt32Array([1, 1])
var opening_done: PackedByteArray = PackedByteArray([0, 0])
var _road_masks: PackedInt32Array = PackedInt32Array([0, 0])
var _road_masks_dirty: bool = true
var _road_status: PackedByteArray = PackedByteArray([0, 0])
var _road_status_dirty: PackedByteArray = PackedByteArray([1, 1])
var _occupied_count: int = 0
var _trusted_random_signature: int = 0
var _has_trusted_random_move: bool = false
const RULE_WALLS_BLOCK: int = 1
const RULE_TOPPLE_ENEMY_TOP: int = 2
const RULE_BIDIRECTIONAL: int = 4
const RULE_TOP_MOVE: int = 8
const RULE_WALLS_MOVE: int = 16
var rule_flags: int = 0
var current: int = 0
var over: bool = false
var winner: int = -1
var turn_number: int = 0
var since_progress: int = 0
var occ_high: int = 0

func set_rules(walls_block: bool, topple_enemy_top: bool, bidirectional: bool, top_move: bool, walls_move: bool) -> void:
	rule_flags = 0
	if walls_block:
		rule_flags |= RULE_WALLS_BLOCK
	if topple_enemy_top:
		rule_flags |= RULE_TOPPLE_ENEMY_TOP
	if bidirectional:
		rule_flags |= RULE_BIDIRECTIONAL
	if top_move:
		rule_flags |= RULE_TOP_MOVE
	if walls_move:
		rule_flags |= RULE_WALLS_MOVE
	_mark_road_masks_dirty()

func get_rules() -> Array[bool]:
	return [(rule_flags & RULE_WALLS_BLOCK) != 0, (rule_flags & RULE_TOPPLE_ENEMY_TOP) != 0, (rule_flags & RULE_BIDIRECTIONAL) != 0, (rule_flags & RULE_TOP_MOVE) != 0, (rule_flags & RULE_WALLS_MOVE) != 0]

func _counts_in_road(piece: int) -> bool:
	if piece == FLAT or piece == CAPSTONE:
		return true
	return piece == WALL and (rule_flags & RULE_WALLS_BLOCK) == 0

func _road_direction_allowed(player: int, horizontal: bool) -> bool:
	if (rule_flags & RULE_BIDIRECTIONAL) != 0:
		return true
	return player == 0 if horizontal else player == 1

func _init() -> void:
	cells.resize(CELL_COUNT * MAX_STACK)
	cells.fill(0)
	heights.resize(CELL_COUNT)
	heights.fill(0)

func clone() -> TakState:
	var result: TakState = TakState.new()
	result.cells = cells.duplicate()
	result.heights = heights.duplicate()
	result.reserve_flats = reserve_flats.duplicate()
	result.reserve_caps = reserve_caps.duplicate()
	result.opening_done = opening_done.duplicate()
	result._road_masks = _road_masks.duplicate()
	result._road_masks_dirty = _road_masks_dirty
	result._road_status = _road_status.duplicate()
	result._road_status_dirty = _road_status_dirty.duplicate()
	result._occupied_count = _occupied_count
	result.rule_flags = rule_flags
	result.current = current
	result.over = over
	result.winner = winner
	result.turn_number = turn_number
	result.since_progress = since_progress
	result.occ_high = occ_high
	return result

func piece_owner(cell: int, layer: int = -1) -> int:
	if cell < 0 or cell >= CELL_COUNT:
		return -1
	var level: int = int(heights[cell]) - 1 if layer < 0 else layer
	if level < 0 or level >= int(heights[cell]):
		return -1
	return int(cells[cell * MAX_STACK + level]) / 3

func piece_type(cell: int, layer: int = -1) -> int:
	if cell < 0 or cell >= CELL_COUNT:
		return -1
	var level: int = int(heights[cell]) - 1 if layer < 0 else layer
	if level < 0 or level >= int(heights[cell]):
		return -1
	return int(cells[cell * MAX_STACK + level]) % 3

func road_exists(player: int) -> bool:
	if _road_masks_dirty:
		_rebuild_road_masks()
	if _road_status_dirty[player] != 0:
		var found: bool = false
		for horizontal: bool in [true, false]:
			if _road_direction_allowed(player, horizontal) and _mask_connects(int(_road_masks[player]), horizontal):
				found = true
		_road_status[player] = 1 if found else 0
		_road_status_dirty[player] = 0
	return _road_status[player] != 0

func _mask_connects(qualifying: int, horizontal: bool) -> bool:
	var start: int = LEFT_EDGE_MASK if horizontal else TOP_EDGE_MASK
	var goal: int = RIGHT_EDGE_MASK if horizontal else BOTTOM_EDGE_MASK
	var frontier: int = qualifying & start
	var seen: int = 0
	while frontier != 0:
		if (frontier & goal) != 0:
			return true
		seen |= frontier
		var neighbors: int = ((frontier << 1) & ~LEFT_EDGE_MASK) | ((frontier >> 1) & ~RIGHT_EDGE_MASK) | (((frontier << BOARD_SIZE) | (frontier >> BOARD_SIZE)) & BOARD_MASK)
		frontier = neighbors & qualifying & BOARD_MASK & ~seen
	return false

func road_cells(player: int) -> Array[int]:
	if _road_masks_dirty:
		_rebuild_road_masks()
	var qualifying: int = int(_road_masks[player])
	for horizontal: bool in [true, false]:
		if not _road_direction_allowed(player, horizontal):
			continue
		var found: Array[int] = _road_cells_dir(qualifying, horizontal)
		if not found.is_empty():
			return found
	return []

func _road_cells_dir(qualifying: int, horizontal: bool) -> Array[int]:
	var start: int = LEFT_EDGE_MASK if horizontal else TOP_EDGE_MASK
	var goal: int = RIGHT_EDGE_MASK if horizontal else BOTTOM_EDGE_MASK
	var frontier: int = qualifying & start
	var seen: int = 0
	while frontier != 0:
		seen |= frontier
		if (frontier & goal) != 0:
			var result: Array[int] = []
			for cell: int in range(CELL_COUNT):
				if (seen & (1 << cell)) != 0:
					result.append(cell)
			return result
		var neighbors: int = ((frontier << 1) & ~LEFT_EDGE_MASK) | ((frontier >> 1) & ~RIGHT_EDGE_MASK) | (((frontier << BOARD_SIZE) | (frontier >> BOARD_SIZE)) & BOARD_MASK)
		frontier = neighbors & qualifying & BOARD_MASK & ~seen
	return []

func _rebuild_road_masks() -> void:
	_road_masks[0] = 0
	_road_masks[1] = 0
	for cell: int in range(CELL_COUNT):
		if int(heights[cell]) == 0:
			continue
		var encoded: int = int(cells[cell * MAX_STACK + int(heights[cell]) - 1])
		var piece: int = encoded % 3
		if _counts_in_road(piece):
			_road_masks[encoded / 3] |= 1 << cell
	_road_masks_dirty = false
	_road_status_dirty[0] = 1
	_road_status_dirty[1] = 1

func _mark_road_masks_dirty() -> void:
	_road_masks_dirty = true
	_road_status_dirty[0] = 1
	_road_status_dirty[1] = 1

func _update_road_mask_cell(cell: int) -> void:
	var bit: int = 1 << cell
	var old_light: int = int(_road_masks[0]) & bit
	var old_dark: int = int(_road_masks[1]) & bit
	_road_masks[0] &= ~bit
	_road_masks[1] &= ~bit
	if int(heights[cell]) > 0:
		var encoded: int = int(cells[cell * MAX_STACK + int(heights[cell]) - 1])
		var piece: int = encoded % 3
		if _counts_in_road(piece):
			_road_masks[encoded / 3] |= bit
	if old_light != (int(_road_masks[0]) & bit):
		_road_status_dirty[0] = 1
	if old_dark != (int(_road_masks[1]) & bit):
		_road_status_dirty[1] = 1

func flats_count(player: int) -> int:
	var total: int = 0
	for cell: int in range(CELL_COUNT):
		if int(heights[cell]) > 0 and piece_owner(cell) == player and piece_type(cell) == FLAT:
			total += 1
	return total

func _landing_legal(destination: int, stone_type: int, stone_owner: int) -> bool:
	var top: int = piece_type(destination)
	if top == CAPSTONE:
		return false
	if top == WALL:
		return stone_type == CAPSTONE and piece_owner(destination) != current
	if top == FLAT:
		return piece_owner(destination) != current
	return true

func _stone_movable(stone_type: int) -> bool:
	if stone_type == WALL:
		return (rule_flags & RULE_WALLS_MOVE) != 0
	return true

func _top_peelable(stone_type: int) -> bool:
	if (rule_flags & RULE_TOP_MOVE) == 0:
		return false
	return _stone_movable(stone_type)

func _stone_move_legal(origin: int, direction: int) -> bool:
	if over or opening_done[current] == 0:
		return false
	if origin < 0 or origin >= CELL_COUNT or direction < 0 or direction > 3:
		return false
	if int(heights[origin]) != 1:
		return false
	var stone: int = int(cells[origin * MAX_STACK])
	var stone_owner: int = int(stone / 3)
	var stone_type: int = stone % 3
	if stone_owner != current or not _stone_movable(stone_type):
		return false
	var destination: int = _neighbor(origin, direction, 1)
	if destination < 0:
		return false
	return _landing_legal(destination, stone_type, stone_owner)

func peel_landing(origin: int, direction: int) -> int:
	if over or opening_done[current] == 0 or origin < 0 or origin >= CELL_COUNT or direction < 0 or direction > 3:
		return -1
	if int(heights[origin]) < 2:
		return -1
	var stone: int = int(cells[origin * MAX_STACK + int(heights[origin]) - 1])
	var stone_owner: int = int(stone / 3)
	var stone_type: int = stone % 3
	if stone_owner != current or not _top_peelable(stone_type):
		return -1
	var destination: int = _neighbor(origin, direction, 1)
	if destination < 0:
		return -1
	if not _landing_legal(destination, stone_type, stone_owner):
		return -1
	return destination

func topple_landing_cells(from: int, direction: int) -> Array[int]:
	var result: Array[int] = []
	if over or opening_done[current] == 0:
		return result
	var height: int = int(heights[from])
	var min_height: int = 3 if (rule_flags & RULE_TOP_MOVE) != 0 else 2
	if height < min_height:
		return result
	if piece_owner(from) != current and (rule_flags & RULE_TOPPLE_ENEMY_TOP) == 0:
		return []
	if direction < 0 or direction > 3:
		return result
	for step: int in range(1, height + 1):
		var cell: int = _neighbor(from, direction, step)
		if cell < 0:
			return []
		var stone: int = int(cells[from * MAX_STACK + step - 1])
		var stone_type: int = stone % 3
		var stone_owner: int = int(stone / 3)
		var top: int = piece_type(cell)
		if top == WALL or top == CAPSTONE:
			return []
		if top == FLAT:
			if stone_type == WALL:
				return []
			if stone_owner == piece_owner(cell):
				return []
		result.append(cell)
	return result

func legal_moves() -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if over:
		return moves
	if opening_done[current] == 0:
		for cell: int in range(CELL_COUNT):
			if int(heights[cell]) == 0 and reserve_flats[1 - current] > 0:
				moves.append({"kind": "place", "cell": cell, "piece_type": FLAT})
		return moves
	for cell: int in range(CELL_COUNT):
		if int(heights[cell]) == 0:
			if reserve_flats[current] > 0:
				moves.append({"kind": "place", "cell": cell, "piece_type": FLAT})
				moves.append({"kind": "place", "cell": cell, "piece_type": WALL})
			if reserve_caps[current] > 0:
				moves.append({"kind": "place", "cell": cell, "piece_type": CAPSTONE})
			continue
		if piece_owner(cell) == current:
			if int(heights[cell]) == 1:
				for direction: int in range(4):
					if _stone_move_legal(cell, direction):
						moves.append({"kind": "move", "from": cell, "carry": 1, "dir": direction, "drops": [1]})
		if int(heights[cell]) >= 2:
			for direction: int in range(4):
				if peel_landing(cell, direction) >= 0:
					moves.append({"kind": "peel", "from": cell, "dir": direction})
			if piece_owner(cell) == current or (rule_flags & RULE_TOPPLE_ENEMY_TOP) != 0:
				for direction: int in range(4):
					if not topple_landing_cells(cell, direction).is_empty():
						moves.append({"kind": "topple", "from": cell, "dir": direction})
	return moves

func has_legal_move() -> bool:
	if over:
		return false
	if opening_done[current] == 0:
		return reserve_flats[1 - current] > 0 and _occupied_count < CELL_COUNT
	if (reserve_flats[current] > 0 or reserve_caps[current] > 0) and _occupied_count < CELL_COUNT:
		return true
	for cell: int in range(CELL_COUNT):
		var height: int = int(heights[cell])
		if height == 0:
			continue
		if height == 1 and piece_owner(cell) == current:
			for direction: int in range(4):
				if _stone_move_legal(cell, direction):
					return true
		elif height >= 2:
			for direction: int in range(4):
				if peel_landing(cell, direction) >= 0:
					return true
			if piece_owner(cell) == current or (rule_flags & RULE_TOPPLE_ENEMY_TOP) != 0:
				for direction: int in range(4):
					if not topple_landing_cells(cell, direction).is_empty():
						return true
	return false

func is_legal(move: Dictionary) -> bool:
	if over or not move.has("kind"):
		return false
	if str(move["kind"]) == "place":
		if not move.has("cell") or not move.has("piece_type"):
			return false
		var cell: int = int(move["cell"])
		var piece: int = int(move["piece_type"])
		if cell < 0 or cell >= CELL_COUNT or int(heights[cell]) != 0:
			return false
		if opening_done[current] == 0:
			return piece == FLAT and reserve_flats[1 - current] > 0
		if piece == FLAT or piece == WALL:
			return reserve_flats[current] > 0
		return piece == CAPSTONE and reserve_caps[current] > 0
	if str(move["kind"]) == "topple":
		if not move.has("from") or not move.has("dir"):
			return false
		return not topple_landing_cells(int(move["from"]), int(move["dir"])).is_empty()
	if str(move["kind"]) == "peel":
		if not move.has("from") or not move.has("dir"):
			return false
		return peel_landing(int(move["from"]), int(move["dir"])) >= 0
	if str(move["kind"]) != "move" or not move.has("from") or not move.has("dir"):
		return false
	var origin: int = int(move["from"])
	var direction: int = int(move["dir"])
	var carry: int = int(move.get("carry", 1))
	if carry != 1:
		return false
	if move.has("drops"):
		var drops: Array = move["drops"]
		if drops.size() != 1 or int(drops[0]) != 1:
			return false
	return _stone_move_legal(origin, direction)

func apply_move(move: Dictionary) -> void:
	var sampler_verified: bool = _has_trusted_random_move and _move_signature(move) == _trusted_random_signature
	_has_trusted_random_move = false
	_trusted_random_signature = 0
	if not sampler_verified and not is_legal(move):
		push_error("Attempted to apply an illegal Tak move: %s" % [move])
		return
	if _road_masks_dirty:
		_rebuild_road_masks()
	var actor: int = current
	var occ_before: int = _occupied_count
	var made_progress: bool = false
	if str(move["kind"]) == "place":
		var cell: int = int(move["cell"])
		var piece: int = int(move["piece_type"])
		var owner: int = actor if opening_done[actor] != 0 else 1 - actor
		_push_piece(cell, owner, piece)
		_update_road_mask_cell(cell)
		if piece == CAPSTONE:
			reserve_caps[owner] -= 1
		else:
			reserve_flats[owner] -= 1
		opening_done[actor] = 1
		made_progress = true
	elif str(move["kind"]) == "topple":
		_apply_topple(move)
	elif str(move["kind"]) == "peel":
		_apply_peel(move)
	else:
		var dest_cell: int = _neighbor(int(move["from"]), int(move["dir"]), 1)
		made_progress = piece_type(dest_cell) == WALL
		_apply_single_move(move)
	turn_number += 1
	if made_progress or _occupied_count > occ_high:
		occ_high = maxi(occ_high, _occupied_count)
		since_progress = 0
	else:
		since_progress += 1
	if road_exists(actor):
		over = true
		winner = actor
		return
	current = 1 - actor
	if road_exists(current):
		over = true
		winner = current
		return
	if _board_full() or since_progress >= 120 or not has_legal_move():
		_finish_by_count()

func _apply_single_move(move: Dictionary) -> void:
	var origin: int = int(move["from"])
	var direction: int = int(move["dir"])
	var destination: int = _neighbor(origin, direction, 1)
	var base: int = origin * MAX_STACK
	var stone: int = int(cells[base])
	cells[base] = 0
	heights[origin] = 0
	_occupied_count -= 1
	_update_road_mask_cell(origin)
	if piece_type(destination) == WALL:
		cells[destination * MAX_STACK + int(heights[destination]) - 1] = piece_owner(destination) * 3 + FLAT
	_push_encoded(destination, stone)
	_update_road_mask_cell(destination)

func _apply_peel(move: Dictionary) -> void:
	var origin: int = int(move["from"])
	var destination: int = peel_landing(origin, int(move["dir"]))
	var top_index: int = origin * MAX_STACK + int(heights[origin]) - 1
	var stone: int = int(cells[top_index])
	cells[top_index] = 0
	heights[origin] = int(heights[origin]) - 1
	_update_road_mask_cell(origin)
	if piece_type(destination) == WALL:
		cells[destination * MAX_STACK + int(heights[destination]) - 1] = piece_owner(destination) * 3 + FLAT
	_push_encoded(destination, stone)
	_update_road_mask_cell(destination)

func _apply_topple(move: Dictionary) -> void:
	var origin: int = int(move["from"])
	var direction: int = int(move["dir"])
	var landing: Array[int] = topple_landing_cells(origin, direction)
	var height: int = int(heights[origin])
	var base: int = origin * MAX_STACK
	var carried: Array[int] = []
	for index: int in range(height):
		carried.append(int(cells[base + index]))
	for index: int in range(height):
		cells[base + index] = 0
	heights[origin] = 0
	_occupied_count -= 1
	_update_road_mask_cell(origin)
	for index: int in range(height):
		var destination: int = landing[index]
		var previous: int = int(heights[destination])
		cells[destination * MAX_STACK + previous] = carried[index]
		heights[destination] = previous + 1
		if previous == 0:
			_occupied_count += 1
		_update_road_mask_cell(destination)

func random_move(rng: RandomNumberGenerator) -> Dictionary:
	if over:
		return {}
	_trusted_random_signature = 0
	_has_trusted_random_move = false
	if _road_masks_dirty:
		_rebuild_road_masks()
	var empty_count: int = CELL_COUNT - _occupied_count
	if opening_done[current] == 0:
		if empty_count > 0 and reserve_flats[1 - current] > 0:
			var target_opening: int = rng.randi_range(0, empty_count - 1)
			for cell: int in range(CELL_COUNT):
				if int(heights[cell]) == 0:
					if target_opening == 0:
						return _stamp_random_move({"kind": "place", "cell": cell, "piece_type": FLAT})
					target_opening -= 1
		return {}
	if rng.randf() < 0.34 and empty_count > 0 and (reserve_flats[current] > 0 or reserve_caps[current] > 0):
		var target_empty: int = rng.randi_range(0, empty_count - 1)
		for cell: int in range(CELL_COUNT):
			if int(heights[cell]) == 0:
				if target_empty == 0:
					var piece: int = FLAT
					if reserve_flats[current] > 0 and rng.randf() < 0.25:
						piece = WALL
					if reserve_caps[current] > 0 and (reserve_flats[current] == 0 or rng.randf() < 0.04):
						piece = CAPSTONE
					if piece == WALL and reserve_flats[current] <= 0:
						piece = FLAT
					if piece == FLAT and reserve_flats[current] <= 0:
						piece = CAPSTONE
					return _stamp_random_move({"kind": "place", "cell": cell, "piece_type": piece})
				target_empty -= 1
	for attempt: int in range(10):
		var cell: int = rng.randi_range(0, CELL_COUNT - 1)
		var height: int = int(heights[cell])
		if height == 0:
			continue
		var direction: int = rng.randi_range(0, 3)
		if height == 1:
			if _stone_move_legal(cell, direction):
				return _stamp_random_move({"kind": "move", "from": cell, "carry": 1, "dir": direction, "drops": [1]})
		elif piece_owner(cell) == current or (rule_flags & RULE_TOPPLE_ENEMY_TOP) != 0:
			if not topple_landing_cells(cell, direction).is_empty():
				return _stamp_random_move({"kind": "topple", "from": cell, "dir": direction})
	var fallback: Array[Dictionary] = legal_moves()
	if not fallback.is_empty():
		return _stamp_random_move(fallback[rng.randi_range(0, fallback.size() - 1)])
	return {}

func _stamp_random_move(move: Dictionary) -> Dictionary:
	_trusted_random_signature = _move_signature(move)
	_has_trusted_random_move = true
	return move

func _move_signature(move: Dictionary) -> int:
	if str(move.get("kind", "")) == "place":
		return (1 << 30) | (int(move["cell"]) << 3) | int(move["piece_type"])
	if str(move.get("kind", "")) == "topple":
		return (2 << 30) | int(move["from"]) | (int(move["dir"]) << 5)
	if str(move.get("kind", "")) == "peel":
		return (3 << 30) | int(move["from"]) | (int(move["dir"]) << 5)
	return int(move["from"]) | (int(move["dir"]) << 5)

func _push_piece(cell: int, owner: int, piece: int) -> void:
	_push_encoded(cell, owner * 3 + piece)

func _push_encoded(cell: int, piece: int) -> void:
	var height: int = int(heights[cell])
	if height >= MAX_STACK:
		push_error("Tak stack buffer capacity exceeded")
		return
	if height == 0:
		_occupied_count += 1
	cells[cell * MAX_STACK + height] = piece
	heights[cell] = height + 1

func _board_full() -> bool:
	return _occupied_count == CELL_COUNT

func _finish_by_count() -> void:
	over = true
	var light_flats: int = flats_count(0)
	var dark_flats: int = flats_count(1)
	winner = 0 if light_flats > dark_flats else (1 if dark_flats > light_flats else 2)

func _neighbor(cell: int, direction: int, distance: int = 1) -> int:
	var x: int = cell % BOARD_SIZE
	var y: int = cell / BOARD_SIZE
	match direction:
		0:
			x += distance
		1:
			x -= distance
		2:
			y += distance
		3:
			y -= distance
	if x < 0 or x >= BOARD_SIZE or y < 0 or y >= BOARD_SIZE:
		return -1
	return y * BOARD_SIZE + x
