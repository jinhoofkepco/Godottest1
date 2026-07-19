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

var _grid: GridBoard


func setup(board: GridBoard, new_target: Node2D, hit_damage: float, speed: float) -> void:
	_grid = board
	target = new_target
	damage = hit_damage
	move_speed = speed
	_update_presentation()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or bool(target.get("is_dead")):
		queue_free()
		return
	var target_grid_position: Vector2 = target.grid_position
	var distance := grid_position.distance_to(target_grid_position)
	var travel := move_speed * delta
	if distance <= maxf(10.0 / GameConfig.CELL_SIZE, travel):
		target.take_damage(damage)
		queue_free()
		return
	grid_position = grid_position.move_toward(target_grid_position, travel)
	queue_redraw()


func _update_presentation() -> void:
	if is_instance_valid(_grid):
		position = _grid.grid_to_screen(grid_position)


func _draw() -> void:
	draw_line(Vector2(0, -3), Vector2(0, -15), Color(GameConfig.COLOR_TEAL, 0.4), 3.0)
	draw_circle(Vector2(0, -8), 6.0, GameConfig.COLOR_TEAL)
	draw_circle(Vector2(0, -8), 2.5, Color.WHITE)
