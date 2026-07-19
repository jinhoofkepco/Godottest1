class_name DefenseHud
extends Control

signal next_wave_pressed
signal restart_pressed

const GameConfig = preload("res://scripts/game_config.gd")

var gold_label: Label
var core_label: Label
var wave_label: Label
var next_button: Button
var result_overlay: ColorRect
var result_label: Label
var restart_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_result_overlay()


func update_stats(gold: int, core_hp: int, wave: int) -> void:
	gold_label.text = "GOLD  %03d" % gold
	core_label.text = "CORE  %02d" % core_hp
	wave_label.text = "WAVE  %d/%d" % [wave, GameConfig.TOTAL_WAVES]


func set_wave_button(enabled: bool, wave: int) -> void:
	next_button.disabled = not enabled
	next_button.text = "START WAVE %d" % clampi(wave + 1, 1, GameConfig.TOTAL_WAVES)


func show_result(result: String) -> void:
	result_label.text = result
	result_label.modulate = GameConfig.COLOR_TEAL if result == "VICTORY" else GameConfig.COLOR_ORANGE
	result_overlay.visible = true


func _build_top_bar() -> void:
	var panel := ColorRect.new()
	panel.position = Vector2(14, 12)
	panel.size = Vector2(512, 84)
	panel.color = GameConfig.COLOR_PANEL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var title := Label.new()
	title.position = Vector2(14, 7)
	title.size = Vector2(300, 25)
	title.text = "WAR GRID // SECTOR 09"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", GameConfig.COLOR_TEAL)
	panel.add_child(title)

	gold_label = _stat_label(Vector2(14, 39), 128)
	core_label = _stat_label(Vector2(146, 39), 120)
	wave_label = _stat_label(Vector2(270, 39), 115)
	panel.add_child(gold_label)
	panel.add_child(core_label)
	panel.add_child(wave_label)

	next_button = Button.new()
	next_button.position = Vector2(388, 13)
	next_button.size = Vector2(112, 58)
	next_button.text = "START WAVE 1"
	next_button.add_theme_font_size_override("font_size", 13)
	_style_button(next_button, GameConfig.COLOR_TEAL)
	next_button.pressed.connect(func() -> void: next_wave_pressed.emit())
	panel.add_child(next_button)


func _build_result_overlay() -> void:
	result_overlay = ColorRect.new()
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.color = Color(0.035, 0.055, 0.09, 0.9)
	result_overlay.visible = false
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(result_overlay)

	var card := ColorRect.new()
	card.position = Vector2(65, 330)
	card.size = Vector2(410, 250)
	card.color = GameConfig.COLOR_PANEL
	result_overlay.add_child(card)

	result_label = Label.new()
	result_label.position = Vector2(20, 38)
	result_label.size = Vector2(370, 70)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 42)
	card.add_child(result_label)

	var subtitle := Label.new()
	subtitle.position = Vector2(20, 112)
	subtitle.size = Vector2(370, 30)
	subtitle.text = "SECTOR RUN COMPLETE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(GameConfig.COLOR_TEXT, 0.7))
	card.add_child(subtitle)

	restart_button = Button.new()
	restart_button.position = Vector2(95, 164)
	restart_button.size = Vector2(220, 58)
	restart_button.text = "RESTART"
	restart_button.add_theme_font_size_override("font_size", 19)
	_style_button(restart_button, GameConfig.COLOR_ORANGE)
	restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	card.add_child(restart_button)


func _stat_label(at: Vector2, width: float) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(width, 30)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", GameConfig.COLOR_TEXT)
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
	var disabled := normal.duplicate()
	disabled.bg_color = GameConfig.COLOR_NEUTRAL
	disabled.border_color = GameConfig.COLOR_GRID_LINE
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", pressed)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", GameConfig.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Color(GameConfig.COLOR_TEXT, 0.35))

