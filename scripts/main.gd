extends Node2D

const TakState = preload("res://scripts/tak_state.gd")
const MctsBot = preload("res://scripts/mcts_bot.gd")
const CELL: float = 112.0
const BOARD_ORIGIN: Vector2 = Vector2(52.0, 126.0)
const BOARD_PIXELS: float = CELL * 5.0
var LIGHT_COLOR: Color = Color("#f5ecd4")
var DARK_COLOR: Color = Color("#1d5c55")
var PARCHMENT: Color = Color("#efe5cb")
var PARCHMENT_DEEP: Color = Color("#e6d9b8")
var BRONZE: Color = Color("#4f3f26")
var GOLD: Color = Color("#c9a227")
var GOLD_PALE: Color = Color("#dcc06a")
var SAGE_A: Color = Color("#aeb98e")
var SAGE_B: Color = Color("#a2b084")
var TEAL: Color = Color("#2e6b66")
var FRAME_MID: Color = Color("#6b5530")
var GRID_LINE: Color = Color(0.31, 0.25, 0.13, 0.55)
var LEGAL_HI: Color = Color(0.80, 0.64, 0.20, 0.32)
var TOPPLE_HI: Color = Color(0.18, 0.42, 0.40, 0.35)
var LABEL_BRIGHT: Color = Color("#f7efda")
var VEIL: Color = Color(0.16, 0.12, 0.05, 0.55)
var BANNER_BG: Color = Color(0.94, 0.89, 0.73, 0.95)
var BANNER_LINE: Color = Color(0.31, 0.25, 0.13, 0.5)
var BADGE_BG: Color = Color(0.15, 0.10, 0.06, 0.75)
var BADGE_RING: Color = Color("#f3e8ca")
var RIM_DARK: Color = Color("#8fae9f")
var PETAL_D: Color = Color("#e9f2ea", 0.3)
var TEXT_INK: Color = Color("#3e3524")
var TEXT_HEADING: Color = Color("#8a6d1f")
var TEXT_STATUS: Color = Color("#4a3b22")
var TEXT_RESERVE: Color = Color("#3e5248")
var TEXT_HELP: Color = Color("#5a5136")
var THEME_BG: Color = Color("#ecdfbe")
var THEME_HOVER: Color = Color("#f6edd3")
var THEME_TEXT: Color = Color("#3e3524")
var THEME_HOVER_TEXT: Color = Color("#233a35")
var THEME_PRESSED_TEXT: Color = Color("#f2e9d4")
var THEME_DISABLED_TEXT: Color = Color("#a29075")
var DECO_LINE: Color = Color(0.30, 0.24, 0.08, 0.16)
const STONE_FLIGHT: float = 0.28
const SFX_PLACE = preload("res://assets/sounds/place.wav")
const SFX_MOVE = preload("res://assets/sounds/move.wav")
const SFX_TICK = preload("res://assets/sounds/tick.wav")
const SFX_FLATTEN = preload("res://assets/sounds/flatten.wav")
const SFX_WIN = preload("res://assets/sounds/win.wav")
const SFX_LOSE = preload("res://assets/sounds/lose.wav")
const SFX_DRAW = preload("res://assets/sounds/draw.wav")
const SFX_UNDO = preload("res://assets/sounds/undo.wav")
const TOPPLE_STAGGER: float = 0.09
const PLACE_POP: float = 0.22

var state: TakState = TakState.new()
var bots: Array[TakBrains] = [TakBrains.new(), TakBrains.new()]
var current_brain: int = 0
var brain_popup: Control
var brain_radios: Array[CheckButton] = []
var hint_inst: TakBrains = null
var hint_state: int = 0
var hint_flash: Dictionary = {}
var hint_entries: Array[Dictionary] = []
var hint_time: float = 0.0
var hint_length: float = 0.0
var hint_cells: Array[int] = []
var court_cells: Array[int] = []
var spectate_wait: float = 5.0
var court_label: Label
var hint_def_button: Button
var hint_off_button: Button
const HINT_IDLE: int = 0
const HINT_COMPUTE: int = 1
const HINT_FLASH: int = 2
const HINT_SHOW: int = 3
var mode: int = 0
var bot_thinking: bool = false
var active_bot: int = -1
var piece_choice: int = TakState.FLAT
var selected_from: int = -1
var legal_destinations: Array[int] = []
var topple_options: Dictionary = {}
var undo_states: Array[TakState] = []
var undo_actors: Array[int] = []
var undo_visuals: Array[Dictionary] = []
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_i: int = 0
var muted: bool = false
var anim_entries: Array[Dictionary] = []
var anim_time: float = 0.0
var anim_length: float = 0.0
var indicator_cells: Array[int] = []
var clock: float = 0.0
var hud: Control
var app_theme: Theme
var dark_mode: bool = false
var rules: Array[bool] = [false, false, false, false, false]
var role_labels: Array[Dictionary] = []
var rule_popup: Control
var rule_checks: Array[CheckButton] = []
var move_label: Label
var topple_label: Label
var wall_label: Label
var win_label: Label
var house_list_label: Label
var hint_label: Label
var house_note_label: Label
var status_label: Label
var reserve_label: Label
var undo_button: Button
var tool_buttons: Array[Button] = []

func _sfx(kind: String, pitch: float = 1.0) -> void:
	if muted:
		return
	var stream: AudioStream = SFX_PLACE
	var vol: float = -5.0
	match kind:
		"place":
			stream = SFX_PLACE
		"move":
			stream = SFX_MOVE
			vol = -6.0
		"tick":
			stream = SFX_TICK
			vol = -8.0
		"flatten":
			stream = SFX_FLATTEN
			vol = -3.0
		"win":
			stream = SFX_WIN
			vol = -2.0
		"lose":
			stream = SFX_LOSE
			vol = -2.0
		"draw":
			stream = SFX_DRAW
			vol = -2.0
		"undo":
			stream = SFX_UNDO
			vol = -9.0
	var player: AudioStreamPlayer = sfx_pool[sfx_i % sfx_pool.size()]
	sfx_i += 1
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.6, 1.6)
	player.volume_db = vol
	player.play()

func _ready() -> void:
	for i: int in range(8):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		sfx_pool.append(player)
	bots[0].budget_seconds = 2.0
	bots[1].budget_seconds = 2.0
	_build_hud()
	_update_hud()
	queue_redraw()

func _bot_should_act() -> bool:
	if mode == 1 or state.over:
		return false
	return mode == 2 or state.current == 1

func _process(delta: float) -> void:
	clock += delta
	_process_hint(delta)
	if mode == 2 and state.over and not bot_thinking:
		spectate_wait -= delta
		status_label.text = "New game in %d..." % int(ceilf(spectate_wait))
		if spectate_wait <= 0.0:
			_new_game()
			return
	if hint_state != HINT_IDLE or not court_cells.is_empty():
		queue_redraw()
	if anim_entries.is_empty():
		if not indicator_cells.is_empty():
			queue_redraw()
	else:
		anim_time += delta
		for e: Dictionary in anim_entries:
			if not bool(e.get("fired", false)) and anim_time >= float(e["t0"]) + float(e["dur"]):
				e["fired"] = true
				_sfx(str(e.get("sfx", "tick")), float(e.get("pitch", 1.0)))
		if anim_time >= anim_length:
			anim_entries = []
		queue_redraw()
	if bot_thinking:
		var bot: TakBrains = bots[active_bot]
		bot.tick()
		status_label.text = "Bot %s thinking... %d playouts" % ["A" if active_bot == 0 else "B", bot.playouts]
		undo_button.disabled = true
		if bot.is_done():
			bot_thinking = false
			var move: Dictionary = bot.get_move()
			if not move.is_empty() and state.is_legal(move):
				_commit_move(move)
			else:
				var fallback: Array[Dictionary] = state.legal_moves()
				if not fallback.is_empty():
					_commit_move(fallback[randi_range(0, fallback.size() - 1)])
				else:
					_update_hud()

func _cell_center(cell: int) -> Vector2:
	return BOARD_ORIGIN + Vector2((cell % 5) * CELL + CELL / 2.0, int(cell / 5) * CELL + CELL / 2.0)

