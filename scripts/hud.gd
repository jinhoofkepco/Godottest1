class_name DefenseHud
extends Control

signal restart_pressed
signal build_kind_selected(build_kind: int)
signal template_selected(template: Dictionary, formation: int)
signal barracks_config_changed(building_id: int, template: Dictionary, formation: int)
signal waypoint_requested(building_id: int)
signal demolish_requested(building_id: int)

const GameConfig = preload("res://scripts/game_config.gd")

const BLUE := Color("39a8ff")
const BLUE_DARK := Color("153f68")
const RED := Color("ff5468")
const RED_DARK := Color("682333")
const BAR_WIDTH := 484.0
const BUILD_BARRACKS := 0
const BUILD_DEFENSE_TOWER := 2
const FORMATION_LINE := 0
const FORMATION_WEDGE := 1
const FORMATION_LOOSE := 2

var gold_label: Label
var ally_hq_label: Label
var enemy_hq_label: Label
var timer_label: Label
var ally_percent_label: Label
var enemy_percent_label: Label
var ally_occupancy_fill: ColorRect
var enemy_occupancy_fill: ColorRect
var message_label: Label
var instruction_label: Label
var result_overlay: ColorRect
var result_label: Label
var restart_button: Button
var barracks_button: Button
var tower_button: Button
var template_buttons: Array[Button] = []
var edit_panel: ColorRect
var edit_count_labels: Dictionary = {}
var edit_formation_buttons: Array[Button] = []

var message_time_left := 0.0
var last_ally_occupancy := 0.5
var selected_build_kind := BUILD_BARRACKS
var selected_template := {"melee": 7, "ranged": 4, "siege": 1, "dragon": 0}
var selected_formation := FORMATION_LINE
var editing_building_id := -1
var editing_template: Dictionary = {}
var editing_formation := FORMATION_LINE

@export var message_duration := 1.1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_status_panel()
	_build_message()
	_build_spawner_selector()
	_build_barracks_editor()
	_build_instruction()
	_build_result_overlay()
	update_stats(GameConfig.START_GOLD, GameConfig.HQ_MAX_HP, GameConfig.HQ_MAX_HP, GameConfig.MATCH_DURATION, 0.5)


func update_stats(
	ally_gold: int,
	ally_hq_hp: float,
	enemy_hq_hp: float,
	time_remaining: float,
	ally_occupancy: float
) -> void:
	var blue_share := clampf(ally_occupancy, 0.0, 1.0)
	last_ally_occupancy = blue_share
	var red_share := 1.0 - blue_share
	gold_label.text = "GOLD  %03d" % max(0, ally_gold)
	ally_hq_label.text = "BLUE HQ  %04d" % ceili(maxf(0.0, ally_hq_hp))
	enemy_hq_label.text = "RED HQ  %04d" % ceili(maxf(0.0, enemy_hq_hp))
	timer_label.text = _format_time(time_remaining)
	ally_percent_label.text = "BLUE %d%%" % roundi(blue_share * 100.0)
	enemy_percent_label.text = "%d%% RED" % roundi(red_share * 100.0)
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
	if message_time_left <= 0.0:
		return
	message_time_left = maxf(0.0, message_time_left - delta)
	message_label.modulate.a = minf(1.0, message_time_left / 0.22)
	if message_time_left <= 0.0:
		message_label.visible = false


func _build_status_panel() -> void:
	var panel := ColorRect.new()
	panel.position = Vector2(14, 12)
	panel.size = Vector2(512, 126)
	panel.color = Color(GameConfig.COLOR_PANEL, 0.96)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var title := _make_label(Vector2(14, 7), Vector2(300, 24), 16, GameConfig.COLOR_TEAL)
	title.text = "FRONTLINE // LIVE SECTOR"
	panel.add_child(title)

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
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(message_label)


func _build_instruction() -> void:
	var plate := ColorRect.new()
	plate.position = Vector2(30, 891)
	plate.size = Vector2(480, 48)
	plate.color = Color(GameConfig.COLOR_PANEL, 0.94)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	instruction_label = _make_label(Vector2.ZERO, plate.size, 17, BLUE)
	instruction_label.text = "TAP BLUE TERRITORY // BARRACKS 100"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(instruction_label)


