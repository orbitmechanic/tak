class_name MctsBot
extends RefCounted

const UCB_C: float = 1.4
const CHUNK_SECONDS: float = 0.05
const ROLLOUT_LIMIT: int = 200

var budget_seconds: float = 2.0
var playouts: int = 0
var _started_usec: int = 0
var _deadline_usec: int = 0
var _chunk_end_usec: int = 0
var _done: bool = true
var _root_player: int = 0
var _root: Dictionary = {}
var _selected_move: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func start_thinking(state: TakState) -> void:
	_rng.randomize()
	playouts = 0
	_root_player = state.current
	_started_usec = Time.get_ticks_usec()
	_deadline_usec = _started_usec + int(maxf(0.01, budget_seconds) * 1000000.0)
	var moves: Array[Dictionary] = state.legal_moves()
	_root = {
		"state": state.clone(),
		"untried": moves,
		"moves_ready": true,
		"children": [],
		"visits": 0,
		"score": 0.0,
		"move": {}
	}
	_selected_move = moves[0] if not moves.is_empty() else {}
	_done = moves.is_empty()

func tick() -> void:
	if _done:
		return
	var chunk_end: int = mini(_deadline_usec, Time.get_ticks_usec() + int(CHUNK_SECONDS * 1000000.0))
	_chunk_end_usec = chunk_end
	while Time.get_ticks_usec() < chunk_end:
		_iteration()
	if Time.get_ticks_usec() >= _deadline_usec:
		_finish()

func is_done() -> bool:
	return _done

func get_move() -> Dictionary:
	return _selected_move.duplicate(true)

func _iteration() -> void:
	var node: Dictionary = _root
	var path: Array[Dictionary] = [_root]
	_ensure_untried(node)
	while not bool(node["state"].over) and (node["untried"] as Array).is_empty() and not (node["children"] as Array).is_empty():
		node = _best_child(node)
		path.append(node)
		_ensure_untried(node)
	if not bool(node["state"].over) and not (node["untried"] as Array).is_empty():
		var untried: Array = node["untried"]
		var move_index: int = _rng.randi_range(0, untried.size() - 1)
		var move: Dictionary = untried.pop_at(move_index)
		var next_state: TakState = (node["state"] as TakState).clone()
		next_state.apply_move(move)
		var child: Dictionary = {
			"state": next_state,
			"untried": [],
			"moves_ready": false,
			"children": [],
			"visits": 0,
			"score": 0.0,
			"move": move
		}
		(node["children"] as Array).append(child)
		node = child
		path.append(node)
	var result: float = _rollout(node["state"] as TakState)
	for cursor: Dictionary in path:
		cursor["visits"] = int(cursor["visits"]) + 1
		cursor["score"] = float(cursor["score"]) + result
	playouts += 1

func _ensure_untried(node: Dictionary) -> void:
	if bool(node["moves_ready"]):
		return
	var state: TakState = node["state"]
	node["untried"] = state.legal_moves()
	node["moves_ready"] = true

func _best_child(parent: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_value: float = -INF
	var maximizing: bool = (parent["state"] as TakState).current == _root_player
	for child_value: Variant in parent["children"]:
		var child: Dictionary = child_value
		var visits: int = int(child["visits"])
		if visits == 0:
			return child
		var exploitation: float = float(child["score"]) / float(visits)
		if not maximizing:
			exploitation = 1.0 - exploitation
		var exploration: float = UCB_C * sqrt(log(float(maxi(1, int(parent["visits"])))) / float(visits))
		var value: float = exploitation + exploration
		if value > best_value:
			best_value = value
			best = child
	return best

func _rollout(initial: TakState) -> float:
	var state: TakState = initial.clone()
	var interrupted: bool = false
	for ply: int in range(ROLLOUT_LIMIT):
		if state.over:
			break
		if ply % 8 == 0 and Time.get_ticks_usec() >= _chunk_end_usec:
			interrupted = not state.over
			break
		var move: Dictionary = state.random_move(_rng)
		if move.is_empty():
			break
		state.apply_move(move)
	if state.winner == _root_player:
		return 1.0
	if state.winner == 2:
		return 0.5
	if state.winner >= 0:
		return 0.0
	var root_flats: int = state.flats_count(_root_player)
	var other_flats: int = state.flats_count(1 - _root_player)
	if interrupted and root_flats == other_flats:
		return 0.5
	return 0.5 if root_flats == other_flats else (1.0 if root_flats > other_flats else 0.0)

func _finish() -> void:
	var best_child: Dictionary = {}
	var best_visits: int = -1
	for child_value: Variant in _root["children"]:
		var child: Dictionary = child_value
		if int(child["visits"]) > best_visits:
			best_visits = int(child["visits"])
			best_child = child
	if not best_child.is_empty():
		_selected_move = best_child["move"]
	_done = true