func _build_plan(move: Dictionary) -> Dictionary:
	var entries: Array[Dictionary] = []
	var cells_touched: Array[int] = []
	var kind: String = str(move.get("kind", ""))
	if kind == "place":
		var cell: int = int(move["cell"])
		var owner: int = state.current if state.opening_done[state.current] != 0 else 1 - state.current
		entries.append({"piece": owner * 3 + int(move["piece_type"]), "from": cell, "to": cell, "t0": 0.0, "dur": PLACE_POP, "pop": true, "sfx": "place"})
		cells_touched.append(cell)
	elif kind == "move":
		var from: int = int(move["from"])
		var dest: int = state._neighbor(from, int(move["dir"]), 1)
		var sfx_kind: String = "flatten" if state.piece_type(dest) == TakState.WALL else "move"
		entries.append({"piece": int(state.cells[from * TakState.MAX_STACK]), "from": from, "to": dest, "t0": 0.0, "dur": STONE_FLIGHT, "pop": false, "sfx": sfx_kind, "layer": 0})
		cells_touched.append(from)
		cells_touched.append(dest)
	elif kind == "peel":
		var origin_p: int = int(move["from"])
		var dest_p: int = state.peel_landing(origin_p, int(move["dir"]))
		var layer_p: int = int(state.heights[origin_p]) - 1
		var sfx_p: String = "flatten" if state.piece_type(dest_p) == TakState.WALL else "move"
		entries.append({"piece": int(state.cells[origin_p * TakState.MAX_STACK + layer_p]), "from": origin_p, "to": dest_p, "t0": 0.0, "dur": STONE_FLIGHT, "pop": false, "sfx": sfx_p, "layer": layer_p})
		cells_touched.append(origin_p)
		cells_touched.append(dest_p)
	elif kind == "topple":
		var origin: int = int(move["from"])
		var landing: Array[int] = state.topple_landing_cells(origin, int(move["dir"]))
		for i: int in range(landing.size()):
			entries.append({"piece": int(state.cells[origin * TakState.MAX_STACK + i]), "from": origin, "to": landing[i], "t0": float(i) * TOPPLE_STAGGER, "dur": STONE_FLIGHT, "pop": false, "sfx": "tick", "pitch": 0.94 + 0.05 * i, "layer": i})
			cells_touched.append(landing[i])
		cells_touched.append(origin)
	var total: float = 0.0
	for e: Dictionary in entries:
		total = maxf(total, float(e["t0"]) + float(e["dur"]))
	return {"entries": entries, "cells": cells_touched, "length": total + 0.05}

func _start_animation(plan: Dictionary) -> void:
	anim_entries = plan["entries"]
	anim_length = float(plan["length"])
	anim_time = 0.0
	indicator_cells = plan["cells"]

