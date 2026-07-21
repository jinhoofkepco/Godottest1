class_name MatchSettingsPanel
extends Control

signal start_requested(values: Dictionary)

const GameConfig = preload("res://scripts/game_config.gd")
const TAB_ORDER := ["melee", "ranged", "siege", "dragon"]
const CHANGED_COLOR := Color("ffad5b")
const INVALID_COLOR := Color("ff5c70")
const FIELD_BACKGROUND := Color("101b2d")

var _schema: Array = []
var _pending_values: Dictionary = {}
var _default_values: Dictionary = {}
var _fields_by_path: Dictionary = {}
var _field_paths := PackedStringArray()
var _field_rows: Dictionary = {}
var _field_editors: Dictionary = {}
var _invalid_paths: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _active_group := "melee"

var _scroll: ScrollContainer
var _field_list: VBoxContainer
var _feedback: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = Vector2(GameConfig.VIEW_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 2000
	_build_ui()
	visible = false


func open(schema: Array, values: Dictionary) -> void:
	_schema = schema.duplicate(true)
	_pending_values = values.duplicate(true)
	_default_values = values.duplicate(true)
	_fields_by_path.clear()
	_field_paths.clear()
	for raw_field in _schema:
		var field: Dictionary = raw_field
		var path := "%s.%s" % [String(field.get("group", "")), String(field.get("key", ""))]
		_fields_by_path[path] = field.duplicate(true)
		_field_paths.append(path)
		_set_dictionary_path(_default_values, path, _normalized_value(field, field.get("default", 0.0)))
	_active_group = String(TAB_ORDER[0])
	_invalid_paths.clear()
	_set_feedback("CHANGES APPLY TO BLUE AND RED", GameConfig.COLOR_TEXT)
	_refresh_tabs()
	_rebuild_fields()
	visible = true
	move_to_front()


func accept_normalized(values: Dictionary) -> void:
	_pending_values = values.duplicate(true)
	_invalid_paths.clear()
	visible = false


func show_validation_errors(errors: Array) -> void:
	_invalid_paths.clear()
	var messages := PackedStringArray()
	for raw_error in errors:
		var message := String(raw_error)
		messages.append(message)
		for path in _field_paths:
			if message.contains(path):
				_invalid_paths[path] = true
	_set_feedback("CHECK SETTINGS\n%s" % "\n".join(messages.slice(0, mini(3, messages.size()))), INVALID_COLOR)
	_rebuild_fields()


func serialize_settings(values: Dictionary) -> String:
	var sort_keys := true
	return JSON.stringify({"schema_version": 1, "settings": values}, "  ", sort_keys, true)


func press_start() -> void:
	start_requested.emit(_pending_values.duplicate(true))


func press_defaults() -> void:
	_pending_values = _default_values.duplicate(true)
	_invalid_paths.clear()
	_set_feedback("DEFAULT SETTINGS RESTORED", GameConfig.COLOR_TEAL)
	_rebuild_fields()


func press_copy() -> void:
	DisplayServer.clipboard_set(serialize_settings(_pending_values))
	_set_feedback("SETTINGS COPIED", GameConfig.COLOR_TEAL)


func select_group(group: String) -> bool:
	if not TAB_ORDER.has(group):
		return false
	_active_group = group
	_refresh_tabs()
	_rebuild_fields()
	return true


func set_field_value(path: String, value: Variant) -> bool:
	if not _fields_by_path.has(path):
		return false
	var field: Dictionary = _fields_by_path[path]
	var normalized: Variant = _normalized_value(field, value)
	_set_dictionary_path(_pending_values, path, normalized)
	_invalid_paths.erase(path)
	if _field_editors.has(path):
		_field_editors[path].text = _format_value(field, normalized)
	_update_row_style(path)
	return true


func get_field_value(path: String) -> Variant:
	return _get_dictionary_path(_pending_values, path)


func get_field_metadata(path: String) -> Dictionary:
	return Dictionary(_fields_by_path.get(path, {})).duplicate(true)


func get_field_display_text(path: String) -> String:
	if _field_editors.has(path):
		return String(_field_editors[path].text)
	if not _fields_by_path.has(path):
		return ""
	return _format_value(_fields_by_path[path], get_field_value(path))


func get_field_paths() -> PackedStringArray:
	return _field_paths.duplicate()


func get_pending_values() -> Dictionary:
	return _pending_values.duplicate(true)


func get_tab_order() -> PackedStringArray:
	return PackedStringArray(TAB_ORDER)


func get_scroll_container() -> ScrollContainer:
	return _scroll


func get_feedback_text() -> String:
	return _feedback.text


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "OpaqueBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(GameConfig.VIEW_SIZE)
	backdrop.color = Color("091221")
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var accent := ColorRect.new()
	accent.position = Vector2(0, 0)
	accent.size = Vector2(540, 5)
	accent.color = GameConfig.COLOR_TEAL
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(accent)

	var title := _make_label("MATCH SETTINGS // UNIT LAB", Vector2(22, 22), Vector2(496, 34), 24, GameConfig.COLOR_TEAL)
	add_child(title)
	var subtitle := _make_label("ONE PROFILE CONTROLS BOTH ARMIES", Vector2(23, 58), Vector2(494, 24), 13, Color(GameConfig.COLOR_TEXT, 0.67))
	add_child(subtitle)

	for index in TAB_ORDER.size():
		var group: String = String(TAB_ORDER[index])
		var tab := Button.new()
		tab.position = Vector2(18 + index * 126, 94)
		tab.size = Vector2(120, 46)
		tab.text = group.to_upper()
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.add_theme_font_size_override("font_size", 13)
		tab.pressed.connect(select_group.bind(group))
		_tab_buttons[group] = tab
		add_child(tab)

	_scroll = ScrollContainer.new()
	_scroll.name = "SettingsScroll"
	_scroll.position = Vector2(18, 153)
	_scroll.size = Vector2(504, 610)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	_field_list = VBoxContainer.new()
	_field_list.custom_minimum_size = Vector2(486, 0)
	_field_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_field_list)

	_feedback = _make_label("", Vector2(22, 772), Vector2(496, 62), 12, GameConfig.COLOR_TEXT)
	_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_feedback)

	var defaults := _make_action_button("DEFAULTS", Vector2(18, 850), Vector2(150, 58), GameConfig.COLOR_ORANGE)
	defaults.pressed.connect(press_defaults)
	add_child(defaults)
	var copy := _make_action_button("COPY SETTINGS", Vector2(174, 850), Vector2(174, 58), GameConfig.COLOR_TEAL)
	copy.pressed.connect(press_copy)
	add_child(copy)
	var start := _make_action_button("START", Vector2(354, 850), Vector2(168, 58), GameConfig.COLOR_ALLY)
	start.pressed.connect(press_start)
	add_child(start)

	var hint := _make_label("EDIT VALUES  //  SCROLL FOR ALL STATS", Vector2(22, 917), Vector2(496, 24), 11, Color(GameConfig.COLOR_TEXT, 0.52))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _rebuild_fields() -> void:
	for child in _field_list.get_children():
		child.free()
	_field_rows.clear()
	_field_editors.clear()
	for raw_field in _schema:
		var field: Dictionary = raw_field
		if String(field.get("group", "")) != _active_group:
			continue
		_add_field_row(field)
	_scroll.scroll_vertical = 0


