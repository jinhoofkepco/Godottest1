class_name BattleBuildingView
extends Node2D

signal collapse_finished(building_id: int)

const GameConfig = preload("res://scripts/game_config.gd")
const WORLD_ATLAS = preload("res://assets/world/world_atlas.png")
const WORLD_METADATA_PATH := "res://assets/world/world_atlas.json"
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const BUILDING_HQ := 0
const BUILDING_SPAWNER := 1
const BUILDING_DEFENSE_TOWER := 2
const BUILDING_DRAGON_LAIR := 3
const BUILDING_RALLY_POINT := 4
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_SIEGE := 3

var building_id := 0
var team := TEAM_ALLY
var kind := BUILDING_HQ
var unit_kind := UNIT_MELEE
var cell := Vector2i.ZERO
var hp := 1.0
var max_hp := 1.0
var rally_mode := 0
var formation := 0
var waiting_count := 0
var complete := true
var construction_duration := 0.0
var construction_remaining := 0.0
var construction_progress := 1.0
var _flash_left := 0.0
var _collapse_left := 0.0
static var _opaque_bounds_by_name: Dictionary = {}
static var _metadata_loaded := false


func setup(board: GridBoard, record: Dictionary) -> void:
	building_id = int(record.id)
	team = int(record.team)
	kind = int(record.kind)
	unit_kind = int(record.get("unit_kind", UNIT_MELEE))
	cell = Vector2i(record.cell)
	if kind == BUILDING_RALLY_POINT:
		z_as_relative = false
		z_index = 45
	position = board.cell_to_world(cell)
	update_from_data(record)
	queue_redraw()


func update_from_data(record: Dictionary) -> void:
	hp = float(record.hp)
	max_hp = float(record.max_hp)
	rally_mode = int(record.get("rally_mode", 0))
	formation = int(record.get("formation", 0))
	waiting_count = int(record.get("waiting_count", 0))
	complete = bool(record.get("complete", true))
	construction_duration = float(record.get("construction_duration", 0.0))
	construction_remaining = float(record.get("construction_remaining", 0.0))
	construction_progress = float(record.get("construction_progress", 1.0))
	queue_redraw()


func flash_hit() -> void:
	_flash_left = 0.18
	queue_redraw()


func start_destroy() -> void:
	_collapse_left = 0.6
	queue_redraw()


func _process(delta: float) -> void:
	if not complete and construction_remaining > 0.0:
		construction_remaining = maxf(0.0, construction_remaining - delta)
		construction_progress = 1.0 - construction_remaining / maxf(0.001, construction_duration)
		hp = minf(max_hp, hp + max_hp * (1.0 - GameConfig.BUILDING_CONSTRUCTION_START_HP_RATIO) / maxf(0.001, construction_duration) * delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	if _collapse_left > 0.0:
		_collapse_left = maxf(0.0, _collapse_left - delta)
		scale = Vector2(1.0, maxf(0.05, _collapse_left / 0.6))
		if _collapse_left <= 0.0:
			collapse_finished.emit(building_id)
			set_process(false)
			queue_free()
	queue_redraw()


func _draw() -> void:
	var color := GameConfig.COLOR_ALLY.lightened(0.18) if team == TEAM_ALLY else GameConfig.COLOR_ENEMY.lightened(0.12)
	_draw_ground_plinth(color)
	_draw_soft_shadow()
	if not complete:
		_draw_construction(color)
		_draw_hp_bar(color, -31.0)
		return
	if kind == BUILDING_RALLY_POINT:
		_draw_rally_point(color)
		_draw_hp_bar(color, -40.0)
		return
	var destination := _sprite_destination()
	var source := _sprite_region()
	var modulate := Color(1.85, 1.85, 1.85, 1.0) if _flash_left > 0.0 else Color.WHITE
	draw_texture_rect_region(WORLD_ATLAS, destination, source, modulate)
	var bounds := _sprite_opaque_bounds()
	var bar_y := destination.position.y + float(bounds.position.y) / float(GameConfig.WORLD_ATLAS_CELL_SIZE) * destination.size.y - 7.0
	_draw_hp_bar(color, bar_y)


func uses_baked_sprite() -> bool:
	return WORLD_ATLAS != null and kind != BUILDING_RALLY_POINT


func _draw_construction(color: Color) -> void:
	var ground_y := get_ground_contact_y()
	var height := lerpf(8.0, 46.0, clampf(construction_progress, 0.0, 1.0))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-19, ground_y), Vector2(0, ground_y + 6), Vector2(19, ground_y), Vector2(0, ground_y - 6),
	]), Color(color.darkened(0.36), 0.88))
	for x in [-15.0, 15.0]:
		draw_line(Vector2(x, ground_y), Vector2(x, ground_y - height), Color("b9c5cc", 0.78), 2.0, true)
	draw_line(Vector2(-15, ground_y - height), Vector2(15, ground_y - height), Color(color.lightened(0.25), 0.78), 2.0, true)
	draw_line(Vector2(-15, ground_y - height * 0.48), Vector2(15, ground_y - height * 0.48), Color("b9c5cc", 0.52), 1.4, true)
	draw_line(Vector2(-15, ground_y), Vector2(15, ground_y - height), Color("b9c5cc", 0.42), 1.2, true)
	var percent := "%d%%" % roundi(construction_progress * 100.0)
	draw_string(ThemeDB.fallback_font, Vector2(-14, ground_y + 20), percent, HORIZONTAL_ALIGNMENT_CENTER, 28, 11, Color(GameConfig.COLOR_TEXT, 0.82))


