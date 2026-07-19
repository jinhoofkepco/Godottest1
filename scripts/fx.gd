class_name DefenseFx
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

@export var hit_stop_duration := 0.06
@export var fragment_count := 12
@export var placement_duration := 0.42
@export var damage_duration := 0.55
@export var leak_duration := 0.34

var placement_feedback_count := 0
var damage_feedback_count := 0
var kill_burst_count := 0
var leak_feedback_count := 0
var last_feedback_mode := ""
var last_placement_cell := Vector2i(-1, -1)
var last_placement_valid := false
var last_placement_range := 0.0
var placement_time_left := 0.0
var leak_time_left := 0.0

var _fragments: Array[Dictionary] = []
var _damage_numbers: Array[Dictionary] = []
var _hit_stop_active := false
var _rng := RandomNumberGenerator.new()
var _grid: GridBoard
var _enemies: Node
var _leak_from := Vector2.ZERO
var _leak_to := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 90714


func setup(board: GridBoard, enemy_source: Node) -> void:
	_grid = board
	_enemies = enemy_source
	queue_redraw()


func show_placement(cell: Vector2i, is_valid: bool, range_cells: float) -> void:
	last_placement_cell = cell
	last_placement_valid = is_valid
	last_placement_range = range_cells
	placement_time_left = placement_duration
	placement_feedback_count += 1
	last_feedback_mode = "placement_valid" if is_valid else "placement_invalid"
	queue_redraw()


func show_damage(grid_position: Vector2, amount: float) -> void:
	_damage_numbers.append({
		"grid_position": grid_position,
		"amount": amount,
		"life": damage_duration,
	})
	damage_feedback_count += 1
	last_feedback_mode = "damage"
	queue_redraw()


func spawn_kill_burst(grid_position: Vector2) -> void:
	var at := _grid.grid_to_screen(grid_position) if is_instance_valid(_grid) else grid_position
	for index in fragment_count:
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(75.0, 180.0)
		_fragments.append({
			"position": at,
			"velocity": Vector2.from_angle(angle) * speed,
			"life": _rng.randf_range(0.18, 0.34),
			"size": _rng.randf_range(3.0, 7.0),
		})
	kill_burst_count += 1
	last_feedback_mode = "kill"
	queue_redraw()
	if hit_stop_duration > 0.0 and not _hit_stop_active and is_inside_tree():
		_hit_stop()


func show_leak(from_grid: Vector2, core_anchor: Vector2) -> void:
	_leak_from = _grid.grid_to_screen(from_grid) if is_instance_valid(_grid) else from_grid
	_leak_to = core_anchor
	leak_time_left = leak_duration
	leak_feedback_count += 1
	last_feedback_mode = "leak"
	queue_redraw()


func _process(delta: float) -> void:
	placement_time_left = maxf(0.0, placement_time_left - delta)
	leak_time_left = maxf(0.0, leak_time_left - delta)
	for index in range(_fragments.size() - 1, -1, -1):
		var fragment := _fragments[index]
		fragment.life = float(fragment.life) - delta
		if float(fragment.life) <= 0.0:
			_fragments.remove_at(index)
			continue
		fragment.position = Vector2(fragment.position) + Vector2(fragment.velocity) * delta
		fragment.velocity = Vector2(fragment.velocity) * 0.9
		_fragments[index] = fragment
	for index in range(_damage_numbers.size() - 1, -1, -1):
		var damage_number := _damage_numbers[index]
		damage_number.life = float(damage_number.life) - delta
		if float(damage_number.life) <= 0.0:
			_damage_numbers.remove_at(index)
			continue
		_damage_numbers[index] = damage_number
	queue_redraw()


func _hit_stop() -> void:
	_hit_stop_active = true
	get_tree().paused = true
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	get_tree().paused = false
	_hit_stop_active = false


func _draw() -> void:
	_draw_enemy_health()
	_draw_placement()
	_draw_damage_numbers()
	_draw_leak()
	for fragment in _fragments:
		var position_value := Vector2(fragment.position)
		var size_value := float(fragment.size)
		draw_rect(Rect2(position_value - Vector2.ONE * size_value * 0.5, Vector2.ONE * size_value), GameConfig.COLOR_ORANGE)


func _draw_enemy_health() -> void:
	if not is_instance_valid(_grid) or not is_instance_valid(_enemies):
		return
	for enemy in _enemies.get_children():
		if not enemy is Node2D or bool(enemy.get("is_dead")):
			continue
		var max_health := float(enemy.get("max_health"))
		if max_health <= 0.0:
			continue
		var anchor: Vector2 = _grid.grid_to_screen(enemy.grid_position) + Vector2(0, -43)
		var ratio := clampf(float(enemy.get("health")) / max_health, 0.0, 1.0)
		draw_rect(Rect2(anchor - Vector2(17, 2), Vector2(34, 5)), Color(0.03, 0.04, 0.07, 0.9))
		draw_rect(Rect2(anchor - Vector2(16, 1), Vector2(32 * ratio, 3)), GameConfig.COLOR_ORANGE)


func _draw_placement() -> void:
	if placement_time_left <= 0.0 or not is_instance_valid(_grid):
		return
	var cell := last_placement_cell
	var diamond := PackedVector2Array([
		_grid.grid_to_screen(Vector2(cell.x, cell.y)),
		_grid.grid_to_screen(Vector2(cell.x + 1, cell.y)),
		_grid.grid_to_screen(Vector2(cell.x + 1, cell.y + 1)),
		_grid.grid_to_screen(Vector2(cell.x, cell.y + 1)),
		_grid.grid_to_screen(Vector2(cell.x, cell.y)),
	])
	var fade := clampf(placement_time_left / placement_duration, 0.0, 1.0)
	var color := Color(GameConfig.COLOR_TEAL if last_placement_valid else Color("ff455d"), fade)
	draw_polyline(diamond, color, 4.0, true)
	var center: Vector2 = _grid.cell_to_world(cell)
	if last_placement_valid:
		var range_points := PackedVector2Array()
		var center_grid := Vector2(cell) + Vector2(0.5, 0.5)
		for index in 49:
			var angle := TAU * float(index) / 48.0
			range_points.append(_grid.grid_to_screen(center_grid + Vector2.from_angle(angle) * last_placement_range))
		draw_polyline(range_points, Color(GameConfig.COLOR_TEAL, fade * 0.72), 2.2, true)
	else:
		draw_line(center + Vector2(-13, -7), center + Vector2(13, 7), color, 4.0, true)
		draw_line(center + Vector2(-13, 7), center + Vector2(13, -7), color, 4.0, true)


func _draw_damage_numbers() -> void:
	if not is_instance_valid(_grid):
		return
	for damage_number in _damage_numbers:
		var life_ratio := clampf(float(damage_number.life) / damage_duration, 0.0, 1.0)
		var rise := (1.0 - life_ratio) * 18.0
		var at: Vector2 = _grid.grid_to_screen(Vector2(damage_number.grid_position)) + Vector2(-10, -48 - rise)
		var text := "%d" % roundi(float(damage_number.amount))
		draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(GameConfig.COLOR_ORANGE, life_ratio))


func _draw_leak() -> void:
	if leak_time_left <= 0.0:
		return
	var fade := clampf(leak_time_left / leak_duration, 0.0, 1.0)
	var red := Color(Color("ff455d"), fade)
	draw_line(_leak_from, _leak_to, Color(red, fade * 0.45), 5.0, true)
	var slash_center := _leak_from.lerp(_leak_to, 1.0 - fade)
	draw_line(slash_center + Vector2(-13, -17), slash_center + Vector2(13, 17), red, 7.0, true)
