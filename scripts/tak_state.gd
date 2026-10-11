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
var _movable_cells: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _movable_owner: PackedByteArray = PackedByteArray()
var _occupied_count: int = 0
var _trusted_random_signature: int = 0
var _has_trusted_random_move: bool = false
var current: int = 0
var over: bool = false
var winner: int = -1
var turn_number: int = 0

func _init() -> void:
	cells.resize(CELL_COUNT * MAX_STACK)
	cells.fill(0)
	heights.resize(CELL_COUNT)
	heights.fill(0)
	_movable_owner.resize(CELL_COUNT)
	_movable_owner.fill(0)

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
	result._movable_cells = [_movable_cells[0].duplicate(), _movable_cells[1].duplicate()]
	result._movable_owner = _movable_owner.duplicate()
	result._occupied_count = _occupied_count
	result.current = current
	result.over = over
	result.winner = winner
	result.turn_number = turn_number
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
		_road_status[player] = 1 if _mask_connects(int(_road_masks[player]), true) or _mask_connects(int(_road_masks[player]), false) else 0
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
	_movable_cells[0].clear()
	_movable_cells[1].clear()
	_movable_owner.fill(0)
	for cell: int in range(CELL_COUNT):
		if int(heights[cell]) == 0:
			continue
		var encoded: int = int(cells[cell * MAX_STACK + int(heights[cell]) - 1])
		var owner: int = encoded / 3
		var piece: int = encoded % 3
		if piece != WALL:
			_movable_cells[owner].append(cell)
			_movable_owner[cell] = owner + 1
		if piece == FLAT or piece == CAPSTONE:
			_road_masks[owner] |= 1 << cell
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
	var old_movable_owner: int = int(_movable_owner[cell]) - 1
	_road_masks[0] &= ~bit
	_road_masks[1] &= ~bit
	var new_movable_owner: int = -1
	if int(heights[cell]) > 0:
		var encoded: int = int(cells[cell * MAX_STACK + int(heights[cell]) - 1])
		var piece: int = encoded % 3
		if piece == FLAT or piece == CAPSTONE:
			var owner: int = encoded / 3
			_road_masks[owner] |= bit
		if piece != WALL:
			new_movable_owner = encoded / 3
	if old_movable_owner != new_movable_owner:
		if old_movable_owner >= 0:
			var old_cells: PackedInt32Array = _movable_cells[old_movable_owner]
			var old_index: int = old_cells.find(cell)
			if old_index >= 0:
				old_cells.remove_at(old_index)
				_movable_cells[old_movable_owner] = old_cells
		if new_movable_owner >= 0:
			var new_cells: PackedInt32Array = _movable_cells[new_movable_owner]
			new_cells.append(cell)
			_movable_cells[new_movable_owner] = new_cells
		_movable_owner[cell] = new_movable_owner + 1
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
			if reserve_flats[current] > 0:
				moves.append({"kind": "place", "cell": cell, "piece_type": WALL})
			if reserve_caps[current] > 0:
				moves.append({"kind": "place", "cell": cell, "piece_type": CAPSTONE})
		if piece_owner(cell) != current or piece_type(cell) == WALL:
			continue
		var max_carry: int = mini(5, int(heights[cell]))
		for carry: int in range(1, max_carry + 1):
			for direction: int in range(4):
				_append_paths(moves, cell, carry, direction, 0, [], 0)
	for cell: int in range(CELL_COUNT):
		if int(heights[cell]) < 2 or piece_owner(cell) != current:
			continue
		for direction: int in range(4):
			if not topple_landing_cells(cell, direction).is_empty():
				moves.append({"kind": "topple", "from": cell, "dir": direction})
	return moves

func has_legal_move() -> bool:
	if over:
		return false
	if opening_done[current] == 0:
		return reserve_flats[1 - current] > 0 and _occupied_count < CELL_COUNT
	if reserve_flats[current] > 0 or reserve_caps[current] > 0:
		if _occupied_count < CELL_COUNT:
			return true
	for cell: int in range(CELL_COUNT):
		if piece_owner(cell) != current:
			continue
		if piece_type(cell) != WALL:
			for carry: int in range(1, mini(5, int(heights[cell])) + 1):
				for direction: int in range(4):
					if _has_any_path(cell, carry, direction):
						return true
		if int(heights[cell]) >= 2:
			for direction: int in range(4):
				if not topple_landing_cells(cell, direction).is_empty():
					return true
	return false

