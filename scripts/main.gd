extends Node2D

const TakState = preload("res://scripts/tak_state.gd")
const MctsBot = preload("res://scripts/mcts_bot.gd")
const CELL: float = 112.0
const BOARD_ORIGIN: Vector2 = Vector2(52.0, 126.0)
const BOARD_PIXELS: float = CELL * 5.0
const LIGHT_COLOR: Color = Color("#f3e8ca")
const DARK_COLOR: Color = Color("#9d2938")

var state: TakState = TakState.new()
var bots: Array[MctsBot] = [MctsBot.new(), MctsBot.new()]
var mode: int = 0
var bot_thinking: bool = false
var active_bot: int = -1
var piece_choice: int = TakState.FLAT
var selected_from: int = -1
var legal_destinations: Array[int] = []
var topple_options: Dictionary = {}
var undo_states: Array[TakState] = []
var undo_actors: Array[int] = []
var hud: Control
var status_label: Label
var reserve_label: Label
var undo_button: Button
var tool_buttons: Array[Button] = []

func _ready() -> void:
	bots[0].budget_seconds = 2.0
	bots[1].budget_seconds = 2.0
	_build_hud()
	_update_hud()
	queue_redraw()

func _bot_should_act() -> bool:
	if mode == 1 or state.over:
		return false
	return mode == 2 or state.current == 1

func _process(_delta: float) -> void:
	if bot_thinking:
		var bot: MctsBot = bots[active_bot]
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
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("#e8ddc8"))
	draw_rect(Rect2(BOARD_ORIGIN - Vector2(9, 9), Vector2(BOARD_PIXELS + 18, BOARD_PIXELS + 18)), Color("#70452e"))
	draw_rect(Rect2(BOARD_ORIGIN, Vector2(BOARD_PIXELS, BOARD_PIXELS)), Color("#c99b64"))
	for cell: int in range(25):
		var x: int = cell % 5
		var y: int = int(cell / 5)
		var rect: Rect2 = Rect2(BOARD_ORIGIN + Vector2(x * CELL, y * CELL), Vector2(CELL, CELL))
		draw_rect(rect, Color("#d4ad78") if (x + y) % 2 == 0 else Color("#cba06c"))
		if cell in legal_destinations:
			draw_rect(rect.grow(-7), Color(0.23, 0.56, 0.29, 0.33))
			if selected_from >= 0 and state.piece_type(cell) == TakState.WALL and int(state.heights[selected_from]) == 1 and state.piece_type(selected_from) == TakState.CAPSTONE:
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(22, CELL - 9), "FLATTEN", HORIZONTAL_ALIGNMENT_LEFT, 72, 12, Color("#fff7d8"))
		if topple_options.has(cell):
			draw_rect(rect.grow(-7), Color(0.16, 0.40, 0.72, 0.30))
			if bool(topple_options[cell]["last"]):
				draw_rect(rect.grow(-4), Color(0.98, 0.65, 0.20, 0.9), false, 3.0)
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, CELL - 9), "TOPPLE", HORIZONTAL_ALIGNMENT_LEFT, 100, 12, Color("#fff7d8"))
		if cell == selected_from:
			draw_rect(rect.grow(-4), Color(0.95, 0.79, 0.28, 0.54))
		draw_rect(rect, Color("#78583b"), false, 2.0)
		_draw_stack(cell, rect)
	draw_rect(Rect2(BOARD_ORIGIN - Vector2(9, 0), Vector2(9, BOARD_PIXELS)), Color("#8d775c"))
	draw_rect(Rect2(BOARD_ORIGIN + Vector2(BOARD_PIXELS, 0), Vector2(9, BOARD_PIXELS)), Color("#8d775c"))
	draw_line(BOARD_ORIGIN, BOARD_ORIGIN + Vector2(0, BOARD_PIXELS), Color("#78583b"), 2.0)
	draw_line(BOARD_ORIGIN + Vector2(BOARD_PIXELS - 9, 0), BOARD_ORIGIN + Vector2(BOARD_PIXELS - 9, BOARD_PIXELS), Color("#78583b"), 2.0)
	draw_rect(Rect2(BOARD_ORIGIN, Vector2(BOARD_PIXELS, 9)), Color("#8d775c"))
	draw_rect(Rect2(BOARD_ORIGIN + Vector2(0, BOARD_PIXELS), Vector2(BOARD_PIXELS, 9)), Color("#8d775c"))
	if state.over:
		draw_rect(Rect2(BOARD_ORIGIN, Vector2(BOARD_PIXELS, BOARD_PIXELS)), Color(0.10, 0.08, 0.07, 0.46))
		var winning_cells: Array[int] = []
		if state.winner < 2:
			winning_cells = state.road_cells(state.winner)
		for cell: int in winning_cells:
			var rect: Rect2 = Rect2(BOARD_ORIGIN + Vector2((cell % 5) * CELL, int(cell / 5) * CELL), Vector2(CELL, CELL))
			draw_rect(rect.grow(-10), Color(0.92, 0.78, 0.25, 0.52))
		var result: String = "DRAW" if state.winner == 2 else ("LIGHT WINS" if state.winner == 0 else "DARK WINS")
		draw_string(ThemeDB.fallback_font, BOARD_ORIGIN + Vector2(145, 284), result, HORIZONTAL_ALIGNMENT_CENTER, 270, 34, Color.WHITE)

