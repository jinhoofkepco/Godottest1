class_name FrontlineLayer
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var rebuild_count := 0
var _segments: Array[PackedVector2Array] = []


func set_segments(value: Array[PackedVector2Array]) -> void:
	_segments = value
	rebuild_count += 1
	queue_redraw()


func _draw() -> void:
	for segment in _segments:
		draw_line(segment[0], segment[1], Color(GameConfig.COLOR_FRONTLINE, 0.82), 1.35, true)
