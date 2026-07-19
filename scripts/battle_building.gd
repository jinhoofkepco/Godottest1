class_name BattleBuildingView
extends Node2D

signal collapse_finished(building_id: int)

const GameConfig = preload("res://scripts/game_config.gd")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const BUILDING_HQ := 0

var building_id := 0
var team := TEAM_ALLY
var kind := BUILDING_HQ
var cell := Vector2i.ZERO
var hp := 1.0
var max_hp := 1.0
var _flash_left := 0.0
var _collapse_left := 0.0


func setup(board: GridBoard, record: Dictionary) -> void:
	building_id = int(record.id)
	team = int(record.team)
	kind = int(record.kind)
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
	if _flash_left > 0.0:
		color = Color.WHITE
	var shadow := PackedVector2Array([Vector2(-23, 0), Vector2(0, -11), Vector2(23, 0), Vector2(0, 11)])
	draw_colored_polygon(shadow, Color("111827"))
	if kind == BUILDING_HQ:
		draw_colored_polygon(PackedVector2Array([Vector2(-25, -2), Vector2(-18, -38), Vector2(0, -50), Vector2(18, -38), Vector2(25, -2)]), color.darkened(0.18))
		draw_rect(Rect2(Vector2(-17, -34), Vector2(34, 27)), color)
		draw_rect(Rect2(Vector2(-4, -50), Vector2(8, 35)), Color("f0f6ff"))
	else:
		draw_rect(Rect2(Vector2(-18, -28), Vector2(36, 24)), color.darkened(0.16))
		draw_rect(Rect2(Vector2(-11, -38), Vector2(22, 15)), color)
		draw_circle(Vector2(0, -42), 6.0, Color("f0f6ff"))
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-22, -60 if kind == BUILDING_HQ else -51), Vector2(44, 5)), Color("0b101b"))
	draw_rect(Rect2(Vector2(-21, -59 if kind == BUILDING_HQ else -50), Vector2(42 * ratio, 3)), color.lightened(0.3))