func _unarrived_at(cell: int) -> int:
	var count: int = 0
	for e: Dictionary in anim_entries:
		if int(e["to"]) == cell and anim_time < float(e["t0"]) + float(e["dur"]):
			count += 1
	return count

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		match key.keycode:
			KEY_F:
				_select_tool(TakState.FLAT)
			KEY_W:
				_select_tool(TakState.WALL)
			KEY_C:
				_select_tool(TakState.CAPSTONE)
			KEY_ESCAPE:
				_clear_selection()
			KEY_Z:
				if key.ctrl_pressed:
					_undo()
			KEY_M:
				muted = not muted
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if bot_thinking or state.over or mode == 2:
			return
		if mode == 0 and state.current == 1:
			return
		var position: Vector2 = event.position
		if position.x < BOARD_ORIGIN.x or position.y < BOARD_ORIGIN.y or position.x >= BOARD_ORIGIN.x + BOARD_PIXELS or position.y >= BOARD_ORIGIN.y + BOARD_PIXELS:
			return
		var x: int = int((position.x - BOARD_ORIGIN.x) / CELL)
		var y: int = int((position.y - BOARD_ORIGIN.y) / CELL)
		_on_cell_clicked(y * 5 + x)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), PARCHMENT)
	draw_rect(Rect2(0, get_viewport_rect().size.y - 46, get_viewport_rect().size.x, 46), PARCHMENT_DEEP)
	draw_rect(Rect2(BOARD_ORIGIN - Vector2(16, 16), Vector2(BOARD_PIXELS + 32, BOARD_PIXELS + 32)), BRONZE)
	draw_rect(Rect2(BOARD_ORIGIN - Vector2(11, 11), Vector2(BOARD_PIXELS + 22, BOARD_PIXELS + 22)), FRAME_MID)
	draw_rect(Rect2(BOARD_ORIGIN - Vector2(9, 9), Vector2(BOARD_PIXELS + 18, BOARD_PIXELS + 18)), GOLD, false, 1.6)
	draw_rect(Rect2(BOARD_ORIGIN, Vector2(BOARD_PIXELS, BOARD_PIXELS),), SAGE_A)
	for i: int in range(20):
		var bx: float = BOARD_ORIGIN.x + 14.5 + float(i) * (BOARD_PIXELS - 29.0) / 19.0
		draw_circle(Vector2(bx, BOARD_ORIGIN.y - 13.5), 2.2, GOLD_PALE)
		draw_circle(Vector2(bx, BOARD_ORIGIN.y + BOARD_PIXELS + 13.5), 2.2, GOLD_PALE)
	for i: int in range(20):
		var by: float = BOARD_ORIGIN.y + 14.5 + float(i) * (BOARD_PIXELS - 29.0) / 19.0
		draw_circle(Vector2(BOARD_ORIGIN.x - 13.5, by), 2.2, GOLD_PALE)
		draw_circle(Vector2(BOARD_ORIGIN.x + BOARD_PIXELS + 13.5, by), 2.2, GOLD_PALE)
	for corner: Vector2 in [BOARD_ORIGIN - Vector2(13.5, 13.5), BOARD_ORIGIN + Vector2(BOARD_PIXELS + 13.5, 13.5), BOARD_ORIGIN + Vector2(13.5, BOARD_PIXELS + 13.5), BOARD_ORIGIN + Vector2(BOARD_PIXELS + 13.5, BOARD_PIXELS + 13.5)]:
		_rosette(corner, 7.0)
	for cell: int in range(25):
		var x: int = cell % 5
		var y: int = int(cell / 5)
		var rect: Rect2 = Rect2(BOARD_ORIGIN + Vector2(x * CELL, y * CELL), Vector2(CELL, CELL))
		draw_rect(rect, SAGE_A if (x + y) % 2 == 0 else SAGE_B)
		_draw_deco_motif(rect, (x + y) % 2 == 0)
		if cell in legal_destinations:
			draw_rect(rect.grow(-7), LEGAL_HI)
			if selected_from >= 0 and state.piece_type(cell) == TakState.WALL and int(state.heights[selected_from]) == 1 and state.piece_type(selected_from) == TakState.CAPSTONE:
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(22, CELL - 9), "FLATTEN", HORIZONTAL_ALIGNMENT_LEFT, 72, 12, TEXT_INK)
		if cell in court_cells:
			draw_rect(rect.grow(-5), Color(0.16, 0.50, 0.46, 0.22 + 0.16 * (0.5 + 0.5 * sin(clock * 3.0))))
		if cell in hint_cells:
			draw_rect(rect.grow(-7), Color(0.23, 0.56, 0.29, 0.36))
		if topple_options.has(cell):
			draw_rect(rect.grow(-7), TOPPLE_HI)
			if bool(topple_options[cell]["last"]):
				draw_rect(rect.grow(-4), Color(GOLD, 0.95), false, 3.0)
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, CELL - 9), "TOPPLE", HORIZONTAL_ALIGNMENT_LEFT, 100, 12, LABEL_BRIGHT)
		if cell == selected_from:
			draw_rect(rect.grow(-4), Color(GOLD_PALE, 0.55))
		draw_rect(rect, GRID_LINE, false, 1.4)
		_draw_stack(cell, rect)
	if anim_entries.is_empty() and not indicator_cells.is_empty():
		var pulse: float = 0.5 + 0.5 * sin(clock * 4.0)
		for cell: int in indicator_cells:
			if int(state.heights[cell]) == 0:
				draw_rect(Rect2(BOARD_ORIGIN + Vector2((cell % 5) * CELL, int(cell / 5) * CELL), Vector2(CELL, CELL)).grow(-3), Color(GOLD, 0.25 + 0.35 * pulse), false, 3.0)
			else:
				draw_arc(_cell_center(cell), 44.0, 0.0, TAU, 40, Color(GOLD, 0.30 + 0.40 * pulse), 3.0, true)
	for e: Dictionary in anim_entries:
		var t0: float = float(e["t0"])
		var dur: float = float(e["dur"])
		var raw: float = clampf((anim_time - t0) / dur, 0.0, 1.0)
		if raw <= 0.0:
			raw = 0.0
		if anim_time < t0:
			raw = 0.0
		var scale: float
		var pos: Vector2
		if bool(e["pop"]):
			var u: float = raw - 1.0
			scale = clampf(1.0 + 2.70158 * u * u * u + 1.70158 * u * u, 0.05, 2.0)
			pos = _cell_center(int(e["to"]))
		else:
			var ease_t: float = 1.0 - pow(1.0 - raw, 2.0)
			pos = _cell_center(int(e["from"])).lerp(_cell_center(int(e["to"])), ease_t)
			pos.y -= sin(raw * PI) * 20.0
			scale = 1.0 + 0.14 * sin(raw * PI)
		if raw < 1.0:
			_draw_piece_at(int(e["piece"]), pos, scale, 1.0 - raw)
	var band_lr: Color = TEAL if rules[2] else LIGHT_COLOR
	var band_tb: Color = TEAL
	if hint_state == HINT_FLASH:
		var frect: Rect2 = Rect2(BOARD_ORIGIN + Vector2((int(hint_flash["cell"]) % 5) * CELL, int(int(hint_flash["cell"]) / 5) * CELL), Vector2(CELL, CELL))
		var t: float = hint_time
		var falpha: float = (0.5 + 0.4 * sin(t * 9.0)) * clampf((3.2 - t) / 0.5, 0.0, 1.0)
		var fcolor: Color = LIGHT_COLOR if int(hint_flash["owner"]) == 0 else DARK_COLOR
		var fc: Vector2 = frect.get_center()
		if int(hint_flash["type"]) == TakState.FLAT:
			draw_arc(fc, 36.0, 0.0, TAU, 48, Color(fcolor, falpha), 3.5, true)
			draw_arc(fc, 30.0, 0.0, TAU, 48, Color(GOLD, falpha * 0.8), 1.5, true)
		elif int(hint_flash["type"]) == TakState.WALL:
			draw_rect(Rect2(fc + Vector2(-20, -33), Vector2(40, 66)), Color(fcolor, falpha), false, 3.5)
			draw_rect(Rect2(fc + Vector2(-15, -28), Vector2(30, 56)), Color(GOLD, falpha * 0.8), false, 1.5)
		else:
			draw_rect(Rect2(fc + Vector2(-29, -29), Vector2(58, 58)), Color(fcolor, falpha), false, 3.5)
			draw_line(fc + Vector2(-16, -16), fc + Vector2(16, 16), Color(fcolor, falpha), 2.5)
			draw_line(fc + Vector2(16, -16), fc + Vector2(-16, 16), Color(fcolor, falpha), 2.5)
	if hint_state == HINT_SHOW:
		for e: Dictionary in hint_entries:
			var raw: float = (hint_time - float(e["t0"])) / float(e["dur"])
			if raw <= 0.0 or raw >= 1.0:
				continue
			var ease_t: float = 1.0 - pow(1.0 - raw, 2.0)
			var pos: Vector2 = _cell_center(int(e["from"])).lerp(_cell_center(int(e["to"])), ease_t)
			pos.y -= sin(raw * PI) * 20.0
			_draw_piece_at(int(e["piece"]), pos, 1.0 + 0.14 * sin(raw * PI), 1.0 - raw)
	draw_rect(Rect2(BOARD_ORIGIN - Vector2(9, 0), Vector2(9, BOARD_PIXELS)), band_lr)
	draw_rect(Rect2(BOARD_ORIGIN + Vector2(BOARD_PIXELS, 0), Vector2(9, BOARD_PIXELS)), band_lr)
	draw_rect(Rect2(BOARD_ORIGIN, Vector2(BOARD_PIXELS, 9)), band_tb)
	draw_rect(Rect2(BOARD_ORIGIN + Vector2(0, BOARD_PIXELS), Vector2(BOARD_PIXELS, 9)), band_tb)
	for i: int in range(20):
		var gy: float = BOARD_ORIGIN.y + 14.0 + float(i) * (BOARD_PIXELS - 28.0) / 19.0
		draw_circle(Vector2(BOARD_ORIGIN.x - 4.5, gy), 1.6, GOLD_PALE)
		draw_circle(Vector2(BOARD_ORIGIN.x + BOARD_PIXELS + 4.5, gy), 1.6, GOLD_PALE)
	for i: int in range(20):
		var gx: float = BOARD_ORIGIN.x + 14.0 + float(i) * (BOARD_PIXELS - 28.0) / 19.0
		draw_circle(Vector2(gx, BOARD_ORIGIN.y - 4.5), 1.6, GOLD_PALE)
		draw_circle(Vector2(gx, BOARD_ORIGIN.y + BOARD_PIXELS + 4.5), 1.6, GOLD_PALE)
	_draw_nouveau_ornament()
	if state.over:
		draw_rect(Rect2(BOARD_ORIGIN, Vector2(BOARD_PIXELS, BOARD_PIXELS)), VEIL)
		var winning_cells: Array[int] = []
		if state.winner < 2:
			winning_cells = state.road_cells(state.winner)
		for cell: int in winning_cells:
			var rect: Rect2 = Rect2(BOARD_ORIGIN + Vector2((cell % 5) * CELL, int(cell / 5) * CELL), Vector2(CELL, CELL))
			draw_rect(rect.grow(-10), Color(0.92, 0.78, 0.25, 0.52))
		var result: String = "DRAW" if state.winner == 2 else ("LIGHT WINS" if state.winner == 0 else "DARK WINS")
		var banner: Rect2 = Rect2(BOARD_ORIGIN + Vector2(105, 236), Vector2(350, 96))
		draw_rect(banner, BANNER_BG)
		draw_rect(banner.grow(-6), Color(GOLD, 0.9), false, 2.0)
		draw_rect(banner.grow(-11), BANNER_LINE, false, 1.0)
		draw_string(ThemeDB.fallback_font, banner.position + Vector2(0, 62), result, HORIZONTAL_ALIGNMENT_CENTER, banner.size.x, 32, TEXT_INK)
		_rosette(banner.position + Vector2(20, 48), 6.0)
		_rosette(banner.end - Vector2(20, 48), 6.0)

func _bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps + 1):
		var t: float = float(i) / steps
		var u: float = 1.0 - t
		pts.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
	return pts

func _curve(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Color, width: float) -> void:
	draw_polyline(_bezier_points(p0, p1, p2, p3, 26), color, width, true)

