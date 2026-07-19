class_name DefenseEnemy
extends Node2D

signal defeated(at_grid: Vector2)
signal reached_core(at_grid: Vector2)
signal damaged(at_grid: Vector2, amount: float)

const GameConfig = preload("res://scripts/game_config.gd")
const CORE_GRID_ROW := (GameConfig.ENEMY_CORE_Y - GameConfig.GRID_ORIGIN.y) / GameConfig.CELL_SIZE

@export var body_size := Vector2(28, 34)
@export var flash_duration := 0.085

var health := 1.0
var max_health := 1.0
var move_speed := 46.0 / GameConfig.CELL_SIZE
var is_dead := false
var grid_position := Vector2.ZERO:
	set(value):
		grid_position = value
		_update_presentation()

var _grid: GridBoard
var _flash_left := 0.0


func setup(board: GridBoard, column: int, speed: float, starting_health: float) -> void:
	_grid = board
	move_speed = speed / GameConfig.CELL_SIZE
	health = starting_health
	max_health = starting_health
	grid_position = Vector2(float(column) + 0.5, 0.5)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	grid_position.y += move_speed * delta
	if grid_position.y >= CORE_GRID_ROW:
		is_dead = true
		reached_core.emit(grid_position)
		queue_free()


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		queue_redraw()


func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = maxf(0.0, health - amount)
	_flash_left = flash_duration
	damaged.emit(grid_position, amount)
	queue_redraw()
	if health <= 0.0:
		is_dead = true
		defeated.emit(grid_position)
		queue_free()


func _update_presentation() -> void:
	if is_instance_valid(_grid):
		position = _grid.grid_to_screen(grid_position)


func _draw() -> void:
	var body_color := Color.WHITE if _flash_left > 0.0 else GameConfig.COLOR_ENEMY
	var body_rect := Rect2(Vector2(-body_size.x * 0.5, -body_size.y), body_size)
	_draw_ellipse_shadow(Vector2.ZERO, Vector2(18, 6), Color(0.02, 0.03, 0.06, 0.4))
	draw_rect(Rect2(body_rect.position + Vector2(4, 4), body_rect.size), Color(0.02, 0.03, 0.06, 0.4))
	draw_rect(body_rect, body_color)
	draw_rect(Rect2(Vector2(-9, -28), Vector2(18, 7)), GameConfig.COLOR_ENEMY_DARK)
	draw_rect(Rect2(Vector2(-8, -14), Vector2(5, 9)), GameConfig.COLOR_ORANGE)
	draw_rect(Rect2(Vector2(3, -14), Vector2(5, 9)), GameConfig.COLOR_ORANGE)


func _draw_ellipse_shadow(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 16:
		var angle := TAU * float(index) / 16.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