func _draw_stack(cell: int, rect: Rect2) -> void:
	var height: int = int(state.heights[cell])
	if height == 0:
		return
	var center: Vector2 = rect.get_center()
	var visible: int = mini(height, 5)
	for index: int in range(visible):
		var layer: int = height - visible + index
		var encoded: int = state.cells[cell * TakState.MAX_STACK + layer]
		var owner: int = int(encoded / 3)
		var kind: int = encoded % 3
		var shift: Vector2 = Vector2(0, -float(index) * 7.0)
		var piece_center: Vector2 = center + shift
		var base: Color = LIGHT_COLOR if owner == 0 else DARK_COLOR
		if kind == TakState.FLAT:
			var radius: float = 34.0
			_draw_transformed_ellipse(piece_center + Vector2(5, 8), radius + 2.0, Vector2(1.0, 0.5), Color(0.20, 0.13, 0.06, 0.30))
			draw_circle(piece_center + Vector2(0, 5), radius, base.darkened(0.55))
			draw_circle(piece_center, radius, base)
			var toward_light: Vector2 = Vector2(-1, -1).normalized()
			for i: int in range(8):
				var amount: float = float(i) / 7.0
				draw_circle(piece_center + toward_light * float(i) * 1.2, radius - float(i) * 3.4, base.lightened(0.28).lerp(base, amount))
			_draw_transformed_ellipse(piece_center + Vector2(-radius * 0.38, -radius * 0.42), 9.0, Vector2(1.0, 0.62), Color(1.0, 1.0, 0.95, 0.35))
			draw_arc(piece_center, radius - 1.5, PI * 0.10, PI * 0.90, 24, base.darkened(0.5), 2.0, true)
		elif kind == TakState.WALL:
			var face: Rect2 = Rect2(piece_center + Vector2(-19, -32), Vector2(38, 64))
			_draw_transformed_ellipse(piece_center + Vector2(4, 6), 22.0, Vector2(1.0, 0.38), Color(0.20, 0.13, 0.06, 0.30))
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
			var square: Rect2 = Rect2(piece_center + Vector2(-28, -28), Vector2(56, 56))
			_draw_transformed_ellipse(piece_center + Vector2(4, 7), 33.0, Vector2(1.0, 0.45), Color(0.20, 0.13, 0.06, 0.30))
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
			var x_color_light: Color = Color(base.lightened(0.30), 0.55)
			draw_line(square.position + Vector2(inset + 1.2, inset + 1.2), square.end - Vector2(inset - 1.2, inset - 1.2), x_color_light, 6.0)
			draw_line(Vector2(square.end.x - inset + 1.2, square.position.y + inset + 1.2), Vector2(square.position.x + inset + 1.2, square.end.y - inset + 1.2), x_color_light, 6.0)
			draw_line(square.position + Vector2(inset, inset), square.end - Vector2(inset, inset), base.darkened(0.55), 4.5)
			draw_line(Vector2(square.end.x - inset, square.position.y + inset), Vector2(square.position.x + inset, square.end.y - inset), base.darkened(0.55), 4.5)
	if height > 2:
		var badge_center: Vector2 = rect.position + Vector2(CELL - 15, 15)
		draw_circle(badge_center, 11, Color(0.15, 0.10, 0.06, 0.75))
		draw_arc(badge_center, 9.5, 0.0, TAU, 24, Color("#f3e8ca", 0.75), 1.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(CELL - 20, 20), str(height), HORIZONTAL_ALIGNMENT_CENTER, 10, 13, Color.WHITE)

