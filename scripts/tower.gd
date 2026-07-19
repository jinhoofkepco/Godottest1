class_name DefenseTower
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const ProjectileScene = preload("res://scenes/projectile.tscn")

@export var attack_range := GameConfig.TOWER_RANGE / GameConfig.CELL_SIZE
@export var fire_interval := GameConfig.TOWER_FIRE_INTERVAL
@export var damage := GameConfig.TOWER_DAMAGE
@export var projectile_speed := GameConfig.PROJECTILE_SPEED / GameConfig.CELL_SIZE
@export var recoil_duration := 0.10
@export var muzzle_flash_duration := 0.08

var is_aiming := false
var shot_feedback_count := 0
var recoil_time_left := 0.0
var muzzle_flash_left := 0.0

var enemy_container: Node
var projectile_container: Node
var grid_position := Vector2.ZERO:
	set(value):
		grid_position = value
		_update_presentation()

var _grid: GridBoard
var _cooldown := 0.12
var _aim_direction := Vector2.UP
var _last_shot_direction := Vector2.UP


func setup(board: GridBoard, enemies: Node, projectiles: Node) -> void:
	_grid = board
	enemy_container = enemies
	projectile_container = projectiles
	_update_presentation()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var target := _nearest_target()
	if target == null:
		is_aiming = false
		_aim_direction = Vector2.UP
		queue_redraw()
		return
	is_aiming = true
	_aim_direction = position.direction_to(target.position)
	queue_redraw()
	if _cooldown <= 0.0:
		_fire(target)
		_cooldown = fire_interval


func _process(delta: float) -> void:
	recoil_time_left = maxf(0.0, recoil_time_left - delta)
	muzzle_flash_left = maxf(0.0, muzzle_flash_left - delta)
	if recoil_time_left > 0.0 or muzzle_flash_left > 0.0:
		queue_redraw()


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


func get_aim_direction() -> Vector2:
	return _aim_direction


func get_barrel_recoil_offset() -> Vector2:
	if not is_aiming:
		return Vector2.ZERO
	return _get_shot_recoil_offset()


func get_muzzle_flash_direction() -> Vector2:
	return _last_shot_direction


func _fire(target: Node2D) -> void:
	if not is_instance_valid(projectile_container):
		return
	var projectile = ProjectileScene.instantiate()
	projectile_container.add_child(projectile)
	var logical_direction := grid_position.direction_to(target.grid_position)
	_last_shot_direction = position.direction_to(target.position)
	projectile.grid_position = grid_position + logical_direction * (18.0 / GameConfig.CELL_SIZE)
	projectile.setup(_grid, target, damage, projectile_speed)
	shot_feedback_count += 1
	recoil_time_left = recoil_duration
	muzzle_flash_left = muzzle_flash_duration
	queue_redraw()


func _update_presentation() -> void:
	if is_instance_valid(_grid):
		position = _grid.grid_to_screen(grid_position)


func _draw() -> void:
	var active_color := GameConfig.COLOR_TEAL if is_aiming else GameConfig.COLOR_TEAL.darkened(0.48)
	var pivot := Vector2(0, -17) + get_barrel_recoil_offset()
	draw_circle(Vector2(3, 1), 22.0, Color(0.02, 0.03, 0.05, 0.35))
	draw_rect(Rect2(Vector2(-19, -24), Vector2(38, 24)), GameConfig.COLOR_ALLY_DARK)
	draw_rect(Rect2(Vector2(-14, -20), Vector2(28, 17)), active_color.darkened(0.42))
	draw_circle(pivot, 10.0, active_color)
	draw_line(pivot + _aim_direction * 6.0, pivot + _aim_direction * 23.0, active_color.lightened(0.28), 7.0)
	draw_circle(pivot, 3.0, Color.WHITE if is_aiming else GameConfig.COLOR_NEUTRAL)
	if muzzle_flash_left > 0.0:
		var muzzle := Vector2(0, -17) + _get_shot_recoil_offset() + _last_shot_direction * 27.0
		var side := _last_shot_direction.orthogonal() * 5.0
		draw_colored_polygon(PackedVector2Array([muzzle + _last_shot_direction * 8.0, muzzle + side, muzzle - _last_shot_direction * 5.0, muzzle - side]), Color.WHITE)


func _get_shot_recoil_offset() -> Vector2:
	var recoil_ratio := recoil_time_left / recoil_duration if recoil_duration > 0.0 else 0.0
	return -_last_shot_direction * recoil_ratio * 6.0