func _draw_rally_point(color: Color) -> void:
	var ground_y := get_ground_contact_y()
	draw_line(Vector2(-7, ground_y), Vector2(-7, ground_y - 34), Color("d8e2ef"), 3.0, true)
	if rally_mode == 0:
		draw_colored_polygon(PackedVector2Array([Vector2(-5, ground_y - 33), Vector2(21, ground_y - 26), Vector2(-5, ground_y - 18)]), color.lightened(0.25))
		draw_line(Vector2(6, ground_y - 10), Vector2(20, ground_y - 10), color.lightened(0.45), 3.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(20, ground_y - 15), Vector2(29, ground_y - 10), Vector2(20, ground_y - 5)]), color.lightened(0.45))
	else:
		draw_circle(Vector2(3, ground_y - 19), 17.0, Color(color, 0.18))
		draw_arc(Vector2(3, ground_y - 19), 17.0, 0.0, TAU, 24, color.lightened(0.35), 3.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(3, ground_y - 31), Vector2(14, ground_y - 26), Vector2(11, ground_y - 12), Vector2(3, ground_y - 5), Vector2(-5, ground_y - 12), Vector2(-8, ground_y - 26)]), Color(color.darkened(0.18), 0.92))
	var label := "%d" % waiting_count
	draw_string(ThemeDB.fallback_font, Vector2(-7 - label.length() * 3, ground_y + 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _draw_hp_bar(color: Color, bar_y: float) -> void:
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-22, bar_y), Vector2(44, 5)), Color("0b101b"))
	draw_rect(Rect2(Vector2(-21, bar_y + 1.0), Vector2(42 * ratio, 3)), color.lightened(0.3))


func _sprite_index() -> int:
	var team_offset := 1 if team == TEAM_ENEMY else 0
	if kind == BUILDING_HQ:
		return team_offset
	if kind == BUILDING_SPAWNER:
		if unit_kind == UNIT_SIEGE:
			return 6 + team_offset
		return (4 if unit_kind == UNIT_RANGED else 2) + team_offset
	if kind == BUILDING_DEFENSE_TOWER:
		return 6 + team_offset
	return 8 + team_offset


func _sprite_region() -> Rect2:
	var sprite_index := _sprite_index()
	var cell_size := float(GameConfig.WORLD_ATLAS_CELL_SIZE)
	return Rect2(Vector2(float(sprite_index % 4), float(sprite_index / 4)) * cell_size, Vector2.ONE * cell_size)


func _sprite_size() -> Vector2:
	if kind == BUILDING_HQ:
		return Vector2(86, 86)
	if kind == BUILDING_DEFENSE_TOWER:
		return Vector2(76, 76)
	if kind == BUILDING_DRAGON_LAIR:
		return Vector2(78, 78)
	return Vector2(72, 72)


func get_ground_contact_y() -> float:
	return GameConfig.BUILDING_GROUND_CONTACT_Y


func get_sprite_opaque_bottom_y() -> float:
	var destination := _sprite_destination()
	var bounds := _sprite_opaque_bounds()
	var opaque_bottom := float(bounds.position.y + bounds.size.y)
	return destination.position.y + opaque_bottom / float(GameConfig.WORLD_ATLAS_CELL_SIZE) * destination.size.y


func _sprite_destination() -> Rect2:
	var sprite_size := _sprite_size()
	var bounds := _sprite_opaque_bounds()
	var opaque_bottom := float(bounds.position.y + bounds.size.y)
	var top := get_ground_contact_y() - opaque_bottom / float(GameConfig.WORLD_ATLAS_CELL_SIZE) * sprite_size.y
	return Rect2(Vector2(-sprite_size.x * 0.5, top), sprite_size)


func _sprite_opaque_bounds() -> Rect2i:
	_ensure_world_metadata()
	var values: Array = _opaque_bounds_by_name.get(_sprite_name(), [0, 0, GameConfig.WORLD_ATLAS_CELL_SIZE, GameConfig.WORLD_ATLAS_CELL_SIZE])
	if values.size() != 4:
		return Rect2i(Vector2i.ZERO, Vector2i.ONE * GameConfig.WORLD_ATLAS_CELL_SIZE)
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func _sprite_name() -> String:
	var names := [
		"blue_hq", "red_hq", "blue_melee_spawner", "red_melee_spawner",
		"blue_ranged_spawner", "red_ranged_spawner", "blue_tower", "red_tower",
		"blue_dragon_lair", "red_dragon_lair",
	]
	return names[_sprite_index()]


static func _ensure_world_metadata() -> void:
	if _metadata_loaded:
		return
	_metadata_loaded = true
	var metadata_file := FileAccess.open(WORLD_METADATA_PATH, FileAccess.READ)
	if metadata_file == null:
		return
	var metadata = JSON.parse_string(metadata_file.get_as_text())
	if metadata is Dictionary:
		_opaque_bounds_by_name = metadata.get("opaque_bounds", {})


func _draw_ground_plinth(color: Color) -> void:
	var center_y := get_ground_contact_y() + 1.0
	var points := PackedVector2Array([
		Vector2(-24, center_y), Vector2(0, center_y + 7),
		Vector2(24, center_y), Vector2(0, center_y - 7),
	])
	draw_colored_polygon(points, Color(color.darkened(0.62), 0.92))
	points.append(points[0])
	draw_polyline(points, Color(color.lightened(0.08), 0.72), 1.5, true)


func _draw_soft_shadow() -> void:
	for ring in 3:
		var points := PackedVector2Array()
		var width := 42.0 - float(ring) * 5.0
		var height := 13.0 - float(ring) * 2.0
		for index in 20:
			var angle := TAU * float(index) / 20.0
			points.append(Vector2(cos(angle) * width * 0.5, sin(angle) * height * 0.5 + get_ground_contact_y()))
		draw_colored_polygon(points, Color(0.02, 0.03, 0.05, 0.10 + float(ring) * 0.05))
