extends Node2D

const TakState = preload("res://scripts/tak_state.gd")
const MctsBot = preload("res://scripts/mcts_bot.gd")
const CELL: float = 112.0
const BOARD_ORIGIN: Vector2 = Vector2(52.0, 126.0)
const BOARD_PIXELS: float = CELL * 5.0
const LIGHT_COLOR: Color = Color("#f3e8ca")
const DARK_COLOR: Color = Color("#9d2938")

var state: TakState = TakState.new()
var bot: MctsBot = MctsBot.new()
var hotseat: bool = false
var bot_thinking: bool = false
var piece_choice: int = TakState.FLAT
var selected_from: int = -1
var selected_carry: int = 1
var selected_direction: int = -1
var legal_destinations: Array[int] = []
var undo_states: Array[TakState] = []
var undo_actors: Array[int] = []
var hud: Control
var status_label: Label
var reserve_label: Label
var undo_button: Button
var carry_buttons: Array[Button] = []
var direction_buttons: Array[Button] = []
var tool_buttons: Array[Button] = []

func _ready() -> void:
	bot.budget_seconds = 2.0
	_build_hud()
	_update_hud()
	queue_redraw()

func _process(_delta: float) -> void:
	if bot_thinking:
		bot.tick()
		status_label.text = "Bot thinking... %d playouts" % bot.playouts
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
		if bot_thinking or state.over or (not hotseat and state.current == 1):
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
	draw_rect(Rect2(BOARD_ORIGIN - Vector2(7, 0), Vector2(7, BOARD_PIXELS)), Color("#b9a07a"))
	draw_rect(Rect2(BOARD_ORIGIN + Vector2(BOARD_PIXELS, 0), Vector2(7, BOARD_PIXELS)), Color("#b9a07a"))
	draw_rect(Rect2(BOARD_ORIGIN, Vector2(BOARD_PIXELS, 7)), Color("#51465e"))
	draw_rect(Rect2(BOARD_ORIGIN + Vector2(0, BOARD_PIXELS), Vector2(BOARD_PIXELS, 7)), Color("#51465e"))
	for cell: int in range(25):
		var x: int = cell % 5
		var y: int = int(cell / 5)
		var rect: Rect2 = Rect2(BOARD_ORIGIN + Vector2(x * CELL, y * CELL), Vector2(CELL, CELL))
		draw_rect(rect, Color("#d4ad78") if (x + y) % 2 == 0 else Color("#cba06c"))
		if cell in legal_destinations:
			draw_rect(rect.grow(-7), Color(0.23, 0.56, 0.29, 0.33))
			if state.piece_type(cell) == TakState.WALL and selected_carry == 1 and state.piece_type(selected_from, int(state.heights[selected_from]) - 1) == TakState.CAPSTONE:
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(22, CELL - 9), "TOPPLE", HORIZONTAL_ALIGNMENT_LEFT, 72, 12, Color("#fff7d8"))
		if cell == selected_from:
			draw_rect(rect.grow(-4), Color(0.95, 0.79, 0.28, 0.54))
		draw_rect(rect, Color("#78583b"), false, 2.0)
		_draw_stack(cell, rect)
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
		var shift: Vector2 = Vector2(0, -float(index) * 5.0)
		var color: Color = LIGHT_COLOR if owner == 0 else DARK_COLOR
		if kind == TakState.FLAT:
			draw_circle(center + shift + Vector2(1.5, 3), 34, Color("#4e3726", 0.28))
			draw_circle(center + shift, 33, color.darkened(0.25))
			draw_circle(center + shift, 29, color)
			draw_arc(center + shift, 29, 0.0, TAU, 48, Color("#fff5dc", 0.72), 2.0)
		elif kind == TakState.WALL:
			var bar: Rect2 = Rect2(center + shift + Vector2(-19, -32), Vector2(38, 64))
			draw_rect(bar, Color("#513926"))
			draw_rect(bar.grow(-4), color)
			draw_rect(Rect2(bar.position + Vector2(6, 3), Vector2(6, 54)), Color("#fff3d3", 0.5))
		else:
			var square: Rect2 = Rect2(center + shift + Vector2(-29, -29), Vector2(58, 58))
			draw_rect(square, color.darkened(0.24))
			draw_rect(square.grow(-5), color)
			draw_line(square.position + Vector2(9, 9), square.end - Vector2(9, 9), Color("#513926"), 5.0)
			draw_line(Vector2(square.end.x - 9, square.position.y + 9), Vector2(square.position.x + 9, square.end.y - 9), Color("#513926"), 5.0)
	if height > 2:
		draw_circle(rect.position + Vector2(CELL - 15, 15), 12, Color("#30251e"))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(CELL - 20, 20), str(height), HORIZONTAL_ALIGNMENT_CENTER, 10, 13, Color.WHITE)

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)
	_add_label("TAK", Vector2(58, 24), Vector2(90, 36), 28, Color("#533c2c"))
	status_label = _add_label("", Vector2(170, 25), Vector2(480, 32), 17, Color("#33302b"))
	reserve_label = _add_label("", Vector2(665, 88), Vector2(390, 46), 17, Color("#41372f"))
	var mode: OptionButton = OptionButton.new()
	mode.position = Vector2(780, 24)
	mode.size = Vector2(170, 34)
	mode.add_item("Human vs Bot", 0)
	mode.add_item("Hotseat", 1)
	mode.item_selected.connect(_on_mode_selected)
	hud.add_child(mode)
	undo_button = _add_button("Undo", Vector2(960, 24), Vector2(68, 34))
	undo_button.pressed.connect(_undo)
	var fresh: Button = _add_button("New Game", Vector2(1033, 24), Vector2(66, 34))
	fresh.pressed.connect(_new_game)
	_add_label("PLACE TOOL", Vector2(665, 158), Vector2(160, 25), 15, Color("#554533"))
	for type: int in range(3):
		var labels: Array[String] = ["Flat  F", "Wall  W", "Cap  C"]
		var button: Button = _add_button(labels[type], Vector2(665 + type * 96, 188), Vector2(88, 38))
		button.toggle_mode = true
		button.button_pressed = type == piece_choice
		button.pressed.connect(_on_tool_pressed.bind(type))
		tool_buttons.append(button)
	_add_label("MOVEMENT", Vector2(665, 263), Vector2(150, 25), 15, Color("#554533"))
	_add_label("Select a stack, carry, direction, then destination.", Vector2(665, 291), Vector2(390, 48), 14, Color("#51473d"))
	for direction: int in range(4):
		var names: Array[String] = ["→", "←", "↓", "↑"]
		var positions: Array[Vector2] = [Vector2(665, 346), Vector2(711, 346), Vector2(757, 346), Vector2(803, 346)]
		var button: Button = _add_button(names[direction], positions[direction], Vector2(40, 36))
		button.pressed.connect(_on_direction_pressed.bind(direction))
		button.disabled = true
		direction_buttons.append(button)
	_add_label("CARRY", Vector2(665, 403), Vector2(110, 25), 15, Color("#554533"))
	_add_label("Road goal: Light left-right; Dark top-bottom.", Vector2(665, 488), Vector2(390, 50), 14, Color("#51473d"))
	_add_label("Click an empty square to place. F/W/C select stone; Esc clears selection.", Vector2(665, 549), Vector2(390, 64), 14, Color("#51473d"))

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
	hotseat = index == 1
	_new_game()

