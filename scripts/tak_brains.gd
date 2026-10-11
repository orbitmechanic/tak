class_name TakBrains
extends RefCounted

const RALPH: int = 0
const DEFENSIVE: int = 1
const OFFENSIVE: int = 2
const DEFENSE_FIRST: int = 3
const OFFENSE_FIRST: int = 4
const NAMES: Array[String] = ["Ralph", "Defensive", "Offensive", "Defense First", "Offense First"]

const CHUNK_SECONDS: float = 0.05

var brain: int = RALPH
var budget_seconds: float = 2.0
var playouts: int = 0

var _state: TakState
var _me: int = 0
var _phase: int = 0
var _done: bool = true
var _deadline_usec: int = 0
var _result: Dictionary = {}
var _my_moves: Array[Dictionary] = []
var _threats: Array[Dictionary] = []
var _i: int = 0
var _base_score: float = 0.0
var _best_score: float = 0.0
var _best_move: Dictionary = {}
var _ralph: MctsBot = MctsBot.new()

const PH_WIN: int = 0
const PH_THREATS: int = 1
const PH_BLOCK: int = 2
const PH_PROGRESS: int = 3
const PH_RALPH: int = 4

var _plan: Array[int] = []

func set_brain(value: int) -> void:
	brain = clampi(value, RALPH, OFFENSE_FIRST)

func start_thinking(state: TakState) -> void:
	_state = state
	_me = state.current
	_result = {}
	_playouts_reset()
	_deadline_usec = Time.get_ticks_usec() + int(maxf(0.05, budget_seconds) * 1000000.0)
	_plan = []
	match brain:
		DEFENSIVE:
			_plan = [PH_WIN, PH_THREATS, PH_BLOCK, PH_RALPH]
		OFFENSIVE:
			_plan = [PH_WIN, PH_PROGRESS, PH_RALPH]
		DEFENSE_FIRST:
			_plan = [PH_WIN, PH_THREATS, PH_BLOCK, PH_PROGRESS, PH_RALPH]
		OFFENSE_FIRST:
			_plan = [PH_WIN, PH_PROGRESS, PH_THREATS, PH_BLOCK, PH_RALPH]
		_:
			_start_ralph()
			return
	_my_moves = state.legal_moves()
	_i = 0
	_threats = []
	_best_move = {}
	_best_score = _base_score
	_phase = _plan.pop_front()
	_enter_phase()
	_done = false

func _playouts_reset() -> void:
	playouts = 0

func _enter_phase() -> void:
	_i = 0
	if _phase == PH_WIN:
		if _my_moves.is_empty():
			_advance()
	elif _phase == PH_THREATS:
		var opp: TakState = _state.clone()
		opp.current = 1 - _me
		_my_threat_moves = opp.legal_moves()
	elif _phase == PH_BLOCK:
		if _threats.is_empty():
			_advance()
	elif _phase == PH_PROGRESS:
		_base_score = _road_score(_state)
		_best_score = _base_score
		_best_move = {}
		if _my_moves.is_empty():
			_advance()
	elif _phase == PH_RALPH:
		_start_ralph()

var _my_threat_moves: Array[Dictionary] = []

func _start_ralph() -> void:
	var remaining: float = maxf(0.15, float(_deadline_usec - Time.get_ticks_usec()) / 1000000.0)
	_ralph = MctsBot.new()
	_ralph.budget_seconds = remaining
	_ralph.start_thinking(_state)
	_phase = PH_RALPH
	_done = false

func _advance() -> void:
	if _plan.is_empty():
		_start_ralph()
		return
	_phase = _plan.pop_front()
	_enter_phase()
	if _phase == PH_RALPH:
		pass

func tick() -> void:
	if _done:
		return
	if _phase == PH_RALPH:
		_ralph.tick()
		playouts = _ralph.playouts
		if _ralph.is_done():
			_result = _ralph.get_move()
			_done = true
		return
	var chunk_end: int = mini(_deadline_usec, Time.get_ticks_usec() + int(CHUNK_SECONDS * 1000000.0))
	while Time.get_ticks_usec() < chunk_end and not _done:
		var started: bool = _step_unit()
		if not started:
			if Time.get_ticks_usec() >= _deadline_usec:
				_start_ralph()
				return

