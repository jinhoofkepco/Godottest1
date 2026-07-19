class_name DefenseHud
extends Control

signal restart_pressed
signal spawner_kind_selected(unit_kind: int)

const GameConfig = preload("res://scripts/game_config.gd")

const BLUE := Color("39a8ff")
const BLUE_DARK := Color("153f68")
const RED := Color("ff5468")
const RED_DARK := Color("682333")
const BAR_WIDTH := 484.0
const UNIT_MELEE := 0
const UNIT_RANGED := 1

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
var melee_button: Button
var ranged_button: Button

var message_time_left := 0.0
var last_ally_occupancy := 0.5
var selected_unit_kind := UNIT_MELEE

@export var message_duration := 1.1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_status_panel()
	_build_message()
	_build_spawner_selector()
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
	instruction_label.text = "TAP BLUE TERRITORY // MELEE SPAWNER 60"
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

	melee_button = _make_selector_button("MELEE 60", Vector2(8, 7))
	ranged_button = _make_selector_button("RANGED 80", Vector2(244, 7))
	melee_button.pressed.connect(func() -> void: _select_spawner_kind(UNIT_MELEE))
	ranged_button.pressed.connect(func() -> void: _select_spawner_kind(UNIT_RANGED))
	plate.add_child(melee_button)
	plate.add_child(ranged_button)
	_update_selector_styles()


func _make_selector_button(label_text: String, at: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = Vector2(228, 48)
	button.text = label_text
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 17)
	return button


func _select_spawner_kind(unit_kind: int) -> void:
	if unit_kind not in [UNIT_MELEE, UNIT_RANGED] or unit_kind == selected_unit_kind:
		return
	selected_unit_kind = unit_kind
	instruction_label.text = "TAP BLUE TERRITORY // %s SPAWNER %d" % [
		"RANGED" if unit_kind == UNIT_RANGED else "MELEE",
		GameConfig.RANGED_SPAWNER_COST if unit_kind == UNIT_RANGED else GameConfig.SPAWNER_COST,
	]
	_update_selector_styles()
	spawner_kind_selected.emit(unit_kind)


func _update_selector_styles() -> void:
	_style_selector_button(melee_button, selected_unit_kind == UNIT_MELEE)
	_style_selector_button(ranged_button, selected_unit_kind == UNIT_RANGED)


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