func _on_tool_pressed(type: int) -> void:
	_select_tool(type)

func _select_tool(type: int) -> void:
	piece_choice = type
	for index: int in range(tool_buttons.size()):
		tool_buttons[index].button_pressed = index == type
	_update_hud()

func _on_cell_clicked(cell: int) -> void:
	if selected_from >= 0 and selected_direction >= 0 and cell in legal_destinations:
		var move: Dictionary = _make_move(cell)
		if state.is_legal(move):
			_commit_move(move)
			return
	if selected_from >= 0 and selected_direction >= 0 and cell == selected_from:
		_clear_selection()
		return
	if int(state.heights[cell]) == 0:
		if selected_from < 0:
			var move: Dictionary = {"kind": "place", "cell": cell, "piece_type": piece_choice}
			if state.is_legal(move):
				_commit_move(move)
		return
	if state.piece_owner(cell) == state.current and state.piece_type(cell) != TakState.WALL:
		_select_stack(cell)
	else:
		_clear_selection()

func _select_stack(cell: int) -> void:
	_clear_selection()
	selected_from = cell
	selected_carry = mini(5, int(state.heights[cell]))
	for carry: int in range(1, selected_carry + 1):
		var button: Button = _add_button(str(carry), Vector2(665 + (carry - 1) * 43, 433), Vector2(37, 32))
		button.toggle_mode = true
		button.button_pressed = carry == selected_carry
		button.pressed.connect(_on_carry_pressed.bind(carry))
		carry_buttons.append(button)
	for button: Button in direction_buttons:
		button.disabled = false
	_refresh_destinations()
	queue_redraw()