func _build_spawner_selector() -> void:
	var plate := ColorRect.new()
	plate.position = Vector2(30, 817)
	plate.size = Vector2(480, 62)
	plate.color = Color(GameConfig.COLOR_PANEL, 0.94)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	barracks_button = _make_selector_button("BARRACKS\n100", Vector2(3, 7), Vector2(104, 48))
	tower_button = _make_selector_button("TOWER\n120", Vector2(111, 7), Vector2(82, 48))
	template_buttons = [
		_make_selector_button("SHIELD\nLINE", Vector2(197, 7), Vector2(90, 48)),
		_make_selector_button("FIRE\nLOOSE", Vector2(291, 7), Vector2(90, 48)),
		_make_selector_button("CHARGE\nWEDGE", Vector2(385, 7), Vector2(90, 48)),
	]
	barracks_button.pressed.connect(func() -> void: _select_build_kind(BUILD_BARRACKS))
	tower_button.pressed.connect(func() -> void: _select_build_kind(BUILD_DEFENSE_TOWER))
	for index in template_buttons.size():
		template_buttons[index].pressed.connect(func() -> void: select_template_preset(index))
	plate.add_child(barracks_button)
	plate.add_child(tower_button)
	for button in template_buttons: plate.add_child(button)
	_update_selector_styles()


func _make_selector_button(label_text: String, at: Vector2, dimensions := Vector2(92, 48)) -> Button:
	var button := Button.new()
	button.position = at
	button.size = dimensions
	button.text = label_text
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 10)
	return button


func _select_build_kind(build_kind: int) -> void:
	if build_kind not in [BUILD_BARRACKS, BUILD_DEFENSE_TOWER]:
		return
	selected_build_kind = build_kind
	instruction_label.text = "TAP WITHIN HQ 5x5 // DEFENSE TOWER 120" if build_kind == BUILD_DEFENSE_TOWER else "TAP BLUE TERRITORY // BARRACKS 100"
	_update_selector_styles()
	build_kind_selected.emit(build_kind)


func _update_selector_styles() -> void:
	_style_selector_button(barracks_button, selected_build_kind == BUILD_BARRACKS)
	_style_selector_button(tower_button, selected_build_kind == BUILD_DEFENSE_TOWER)
	for index in template_buttons.size(): _style_selector_button(template_buttons[index], _preset_matches(index))


func select_template_preset(preset: int) -> void:
	match clampi(preset, 0, 2):
		1:
			selected_template = {"melee": 4, "ranged": 7, "siege": 1, "dragon": 0}
			selected_formation = FORMATION_LOOSE
		2:
			selected_template = {"melee": 9, "ranged": 1, "siege": 1, "dragon": 1}
			selected_formation = FORMATION_WEDGE
		_:
			selected_template = {"melee": 7, "ranged": 4, "siege": 1, "dragon": 0}
			selected_formation = FORMATION_LINE
	_select_build_kind(BUILD_BARRACKS)
	_update_selector_styles()
	template_selected.emit(selected_template.duplicate(), selected_formation)


func get_selected_template() -> Dictionary:
	return selected_template.duplicate()


func get_selected_formation() -> int:
	return selected_formation


func _preset_matches(index: int) -> bool:
	return index == 0 and selected_formation == FORMATION_LINE and int(selected_template.melee) == 7 \
		or index == 1 and selected_formation == FORMATION_LOOSE and int(selected_template.ranged) == 7 \
		or index == 2 and selected_formation == FORMATION_WEDGE and int(selected_template.dragon) == 1


