class_name DefenseHud
extends Control

signal restart_pressed
signal build_kind_selected(build_kind: int)
signal rally_config_changed(building_id: int, mode: int, formation: int)
signal demolish_requested(building_id: int)
signal ai_income_level_changed(level: int)

const GameConfig = preload("res://scripts/game_config.gd")

const BLUE := Color("39a8ff")
const BLUE_DARK := Color("153f68")
const RED := Color("ff5468")
const RED_DARK := Color("682333")
const BAR_WIDTH := 484.0
const BUILD_MELEE := 0
const BUILD_RANGED := 1
const BUILD_TOWER := 2
const BUILD_DRAGON := 3
const BUILD_SIEGE := 4
const BUILD_RALLY := 5
const RALLY_ADVANCE := 0
const RALLY_DEFEND := 1
const FORMATION_LINE := 0
const FORMATION_WEDGE := 1
const FORMATION_LOOSE := 2

var gold_label: Label
var ally_hq_label: Label
var enemy_hq_label: Label
var timer_label: Label
var ally_percent_label: Label
var enemy_percent_label: Label
var population_label: Label
var ai_income_button: Button
var ally_occupancy_fill: ColorRect
var enemy_occupancy_fill: ColorRect
var message_label: Label
var instruction_label: Label
var result_overlay: ColorRect
var result_label: Label
var restart_button: Button
var build_buttons: Dictionary = {}
var edit_panel: ColorRect
var edit_mode_buttons: Array[Button] = []
var edit_formation_buttons: Array[Button] = []

var message_time_left := 0.0
var selected_build_kind := BUILD_MELEE
var editing_building_id := -1
var editing_mode := RALLY_ADVANCE
var editing_formation := FORMATION_LINE
var ai_income_level := GameConfig.AI_INCOME_LEVEL_DEFAULT

@export var message_duration := 1.1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_status_panel()
	_build_message()
	_build_selector()
	_build_rally_editor()
	_build_instruction()
	_build_result_overlay()
	update_stats(GameConfig.START_GOLD, GameConfig.HQ_MAX_HP, GameConfig.HQ_MAX_HP, GameConfig.MATCH_DURATION, 0.5)


func update_stats(ally_gold: int, ally_hq_hp: float, enemy_hq_hp: float, time_remaining: float, ally_occupancy: float, ally_units := 0, unit_cap := GameConfig.TEAM_UNIT_CAP, ally_income_multiplier := 1.0, current_ai_level := GameConfig.AI_INCOME_LEVEL_DEFAULT, ai_income_multiplier := 1.5) -> void:
	var blue_share := clampf(ally_occupancy, 0.0, 1.0)
	var red_share := 1.0 - blue_share
	gold_label.text = "GOLD  %03d" % max(0, ally_gold)
	ally_hq_label.text = "BLUE HQ  %04d" % ceili(maxf(0.0, ally_hq_hp))
	enemy_hq_label.text = "RED HQ  %04d" % ceili(maxf(0.0, enemy_hq_hp))
	timer_label.text = _format_time(time_remaining)
	ally_percent_label.text = "BLUE %d%%" % roundi(blue_share * 100.0)
	enemy_percent_label.text = "%d%% RED" % roundi(red_share * 100.0)
	population_label.text = "UNITS %d/%d  //  INCOME %d%%" % [ally_units, unit_cap, roundi(ally_income_multiplier * 100.0)]
	ai_income_level = clampi(current_ai_level, 1, 5)
	ai_income_button.text = "AI L%d  x%.2f" % [ai_income_level, ai_income_multiplier]
	ally_occupancy_fill.size.x = BAR_WIDTH * blue_share
	enemy_occupancy_fill.position.x = BAR_WIDTH * blue_share
	enemy_occupancy_fill.size.x = BAR_WIDTH * red_share


func show_result(result: String) -> void:
	var victory := result.to_upper() == "VICTORY"
	result_label.text = "BLUE VICTORY" if victory else "BLUE DEFEAT"
	result_label.add_theme_color_override("font_color", BLUE if victory else RED)
	result_overlay.visible = true


