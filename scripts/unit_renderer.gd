class_name UnitRenderer
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const STATE_WAIT := 2

var _grid: GridBoard
var _simulation
var _enemy_melee_units: MultiMeshInstance2D
var _enemy_ranged_units: MultiMeshInstance2D
var _ally_melee_units: MultiMeshInstance2D
var _ally_ranged_units: MultiMeshInstance2D
var _enemy_dragons: MultiMeshInstance2D
var _ally_dragons: MultiMeshInstance2D


func _ready() -> void:
	z_as_relative = false
	z_index = 40
	var melee_mesh := _make_melee_mesh()
	var ranged_mesh := _make_ranged_mesh()
	var dragon_mesh := _make_dragon_mesh()
	_enemy_melee_units = _make_batch("EnemyMeleeUnits", melee_mesh)
	_enemy_ranged_units = _make_batch("EnemyRangedUnits", ranged_mesh)
	_ally_melee_units = _make_batch("AllyMeleeUnits", melee_mesh)
	_ally_ranged_units = _make_batch("AllyRangedUnits", ranged_mesh)
	_enemy_dragons = _make_batch("EnemyDragons", dragon_mesh)
	_ally_dragons = _make_batch("AllyDragons", dragon_mesh)


func setup(board: GridBoard, simulation) -> void:
	_grid = board
	_simulation = simulation
	sync()


func get_multimesh_count() -> int:
	return (
		int(_enemy_melee_units != null)
		+ int(_enemy_ranged_units != null)
		+ int(_ally_melee_units != null)
		+ int(_ally_ranged_units != null)
		+ int(_enemy_dragons != null)
		+ int(_ally_dragons != null)
	)


func sync() -> void:
	if not is_instance_valid(_grid) or _simulation == null or _enemy_melee_units == null:
		return
	_sync_batch(_enemy_melee_units, TEAM_ENEMY, UNIT_MELEE)
	_sync_batch(_enemy_ranged_units, TEAM_ENEMY, UNIT_RANGED)
	_sync_batch(_ally_melee_units, TEAM_ALLY, UNIT_MELEE)
	_sync_batch(_ally_ranged_units, TEAM_ALLY, UNIT_RANGED)
	_sync_batch(_enemy_dragons, TEAM_ENEMY, UNIT_DRAGON)
	_sync_batch(_ally_dragons, TEAM_ALLY, UNIT_DRAGON)
	queue_redraw()


func _make_batch(node_name: String, soldier_mesh: ArrayMesh) -> MultiMeshInstance2D:
	var instance := MultiMeshInstance2D.new()
	instance.name = node_name
	instance.z_as_relative = false
	instance.z_index = 7
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = soldier_mesh
	multimesh.instance_count = 0
	instance.multimesh = multimesh
	add_child(instance)
	return instance


func _make_melee_mesh() -> ArrayMesh:
	var silhouette := PackedVector2Array([
		Vector2(-7, 8), Vector2(7, 8), Vector2(7, -3), Vector2(4, -6),
		Vector2(4, -11), Vector2(0, -16), Vector2(-4, -11), Vector2(-4, -6), Vector2(-7, -3),
	])
	return _make_mesh(silhouette)


func _make_ranged_mesh() -> ArrayMesh:
	var silhouette := PackedVector2Array([
		Vector2(-6, 8), Vector2(6, 8), Vector2(6, -1), Vector2(13, -4),
		Vector2(13, -7), Vector2(5, -7), Vector2(4, -12), Vector2(0, -16),
		Vector2(-4, -12), Vector2(-5, -7), Vector2(-8, -4), Vector2(-6, -1),
	])
	return _make_mesh(silhouette)


func _make_dragon_mesh() -> ArrayMesh:
	var silhouette := PackedVector2Array([
		Vector2(-3, 8), Vector2(3, 8), Vector2(5, 1), Vector2(17, 5),
		Vector2(10, -4), Vector2(17, -10), Vector2(4, -7), Vector2(0, -17),
		Vector2(-4, -7), Vector2(-17, -10), Vector2(-10, -4), Vector2(-17, 5), Vector2(-5, 1),
	])
	return _make_mesh(silhouette)


