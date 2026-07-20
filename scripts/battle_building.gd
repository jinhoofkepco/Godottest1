class_name BattleBuildingView
extends Node2D

signal collapse_finished(building_id: int)

const GameConfig = preload("res://scripts/game_config.gd")
const WORLD_ATLAS = preload("res://assets/world/world_atlas.png")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const BUILDING_HQ := 0
const BUILDING_SPAWNER := 1
const BUILDING_DEFENSE_TOWER := 2
const BUILDING_DRAGON_LAIR := 3
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
var _flash_left := 0.0
var _collapse_left := 0.0


func setup(board: GridBoard, record: Dictionary) -> void:
	building_id = int(record.id)
	team = int(record.team)
	kind = int(record.kind)
	unit_kind = int(record.get("unit_kind", UNIT_MELEE))
	cell = Vector2i(record.cell)
	position = board.cell_to_world(cell)
	update_from_data(record)
	queue_redraw()


func update_from_data(record: Dictionary) -> void:
	hp = float(record.hp)
	max_hp = float(record.max_hp)
	queue_redraw()


func flash_hit() -> void:
	_flash_left = 0.18
	queue_redraw()


func start_destroy() -> void:
	_collapse_left = 0.6
	queue_redraw()


func _process(delta: float) -> void:
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
	_draw_soft_shadow()
	var sprite_size := _sprite_size()
	var destination := Rect2(Vector2(-sprite_size.x * 0.5, -sprite_size.y + 10.0), sprite_size)
	var source := _sprite_region()
	var modulate := Color(1.85, 1.85, 1.85, 1.0) if _flash_left > 0.0 else Color.WHITE
	draw_texture_rect_region(WORLD_ATLAS, destination, source, modulate)
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var bar_y := -60.0 if kind == BUILDING_HQ else -57.0
	draw_rect(Rect2(Vector2(-22, bar_y), Vector2(44, 5)), Color("0b101b"))
	draw_rect(Rect2(Vector2(-21, bar_y + 1.0), Vector2(42 * ratio, 3)), color.lightened(0.3))


func uses_baked_sprite() -> bool:
	return WORLD_ATLAS != null


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


func _draw_soft_shadow() -> void:
	for ring in 3:
		var points := PackedVector2Array()
		var width := 42.0 - float(ring) * 5.0
		var height := 13.0 - float(ring) * 2.0
		for index in 20:
			var angle := TAU * float(index) / 20.0
			points.append(Vector2(cos(angle) * width * 0.5, sin(angle) * height * 0.5 + 2.0))
		draw_colored_polygon(points, Color(0.02, 0.03, 0.05, 0.08 + float(ring) * 0.04))