func show_message(text: String, color := Color.WHITE) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.modulate = Color.WHITE
	message_label.visible = true
	message_time_left = message_duration


func _process(delta: float) -> void:
	if message_time_left <= 0.0: return
	message_time_left = maxf(0.0, message_time_left - delta)
	message_label.modulate.a = minf(1.0, message_time_left / 0.22)
	if message_time_left <= 0.0: message_label.visible = false


func _build_status_panel() -> void:
	var panel := ColorRect.new()
	panel.position = Vector2(14, 12)
	panel.size = Vector2(512, 126)
	panel.color = Color(GameConfig.COLOR_PANEL, 0.96)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var title := _make_label(Vector2(14, 7), Vector2(300, 24), 16, GameConfig.COLOR_TEAL)
	title.text = "FRONTLINE // COMMAND"
	panel.add_child(title)
	ai_income_button = _make_selector_button("AI L3  x1.50", Vector2(272, 4), Vector2(112, 28))
	_style_button(ai_income_button, GameConfig.COLOR_ORANGE.darkened(0.12))
	ai_income_button.pressed.connect(_cycle_ai_income_level)
	panel.add_child(ai_income_button)
	timer_label = _make_label(Vector2(388, 7), Vector2(110, 24), 18, GameConfig.COLOR_TEXT)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(timer_label)
	gold_label = _make_label(Vector2(14, 35), Vector2(135, 24), 16, GameConfig.COLOR_TEXT)
	ally_hq_label = _make_label(Vector2(151, 35), Vector2(165, 24), 15, BLUE)
	enemy_hq_label = _make_label(Vector2(318, 35), Vector2(180, 24), 15, RED)
	panel.add_child(gold_label)
	panel.add_child(ally_hq_label)
	panel.add_child(enemy_hq_label)
	ally_percent_label = _make_label(Vector2(14, 62), Vector2(150, 20), 13, BLUE)
	enemy_percent_label = _make_label(Vector2(348, 62), Vector2(150, 20), 13, RED)
	enemy_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(ally_percent_label)
	panel.add_child(enemy_percent_label)
	population_label = _make_label(Vector2(142, 61), Vector2(200, 22), 11, Color(GameConfig.COLOR_TEXT, 0.78))
	population_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(population_label)
	var bar_back := ColorRect.new()
	bar_back.position = Vector2(14, 88)
	bar_back.size = Vector2(BAR_WIDTH, 22)
	bar_back.color = GameConfig.COLOR_NEUTRAL
	bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bar_back)
	ally_occupancy_fill = ColorRect.new()
	ally_occupancy_fill.size = Vector2(BAR_WIDTH * 0.5, 22)
	ally_occupancy_fill.color = BLUE_DARK
	ally_occupancy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_back.add_child(ally_occupancy_fill)
	enemy_occupancy_fill = ColorRect.new()
	enemy_occupancy_fill.position = Vector2(BAR_WIDTH * 0.5, 0)
	enemy_occupancy_fill.size = Vector2(BAR_WIDTH * 0.5, 22)
	enemy_occupancy_fill.color = RED_DARK
	enemy_occupancy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_back.add_child(enemy_occupancy_fill)
	var midpoint := ColorRect.new()
	midpoint.position = Vector2(BAR_WIDTH * 0.5 - 1.0, 0)
	midpoint.size = Vector2(2, 22)
	midpoint.color = Color(GameConfig.COLOR_TEXT, 0.75)
	midpoint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_back.add_child(midpoint)


func _build_message() -> void:
	message_label = _make_label(Vector2(50, 155), Vector2(440, 52), 25, GameConfig.COLOR_TEXT)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.visible = false
	add_child(message_label)


func _build_instruction() -> void:
	var plate := ColorRect.new()
	plate.position = Vector2(30, 891)
	plate.size = Vector2(480, 48)
	plate.color = Color(GameConfig.COLOR_PANEL, 0.94)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	instruction_label = _make_label(Vector2.ZERO, plate.size, 15, BLUE)
	instruction_label.text = "TAP BLUE TERRITORY // MELEE SPAWNER 60"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(instruction_label)