func _build_barracks_editor() -> void:
	edit_panel = ColorRect.new()
	edit_panel.name = "BarracksEditor"
	edit_panel.position = Vector2(30, 585)
	edit_panel.size = Vector2(480, 218)
	edit_panel.color = Color(GameConfig.COLOR_PANEL, 0.98)
	edit_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	edit_panel.visible = false
	add_child(edit_panel)
	var title := _make_label(Vector2(12, 7), Vector2(280, 24), 16, BLUE)
	title.text = "BARRACKS // NEXT LEGION"
	edit_panel.add_child(title)
	var close := _make_selector_button("X", Vector2(438, 5), Vector2(34, 28))
	close.pressed.connect(close_barracks_panel)
	edit_panel.add_child(close)
	var roles := ["melee", "ranged", "siege", "dragon"]
	for row in roles.size():
		var role: String = roles[row]
		var y := 38.0 + row * 31.0
		var label := _make_label(Vector2(12, y), Vector2(92, 26), 13, GameConfig.COLOR_TEXT)
		label.text = role.to_upper()
		edit_panel.add_child(label)
		var minus := _make_selector_button("−", Vector2(105, y), Vector2(32, 26))
		var count := _make_label(Vector2(140, y), Vector2(38, 26), 15, BLUE)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var plus := _make_selector_button("+", Vector2(181, y), Vector2(32, 26))
		minus.pressed.connect(func() -> void: adjust_edit_role(role, -1))
		plus.pressed.connect(func() -> void: adjust_edit_role(role, 1))
		edit_count_labels[role] = count
		edit_panel.add_child(minus)
		edit_panel.add_child(count)
		edit_panel.add_child(plus)
	edit_formation_buttons = [
		_make_selector_button("LINE", Vector2(232, 42), Vector2(73, 32)),
		_make_selector_button("WEDGE", Vector2(310, 42), Vector2(73, 32)),
		_make_selector_button("LOOSE", Vector2(388, 42), Vector2(73, 32)),
	]
	for formation in edit_formation_buttons.size():
		edit_formation_buttons[formation].pressed.connect(func() -> void: select_edit_formation(formation))
		edit_panel.add_child(edit_formation_buttons[formation])
	var waypoint := _make_selector_button("WAYPOINT", Vector2(232, 90), Vector2(110, 38))
	var demolish := _make_selector_button("DEMOLISH", Vector2(350, 90), Vector2(111, 38))
	waypoint.pressed.connect(request_edit_waypoint)
	demolish.pressed.connect(request_edit_demolish)
	edit_panel.add_child(waypoint)
	edit_panel.add_child(demolish)
	var hint := _make_label(Vector2(232, 137), Vector2(230, 54), 11, Color(GameConfig.COLOR_TEXT, 0.68))
	hint.text = "MAX 12 // SIEGE 2 // DRAGON 1\nCHANGES APPLY TO NEXT LEGION"
	edit_panel.add_child(hint)


func open_barracks_panel(config: Dictionary) -> void:
	editing_building_id = int(config.get("id", -1))
	editing_template = Dictionary(config.get("template", {"melee": 6, "ranged": 3, "siege": 1, "dragon": 0})).duplicate()
	editing_formation = int(config.get("formation", FORMATION_LINE))
	edit_panel.visible = editing_building_id >= 0
	_refresh_barracks_editor()


func close_barracks_panel() -> void:
	edit_panel.visible = false
	editing_building_id = -1


func adjust_edit_role(role: String, delta: int) -> bool:
	if editing_building_id < 0 or role not in ["melee", "ranged", "siege", "dragon"]:
		return false
	var current := int(editing_template.get(role, 0))
	var proposed := current + delta
	if proposed < 0 or role == "siege" and proposed > GameConfig.LEGION_MAX_SIEGE or role == "dragon" and proposed > GameConfig.LEGION_MAX_DRAGONS:
		return false
	var total := 0
	for key in ["melee", "ranged", "siege", "dragon"]: total += int(editing_template.get(key, 0))
	if total + delta < 1 or total + delta > GameConfig.LEGION_MAX_MEMBERS:
		return false
	editing_template[role] = proposed
	_emit_barracks_edit()
	return true


func select_edit_formation(formation: int) -> void:
	if editing_building_id < 0 or formation < FORMATION_LINE or formation > FORMATION_LOOSE:
		return
	editing_formation = formation
	_emit_barracks_edit()


func request_edit_waypoint() -> void:
	if editing_building_id >= 0:
		waypoint_requested.emit(editing_building_id)
		edit_panel.visible = false


func request_edit_demolish() -> void:
	if editing_building_id >= 0:
		demolish_requested.emit(editing_building_id)
		close_barracks_panel()


func _emit_barracks_edit() -> void:
	_refresh_barracks_editor()
	barracks_config_changed.emit(editing_building_id, editing_template.duplicate(), editing_formation)


func _refresh_barracks_editor() -> void:
	for role in edit_count_labels:
		edit_count_labels[role].text = str(int(editing_template.get(role, 0)))
	for formation in edit_formation_buttons.size():
		_style_selector_button(edit_formation_buttons[formation], formation == editing_formation)


func _style_selector_button(button: Button, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BLUE.darkened(0.56) if selected else GameConfig.COLOR_NEUTRAL.darkened(0.18)
	normal.border_color = BLUE if selected else Color(BLUE_DARK, 0.78)
	normal.set_border_width_all(3 if selected else 1)
	normal.corner_radius_top_left = 3
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.corner_radius_bottom_right = 3
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
	card.mouse_filter = Control.MOUSE_FILTER_STOP
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


func _make_label(at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _style_button(button: Button, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.darkened(0.56)
	normal.border_color = accent
	normal.set_border_width_all(2)
	normal.corner_radius_top_left = 3
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.corner_radius_bottom_right = 3
	var pressed := normal.duplicate()
	pressed.bg_color = accent.darkened(0.3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", pressed)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", GameConfig.COLOR_TEXT)
