class_name DefenseCore
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var hp := GameConfig.CORE_MAX_HP
var max_hp := GameConfig.CORE_MAX_HP
var _pulse := 0.0
var damage_flash_count := 0
var damage_flash_left := 0.0


func flash_damage() -> void:
	damage_flash_count += 1
	damage_flash_left = 0.18
	queue_redraw()


func set_hp(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	_pulse = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 4.0)
		queue_redraw()
	if damage_flash_left > 0.0:
		damage_flash_left = maxf(0.0, damage_flash_left - delta)
		queue_redraw()


func _draw() -> void:
	var scale_bonus := _pulse * 3.0
	var core_color := Color("ff455d") if damage_flash_left > 0.0 else GameConfig.COLOR_TEAL
	draw_rect(Rect2(Vector2(-61, -18), Vector2(122, 42)), Color(0.02, 0.03, 0.05, 0.45))
	draw_rect(Rect2(Vector2(-56 - scale_bonus, -22 - scale_bonus), Vector2(112 + scale_bonus * 2.0, 40 + scale_bonus * 2.0)), GameConfig.COLOR_ALLY_DARK)
	draw_rect(Rect2(Vector2(-39, -15), Vector2(78, 26)), core_color.darkened(0.2))
	draw_rect(Rect2(Vector2(-13, -23), Vector2(26, 42)), core_color)
	draw_circle(Vector2(0, -2), 7.0, Color.WHITE)