func _draw_transformed_ellipse(center: Vector2, radius: float, scale: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, scale)
	draw_circle(Vector2.ZERO, radius, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_rounded_rect(position: Vector2, size: Vector2, corner_radius: float, color: Color) -> void:
	var radius: float = minf(corner_radius, minf(size.x, size.y) * 0.5)
	draw_rect(Rect2(position + Vector2(radius, 0), Vector2(size.x - radius * 2.0, size.y)), color)
	draw_rect(Rect2(position + Vector2(0, radius), Vector2(size.x, size.y - radius * 2.0)), color)
	draw_circle(position + Vector2(radius, radius), radius, color)
	draw_circle(position + Vector2(size.x - radius, radius), radius, color)
	draw_circle(position + Vector2(radius, size.y - radius), radius, color)
	draw_circle(position + Vector2(size.x - radius, size.y - radius), radius, color)

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	_add_label("TAK", Vector2(58, 24), Vector2(90, 36), 28, Color("#533c2c"))
	status_label = _add_label("", Vector2(170, 25), Vector2(480, 32), 17, Color("#33302b"))
	reserve_label = _add_label("", Vector2(665, 88), Vector2(390, 46), 17, Color("#41372f"))
	var mode_button: OptionButton = OptionButton.new()
	mode_button.position = Vector2(700, 24)
	mode_button.size = Vector2(180, 34)
	mode_button.add_item("Human vs Bot", 0)
	mode_button.add_item("Hotseat", 1)
	mode_button.add_item("Bot vs Bot", 2)
	mode_button.item_selected.connect(_on_mode_selected)
	hud.add_child(mode_button)
	undo_button = _add_button("Undo", Vector2(890, 24), Vector2(80, 34))
	undo_button.pressed.connect(_undo)
	var fresh: Button = _add_button("New Game", Vector2(980, 24), Vector2(75, 34))
	fresh.pressed.connect(_new_game)
	_add_label("PLACE TOOL", Vector2(665, 158), Vector2(160, 25), 15, Color("#554533"))
	for type: int in range(3):
		var labels: Array[String] = ["Flat  F", "Wall  W", "Cap  C"]
		var button: Button = _add_button(labels[type], Vector2(665 + type * 96, 188), Vector2(88, 38))
		button.toggle_mode = true
		button.button_pressed = type == piece_choice
		button.pressed.connect(_on_tool_pressed.bind(type))
		tool_buttons.append(button)
	_add_label("ACTIONS", Vector2(665, 263), Vector2(150, 25), 15, Color("#554533"))
	_add_label("Single stones move one space onto empty ground or an enemy stone.", Vector2(665, 291), Vector2(390, 48), 14, Color("#51473d"))
	_add_label("Towers never move — click a blue TOPPLE ray to fell one; stones land alternating on empty or enemy tops.", Vector2(665, 341), Vector2(390, 60), 14, Color("#51473d"))
	_add_label("Walls never move and nothing stacks on a wall or capstone; only a lone capstone may flatten a wall.", Vector2(665, 409), Vector2(390, 60), 14, Color("#51473d"))
	_add_label("Win: connect ANY two opposite sides with one chain. Either direction wins for either player.", Vector2(665, 477), Vector2(400, 60), 14, Color("#51473d"))
	_add_label("Click an empty square to place. F/W/C select stone; Esc clears selection.", Vector2(665, 541), Vector2(390, 48), 14, Color("#51473d"))

func _add_label(text: String, position: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	hud.add_child(label)
	return label

func _add_button(text: String, position: Vector2, size: Vector2) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.position = position
	button.size = size
	hud.add_child(button)
	return button

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
	state.apply_move(move)
	_clear_selection()
	queue_redraw()
	_start_bot_if_needed()

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
	var last_actor: int = undo_actors.pop_back()
	state = undo_states.pop_back()
	if mode == 0 and last_actor == 1 and not undo_states.is_empty():
		undo_actors.pop_back()
		state = undo_states.pop_back()
	_clear_selection()
	queue_redraw()
	_update_hud()

func _new_game() -> void:
	state = TakState.new()
	undo_states.clear()
	undo_actors.clear()
	bot_thinking = false
	active_bot = -1
	_clear_selection()
	queue_redraw()
	_update_hud()

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
