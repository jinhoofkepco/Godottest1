class_name DefenseTower
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const ProjectileScene = preload("res://scenes/projectile.tscn")

@export var attack_range := GameConfig.TOWER_RANGE / GameConfig.CELL_SIZE
@export var fire_interval := GameConfig.TOWER_FIRE_INTERVAL
@export var damage := GameConfig.TOWER_DAMAGE
@export var projectile_speed := GameConfig.PROJECTILE_SPEED / GameConfig.CELL_SIZE

var enemy_container: Node
var projectile_container: Node
var grid_position := Vector2.ZERO:
	set(value):
		grid_position = value
		_update_presentation()

var _grid: GridBoard
var _cooldown := 0.12
var _aim_direction := Vector2.UP


func setup(board: GridBoard, enemies: Node, projectiles: Node) -> void:
	_grid = board
	enemy_container = enemies
	projectile_container = projectiles
	_update_presentation()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var target := _nearest_target()
	if target == null:
		return
	_aim_direction = position.direction_to(target.position)
	queue_redraw()
	if _cooldown <= 0.0:
		_fire(target)
		_cooldown = fire_interval


func _nearest_target() -> Node2D:
	if not is_instance_valid(enemy_container):
		return null
	var nearest: Node2D
	var nearest_distance := attack_range
	for child in enemy_container.get_children():
		if not child is Node2D or bool(child.get("is_dead")):
			continue
		var distance := grid_position.distance_to(child.grid_position)
		if distance <= nearest_distance:
			nearest = child
			nearest_distance = distance
	return nearest


func _fire(target: Node2D) -> void:
	if not is_instance_valid(projectile_container):
		return
	var projectile = ProjectileScene.instantiate()
	projectile_container.add_child(projectile)
	var logical_direction := grid_position.direction_to(target.grid_position)
	projectile.grid_position = grid_position + logical_direction * (18.0 / GameConfig.CELL_SIZE)
	projectile.setup(_grid, target, damage, projectile_speed)


func _update_presentation() -> void:
	if is_instance_valid(_grid):
		position = _grid.grid_to_screen(grid_position)


func _draw() -> void:
	draw_circle(Vector2(3, 1), 22.0, Color(0.02, 0.03, 0.05, 0.35))
	draw_rect(Rect2(Vector2(-19, -24), Vector2(38, 24)), GameConfig.COLOR_ALLY_DARK)
	draw_rect(Rect2(Vector2(-14, -20), Vector2(28, 17)), GameConfig.COLOR_TEAL.darkened(0.42))
	draw_circle(Vector2(0, -17), 10.0, GameConfig.COLOR_TEAL)
	draw_line(Vector2(0, -17) + _aim_direction * 6.0, Vector2(0, -17) + _aim_direction * 23.0, GameConfig.COLOR_TEXT, 7.0)
	draw_circle(Vector2(0, -17), 3.0, Color.WHITE)