func topple_landing_cells(from: int, direction: int) -> Array[int]:
	var result: Array[int] = []
	if over:
		return result
	var height: int = int(heights[from])
	if height < 2:
		return result
	var owner: int = piece_owner(from)
	if owner != current:
		return result
	for step: int in range(1, height + 1):
		var cell: int = _neighbor(from, direction, step)
		if cell < 0:
			return []
		var stone: int = int(cells[from * MAX_STACK + step - 1])
		var stone_type: int = stone % 3
		if piece_type(cell) == WALL or piece_type(cell) == CAPSTONE:
			return []
		if stone_type == WALL and int(heights[cell]) > 0:
			return []
		result.append(cell)
	return result

func _append_paths(moves: Array[Dictionary], origin: int, carry: int, direction: int, distance: int, drops: Array[int], used: int) -> void:
	if distance >= BOARD_SIZE:
		return
	var destination: int = _neighbor(origin, direction, distance + 1)
	if destination < 0:
		return
	var top: int = piece_type(destination)
	if top == CAPSTONE:
		return
	var bottom_type: int = piece_type(origin, int(heights[origin]) - carry)
	if top == WALL:
		if carry == 1 and bottom_type == CAPSTONE:
			var topple_drops: Array[int] = drops.duplicate()
			topple_drops.append(1)
			if _path_legal_internal(origin, carry, direction, topple_drops):
				moves.append({"kind": "move", "from": origin, "carry": carry, "dir": direction, "drops": topple_drops})
		return
	if bottom_type == WALL and int(heights[destination]) > 0:
		return
	if bottom_type == CAPSTONE and top == CAPSTONE:
		return
	var remaining: int = carry - used
	for count: int in range(1, remaining + 1):
		var next_drops: Array[int] = drops.duplicate()
		next_drops.append(count)
		var total: int = used + count
		if total == carry and _path_legal_internal(origin, carry, direction, next_drops):
			moves.append({"kind": "move", "from": origin, "carry": carry, "dir": direction, "drops": next_drops})
		_append_paths(moves, origin, carry, direction, distance + 1, next_drops, total)

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
		var origin_t: int = int(move["from"])
		var direction_t: int = int(move["dir"])
		if direction_t < 0 or direction_t > 3:
			return false
		return not topple_landing_cells(origin_t, direction_t).is_empty()
	if str(move["kind"]) != "move" or not move.has("from") or not move.has("carry") or not move.has("dir"):
		return false
	var origin: int = int(move["from"])
	var carry: int = int(move["carry"])
	var direction: int = int(move["dir"])
	if origin < 0 or origin >= CELL_COUNT or direction < 0 or direction > 3:
		return false
	if piece_owner(origin) != current or piece_type(origin) == WALL or carry < 1 or carry > mini(5, int(heights[origin])):
		return false
	if opening_done[current] == 0:
		return false
	if not move.has("drops"):
		return _has_any_path(origin, carry, direction)
	var drops: Array = move["drops"]
	return _path_legal_internal(origin, carry, direction, drops)

func path_legal(from: int, drops: Array, dir: int) -> bool:
	if from < 0 or from >= CELL_COUNT or dir < 0 or dir > 3:
		return false
	if piece_owner(from) != current or piece_type(from) == WALL or opening_done[current] == 0:
		return false
	var carry: int = 0
	for drop: Variant in drops:
		carry += int(drop)
	if carry == 0:
		return false
	return _path_legal_internal(from, carry, dir, drops)

func _has_any_path(origin: int, carry: int, direction: int) -> bool:
	if origin < 0 or origin >= CELL_COUNT or direction < 0 or direction > 3:
		return false
	if carry < 1 or carry > mini(5, int(heights[origin])) or piece_type(origin) == WALL:
		return false
	var destination: int = _neighbor(origin, direction)
	if destination < 0:
		return false
	var bottom: int = piece_type(origin, int(heights[origin]) - carry)
	if piece_type(destination) == CAPSTONE:
		return false
	if piece_type(destination) == WALL:
		return carry == 1 and bottom == CAPSTONE
	if bottom == WALL:
		return int(heights[destination]) == 0
	return true