func _on_carry_pressed(carry: int) -> void:
	selected_carry = carry
	for button: Button in carry_buttons:
		button.button_pressed = button.text == str(carry)
	_refresh_destinations()

func _on_direction_pressed(direction: int) -> void:
	if selected_from < 0:
		return
	selected_direction = direction
	_refresh_destinations()
	queue_redraw()

func _refresh_destinations() -> void:
	legal_destinations.clear()
	if selected_from < 0:
		return
	for direction: int in range(4):
		if selected_direction >= 0 and direction != selected_direction:
			continue
		for distance: int in range(1, 6):
			var destination: int = _cell_at_distance(selected_from, direction, distance)
			if destination < 0:
				break
			var drops: Array[int] = _auto_drops(selected_from, selected_carry, direction, distance)
			if drops.is_empty():
				continue
			var move: Dictionary = {"kind": "move", "from": selected_from, "carry": selected_carry, "dir": direction, "drops": drops}
			if state.is_legal(move):
				legal_destinations.append(destination)

func _auto_drops(origin: int, carry: int, direction: int, distance: int) -> Array[int]:
	var drops: Array[int] = []
	var remaining: int = carry
	for step: int in range(1, distance + 1):
		var cell: int = _cell_at_distance(origin, direction, step)
		if cell < 0:
			return []
		if step < distance and state.piece_type(cell) == TakState.WALL:
			return []
		else:
			var count: int = remaining if step == distance else 1
			if count < 1:
				return []
			drops.append(count)
			remaining -= count
	return drops if remaining == 0 else []

func _make_move(destination: int) -> Dictionary:
	var direction: int = selected_direction
	var distance: int = absi((destination % 5) - (selected_from % 5)) + absi(int(destination / 5) - int(selected_from / 5))
	var drops: Array[int] = _auto_drops(selected_from, selected_carry, direction, distance)
	return {"kind": "move", "from": selected_from, "carry": selected_carry, "dir": direction, "drops": drops}

func _cell_at_distance(origin: int, direction: int, distance: int) -> int:
	var x: int = origin % 5
	var y: int = int(origin / 5)
	match direction:
		0:
			x += distance
		1:
			x -= distance
		2:
			y += distance
		3:
			y -= distance
	if x < 0 or x >= 5 or y < 0 or y >= 5:
		return -1
	return y * 5 + x

func _commit_move(move: Dictionary) -> void:
	undo_states.append(state.clone())
	undo_actors.append(state.current)
	state.apply_move(move)
	_clear_selection()
	queue_redraw()
	if not state.over and not hotseat and state.current == 1:
		bot.start_thinking(state)
		bot_thinking = true
		status_label.text = "Bot thinking... 0 playouts"
	else:
		_update_hud()

func _undo() -> void:
	if bot_thinking or undo_states.is_empty():
		return
	var last_actor: int = undo_actors.pop_back()
	state = undo_states.pop_back()
	if not hotseat and last_actor == 1 and not undo_states.is_empty():
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
	_clear_selection()
	queue_redraw()
	_update_hud()

func _clear_selection() -> void:
	selected_from = -1
	selected_direction = -1
	legal_destinations.clear()
	for button: Button in carry_buttons:
		button.queue_free()
	carry_buttons.clear()
	for button: Button in direction_buttons:
		button.disabled = true
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
		status_label.text = "Bot thinking... %d playouts" % bot.playouts
	else:
		status_label.text = "Your turn — Light" if state.current == 0 else ("Dark's turn" if hotseat else "Dark to move")
	undo_button.disabled = bot_thinking
	for type: int in range(tool_buttons.size()):
		var unavailable: bool = false
		if state.opening_done[state.current] == 0:
			unavailable = type != TakState.FLAT or state.reserve_flats[1 - state.current] <= 0
		elif type == TakState.CAPSTONE:
			unavailable = state.reserve_caps[state.current] <= 0
		else:
			unavailable = state.reserve_flats[state.current] <= 0
		tool_buttons[type].disabled = unavailable
	reserve_label.text = "Light  %dF  %dC          Dark  %dF  %dC" % [state.reserve_flats[0], state.reserve_caps[0], state.reserve_flats[1], state.reserve_caps[1]]