func _make_mesh(silhouette: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for point in silhouette:
		vertices.append(Vector3(point.x, point.y, 0.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(silhouette)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sync_batch(instance: MultiMeshInstance2D, team: int, unit_kind: int) -> void:
	var indices: Array[int] = []
	for index in _simulation.unit_ids.size():
		if (
			_simulation.unit_teams[index] == team
			and _simulation.unit_kinds[index] == unit_kind
			and _simulation.unit_hp[index] > 0.0
		):
			indices.append(index)
	indices.sort_custom(func(a: int, b: int) -> bool:
		return _grid.grid_to_screen(_simulation.unit_positions[a]).y < _grid.grid_to_screen(_simulation.unit_positions[b]).y
	)
	instance.multimesh.instance_count = indices.size()
	for draw_index in indices.size():
		var unit_index := indices[draw_index]
		var screen_position := get_unit_render_position(unit_index)
		var transform := Transform2D(0.0, screen_position)
		instance.multimesh.set_instance_transform_2d(draw_index, transform)
		instance.multimesh.set_instance_color(draw_index, get_unit_color(team, unit_kind, _simulation.unit_states[unit_index]))


func get_unit_color(team: int, unit_kind: int, unit_state: int) -> Color:
	var color := GameConfig.COLOR_ALLY.lightened(0.28) if team == TEAM_ALLY else GameConfig.COLOR_ENEMY.lightened(0.18)
	if unit_kind == UNIT_RANGED:
		color = color.lerp(GameConfig.COLOR_TEAL, 0.38).lightened(0.08)
	elif unit_kind == UNIT_DRAGON:
		color = color.lerp(GameConfig.COLOR_ORANGE, 0.48).lightened(0.14)
	if unit_state == 0:
		color = color.darkened(0.12)
	elif unit_state == STATE_WAIT:
		color = color.darkened(0.34)
	return color


func get_unit_render_position(unit_index: int) -> Vector2:
	var lunge_offset := Vector2.ZERO
	if _simulation.unit_lunge_timers[unit_index] > 0.0:
		var remaining_ratio: float = clampf(
			_simulation.unit_lunge_timers[unit_index] / GameConfig.UNIT_LUNGE_DURATION,
			0.0,
			1.0
		)
		var lunge_envelope := sin((1.0 - remaining_ratio) * PI)
		lunge_offset = _simulation.unit_lunge_directions[unit_index] * GameConfig.UNIT_LUNGE_DISTANCE * lunge_envelope
	return _grid.grid_to_screen(_simulation.unit_positions[unit_index] + lunge_offset) + Vector2(0, -11)


func _draw() -> void:
	if not is_instance_valid(_grid) or _simulation == null:
		return
	for index in _simulation.unit_ids.size():
		var maximum_hp := GameConfig.UNIT_MAX_HP
		if _simulation.unit_kinds[index] == UNIT_RANGED:
			maximum_hp = GameConfig.RANGED_UNIT_MAX_HP
		elif _simulation.unit_kinds[index] == UNIT_DRAGON:
			maximum_hp = GameConfig.DRAGON_UNIT_MAX_HP
		var ratio := clampf(_simulation.unit_hp[index] / maximum_hp, 0.0, 1.0)
		if ratio >= 0.995:
			continue
		var at := _grid.grid_to_screen(_simulation.unit_positions[index]) + Vector2(-9, -26)
		draw_rect(Rect2(at, Vector2(18, 3)), Color("10131c"))
		var color := GameConfig.COLOR_ALLY if _simulation.unit_teams[index] == TEAM_ALLY else GameConfig.COLOR_ENEMY
		draw_rect(Rect2(at + Vector2.ONE, Vector2(16.0 * ratio, 1)), color.lightened(0.25))
