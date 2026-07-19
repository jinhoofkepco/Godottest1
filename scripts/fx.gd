class_name DefenseFx
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

@export var hit_stop_duration := 0.06
@export var fragment_count := 12

var _fragments: Array[Dictionary] = []
var _hit_stop_active := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 90714


func spawn_burst(at: Vector2) -> void:
	for index in fragment_count:
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(75.0, 180.0)
		_fragments.append({
			"position": at,
			"velocity": Vector2.from_angle(angle) * speed,
			"life": _rng.randf_range(0.18, 0.34),
			"size": _rng.randf_range(3.0, 7.0),
		})
	queue_redraw()
	if hit_stop_duration > 0.0 and not _hit_stop_active:
		_hit_stop()


func _process(delta: float) -> void:
	for index in range(_fragments.size() - 1, -1, -1):
		var fragment := _fragments[index]
		fragment.life = float(fragment.life) - delta
		if float(fragment.life) <= 0.0:
			_fragments.remove_at(index)
			continue
		fragment.position = Vector2(fragment.position) + Vector2(fragment.velocity) * delta
		fragment.velocity = Vector2(fragment.velocity) * 0.9
		_fragments[index] = fragment
	queue_redraw()


func _hit_stop() -> void:
	_hit_stop_active = true
	get_tree().paused = true
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	get_tree().paused = false
	_hit_stop_active = false


func _draw() -> void:
	for fragment in _fragments:
		var position_value := Vector2(fragment.position)
		var size_value := float(fragment.size)
		draw_rect(Rect2(position_value - Vector2.ONE * size_value * 0.5, Vector2.ONE * size_value), GameConfig.COLOR_ORANGE)

