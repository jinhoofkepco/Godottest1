class_name DefenseProjectile
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var target: Node2D
var damage := 1.0
var move_speed := 400.0


func setup(new_target: Node2D, hit_damage: float, speed: float) -> void:
	target = new_target
	damage = hit_damage
	move_speed = speed
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or bool(target.get("is_dead")):
		queue_free()
		return
	var distance := global_position.distance_to(target.global_position)
	var travel := move_speed * delta
	if distance <= maxf(10.0, travel):
		target.take_damage(damage)
		queue_free()
		return
	global_position = global_position.move_toward(target.global_position, travel)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, GameConfig.COLOR_TEAL)
	draw_circle(Vector2.ZERO, 2.5, Color.WHITE)
	draw_line(Vector2(0, 5), Vector2(0, 13), Color(GameConfig.COLOR_TEAL, 0.4), 3.0)

