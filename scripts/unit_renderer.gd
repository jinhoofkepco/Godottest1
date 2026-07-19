class_name UnitRenderer
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2

var _grid: GridBoard
var _simulation
var _red_units: MultiMeshInstance2D
var _blue_units: MultiMeshInstance2D


func _ready() -> void:
	z_as_relative = false
	z_index = 40
	var soldier_mesh := _make_soldier_mesh()
	_red_units = _make_team_multimesh("RedUnits", soldier_mesh)
	_blue_units = _make_team_multimesh("BlueUnits", soldier_mesh)


func setup(board: GridBoard, simulation) -> void:
	_grid = board
	_simulation = simulation
	sync()


func get_multimesh_count() -> int:
	return int(_red_units != null) + int(_blue_units != null)


func sync() -> void:
	if not is_instance_valid(_grid) or _simulation == null or _red_units == null:
		return
	_sync_team(_red_units, TEAM_ENEMY, 0.0)
	_sync_team(_blue_units, TEAM_ALLY, 0.0)
	queue_redraw()


func _make_team_multimesh(node_name: String, soldier_mesh: ArrayMesh) -> MultiMeshInstance2D:
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


func _make_soldier_mesh() -> ArrayMesh:
	var silhouette := PackedVector2Array([
		Vector2(-7, 8), Vector2(7, 8), Vector2(7, -3), Vector2(4, -6),
		Vector2(4, -11), Vector2(0, -16), Vector2(-4, -11), Vector2(-4, -6), Vector2(-7, -3),
	])
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


func _sync_team(instance: MultiMeshInstance2D, team: int, body_rotation: float) -> void:
	var indices: Array[int] = []
	for index in _simulation.unit_ids.size():
		if _simulation.unit_teams[index] == team and _simulation.unit_hp[index] > 0.0:
			indices.append(index)
	indices.sort_custom(func(a: int, b: int) -> bool:
		return _grid.grid_to_screen(_simulation.unit_positions[a]).y < _grid.grid_to_screen(_simulation.unit_positions[b]).y
	)
	instance.multimesh.instance_count = indices.size()
	for draw_index in indices.size():
		var unit_index := indices[draw_index]
		var screen_position := _grid.grid_to_screen(_simulation.unit_positions[unit_index]) + Vector2(0, -11)
		var transform := Transform2D(body_rotation, screen_position)
		instance.multimesh.set_instance_transform_2d(draw_index, transform)
		var base_color := GameConfig.COLOR_ALLY.lightened(0.28) if team == TEAM_ALLY else GameConfig.COLOR_ENEMY.lightened(0.18)
		if _simulation.unit_states[unit_index] == 0:
			base_color = base_color.darkened(0.12)
		instance.multimesh.set_instance_color(draw_index, base_color)


func _draw() -> void:
	if not is_instance_valid(_grid) or _simulation == null:
		return
	for index in _simulation.unit_ids.size():
		var ratio := clampf(_simulation.unit_hp[index] / GameConfig.UNIT_MAX_HP, 0.0, 1.0)
		if ratio >= 0.995:
			continue
		var at := _grid.grid_to_screen(_simulation.unit_positions[index]) + Vector2(-9, -26)
		draw_rect(Rect2(at, Vector2(18, 3)), Color("10131c"))
		var color := GameConfig.COLOR_ALLY if _simulation.unit_teams[index] == TEAM_ALLY else GameConfig.COLOR_ENEMY
		draw_rect(Rect2(at + Vector2.ONE, Vector2(16.0 * ratio, 1)), color.lightened(0.25))