func _leaf(pos: Vector2, angle: float, length: float, color: Color) -> void:
	draw_set_transform(pos, angle, Vector2(1.0, 0.42))
	draw_circle(Vector2(length * 0.5, 0), length * 0.5, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _rosette(center: Vector2, size: float) -> void:
	for k: int in range(6):
		_leaf(center, float(k) * PI / 3.0, size * 2.1, GOLD_PALE)
	draw_circle(center, size * 0.62, TEAL)
	draw_circle(center, size * 0.3, GOLD)

func _draw_nouveau_ornament() -> void:
	_curve(Vector2(208, 8), Vector2(260, 26), Vector2(330, -4), Vector2(430, 12), GOLD, 1.4)
	_leaf(Vector2(250, 14), -0.5, 11.0, SAGE_B)
	_leaf(Vector2(402, 8), 2.6, 11.0, SAGE_B)
	var stem_base: Vector2 = Vector2(1064.0, 744.0)
	_curve(stem_base, Vector2(1052, 692), Vector2(1082, 660), Vector2(1062, 616), TEAL, 2.0)
	_curve(Vector2(1062, 616), Vector2(1054, 594), Vector2(1072, 584), Vector2(1064, 566), GOLD, 1.4)
	_leaf(Vector2(1060, 662), -1.9, 20.0, SAGE_B)
	_leaf(Vector2(1066, 634), 1.15, 17.0, Color(TEAL, 0.75))
	_leaf(Vector2(1058, 700), -1.2, 22.0, SAGE_B)
	_lily(Vector2(1064, 560), 10.0)
	_lily(Vector2(60, 646), 9.0)
	_rosette(Vector2(1040.0, 752.0), 5.0)
	_rosette(Vector2(1088.0, 752.0), 5.0)

func _lily(center: Vector2, size: float) -> void:
	for k: int in range(5):
		var ang: float = -PI / 2.0 + float(k - 2) * 0.52
		_leaf(center, ang, size * 2.4, Color("#f4ecd6"))
		_leaf(center, ang, size * 2.4, Color(GOLD, 0.25))
	draw_circle(center, size * 0.32, GOLD)
	draw_arc(center, size * 2.35, -PI * 0.9, -PI * 0.1, 20, Color(TEAL, 0.7), 1.6, true)

func _draw_deco_motif(rect: Rect2, low_cell: bool) -> void:
	var origin: Vector2 = rect.position if not low_cell else rect.end
	var base_angle: float = 0.0 if not low_cell else PI
	var radius: float = CELL * 0.44
	for i: int in range(7):
		var angle: float = base_angle + (float(i) / 6.0) * PI * 0.5
		draw_line(origin, origin + Vector2(cos(angle), sin(angle)) * radius, DECO_LINE, 1.2)
	for k: float in [0.34, 0.67, 1.0]:
		draw_arc(origin, radius * k, base_angle, base_angle + PI * 0.5, 12, DECO_LINE, 1.0, true)
	var nub: float = 5.0
	var sign_v: Vector2 = Vector2(1, 1) if not low_cell else Vector2(-1, -1)
	draw_rect(Rect2(origin, sign_v * nub * 2.0).abs(), Color(DECO_LINE, DECO_LINE.a * 0.8), false, 1.0)
	draw_rect(Rect2(origin, sign_v * nub).abs(), Color(DECO_LINE, DECO_LINE.a * 0.8), false, 1.0)

func _draw_stack(cell: int, rect: Rect2) -> void:
	var height: int = int(state.heights[cell])
	if height == 0:
		return
	var center: Vector2 = rect.get_center()
	if hint_state == HINT_SHOW:
		var hidden: Array[bool] = []
		hidden.resize(height)
		for e: Dictionary in hint_entries:
			if int(e["from"]) == cell and hint_time >= float(e["t0"]) and hint_time < float(e["t0"]) + float(e["dur"]):
				var hl: int = int(e.get("layer", height - 1))
				if hl >= 0 and hl < height:
					hidden[hl] = true
		var vis: Array[int] = []
		for l: int in range(height):
			if not hidden[l]:
				vis.append(l)
		var shown: int = mini(vis.size(), 5)
		for index: int in range(shown):
			var layer: int = vis[vis.size() - shown + index]
			var encoded: int = int(state.cells[cell * TakState.MAX_STACK + layer])
			_draw_piece_at(encoded, center + Vector2(0, -float(index) * 7.0), 1.0, 0.0)
		if height > 2:
			_draw_height_badge(cell, rect)
		return
	var unarrived: int = _unarrived_at(cell)
	var draw_count: int = maxi(0, height - unarrived)
	var visible: int = mini(draw_count, 5)
	for index: int in range(visible):
		var layer: int = draw_count - visible + index
		var encoded: int = int(state.cells[cell * TakState.MAX_STACK + layer])
		var shift: Vector2 = Vector2(0, -float(index) * 7.0)
		_draw_piece_at(encoded, center + shift, 1.0, 0.0)
	if height > 2:
		_draw_height_badge(cell, rect)

func _draw_height_badge(_cell: int, rect: Rect2) -> void:
	var badge_center: Vector2 = rect.position + Vector2(CELL - 15, 15)
	draw_circle(badge_center, 11, BADGE_BG)
	draw_arc(badge_center, 9.5, 0.0, TAU, 24, Color(BADGE_RING, 0.75), 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(CELL - 20, 20), str(int(state.heights[_cell])), HORIZONTAL_ALIGNMENT_CENTER, 10, 13, LABEL_BRIGHT)

func _draw_piece_at(encoded: int, center: Vector2, scale: float, shadow_depth: float) -> void:
	_piece_scale = scale
	_piece_center = center
	draw_set_transform(center, 0.0, Vector2(scale, scale))
	_draw_piece_local(encoded, shadow_depth)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

var _piece_scale: float = 1.0
var _piece_center: Vector2 = Vector2.ZERO

func _local_leaf(local_pos: Vector2, angle: float, length: float, color: Color) -> void:
	var scale_v: Vector2 = Vector2(_piece_scale, _piece_scale * 0.42)
	draw_set_transform(_piece_center + _piece_scale * local_pos, angle, scale_v)
	draw_circle(Vector2(length * 0.5, 0), length * 0.5, color)
	draw_set_transform(_piece_center, 0.0, Vector2(_piece_scale, _piece_scale))

func _local_ellipse(local_pos: Vector2, radius: float, squash: float, color: Color) -> void:
	draw_set_transform(_piece_center + _piece_scale * local_pos, 0.0, Vector2(_piece_scale, _piece_scale * squash))
	draw_circle(Vector2.ZERO, radius, color)
	draw_set_transform(_piece_center, 0.0, Vector2(_piece_scale, _piece_scale))

func _draw_piece_local(encoded: int, shadow_depth: float) -> void:
	var owner: int = int(encoded / 3)
	var kind: int = encoded % 3
	var base: Color = LIGHT_COLOR if owner == 0 else DARK_COLOR
	var fade: float = 1.0 - shadow_depth * 0.35
	if kind == TakState.FLAT:
		var radius: float = 34.0
		_local_ellipse(Vector2(5, 8), radius + 2.0, 0.5, Color(0.20, 0.13, 0.06, 0.30 * fade))
		draw_circle(Vector2(0, 5), radius, base.darkened(0.55))
		draw_circle(Vector2.ZERO, radius, base)
		var toward_light: Vector2 = Vector2(-1, -1).normalized()
		for i: int in range(8):
			var amount: float = float(i) / 7.0
			draw_circle(toward_light * float(i) * 1.2, radius - float(i) * 3.4, base.lightened(0.28).lerp(base, amount))
		_local_ellipse(Vector2(-radius * 0.38, -radius * 0.42), 9.0, 0.62, Color(1.0, 1.0, 0.95, 0.35))
		draw_arc(Vector2.ZERO, radius - 1.5, PI * 0.10, PI * 0.90, 24, base.darkened(0.5), 2.0, true)
		var rim: Color = Color(GOLD, 0.95) if owner == 0 else RIM_DARK
		draw_arc(Vector2.ZERO, radius - 0.5, 0.0, TAU, 52, rim, 2.6, true)
		draw_arc(Vector2.ZERO, radius - 6.0, 0.0, TAU, 48, Color(GOLD, 0.4 * fade), 1.3, true)
		for petal: int in range(3):
			_local_leaf(Vector2.ZERO, float(petal) * TAU / 3.0 - PI / 2.0, radius * 0.52, Color(GOLD, 0.42 * fade) if owner == 0 else Color(PETAL_D, PETAL_D.a * fade / 0.3))
	elif kind == TakState.WALL:
		var face: Rect2 = Rect2(Vector2(-19, -32), Vector2(38, 64))
		_local_ellipse(Vector2(4, 6), 22.0, 0.38, Color(0.20, 0.13, 0.06, 0.30 * fade))
		_draw_rounded_rect(face.position + Vector2(5, 0), face.size, 8.0, base.darkened(0.55))
		_draw_rounded_rect(face.position, face.size, 8.0, base)
		var face_w: float = face.size.x
		for slice: int in range(6):
			var tx: float = (float(slice) + 0.5) / 6.0
			var shade: float = 1.0 - 0.45 * absf(tx - 0.3)
			var slice_color: Color = base.lightened(0.30).lerp(base.darkened(0.40), 1.0 - shade)
			var slice_rect: Rect2 = Rect2(face.position + Vector2(face_w * float(slice) / 6.0, 8.0), Vector2(face_w / 6.0 + 0.25, face.size.y - 16.0))
			draw_rect(slice_rect, slice_color)
		draw_line(face.position + Vector2(3, 3), face.position + Vector2(face_w - 3, 3), Color(base.lightened(0.4), 0.5), 2.0)
	else:
		var square: Rect2 = Rect2(Vector2(-28, -28), Vector2(56, 56))
		_local_ellipse(Vector2(4, 7), 33.0, 0.45, Color(0.20, 0.13, 0.06, 0.30 * fade))
		_draw_rounded_rect(square.position + Vector2(0, 5), square.size, 8.0, base.darkened(0.5))
		_draw_rounded_rect(square.position, square.size, 8.0, base)
		var bevel: Rect2 = square.grow(-7)
		_draw_rounded_rect(bevel.position, bevel.size, 5.0, base.lightened(0.22))
		draw_rect(Rect2(bevel.position + Vector2(0, bevel.size.y * 0.5), Vector2(bevel.size.x, bevel.size.y * 0.5)), base.darkened(0.12))
		draw_rect(Rect2(bevel.position.x, bevel.end.y - 5.0, 5.0, 5.0), base)
		draw_rect(Rect2(bevel.end.x - 5.0, bevel.end.y - 5.0, 5.0, 5.0), base)
		draw_circle(bevel.position + Vector2(5, bevel.size.y - 5), 5.0, base.darkened(0.12))
		draw_circle(bevel.end + Vector2(-5, -5), 5.0, base.darkened(0.12))
		draw_line(bevel.position + Vector2(3, bevel.size.y * 0.5), Vector2(bevel.end.x - 3, bevel.position.y + bevel.size.y * 0.5), base.darkened(0.28), 1.0)
		draw_arc(square.get_center(), 18.0, -PI * 0.95, -PI * 0.05, 24, base.lightened(0.35), 2.0, true)
		var inset: float = 12.0
		var corner_a: Vector2 = Vector2(-28, -28)
		var corner_b: Vector2 = Vector2(28, 28)
		var off_l: Vector2 = Vector2(inset + 1.2, inset + 1.2)
		var x_color_light: Color = Color(base.lightened(0.30), 0.55)
		draw_line(corner_a + off_l, corner_b - off_l, x_color_light, 6.0)
		draw_line(Vector2(corner_b.x - off_l.x, corner_a.y + off_l.y), Vector2(corner_a.x + off_l.x, corner_b.y - off_l.y), x_color_light, 6.0)
		draw_line(corner_a + Vector2(inset, inset), corner_b - Vector2(inset, inset), base.darkened(0.55), 4.5)
		draw_line(Vector2(corner_b.x - inset, corner_a.y + inset), Vector2(corner_a.x + inset, corner_b.y - inset), base.darkened(0.55), 4.5)

func _draw_rounded_rect(position: Vector2, size: Vector2, corner_radius: float, color: Color) -> void:
	var radius: float = minf(corner_radius, minf(size.x, size.y) * 0.5)
	draw_rect(Rect2(position + Vector2(radius, 0), Vector2(size.x - radius * 2.0, size.y)), color)
	draw_rect(Rect2(position + Vector2(0, radius), Vector2(size.x, size.y - radius * 2.0)), color)
	draw_circle(position + Vector2(radius, radius), radius, color)
	draw_circle(position + Vector2(size.x - radius, radius), radius, color)
	draw_circle(position + Vector2(radius, size.y - radius), radius, color)
	draw_circle(position + Vector2(size.x - radius, size.y - radius), radius, color)

func _make_nouveau_theme() -> Theme:
	var theme: Theme = Theme.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = THEME_BG
	box.border_color = Color(GOLD, 0.8)
	box.set_border_width_all(2)
	box.set_corner_radius_all(9)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	var hover: StyleBoxFlat = box.duplicate()
	hover.bg_color = THEME_HOVER
	var pressed: StyleBoxFlat = box.duplicate()
	pressed.bg_color = TEAL
	var disabled: StyleBoxFlat = box.duplicate()
	disabled.bg_color = Color(THEME_BG, 0.45)
	disabled.border_color = Color(GOLD, 0.3)
	theme.set_stylebox("normal", "Button", box)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("normal", "OptionButton", box)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", pressed)
	theme.set_stylebox("selected", "OptionButton", pressed)
	theme.set_stylebox("disabled", "OptionButton", disabled)
	theme.set_stylebox("panel", "PopupPanel", box)
	theme.set_stylebox("panel", "Panel", box)
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for kind: String in ["normal", "hover", "pressed", "disabled", "focused"]:
		theme.set_stylebox(kind, "CheckButton", empty)
	theme.set_color("font_color", "Button", THEME_TEXT)
	theme.set_color("font_hover_color", "Button", THEME_HOVER_TEXT)
	theme.set_color("font_pressed_color", "Button", THEME_PRESSED_TEXT)
	theme.set_color("font_disabled_color", "Button", Color("#a2977a"))
	theme.set_color("font_color", "OptionButton", THEME_TEXT)
	theme.set_color("font_hover_color", "OptionButton", THEME_HOVER_TEXT)
	theme.set_color("font_pressed_color", "OptionButton", THEME_PRESSED_TEXT)
	theme.set_color("font_color", "Label", THEME_TEXT)
	theme.set_color("font_color", "CheckBox", THEME_TEXT)
	theme.set_color("font_hover_color", "CheckBox", THEME_HOVER_TEXT)
	theme.set_color("font_pressed_color", "CheckBox", THEME_HOVER_TEXT)
	theme.set_color("font_hover_color", "CheckBox", THEME_HOVER_TEXT)
	theme.set_color("font_focus_color", "CheckBox", THEME_HOVER_TEXT)
	return theme

func _build_hud() -> void:
	app_theme = _make_nouveau_theme()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.theme = app_theme
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	_add_label("TAK", Vector2(58, 18), Vector2(120, 42), 30, "ink")
	status_label = _add_label("", Vector2(196, 34), Vector2(390, 26), 16, "status")
	reserve_label = _add_label("", Vector2(665, 66), Vector2(435, 30), 17, "reserve")
	var mode_button: OptionButton = OptionButton.new()
	mode_button.position = Vector2(600, 24)
	mode_button.size = Vector2(150, 34)
	mode_button.add_item("Human vs Bot", 0)
	mode_button.add_item("Hotseat", 1)
	mode_button.add_item("Bot vs Bot", 2)
	mode_button.item_selected.connect(_on_mode_selected)
	hud.add_child(mode_button)
	undo_button = _add_button("Undo", Vector2(758, 24), Vector2(62, 34))
	undo_button.pressed.connect(_undo)
	var fresh: Button = _add_button("New Game", Vector2(828, 24), Vector2(72, 34))
	fresh.pressed.connect(_new_game)

	_add_label("PLACE TOOL", Vector2(665, 106), Vector2(160, 25), 15, "heading")
	for type: int in range(3):
		var labels: Array[String] = ["Flat  F", "Wall  W", "Cap  C"]
		var button: Button = _add_button(labels[type], Vector2(665 + type * 96, 134), Vector2(88, 38))
		button.toggle_mode = true
		button.button_pressed = type == piece_choice
		button.pressed.connect(_on_tool_pressed.bind(type))
		tool_buttons.append(button)
	_add_label("ACTIONS", Vector2(665, 190), Vector2(150, 25), 15, "heading")
	move_label = _add_label("", Vector2(665, 218), Vector2(425, 44), 13, "help")
	topple_label = _add_label("", Vector2(665, 246), Vector2(425, 60), 13, "help")
	wall_label = _add_label("", Vector2(665, 280), Vector2(425, 60), 13, "help")
	win_label = _add_label("", Vector2(665, 320), Vector2(425, 60), 13, "help")
	hint_label = _add_label("Pulsing ring = last move. F/W/C stone; Esc clears; M mutes.", Vector2(665, 360), Vector2(425, 44), 13, "help")
	house_list_label = _add_label("", Vector2(665, 396), Vector2(425, 40), 13, "heading")
	house_note_label = _add_label("Rules marked * are house rules (House Rules button).", Vector2(665, 428), Vector2(425, 30), 12, "help")
	house_note_label.visible = false
	hint_off_button = _add_button("Hint Off", Vector2(905, 604), Vector2(88, 36))
	hint_off_button.pressed.connect(_request_hint.bind(false))
	hint_def_button = _add_button("Hint Def", Vector2(1001, 604), Vector2(88, 36))
	hint_def_button.pressed.connect(_request_hint.bind(true))
	var house: Button = _add_button("House Rules", Vector2(665, 646), Vector2(104, 36))
	house.pressed.connect(_toggle_rule_popup)
	var brains: Button = _add_button("Bot Brains", Vector2(775, 646), Vector2(96, 36))
	brains.pressed.connect(_toggle_brain_popup)
	var dark: Button = _add_button("Dark", Vector2(877, 646), Vector2(58, 36))
	dark.name = "DarkButton"
	dark.pressed.connect(_toggle_dark)
	court_label = _add_label("", Vector2(665, 690), Vector2(424, 30), 12, "heading")
	court_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for wrap_label: Label in [move_label, topple_label, wall_label, win_label, hint_label, house_list_label, house_note_label]:
		wrap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_rule_popup()
	_build_brain_popup()
	_refresh_rule_text()

func _role_color(role: String) -> Color:
	match role:
		"ink":
			return TEXT_INK
		"heading":
			return TEXT_HEADING
		"status":
			return TEXT_STATUS
		"reserve":
			return TEXT_RESERVE
		_:
			return TEXT_HELP

func _add_label(text: String, position: Vector2, size: Vector2, font_size: int, role: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", _role_color(role))
	role_labels.append({"l": label, "r": role})
	hud.add_child(label)
	return label

func _add_button(text: String, position: Vector2, size: Vector2) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.position = position
	button.size = size
	hud.add_child(button)
	return button

func _build_rule_popup() -> void:
	rule_popup = Panel.new()
	rule_popup.position = Vector2(110, 150)
	rule_popup.size = Vector2(440, 400)
	rule_popup.visible = false
	rule_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(rule_popup)
	var title: Label = Label.new()
	title.text = "HOUSE RULES"
	title.position = Vector2(0, 12)
	title.size = Vector2(440, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TEXT_INK)
	role_labels.append({"l": title, "r": "ink"})
	rule_popup.add_child(title)
	var names: Array[String] = ["Walls block all paths", "Topple towers with opposing top color", "Bi-directional win paths", "Top piece can slide off towers", "Walls can move one space like tiles"]
	for i: int in range(5):
		var check: CheckButton = CheckButton.new()
		check.text = names[i]
		check.add_theme_font_size_override("font_size", 13)
		check.position = Vector2(20, 52 + i * 38)
		check.size = Vector2(400, 32)
		check.button_pressed = rules[i]
		check.toggled.connect(_on_rule_toggled.bind(i))
		rule_popup.add_child(check)
		rule_checks.append(check)
	var note: Label = Label.new()
	note.text = "Default: all OFF — classical play. Changes apply immediately, including mid-game."
	note.position = Vector2(20, 252)
	note.size = Vector2(400, 60)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", TEXT_HELP)
	role_labels.append({"l": note, "r": "help"})
	rule_popup.add_child(note)
	var close: Button = Button.new()
	close.text = "Close"
	close.position = Vector2(180, 340)
	close.size = Vector2(80, 32)
	close.pressed.connect(func() -> void: rule_popup.visible = false)
	rule_popup.add_child(close)

func _request_hint(defensive: bool) -> void:
	if mode == 2 or bot_thinking or state.over:
		return
	_clear_hint()
	hint_inst = TakBrains.new()
	hint_inst.set_brain(TakBrains.DEFENSIVE if defensive else TakBrains.OFFENSIVE)
	hint_inst.budget_seconds = 0.4
	hint_inst.start_thinking(state.clone())
	hint_state = HINT_COMPUTE
	hint_def_button.disabled = true
	hint_off_button.disabled = true

func _clear_hint() -> void:
	hint_inst = null
	hint_state = HINT_IDLE
	hint_flash = {}
	hint_entries = []
	hint_cells = []
	hint_time = 0.0
	queue_redraw()
	if is_instance_valid(hint_def_button):
		hint_def_button.disabled = false
	if is_instance_valid(hint_off_button):
		hint_off_button.disabled = false

func _process_hint(delta: float) -> void:
	match hint_state:
		HINT_COMPUTE:
			hint_inst.tick()
			if hint_inst.is_done():
				var suggestion: Dictionary = hint_inst.get_move()
				hint_def_button.disabled = false
				hint_off_button.disabled = false
				hint_inst = null
				_present_suggestion(suggestion)
		HINT_FLASH:
			hint_time += delta
			if hint_time >= 3.2:
				_clear_hint()
		HINT_SHOW:
			hint_time += delta
			if hint_time >= hint_length:
				_clear_hint()
		_:
			pass

func _present_suggestion(suggestion: Dictionary) -> void:
	if suggestion.is_empty() or not state.is_legal(suggestion):
		hint_state = HINT_IDLE
		return
	var kind: String = str(suggestion.get("kind", ""))
	if kind == "place":
		hint_flash = {"cell": int(suggestion["cell"]), "type": int(suggestion["piece_type"]), "owner": state.current}
		hint_state = HINT_FLASH
		hint_time = 0.0
		return
	var plan: Dictionary = _build_plan(suggestion)
	var entries: Array[Dictionary] = []
	var stretch: float = hint_stretch(plan)
	for e: Dictionary in plan["entries"]:
		var first: Dictionary = e.duplicate(true)
		first["t0"] = float(e["t0"]) * stretch
		first["dur"] = float(e["dur"]) * stretch
		var second: Dictionary = e.duplicate(true)
		second["t0"] = float(e["t0"]) * stretch + float(plan["length"]) * stretch + 0.3
		second["dur"] = float(e["dur"]) * stretch
		entries.append(first)
		entries.append(second)
	var cells: Array[int] = []
	for e: Dictionary in entries:
		cells.append(int(e["from"]))
		cells.append(int(e["to"]))
	hint_entries = entries
	hint_cells = cells
	hint_length = float(plan["length"]) * stretch * 2.0 + 0.4
	hint_state = HINT_SHOW
	hint_time = 0.0

func hint_stretch(plan: Dictionary) -> float:
	return 1.0 if float(plan["length"]) <= 0.6 else 0.6 / float(plan["length"])

func _toggle_rule_popup() -> void:
	rule_popup.visible = not rule_popup.visible
	brain_popup.visible = false

func _toggle_brain_popup() -> void:
	brain_popup.visible = not brain_popup.visible
	rule_popup.visible = false

func _build_brain_popup() -> void:
	brain_popup = Panel.new()
	brain_popup.position = Vector2(130, 170)
	brain_popup.size = Vector2(420, 330)
	brain_popup.visible = false
	brain_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(brain_popup)
	var title: Label = Label.new()
	title.text = "BOT BRAINS"
	title.position = Vector2(0, 12)
	title.size = Vector2(420, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TEXT_INK)
	role_labels.append({"l": title, "r": "ink"})
	brain_popup.add_child(title)
	var group: ButtonGroup = ButtonGroup.new()
	group.allow_unpress = false
	for i: int in range(5):
		var radio: CheckButton = CheckButton.new()
		radio.text = TakBrains.NAMES[i]
		radio.button_group = group
		radio.add_theme_font_size_override("font_size", 14)
		radio.position = Vector2(24, 52 + i * 36)
		radio.size = Vector2(200, 30)
		radio.button_pressed = i == current_brain
		radio.toggled.connect(_on_brain_selected.bind(i))
		brain_popup.add_child(radio)
		brain_radios.append(radio)
	var desc: Array[String] = [
		"steady MCTS search",
		"blocks enemy wins, else Ralph",
		"races the shortest road, else Ralph",
		"defend, then attack, then Ralph",
		"attack, then defend, then Ralph",
	]
	for i: int in range(5):
		var line: Label = Label.new()
		line.text = desc[i]
		line.position = Vector2(232, 57 + i * 36)
		line.size = Vector2(186, 26)
		line.add_theme_font_size_override("font_size", 11)
		line.add_theme_color_override("font_color", TEXT_HELP)
		role_labels.append({"l": line, "r": "help"})
		brain_popup.add_child(line)
	var note: Label = Label.new()
	note.text = "Applies to both bots from the next move, including live Bot vs Bot games. Every brain falls back to Ralph."
	note.position = Vector2(20, 246)
	note.size = Vector2(384, 44)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", TEXT_HELP)
	role_labels.append({"l": note, "r": "help"})
	brain_popup.add_child(note)
	var close: Button = Button.new()
	close.text = "Close"
	close.position = Vector2(170, 296)
	close.size = Vector2(80, 30)
	close.pressed.connect(func() -> void: brain_popup.visible = false)
	brain_popup.add_child(close)

func _on_brain_selected(pressed: bool, index: int) -> void:
	if not pressed:
		return
	current_brain = index
	for b: TakBrains in bots:
		b.set_brain(index)

func _on_rule_toggled(pressed: bool, index: int) -> void:
	rules[index] = pressed
	state.set_rules(rules[0], rules[1], rules[2], rules[3], rules[4])
	_refresh_rule_text()

func _refresh_rule_text() -> void:
	move_label.text = "Single stones move one space onto empty ground or an enemy stone."
	if rules[1] and rules[3]:
		topple_label.text = "Towers never move — click next to slide the top stone; farther clicks fell 3+ towers, own or enemy-topped (*)."
	elif rules[3]:
		topple_label.text = "Towers never move — click next to slide the top stone; farther clicks fell your 3+ towers (*)."
	elif rules[1]:
		topple_label.text = "Towers never move — click a blue TOPPLE ray to fell your towers or enemy-topped ones (*)."
	else:
		topple_label.text = "Towers never move — click a blue TOPPLE ray to fell your towers; stones land alternating."
	if rules[4]:
		wall_label.text = "Walls slide like stones (*) and nothing stacks on a wall or capstone; only a lone capstone flattens an ENEMY wall."
	elif rules[0]:
		wall_label.text = "Walls never move; nothing stacks on walls or capstones; lone capstone flattens ENEMY walls. Walls break roads (*)."
	else:
		wall_label.text = "Walls never move; nothing stacks on walls or capstones; lone capstone flattens ENEMY walls. Own walls count in roads."
	if rules[2]:
		win_label.text = "Win: connect ANY two opposite sides with one chain — either direction for either player (*)."
	else:
		win_label.text = "Win: Light joins the IVORY sides (left/right); Dark joins the TEAL sides (top/bottom)."
	var active: Array[String] = []
	if rules[0]:
		active.append("* Walls block all paths")
	if rules[1]:
		active.append("* Topple enemy-topped towers")
	if rules[2]:
		active.append("* Bi-directional win paths")
	if rules[3]:
		active.append("* Top stones can slide")
	if rules[4]:
		active.append("* Moving walls")
	house_list_label.text = "  ".join(active)
	house_note_label.visible = not active.is_empty()
	_layout_help()

func _layout_help() -> void:
	if not is_instance_valid(move_label):
		return
	var y: float = 218.0
	for lbl: Label in [move_label, topple_label, wall_label, win_label, hint_label, house_list_label, house_note_label]:
		lbl.position = Vector2(665, y)
		lbl.size.x = 425.0
		y += lbl.get_combined_minimum_size().y + 4.0

func _toggle_dark() -> void:
	dark_mode = not dark_mode
	_apply_palette()
	for child: Node in hud.get_children():
		if child is Button and child.name == "DarkButton":
			(child as Button).text = "Light" if dark_mode else "Dark"

func _apply_palette() -> void:
	if dark_mode:
		LIGHT_COLOR = Color("#ece1bd")
		DARK_COLOR = Color("#2e8577")
		PARCHMENT = Color("#1f241f")
		PARCHMENT_DEEP = Color("#171b16")
		BRONZE = Color("#12100b")
		GOLD = Color("#b98f2a")
		GOLD_PALE = Color("#d3ad55")
		SAGE_A = Color("#4b5747")
		SAGE_B = Color("#424e41")
		TEAL = Color("#276a62")
		FRAME_MID = Color("#2e2416")
		GRID_LINE = Color(0.85, 0.75, 0.45, 0.25)
		LEGAL_HI = Color(0.72, 0.55, 0.18, 0.30)
		TOPPLE_HI = Color(0.16, 0.38, 0.36, 0.35)
		LABEL_BRIGHT = Color("#f2e9cf")
		VEIL = Color(0.02, 0.03, 0.02, 0.6)
		BANNER_BG = Color(0.13, 0.16, 0.13, 0.95)
		BANNER_LINE = Color(0.85, 0.75, 0.45, 0.5)
		BADGE_BG = Color(0.05, 0.06, 0.04, 0.8)
		BADGE_RING = Color("#d9c98f")
		RIM_DARK = Color("#79a894")
		PETAL_D = Color("#dfeee2", 0.3)
		TEXT_INK = Color("#e3d8ba")
		TEXT_HEADING = Color("#cfa64a")
		TEXT_STATUS = Color("#cbbd92")
		TEXT_RESERVE = Color("#8fbcae")
		TEXT_HELP = Color("#b3a67c")
		THEME_BG = Color("#2b3128")
		THEME_HOVER = Color("#353c31")
		THEME_TEXT = Color("#d9ccaa")
		THEME_HOVER_TEXT = Color("#eeddb0")
		THEME_PRESSED_TEXT = Color("#101410")
		THEME_DISABLED_TEXT = Color("#6c6850")
		DECO_LINE = Color(0.85, 0.72, 0.35, 0.09)
	else:
		LIGHT_COLOR = Color("#f5ecd4")
		DARK_COLOR = Color("#1d5c55")
		PARCHMENT = Color("#efe5cb")
		PARCHMENT_DEEP = Color("#e6d9b8")
		BRONZE = Color("#4f3f26")
		GOLD = Color("#c9a227")
		GOLD_PALE = Color("#dcc06a")
		SAGE_A = Color("#aeb98e")
		SAGE_B = Color("#a2b084")
		TEAL = Color("#2e6b66")
		FRAME_MID = Color("#6b5530")
		GRID_LINE = Color(0.31, 0.25, 0.13, 0.55)
		LEGAL_HI = Color(0.80, 0.64, 0.20, 0.32)
		TOPPLE_HI = Color(0.18, 0.42, 0.40, 0.35)
		LABEL_BRIGHT = Color("#f7efda")
		VEIL = Color(0.16, 0.12, 0.05, 0.55)
		BANNER_BG = Color(0.94, 0.89, 0.73, 0.95)
		BANNER_LINE = Color(0.31, 0.25, 0.13, 0.5)
		BADGE_BG = Color(0.15, 0.10, 0.06, 0.75)
		BADGE_RING = Color("#f3e8ca")
		RIM_DARK = Color("#8fae9f")
		PETAL_D = Color("#e9f2ea", 0.3)
		TEXT_INK = Color("#3e3524")
		TEXT_HEADING = Color("#8a6d1f")
		TEXT_STATUS = Color("#4a3b22")
		TEXT_RESERVE = Color("#3e5248")
		TEXT_HELP = Color("#5a5136")
		THEME_BG = Color("#ecdfbe")
		THEME_HOVER = Color("#f6edd3")
		THEME_TEXT = Color("#3e3524")
		THEME_HOVER_TEXT = Color("#233a35")
		THEME_PRESSED_TEXT = Color("#f2e9d4")
		THEME_DISABLED_TEXT = Color("#a29075")
		DECO_LINE = Color(0.30, 0.24, 0.08, 0.16)
	if is_instance_valid(hud):
		app_theme = _make_nouveau_theme()
		hud.theme = app_theme
		for entry: Dictionary in role_labels:
			if is_instance_valid(entry["l"]):
				entry["l"].add_theme_color_override("font_color", _role_color(entry["r"]))
	_refresh_rule_text()
	queue_redraw()

func _on_mode_selected(index: int) -> void:
	mode = index
	_new_game()
	if mode == 2:
		_start_bot_if_needed()

func _on_tool_pressed(type: int) -> void:
	_select_tool(type)

func _select_tool(type: int) -> void:
	piece_choice = type
	for index: int in range(tool_buttons.size()):
		tool_buttons[index].button_pressed = index == type
	_update_hud()

func _on_cell_clicked(cell: int) -> void:
	if selected_from >= 0 and topple_options.has(cell):
		var topple_move: Dictionary = {"kind": "topple", "from": selected_from, "dir": int(topple_options[cell]["dir"])}
		if state.is_legal(topple_move):
			_commit_move(topple_move)
			return
	if selected_from >= 0 and cell in legal_destinations:
		var move: Dictionary = {"kind": "move", "from": selected_from, "carry": 1, "dir": _dir_between(selected_from, cell), "drops": [1]}
		if state.is_legal(move):
			_commit_move(move)
			return
	if selected_from >= 0 and cell == selected_from:
		_clear_selection()
		return
	if int(state.heights[cell]) == 0:
		if selected_from < 0:
			var place: Dictionary = {"kind": "place", "cell": cell, "piece_type": piece_choice}
			if state.is_legal(place):
				_commit_move(place)
		return
	if state.piece_owner(cell) == state.current:
		_select_stack(cell)
	else:
		_clear_selection()

func _dir_between(from: int, cell: int) -> int:
	var dx: int = (cell % 5) - (from % 5)
	var dy: int = int(cell / 5) - int(from / 5)
	if dx == 1:
		return 0
	if dx == -1:
		return 1
	if dy == 1:
		return 2
	return 3

func _select_stack(cell: int) -> void:
	_clear_selection()
	selected_from = cell
	var height: int = int(state.heights[cell])
	if height == 1:
		for direction: int in range(4):
			if state._stone_move_legal(cell, direction):
				var target: int = state._neighbor(cell, direction, 1)
				if target >= 0:
					legal_destinations.append(target)
	else:
		for direction: int in range(4):
			var landing: Array[int] = state.topple_landing_cells(cell, direction)
			if landing.is_empty():
				continue
			for index: int in range(landing.size()):
				topple_options[landing[index]] = {"dir": direction, "last": index == landing.size() - 1}
	queue_redraw()

func _commit_move(move: Dictionary) -> void:
	undo_states.append(state.clone())
	undo_actors.append(state.current)
	undo_visuals.append({"indicator": indicator_cells.duplicate(), "entries": anim_entries.duplicate(true), "time": anim_time, "length": anim_length})
	var plan: Dictionary = _build_plan(move)
	var was_place: bool = str(move.get("kind", "")) == "place"
	state.apply_move(move)
	if was_place:
		_sfx("place", randf_range(0.97, 1.04))
	_start_animation(plan)
	_clear_hint()
	court_cells = []
	court_label.text = ""
	if state.over:
		if state.winner == 2:
			_sfx("draw")
		elif mode == 0 and state.winner == 1:
			_sfx("lose")
			_courtly_review()
		else:
			_sfx("win")
			if mode == 1:
				_courtly_review()
	_clear_selection()
	queue_redraw()
	_start_bot_if_needed()

func _courtly_review() -> void:
	if mode == 2:
		return
	var loser: int = 1 - state.winner
	var snapshot_index: int = -1
	for i: int in range(undo_actors.size() - 1, -1, -1):
		if undo_actors[i] == loser:
			snapshot_index = i
			break
	if snapshot_index < 0:
		return
	var pre: TakState = undo_states[snapshot_index].clone()
	pre.over = false
	pre.winner = -1
	var reviewer: TakBrains = TakBrains.new()
	var blocks: Array[Dictionary] = reviewer.blocking_moves(pre)
	if blocks.is_empty():
		return
	var seen: Dictionary = {}
	for mv: Dictionary in blocks:
		var kind: String = str(mv.get("kind", ""))
		var add: Array[int] = []
		if kind == "place":
			add = [int(mv["cell"])]
		elif kind == "move":
			add = [int(mv["from"]), pre._neighbor(int(mv["from"]), int(mv["dir"]), 1)]
		elif kind == "peel":
			add = [int(mv["from"]), pre.peel_landing(int(mv["from"]), int(mv["dir"]))]
		elif kind == "topple":
			add.append(int(mv["from"]))
			add.append_array(pre.topple_landing_cells(int(mv["from"]), int(mv["dir"])))
		for c: int in add:
			if c >= 0 and c < 25:
				seen[c] = true
	court_cells = []
	for key: int in seen.keys():
		court_cells.append(key)
	court_label.text = "Courtly review: %d blocking move(s) remain — teal cells. Undo to replay." % blocks.size()

func _start_bot_if_needed() -> void:
	if not bot_thinking and _bot_should_act():
		active_bot = state.current
		bots[active_bot].start_thinking(state)
		bot_thinking = true
		status_label.text = "Bot thinking..."
	else:
		_update_hud()

func _undo() -> void:
	if bot_thinking or undo_states.is_empty():
		return
	_sfx("undo")
	var last_actor: int = undo_actors.pop_back()
	state = undo_states.pop_back()
	_clear_hint()
	court_cells = []
	court_label.text = ""
	var visual: Dictionary = undo_visuals.pop_back()
	indicator_cells = visual["indicator"]
	anim_entries = visual["entries"]
	anim_time = visual["time"]
	anim_length = visual["length"]
	if mode == 0 and last_actor == 1 and not undo_states.is_empty():
		undo_actors.pop_back()
		undo_visuals.pop_back()
		state = undo_states.pop_back()
	_clear_selection()
	queue_redraw()
	_update_hud()

func _new_game() -> void:
	state = TakState.new()
	state.set_rules(rules[0], rules[1], rules[2], rules[3], rules[4])
	_refresh_rule_text()
	undo_states.clear()
	undo_actors.clear()
	undo_visuals.clear()
	anim_entries = []
	indicator_cells = []
	bot_thinking = false
	active_bot = -1
	spectate_wait = 5.0
	_clear_selection()
	_clear_hint()
	court_cells = []
	court_label.text = ""
	queue_redraw()
	_update_hud()
	_start_bot_if_needed()

func _clear_selection() -> void:
	selected_from = -1
	legal_destinations.clear()
	topple_options.clear()
	queue_redraw()

func _update_hud() -> void:
	if not is_instance_valid(status_label):
		return
	if state.over:
		if state.winner == 2:
			status_label.text = "Draw by flat count."
		elif state.road_exists(state.winner):
			status_label.text = "Light wins by road!" if state.winner == 0 else "Dark wins by road!"
		else:
			status_label.text = "Light wins by flat count!" if state.winner == 0 else "Dark wins by flat count!"
	elif bot_thinking:
		status_label.text = "Bot thinking..."
	else:
		var tool_names: Array[String] = ["Flat", "Wall", "Capstone"]
		var who: String = "Your turn — Light" if state.current == 0 else ("Dark's turn" if mode == 1 else "Dark to move")
		status_label.text = "%s · placing: %s" % [who, tool_names[piece_choice]]
	undo_button.disabled = bot_thinking or undo_states.is_empty()
	for type: int in range(tool_buttons.size()):
		var unavailable: bool = false
		if state.opening_done[state.current] == 0:
			unavailable = type != TakState.FLAT or state.reserve_flats[1 - state.current] <= 0
		elif type == TakState.CAPSTONE:
			unavailable = state.reserve_caps[state.current] <= 0
		else:
			unavailable = state.reserve_flats[state.current] <= 0
		tool_buttons[type].disabled = unavailable or mode == 2
	reserve_label.text = "Light  %dF  %dC          Dark  %dF  %dC" % [state.reserve_flats[0], state.reserve_caps[0], state.reserve_flats[1], state.reserve_caps[1]]