func _path_legal_internal(origin: int, carry: int, direction: int, drops: Array) -> bool:
	if drops.is_empty() or drops.size() > BOARD_SIZE or drops.size() > CELL_COUNT:
		return false
	if origin < 0 or origin >= CELL_COUNT or direction < 0 or direction > 3:
		return false
	if carry < 1 or carry > mini(5, int(heights[origin])) or piece_type(origin) == WALL:
		return false
	var bottom_type: int = piece_type(origin, int(heights[origin]) - carry)
	var remaining: int = carry
	for index: int in range(drops.size()):
		var drop: int = int(drops[index])
		if drop < 0 or drop > remaining:
			return false
		var cell: int = _neighbor(origin, direction, index + 1)
		if cell < 0:
			return false
		var top: int = piece_type(cell)
		var is_last: bool = index == drops.size() - 1
		if top == WALL:
			if is_last:
				if not (carry == 1 and bottom_type == CAPSTONE and drop == 1):
					return false
				remaining -= drop
				if remaining != 0:
					return false
				continue
			return false
		else:
			if drop == 0:
				return false
			if top == CAPSTONE:
				return false
			if bottom_type == WALL and int(heights[cell]) > 0:
				return false
		remaining -= drop
		if is_last and drop < 1:
			return false
	if remaining != 0:
		return false
	return true

# Every returned rollout move is checked against the same path legality rules as UI moves.
func random_move(rng: RandomNumberGenerator) -> Dictionary:
	if over:
		return {}
	_trusted_random_signature = 0
	_has_trusted_random_move = false
	if _road_masks_dirty:
		_rebuild_road_masks()
	var empty_count: int = CELL_COUNT - _occupied_count
	var can_place: bool
	var placement_owner: int = current
	if opening_done[current] == 0:
		placement_owner = 1 - current
		can_place = reserve_flats[placement_owner] > 0
	else:
		can_place = reserve_flats[current] > 0 or reserve_caps[current] > 0
	if can_place and empty_count > 0 and rng.randf() < 0.34:
		var target_empty: int = rng.randi_range(0, empty_count - 1)
		for cell: int in range(CELL_COUNT):
			if int(heights[cell]) != 0:
				continue
			if target_empty == 0:
				var piece: int = FLAT
				if opening_done[current] != 0 and reserve_caps[current] > 0 and (reserve_flats[current] == 0 or rng.randf() < 0.04):
					piece = CAPSTONE
				return _stamp_random_move({"kind": "place", "cell": cell, "piece_type": piece})
			target_empty -= 1
	if opening_done[current] == 0:
		var opening_moves: Array[Dictionary] = legal_moves()
		if not opening_moves.is_empty():
			return _stamp_random_move(opening_moves[rng.randi_range(0, opening_moves.size() - 1)])
		return {}
	var movable_cells: PackedInt32Array = _movable_cells[current]
	if rng.randf() < 0.25:
		var tower_cells: Array[int] = []
		for cell: int in range(CELL_COUNT):
			if int(heights[cell]) >= 2 and piece_owner(cell) == current:
				tower_cells.append(cell)
		if not tower_cells.is_empty():
			var origin_topple: int = tower_cells[rng.randi_range(0, tower_cells.size() - 1)]
			var dir_topple: int = rng.randi_range(0, 3)
			if not topple_landing_cells(origin_topple, dir_topple).is_empty():
				return _stamp_random_move({"kind": "topple", "from": origin_topple, "dir": dir_topple})
	for attempt: int in range(8):
		if movable_cells.is_empty():
			break
		var from: int = movable_cells[rng.randi_range(0, movable_cells.size() - 1)]
		var carry: int = rng.randi_range(1, mini(5, int(heights[from])))
		var direction: int = rng.randi_range(0, 3)
		var bottom_type: int = piece_type(from, int(heights[from]) - carry)
		var drops: Array[int] = []
		var remaining: int = carry
		var distance: int = rng.randi_range(1, carry)
		var valid_walk: bool = true
		for step: int in range(1, distance + 1):
			var cell: int = _neighbor(from, direction, step)
			if cell < 0:
				valid_walk = false
				break
			var last: bool = step == distance
			var top: int = piece_type(cell)
			if top == WALL:
				if last and carry == 1 and bottom_type == CAPSTONE:
					drops.append(1)
					var topple: Dictionary = {"kind": "move", "from": from, "carry": carry, "dir": direction, "drops": drops}
					if _path_legal_internal(from, carry, direction, drops):
						return _stamp_random_move(topple)
				break
			if top == CAPSTONE:
				valid_walk = false
				break
			if bottom_type == WALL and int(heights[cell]) > 0:
				valid_walk = false
				break
			var amount: int = remaining if last else 1
			drops.append(amount)
			remaining -= amount
		if valid_walk and drops.size() == distance and remaining == 0 and _path_legal_internal(from, carry, direction, drops):
			return _stamp_random_move({"kind": "move", "from": from, "carry": carry, "dir": direction, "drops": drops})
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
	var signature: int = int(move["from"]) | (int(move["carry"]) << 5) | (int(move["dir"]) << 8)
	var drops: Array = move.get("drops", [])
	for index: int in range(drops.size()):
		signature |= int(drops[index]) << (10 + index * 3)
	return signature

