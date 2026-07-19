class_name MapView
extends Node2D

signal tile_tapped(cell: Vector2i)

const GameConfig = preload("res://scripts/game_config.gd")

var frame_rect := Rect2()
var zoom_level := GameConfig.MAP_ZOOM_DEFAULT
var interaction_enabled := true

var _board: GridBoard
var _fit_scale := 1.0
var _mouse_down := false
var _mouse_dragging := false
var _mouse_start := Vector2.ZERO
var _mouse_last := Vector2.ZERO
var _mouse_started_msec := 0
var _touches: Dictionary = {}
var _single_touch_index := -1
var _single_touch_start := Vector2.ZERO
var _single_touch_dragging := false
var _touch_sequence_suppressed := false
var _touch_started_msec := 0


func setup(board: GridBoard, value: Rect2) -> void:
	_board = board
	frame_rect = value
	interaction_enabled = true
	_reset_input_state()
	var bounds := _board.get_board_bounds()
	_fit_scale = minf(frame_rect.size.x / bounds.size.x, frame_rect.size.y / bounds.size.y)
	zoom_level = GameConfig.MAP_ZOOM_DEFAULT
	scale = Vector2.ONE * _fit_scale * zoom_level
	position = frame_rect.get_center() - bounds.get_center() * scale.x
	_clamp_position()


func set_zoom_at(value: float, screen_focus: Vector2) -> void:
	if not is_instance_valid(_board):
		return
	var clamped_zoom := clampf(value, GameConfig.MAP_ZOOM_MIN, GameConfig.MAP_ZOOM_MAX)
	if is_equal_approx(clamped_zoom, zoom_level):
		return
	var local_focus := to_local(screen_focus)
	zoom_level = clamped_zoom
	var new_scale := _fit_scale * zoom_level
	scale = Vector2.ONE * new_scale
	position = screen_focus - local_focus * new_scale
	_clamp_position()


func pan_by(delta: Vector2) -> void:
	if not is_instance_valid(_board):
		return
	position += delta
	_clamp_position()


func screen_to_cell(screen_position: Vector2) -> Vector2i:
	if not is_instance_valid(_board):
		return Vector2i(-1, -1)
	return _board.world_to_cell(to_local(screen_position))


func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value
	if not interaction_enabled:
		_reset_input_state()


func _unhandled_input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		if frame_rect.has_point(event.position):
			set_zoom_at(zoom_level * GameConfig.MAP_ZOOM_STEP, event.position)
			get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		if frame_rect.has_point(event.position):
			set_zoom_at(zoom_level / GameConfig.MAP_ZOOM_STEP, event.position)
			get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if not frame_rect.has_point(event.position):
			return
		_mouse_down = true
		_mouse_dragging = false
		_mouse_start = event.position
		_mouse_last = event.position
		_mouse_started_msec = Time.get_ticks_msec()
	else:
		if not _mouse_down:
			return
		var elapsed := float(Time.get_ticks_msec() - _mouse_started_msec) / 1000.0
		if not _mouse_dragging and elapsed <= GameConfig.MAP_TAP_MAX_SECONDS and frame_rect.has_point(event.position):
			tile_tapped.emit(screen_to_cell(event.position))
		_mouse_down = false
		_mouse_dragging = false
	get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_down:
		return
	if not _mouse_dragging and event.position.distance_to(_mouse_start) > GameConfig.MAP_DRAG_THRESHOLD:
		_mouse_dragging = true
		pan_by(event.position - _mouse_start)
	elif _mouse_dragging:
		pan_by(event.position - _mouse_last)
	_mouse_last = event.position
	get_viewport().set_input_as_handled()


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touches.is_empty() and not frame_rect.has_point(event.position):
			return
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_single_touch_index = event.index
			_single_touch_start = event.position
			_single_touch_dragging = false
			_touch_sequence_suppressed = false
			_touch_started_msec = Time.get_ticks_msec()
		else:
			_touch_sequence_suppressed = true
	else:
		if not _touches.has(event.index):
			return
		var elapsed := float(Time.get_ticks_msec() - _touch_started_msec) / 1000.0
		if (
			_touches.size() == 1
			and event.index == _single_touch_index
			and not _single_touch_dragging
			and not _touch_sequence_suppressed
			and elapsed <= GameConfig.MAP_TAP_MAX_SECONDS
			and frame_rect.has_point(event.position)
		):
			tile_tapped.emit(screen_to_cell(event.position))
		_touches.erase(event.index)
		if _touches.is_empty():
			_single_touch_index = -1
			_single_touch_dragging = false
			_touch_sequence_suppressed = false
		elif _touches.size() == 1:
			_single_touch_index = int(_touches.keys()[0])
			_single_touch_start = Vector2(_touches[_single_touch_index])
			_single_touch_dragging = false
	get_viewport().set_input_as_handled()


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	if _touches.size() >= 2:
		var indices := _touches.keys()
		var first_index: int = int(indices[0])
		var second_index: int = int(indices[1])
		var old_first := Vector2(_touches[first_index])
		var old_second := Vector2(_touches[second_index])
		var old_midpoint := (old_first + old_second) * 0.5
		var old_distance := old_first.distance_to(old_second)
		_touches[event.index] = event.position
		var new_first := Vector2(_touches[first_index])
		var new_second := Vector2(_touches[second_index])
		var new_midpoint := (new_first + new_second) * 0.5
		var new_distance := new_first.distance_to(new_second)
		if old_distance > 0.001:
			set_zoom_at(zoom_level * new_distance / old_distance, old_midpoint)
		pan_by(new_midpoint - old_midpoint)
		_touch_sequence_suppressed = true
	else:
		var old_position := Vector2(_touches[event.index])
		_touches[event.index] = event.position
		if not _single_touch_dragging and event.position.distance_to(_single_touch_start) > GameConfig.MAP_DRAG_THRESHOLD:
			_single_touch_dragging = true
			_touch_sequence_suppressed = true
			pan_by(event.position - _single_touch_start)
		elif _single_touch_dragging:
			pan_by(event.position - old_position)
	get_viewport().set_input_as_handled()


func _clamp_position() -> void:
	var bounds := _board.get_board_bounds()
	var scaled_min := bounds.position * scale.x
	var scaled_max := bounds.end * scale.x
	position.x = _clamp_axis(position.x, scaled_min.x, scaled_max.x, frame_rect.position.x, frame_rect.end.x)
	position.y = _clamp_axis(position.y, scaled_min.y, scaled_max.y, frame_rect.position.y, frame_rect.end.y)


func _reset_input_state() -> void:
	_mouse_down = false
	_mouse_dragging = false
	_touches.clear()
	_single_touch_index = -1
	_single_touch_dragging = false
	_touch_sequence_suppressed = false


func _clamp_axis(value: float, content_min: float, content_max: float, frame_min: float, frame_max: float) -> float:
	if content_max - content_min <= frame_max - frame_min:
		return clampf(value, frame_min - content_min, frame_max - content_max)
	return clampf(value, frame_max - content_max, frame_min - content_min)
