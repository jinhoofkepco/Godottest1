class_name DefenseProjectile
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var target: Node2D
var damage := 1.0
var move_speed := 400.0 / GameConfig.CELL_SIZE
var grid_position := Vector2.ZERO:
	set(value):
		grid_position = value
		_update_presentation()
var tracer_time_left := 0.0

var _grid: GridBoard
var _screen_direction := Vector2.UP


func setup(board: GridBoard, new_target: Node2D, hit_damage: float, speed: float) -> void:
	_grid = board
	target = new_target
	damage = hit_damage
	move_speed = speed
	if is_instance_valid(_grid) and is_instance_valid(target):
		_screen_direction = _grid.grid_to_screen(grid_position).direction_to(_grid.grid_to_screen(target.grid_position))
	tracer_time_left = 0.14
	_update_presentation()
	queue_redraw()


func _process(delta: float) -> void:
	tracer_time_left = maxf(0.0, tracer_time_left - delta)
	if tracer_time_left > 0.0:
		queue_redraw()


func get_tracer_direction() -> Vector2:
	return _screen_direction


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or bool(target.get("is_dead")):
		queue_free()
		return
	var target_grid_position: Vector2 = target.grid_position
	var distance := grid_position.distance_to(target_grid_position)
	var travel := move_speed * delta
	if distance <= maxf(10.0 / GameConfig.CELL_SIZE, travel):
		target.take_damage(damage, grid_position)
		queue_free()
		return
	var previous_position := position
	grid_position = grid_position.move_toward(target_grid_position, travel)
	if not position.is_equal_approx(previous_position):
		_screen_direction = previous_position.direction_to(position)
	queue_redraw()


func _update_presentation() -> void:
	if is_instance_valid(_grid):
		position = _grid.grid_to_screen(grid_position)


func _draw() -> void:
	var center := Vector2(0, -8)
	var trail_alpha := 0.35 + 0.45 * clampf(tracer_time_left / 0.14, 0.0, 1.0)
	draw_line(center, center - _screen_direction * 20.0, Color(GameConfig.COLOR_TEAL, trail_alpha), 4.0)
	draw_circle(center, 6.0, GameConfig.COLOR_TEAL.lightened(0.18))
	draw_circle(center, 2.8, Color.WHITE)