func _build_selector() -> void:
	var plate := ColorRect.new()
	plate.position = Vector2(30, 809)
	plate.size = Vector2(480, 70)
	plate.color = Color(GameConfig.COLOR_PANEL, 0.94)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	var specs := [
		[BUILD_MELEE, "MELEE\n60"], [BUILD_RANGED, "RANGED\n80"], [BUILD_SIEGE, "SIEGE\n140"],
		[BUILD_DRAGON, "DRAGON\n220"], [BUILD_RALLY, "RALLY\n80"], [BUILD_TOWER, "TOWER\n120"],
	]
	for index in specs.size():
		var kind: int = specs[index][0]
		var button := _make_selector_button(specs[index][1], Vector2(3 + index * 79, 8), Vector2(75, 54))
		button.pressed.connect(func() -> void: select_build_kind(kind))
		build_buttons[kind] = button
		plate.add_child(button)
	_update_selector_styles()


func select_build_kind(build_kind: int) -> bool:
	if build_kind not in [BUILD_MELEE, BUILD_RANGED, BUILD_TOWER, BUILD_DRAGON, BUILD_SIEGE, BUILD_RALLY]: return false
	selected_build_kind = build_kind
	var descriptions := {
		BUILD_MELEE: "MELEE SPAWNER 60", BUILD_RANGED: "RANGED SPAWNER 80", BUILD_SIEGE: "SIEGE SPAWNER 140",
		BUILD_DRAGON: "DRAGON LAIR 220", BUILD_RALLY: "RALLY POINT 80", BUILD_TOWER: "HQ 5x5 // TOWER 120",
	}
	instruction_label.text = "TAP BLUE TERRITORY // %s" % descriptions[build_kind]
	_update_selector_styles()
	build_kind_selected.emit(build_kind)
	return true


func _update_selector_styles() -> void:
	for kind in build_buttons: _style_selector_button(build_buttons[kind], int(kind) == selected_build_kind)


func _build_rally_editor() -> void:
	edit_panel = ColorRect.new()
	edit_panel.name = "RallyEditor"
	edit_panel.position = Vector2(55, 620)
	edit_panel.size = Vector2(430, 176)
	edit_panel.color = Color(GameConfig.COLOR_PANEL, 0.98)
	edit_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	edit_panel.visible = false
	add_child(edit_panel)
	var title := _make_label(Vector2(12, 8), Vector2(310, 24), 16, BLUE)
	title.text = "RALLY POINT // ORDERS"
	edit_panel.add_child(title)
	var close := _make_selector_button("X", Vector2(386, 6), Vector2(34, 28))
	close.pressed.connect(close_rally_panel)
	edit_panel.add_child(close)
	edit_mode_buttons = [
		_make_selector_button("ADVANCE", Vector2(12, 42), Vector2(126, 38)),
		_make_selector_button("DEFEND", Vector2(144, 42), Vector2(126, 38)),
	]
	for mode in edit_mode_buttons.size():
		edit_mode_buttons[mode].pressed.connect(func() -> void: select_rally_mode(mode))
		edit_panel.add_child(edit_mode_buttons[mode])
	edit_formation_buttons = [
		_make_selector_button("LINE", Vector2(12, 91), Vector2(92, 34)),
		_make_selector_button("WEDGE", Vector2(109, 91), Vector2(92, 34)),
		_make_selector_button("LOOSE", Vector2(206, 91), Vector2(92, 34)),
	]
	for formation in edit_formation_buttons.size():
		edit_formation_buttons[formation].pressed.connect(func() -> void: select_edit_formation(formation))
		edit_panel.add_child(edit_formation_buttons[formation])
	var demolish := _make_selector_button("DEMOLISH", Vector2(307, 91), Vector2(111, 34))
	demolish.pressed.connect(request_edit_demolish)
	edit_panel.add_child(demolish)
	var hint := _make_label(Vector2(12, 134), Vector2(406, 28), 11, Color(GameConfig.COLOR_TEXT, 0.66))
	hint.text = "ADVANCE 20 // DEFEND 28 + AUTO-LAUNCH OVERFLOW"
	edit_panel.add_child(hint)