func _add_field_row(field: Dictionary) -> void:
	var path := "%s.%s" % [String(field.group), String(field.key)]
	var row := Panel.new()
	row.custom_minimum_size = Vector2(486, 54)
	row.tooltip_text = path
	_field_rows[path] = row
	_field_list.add_child(row)

	var label := _make_label(String(field.label), Vector2(12, 2), Vector2(218, 50), 12, GameConfig.COLOR_TEXT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var minus := Button.new()
	minus.position = Vector2(228, 7)
	minus.size = Vector2(42, 40)
	minus.text = "−"
	minus.add_theme_font_size_override("font_size", 20)
	minus.pressed.connect(_adjust_field.bind(path, -float(field.step)))
	row.add_child(minus)
	var editor := LineEdit.new()
	editor.position = Vector2(274, 7)
	editor.size = Vector2(156, 40)
	editor.text = _format_value(field, get_field_value(path))
	editor.alignment = HORIZONTAL_ALIGNMENT_CENTER
	editor.add_theme_font_size_override("font_size", 14)
	editor.text_submitted.connect(_on_editor_text_submitted.bind(path))
	editor.focus_exited.connect(_on_editor_focus_exited.bind(path))
	editor.tooltip_text = "%s  [%s .. %s]  STEP %s" % [path, field.minimum, field.maximum, field.step]
	_field_editors[path] = editor
	row.add_child(editor)
	var plus := Button.new()
	plus.position = Vector2(434, 7)
	plus.size = Vector2(42, 40)
	plus.text = "+"
	plus.add_theme_font_size_override("font_size", 18)
	plus.pressed.connect(_adjust_field.bind(path, float(field.step)))
	row.add_child(plus)
	_update_row_style(path)


func _on_editor_text_submitted(text: String, path: String) -> void:
	_commit_editor_text(path, text)


func _on_editor_focus_exited(path: String) -> void:
	if _field_editors.has(path):
		_commit_editor_text(path, String(_field_editors[path].text))


func _commit_editor_text(path: String, text: String) -> void:
	if not text.is_valid_float():
		_field_editors[path].text = _format_value(_fields_by_path[path], get_field_value(path))
		_set_feedback("ENTER A NUMERIC VALUE", INVALID_COLOR)
		return
	set_field_value(path, text.to_float())


func _adjust_field(path: String, amount: float) -> void:
	set_field_value(path, float(get_field_value(path)) + amount)


func _normalized_value(field: Dictionary, value: Variant) -> Variant:
	var number := clampf(float(value), float(field.get("minimum", -INF)), float(field.get("maximum", INF)))
	return roundi(number) if bool(field.get("integer", false)) else number


func _format_value(field: Dictionary, value: Variant) -> String:
	if bool(field.get("integer", false)):
		return str(int(value))
	var text := String.num(float(value), 6)
	while text.contains(".") and text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text = text.trim_suffix(".")
	return text


func _update_row_style(path: String) -> void:
	if not _field_rows.has(path):
		return
	var accent := Color(GameConfig.COLOR_TEAL, 0.28)
	if _invalid_paths.has(path):
		accent = INVALID_COLOR
	elif _value_changed(path):
		accent = CHANGED_COLOR
	var style := StyleBoxFlat.new()
	style.bg_color = FIELD_BACKGROUND
	style.border_color = accent
	style.set_border_width_all(2 if _invalid_paths.has(path) or _value_changed(path) else 1)
	style.set_corner_radius_all(4)
	_field_rows[path].add_theme_stylebox_override("panel", style)


func _value_changed(path: String) -> bool:
	var current: Variant = get_field_value(path)
	var original: Variant = _get_dictionary_path(_default_values, path)
	if typeof(current) == TYPE_INT and typeof(original) == TYPE_INT:
		return int(current) != int(original)
	return not is_equal_approx(float(current), float(original))


func _refresh_tabs() -> void:
	for group in _tab_buttons:
		var selected := String(group) == _active_group
		var style := StyleBoxFlat.new()
		style.bg_color = GameConfig.COLOR_TEAL.darkened(0.60) if selected else GameConfig.COLOR_NEUTRAL.darkened(0.18)
		style.border_color = GameConfig.COLOR_TEAL if selected else Color(GameConfig.COLOR_TEAL, 0.30)
		style.set_border_width_all(2 if selected else 1)
		style.set_corner_radius_all(4)
		_tab_buttons[group].add_theme_stylebox_override("normal", style)
		_tab_buttons[group].add_theme_color_override("font_color", GameConfig.COLOR_TEXT if selected else Color(GameConfig.COLOR_TEXT, 0.58))


func _set_feedback(text: String, color: Color) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", color)


func _set_dictionary_path(values: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var cursor := values
	for index in parts.size() - 1:
		var key := String(parts[index])
		if not cursor.has(key) or not cursor[key] is Dictionary:
			cursor[key] = {}
		cursor = cursor[key]
	cursor[String(parts[-1])] = value


func _get_dictionary_path(values: Dictionary, path: String) -> Variant:
	var cursor: Variant = values
	for raw_part in path.split("."):
		if not cursor is Dictionary:
			return null
		cursor = cursor.get(String(raw_part))
	return cursor


func _make_label(text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_action_button(text: String, at: Vector2, dimensions: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 14)
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.darkened(0.62)
	normal.border_color = accent
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	var pressed := normal.duplicate()
	pressed.bg_color = accent.darkened(0.38)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", pressed)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", GameConfig.COLOR_TEXT)
	return button
