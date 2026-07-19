class_name DefenseEnemy
extends Node2D

signal defeated(at: Vector2)
signal reached_core(at: Vector2)

const GameConfig = preload("res://scripts/game_config.gd")

@export var body_size := Vector2(28, 34)
@export var flash_duration := 0.085

var health := 1.0
var max_health := 1.0
var move_speed := 46.0
var is_dead := false
var _flash_left := 0.0


func setup(column: int, speed: float, starting_health: float) -> void:
	move_speed = speed
	health = starting_health
	max_health = starting_health
	position = Vector2(
		GameConfig.GRID_ORIGIN.x + (float(column) + 0.5) * GameConfig.CELL_SIZE,
		GameConfig.GRID_ORIGIN.y + GameConfig.CELL_SIZE * 0.5
	)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	position.y += move_speed * delta
	if position.y >= GameConfig.ENEMY_CORE_Y:
		is_dead = true
		reached_core.emit(global_position)
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
	queue_redraw()
	if health <= 0.0:
		is_dead = true
		defeated.emit(global_position)
		queue_free()


func _draw() -> void:
	var body_color := Color.WHITE if _flash_left > 0.0 else GameConfig.COLOR_ENEMY
	var body_rect := Rect2(-body_size * 0.5, body_size)
	draw_rect(Rect2(body_rect.position + Vector2(3, 4), body_rect.size), Color(0.02, 0.03, 0.06, 0.4))
	draw_rect(body_rect, body_color)
	draw_rect(Rect2(Vector2(-9, -10), Vector2(18, 7)), GameConfig.COLOR_ENEMY_DARK)
	draw_rect(Rect2(Vector2(-8, 4), Vector2(5, 9)), GameConfig.COLOR_ORANGE)
	draw_rect(Rect2(Vector2(3, 4), Vector2(5, 9)), GameConfig.COLOR_ORANGE)
	var ratio := health / max_health if max_health > 0.0 else 0.0
	draw_rect(Rect2(Vector2(-15, -24), Vector2(30, 4)), Color("18202d"))
	draw_rect(Rect2(Vector2(-15, -24), Vector2(30 * ratio, 4)), GameConfig.COLOR_ORANGE)