func open_rally_panel(config: Dictionary) -> void:
	editing_building_id = int(config.get("id", -1))
	editing_mode = int(config.get("mode", RALLY_ADVANCE))
	editing_formation = int(config.get("formation", FORMATION_LINE))
	edit_panel.visible = editing_building_id >= 0
	_refresh_rally_editor()


func close_rally_panel() -> void:
	edit_panel.visible = false
	editing_building_id = -1


func select_rally_mode(mode: int) -> void:
	if editing_building_id < 0 or mode < RALLY_ADVANCE or mode > RALLY_DEFEND: return
	editing_mode = mode
	_emit_rally_edit()


func select_edit_formation(formation: int) -> void:
	if editing_building_id < 0 or formation < FORMATION_LINE or formation > FORMATION_LOOSE: return
	editing_formation = formation
	_emit_rally_edit()


func request_edit_demolish() -> void:
	if editing_building_id < 0: return
	demolish_requested.emit(editing_building_id)
	close_rally_panel()


func _emit_rally_edit() -> void:
	_refresh_rally_editor()
	rally_config_changed.emit(editing_building_id, editing_mode, editing_formation)


func _refresh_rally_editor() -> void:
	for mode in edit_mode_buttons.size(): _style_selector_button(edit_mode_buttons[mode], mode == editing_mode)
	for formation in edit_formation_buttons.size(): _style_selector_button(edit_formation_buttons[formation], formation == editing_formation)


func _style_selector_button(button: Button, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BLUE.darkened(0.56) if selected else GameConfig.COLOR_NEUTRAL.darkened(0.18)
	normal.border_color = BLUE if selected else Color(BLUE_DARK, 0.78)
	normal.set_border_width_all(3 if selected else 1)
	normal.set_corner_radius_all(3)
	var active := normal.duplicate()
	active.bg_color = BLUE.darkened(0.3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_color_override("font_color", GameConfig.COLOR_TEXT if selected else Color(GameConfig.COLOR_TEXT, 0.68))


func _build_result_overlay() -> void:
	result_overlay = ColorRect.new()
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.color = Color(0.025, 0.04, 0.075, 0.92)
	result_overlay.visible = false
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(result_overlay)
	var card := ColorRect.new()
	card.position = Vector2(55, 340)
	card.size = Vector2(430, 250)
	card.color = GameConfig.COLOR_PANEL
	result_overlay.add_child(card)
	result_label = _make_label(Vector2(20, 34), Vector2(390, 80), 38, BLUE)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(result_label)
	var subtitle := _make_label(Vector2(20, 113), Vector2(390, 28), 15, Color(GameConfig.COLOR_TEXT, 0.68))
	subtitle.text = "FRONTLINE SIMULATION COMPLETE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(subtitle)
	restart_button = Button.new()
	restart_button.position = Vector2(105, 166)
	restart_button.size = Vector2(220, 58)
	restart_button.text = "RESTART"
	restart_button.add_theme_font_size_override("font_size", 19)
	_style_button(restart_button, GameConfig.COLOR_TEAL)
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	card.add_child(restart_button)


func _format_time(seconds_left: float) -> String:
	var whole_seconds := maxi(0, ceili(seconds_left))
	return "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]


func _cycle_ai_income_level() -> void:
	ai_income_level = ai_income_level % 5 + 1
	ai_income_level_changed.emit(ai_income_level)


func _make_label(at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_selector_button(label_text: String, at: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = dimensions
	button.text = label_text
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 9)
	return button


func _style_button(button: Button, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.darkened(0.56)
	normal.border_color = accent
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(3)
	var pressed := normal.duplicate()
	pressed.bg_color = accent.darkened(0.3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", pressed)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", GameConfig.COLOR_TEXT)