func apply_move(move: Dictionary) -> void:
	var sampler_verified: bool = _has_trusted_random_move and _move_signature(move) == _trusted_random_signature
	_has_trusted_random_move = false
	_trusted_random_signature = 0
	if move.get("kind", "") == "move" and not move.has("drops"):
		var paths: Array[Dictionary] = []
		_append_paths(paths, int(move.get("from", -1)), int(move.get("carry", 0)), int(move.get("dir", -1)), 0, [], 0)
		if paths.is_empty():
			push_error("Attempted to apply a Tak move without a legal drop path: %s" % [move])
			return
		move = paths[0]
	if not sampler_verified and not is_legal(move):
		push_error("Attempted to apply an illegal Tak move: %s" % [move])
		return
	if _road_masks_dirty:
		_rebuild_road_masks()
	var actor: int = current
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
	elif str(move["kind"]) == "topple":
		_apply_topple(move)
	else:
		_apply_stack_move(move)
	turn_number += 1
	if road_exists(actor):
		over = true
		winner = actor
		return
	current = 1 - actor
	if road_exists(current):
		over = true
		winner = current
		return
	if _board_full() or not has_legal_move():
		_finish_by_count()

func _apply_stack_move(move: Dictionary) -> void:
	var origin: int = int(move["from"])
	var carry: int = int(move["carry"])
	var direction: int = int(move["dir"])
	var drops: Array = move["drops"]
	var base: int = origin * MAX_STACK
	var start: int = int(heights[origin]) - carry
	if carry == 1:
		var piece: int = int(cells[base + start])
		cells[base + start] = 0
		heights[origin] = start
		if start == 0:
			_occupied_count -= 1
		_update_road_mask_cell(origin)
		var destination: int = _neighbor(origin, direction)
		if piece_type(destination) == WALL:
			cells[destination * MAX_STACK + int(heights[destination]) - 1] = piece_owner(destination) * 3 + FLAT
		_push_encoded(destination, piece)
		_update_road_mask_cell(destination)
		return
	var carried: Array[int] = []
	for index: int in range(carry):
		carried.append(int(cells[base + start + index]))
	for index: int in range(carry):
		cells[base + start + index] = 0
	heights[origin] = start
	if start == 0:
		_occupied_count -= 1
	_update_road_mask_cell(origin)
	var offset: int = 0
	for step: int in range(drops.size()):
		var destination: int = _neighbor(origin, direction, step + 1)
		var count: int = int(drops[step])
		if count == 0:
			continue
		if piece_type(destination) == WALL:
			cells[destination * MAX_STACK + int(heights[destination]) - 1] = piece_owner(destination) * 3 + FLAT
		for piece_index: int in range(count):
			_push_encoded(destination, carried[offset])
			offset += 1
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