func _step_unit() -> bool:
	match _phase:
		PH_WIN:
			if _i >= _my_moves.size():
				_advance()
				return true
			var win_move: Dictionary = _my_moves[_i]
			_i += 1
			playouts += 1
			var sim: TakState = _state.clone()
			sim.apply_move(win_move)
			if sim.over and sim.winner == _me:
				_result = win_move
				_done = true
			return true
		PH_THREATS:
			if _i >= _my_threat_moves.size():
				_advance()
				return true
			var opp_move: Dictionary = _my_threat_moves[_i]
			_i += 1
			var opp_state: TakState = _state.clone()
			opp_state.current = 1 - _me
			if opp_state.is_legal(opp_move):
				opp_state.apply_move(opp_move)
				if opp_state.over and opp_state.winner == 1 - _me:
					_threats.append(opp_move)
			return true
		PH_BLOCK:
			if _i >= _my_moves.size():
				if _best_move.is_empty():
					_advance()
				else:
					_result = _best_move
					_done = true
				return true
			var my_move: Dictionary = _my_moves[_i]
			_i += 1
			playouts += 1
			var after: TakState = _state.clone()
			after.apply_move(my_move)
			var still_losing: bool = false
			for threat: Dictionary in _threats:
				var t2: TakState = after.clone()
				if t2.current == 1 - _me and t2.is_legal(threat):
					t2.apply_move(threat)
					if t2.over and t2.winner == 1 - _me:
						still_losing = true
						break
			if not still_losing:
				_result = my_move
				_done = true
			return true
		PH_PROGRESS:
			if _i >= _my_moves.size():
				if _best_score > _base_score:
					_result = _best_move
					_done = true
				else:
					_advance()
				return true
			var prog_move: Dictionary = _my_moves[_i]
			_i += 1
			playouts += 1
			var next: TakState = _state.clone()
			next.apply_move(prog_move)
			var score: float = _road_score(next)
			if score > _best_score:
				_best_score = score
				_best_move = prog_move
			return true
		_:
			return false
	return false

func _road_score(st: TakState) -> float:
	var score: float = 0.0
	for player: int in [_me, 1 - _me]:
		var mask: int = 0
		for cell: int in range(25):
			if int(st.heights[cell]) == 0:
				continue
			if st.piece_owner(cell) != player:
				continue
			if not st._counts_in_road(st.piece_type(cell)):
				continue
			mask |= 1 << cell
		var sign: float = 1.0 if player == _me else -0.6
		for horizontal: bool in [true, false]:
			if not st._road_direction_allowed(player, horizontal):
				continue
			var visited: int = 0
			for cell: int in range(25):
				if (mask & (1 << cell)) == 0 or (visited & (1 << cell)) != 0:
					continue
				var group: int = 0
				var stack: Array[int] = [cell]
				var touches_left: bool = false
				var touches_right: bool = false
				var touches_top: bool = false
				var touches_bottom: bool = false
				while not stack.is_empty():
					var current: int = stack.pop_back()
					if (group & (1 << current)) != 0:
						continue
					group |= 1 << current
					var gx: int = current % 5
					var gy: int = int(current / 5)
					touches_left = touches_left or gx == 0
					touches_right = touches_right or gx == 4
					touches_top = touches_top or gy == 0
					touches_bottom = touches_bottom or gy == 4
					for neighbor: int in [current - 1 if gx > 0 else -1, current + 1 if gx < 4 else -1, current - 5 if gy > 0 else -1, current + 5 if gy < 4 else -1]:
						if neighbor >= 0 and (mask & (1 << neighbor)) != 0 and (group & (1 << neighbor)) == 0:
							stack.append(neighbor)
				visited |= group
				var contacts: int = 0
				if horizontal:
					contacts = (1 if touches_left else 0) + (1 if touches_right else 0)
				else:
					contacts = (1 if touches_top else 0) + (1 if touches_bottom else 0)
				var size: int = 0
				for bit: int in range(25):
					if (group & (1 << bit)) != 0:
						size += 1
				var value: float = float(size) + 3.0 * float(contacts) + 9.0 * float(contacts * contacts)
				if value >= 12.0 and contacts < 2:
					value -= float(size)
				score += sign * value
	return score

func blocking_moves(state: TakState) -> Array[Dictionary]:
	var defender: int = state.current
	var attacker: int = 1 - defender
	var threats: Array[Dictionary] = []
	var a_state: TakState = state.clone()
	a_state.current = attacker
	for m: Dictionary in a_state.legal_moves():
		var sim: TakState = a_state.clone()
		sim.apply_move(m)
		if sim.over and sim.winner == attacker:
			threats.append(m)
			if threats.size() >= 12:
				break
	var blocks: Array[Dictionary] = []
	if threats.is_empty():
		return blocks
	for mv: Dictionary in state.legal_moves():
		var after: TakState = state.clone()
		after.apply_move(mv)
		var still: bool = false
		for t: Dictionary in threats:
			var t2: TakState = after.clone()
			if t2.current == attacker and t2.is_legal(t):
				t2.apply_move(t)
				if t2.over and t2.winner == attacker:
					still = true
					break
		if not still:
			blocks.append(mv)
			if blocks.size() >= 10:
				break
	return blocks

func is_done() -> bool:
	return _done

func get_move() -> Dictionary:
	return _result.duplicate(true)
