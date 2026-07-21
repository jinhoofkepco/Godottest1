class_name GridBoard
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const StaticTerrainLayerScript = preload("res://scripts/static_terrain_layer.gd")
const FrontlineLayerScript = preload("res://scripts/frontline_layer.gd")
const CELL_COUNT := GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS
const FLASH_INACTIVE_TIME := -1000.0

var simulation
var tile_transform_write_count := 0
var tile_incremental_update_count := 0
var last_flash_update_count := 0
var full_sync_count := 0

var _board_version := -1
var _ownership := PackedByteArray()
var _blocked := PackedByteArray()
var _water := PackedByteArray()
var _elevation := PackedByteArray()
var _buildings: Array = []
var _cell_to_instance := PackedInt32Array()
var _flash_times := PackedFloat32Array()
var _tile_layer: MultiMeshInstance2D
var _tile_multimesh: MultiMesh
var _static_layer: StaticTerrainLayer
var _frontline_layer: FrontlineLayer
var _tiles_initialized := false


func _ready() -> void:
	_ensure_layers()


func set_simulation(value) -> void:
	simulation = value


func sync_board(snapshot: Dictionary) -> void:
	sync_initial(snapshot)


func sync_initial(snapshot: Dictionary) -> void:
	_ensure_layers()
	_board_version = int(snapshot.get("version", -1))
	_ownership = PackedByteArray(snapshot.get("ownership", PackedByteArray())).duplicate()
	_blocked = PackedByteArray(snapshot.get("blocked", PackedByteArray())).duplicate()
	_water = PackedByteArray(snapshot.get("water", PackedByteArray())).duplicate()
	_elevation = PackedByteArray(snapshot.get("elevation", PackedByteArray())).duplicate()
	_buildings = Array(snapshot.get("buildings", []))
	full_sync_count += 1
	_initialize_or_refresh_tiles()
	_static_layer.setup(self)
	_frontline_layer.set_segments(get_frontline_segments(_ownership))


func apply_board_delta(delta: Dictionary) -> void:
	if not _tiles_initialized:
		return
	_board_version = int(delta.get("version", _board_version))
	_buildings = Array(delta.get("buildings", _buildings))
	last_flash_update_count = 0
	var ownership_indices: PackedInt32Array = delta.get("ownership_indices", PackedInt32Array())
	var ownership_owners: PackedInt32Array = delta.get("ownership_owners", PackedInt32Array())
	var ownership_count := mini(ownership_indices.size(), ownership_owners.size())
	var flash_time := float(Time.get_ticks_msec()) * 0.001
	for delta_index in ownership_count:
		var cell_index := ownership_indices[delta_index]
		if cell_index < 0 or cell_index >= CELL_COUNT:
			continue
		_ownership[cell_index] = clampi(ownership_owners[delta_index], 0, 2)
		_flash_times[cell_index] = flash_time
		_update_tile_instance(cell_index, true)
		last_flash_update_count += 1
	var blocked_indices: PackedInt32Array = delta.get("blocked_indices", PackedInt32Array())
	var blocked_values: PackedInt32Array = delta.get("blocked_values", PackedInt32Array())
	for delta_index in mini(blocked_indices.size(), blocked_values.size()):
		var cell_index := blocked_indices[delta_index]
		if cell_index < 0 or cell_index >= CELL_COUNT:
			continue
		_blocked[cell_index] = 1 if blocked_values[delta_index] != 0 else 0
		_update_tile_instance(cell_index, true)
	if ownership_count > 0:
		_frontline_layer.set_segments(get_frontline_segments(_ownership))


func can_build(cell: Vector2i, team: int = 2) -> bool:
	if not _cell_is_valid(cell) or simulation == null:
		return false
	var cell_index := cell.y * GameConfig.GRID_COLUMNS + cell.x
	var cell_blocked: bool = not _blocked.is_empty() and _blocked[cell_index] != 0
	cell_blocked = cell_blocked or (not _water.is_empty() and _water[cell_index] != 0)
	return _can_build_with_ownership(cell, team, _ownership, cell_blocked)


func _can_build_with_ownership(cell: Vector2i, team: int, current_ownership: PackedByteArray, cell_blocked: bool) -> bool:
	if not _cell_is_valid(cell) or simulation == null or cell_blocked or current_ownership.size() != CELL_COUNT:
		return false
	if current_ownership[cell.y * GameConfig.GRID_COLUMNS + cell.x] != team:
		return false
	for building in _buildings:
		if not bool(building.destroyed) and Vector2i(building.cell) == cell:
			return false
	return true


func occupy(_cell: Vector2i) -> void:
	pass


func grid_to_screen(grid_position: Vector2) -> Vector2:
	return Vector2(
		(grid_position.x - grid_position.y) * GameConfig.ISO_TILE_WIDTH * 0.5,
		(grid_position.x + grid_position.y) * GameConfig.ISO_TILE_HEIGHT * 0.5
	)


func grid_to_screen_elevated(grid_position: Vector2, elevation_level: int) -> Vector2:
	return grid_to_screen(grid_position) - Vector2(0.0, float(elevation_level) * GameConfig.ELEVATION_PIXEL_STEP)


func position_to_world(grid_position: Vector2) -> Vector2:
	var cell := Vector2i(clampi(floori(grid_position.x), 0, GameConfig.GRID_COLUMNS - 1), clampi(floori(grid_position.y), 0, GameConfig.GRID_ROWS - 1))
	return grid_to_screen_elevated(grid_position, _elevation_at(cell))


func screen_to_grid(screen_position: Vector2) -> Vector2:
	return Vector2(
		screen_position.x / GameConfig.ISO_TILE_WIDTH + screen_position.y / GameConfig.ISO_TILE_HEIGHT,
		screen_position.y / GameConfig.ISO_TILE_HEIGHT - screen_position.x / GameConfig.ISO_TILE_WIDTH
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return grid_to_screen_elevated(Vector2(cell) + Vector2(0.5, 0.5), _elevation_at(cell))


func world_to_cell(world_position: Vector2) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_depth := -1
	var visited: Dictionary = {}
	for elevation_level in GameConfig.ELEVATION_LEVELS:
		var corrected := screen_to_grid(world_position + Vector2(0.0, float(elevation_level) * GameConfig.ELEVATION_PIXEL_STEP))
		var origin := Vector2i(floori(corrected.x), floori(corrected.y))
		for y_offset in range(-1, 2):
			for x_offset in range(-1, 2):
				var cell := origin + Vector2i(x_offset, y_offset)
				if not _cell_is_valid(cell) or visited.has(cell):
					continue
				visited[cell] = true
				var depth := cell.x + cell.y
				if Geometry2D.is_point_in_polygon(world_position, _cell_diamond(cell)) and depth >= best_depth:
					best_cell = cell
					best_depth = depth
	if best_cell.x >= 0:
		return best_cell
	var flat_position := screen_to_grid(world_position)
	return Vector2i(floori(flat_position.x), floori(flat_position.y))


func get_board_bounds() -> Rect2:
	var corners: Array[Vector2] = [
		grid_to_screen(Vector2.ZERO),
		grid_to_screen(Vector2(GameConfig.GRID_COLUMNS, 0)),
		grid_to_screen(Vector2(0, GameConfig.GRID_ROWS)),
		grid_to_screen(Vector2(GameConfig.GRID_COLUMNS, GameConfig.GRID_ROWS)),
	]
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum = Vector2(minf(minimum.x, corner.x), minf(minimum.y, corner.y))
		maximum = Vector2(maxf(maximum.x, corner.x), maxf(maximum.y, corner.y))
	minimum.y -= float(GameConfig.ELEVATION_LEVELS - 1) * GameConfig.ELEVATION_PIXEL_STEP
	return Rect2(minimum, maximum - minimum)


func get_core_anchor() -> Vector2:
	var bounds := get_board_bounds()
	return Vector2(bounds.get_center().x, bounds.end.y + GameConfig.CORE_ANCHOR_GAP)


func has_elevation_side_walls() -> bool:
	return true


func get_cell_diamond(cell: Vector2i) -> PackedVector2Array:
	return _cell_diamond(cell)


func get_elevation_at(cell: Vector2i) -> int:
	return _elevation_at(cell)


func is_water(cell: Vector2i) -> bool:
	return _cell_is_valid(cell) and _water.size() == CELL_COUNT and _water[cell.y * GameConfig.GRID_COLUMNS + cell.x] != 0


func get_tile_instance_count() -> int:
	return _tile_multimesh.instance_count if _tile_multimesh != null else 0


func get_static_terrain_redraw_count() -> int:
	return _static_layer.build_count if is_instance_valid(_static_layer) else 0


func get_frontline_rebuild_count() -> int:
	return _frontline_layer.rebuild_count if is_instance_valid(_frontline_layer) else 0


func get_frontline_segments(current_ownership: PackedByteArray) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	if current_ownership.size() != CELL_COUNT:
		return segments
	for row in GameConfig.GRID_ROWS:
		for column in GameConfig.GRID_COLUMNS:
			var owner: int = current_ownership[row * GameConfig.GRID_COLUMNS + column]
			var right_owner := int(current_ownership[row * GameConfig.GRID_COLUMNS + column + 1]) if column + 1 < GameConfig.GRID_COLUMNS else owner
			if column + 1 < GameConfig.GRID_COLUMNS and owner != 0 and right_owner != 0 and right_owner != owner:
				var edge_elevation := maxi(_elevation_at(Vector2i(column, row)), _elevation_at(Vector2i(column + 1, row)))
				segments.append(PackedVector2Array([
					grid_to_screen_elevated(Vector2(column + 1, row), edge_elevation),
					grid_to_screen_elevated(Vector2(column + 1, row + 1), edge_elevation),
				]))
			var lower_owner := int(current_ownership[(row + 1) * GameConfig.GRID_COLUMNS + column]) if row + 1 < GameConfig.GRID_ROWS else owner
			if row + 1 < GameConfig.GRID_ROWS and owner != 0 and lower_owner != 0 and lower_owner != owner:
				var edge_elevation := maxi(_elevation_at(Vector2i(column, row)), _elevation_at(Vector2i(column, row + 1)))
				segments.append(PackedVector2Array([
					grid_to_screen_elevated(Vector2(column + 1, row + 1), edge_elevation),
					grid_to_screen_elevated(Vector2(column, row + 1), edge_elevation),
				]))
	return segments


func _ensure_layers() -> void:
	if is_instance_valid(_tile_layer):
		return
	_static_layer = StaticTerrainLayerScript.new()
	_static_layer.name = "StaticTerrain"
	_static_layer.z_index = 0
	add_child(_static_layer)
	_tile_layer = MultiMeshInstance2D.new()
	_tile_layer.name = "TileMultiMesh"
	_tile_layer.z_index = 1
	add_child(_tile_layer)
	_frontline_layer = FrontlineLayerScript.new()
	_frontline_layer.name = "Frontline"
	_frontline_layer.z_index = 2
	add_child(_frontline_layer)


func _initialize_or_refresh_tiles() -> void:
	if _ownership.size() != CELL_COUNT or _blocked.size() != CELL_COUNT or _water.size() != CELL_COUNT or _elevation.size() != CELL_COUNT:
		return
	if not _tiles_initialized:
		_cell_to_instance.resize(CELL_COUNT)
		_cell_to_instance.fill(-1)
		_flash_times.resize(CELL_COUNT)
		_flash_times.fill(FLASH_INACTIVE_TIME)
		_tile_multimesh = MultiMesh.new()
		_tile_multimesh.transform_format = MultiMesh.TRANSFORM_2D
		_tile_multimesh.use_colors = true
		_tile_multimesh.use_custom_data = true
		_tile_multimesh.mesh = _make_diamond_mesh()
		_tile_multimesh.instance_count = CELL_COUNT
		_tile_layer.multimesh = _tile_multimesh
		_tile_layer.material = _make_tile_material()
		_tiles_initialized = true
	var instance_index := 0
	for depth in GameConfig.GRID_COLUMNS + GameConfig.GRID_ROWS - 1:
		var first_row := maxi(0, depth - GameConfig.GRID_COLUMNS + 1)
		var last_row := mini(GameConfig.GRID_ROWS - 1, depth)
		for row in range(first_row, last_row + 1):
			var cell := Vector2i(depth - row, row)
			var cell_index := row * GameConfig.GRID_COLUMNS + cell.x
			_cell_to_instance[cell_index] = instance_index
			_tile_multimesh.set_instance_transform_2d(instance_index, Transform2D(0.0, cell_to_world(cell)))
			tile_transform_write_count += 1
			_write_tile_visual(cell_index, instance_index)
			instance_index += 1


func _update_tile_instance(cell_index: int, count_incremental: bool) -> void:
	var instance_index := _cell_to_instance[cell_index]
	if instance_index < 0:
		return
	_write_tile_visual(cell_index, instance_index)
	if count_incremental:
		tile_incremental_update_count += 1


func _write_tile_visual(cell_index: int, instance_index: int) -> void:
	var cell := Vector2i(cell_index % GameConfig.GRID_COLUMNS, cell_index / GameConfig.GRID_COLUMNS)
	var elevation_level := _elevation_at(cell)
	_tile_multimesh.set_instance_color(instance_index, _cell_color(cell, _ownership).lightened(float(elevation_level) * GameConfig.ELEVATION_BRIGHTNESS_STEP))
	var cell_blocked := _blocked[cell_index] != 0 or _water[cell_index] != 0
	var buildable := _can_build_with_ownership(cell, 2, _ownership, cell_blocked)
	_tile_multimesh.set_instance_custom_data(instance_index, Color(
		_flash_times[cell_index],
		1.0 if buildable else 0.0,
		float(elevation_level) / maxf(1.0, float(GameConfig.ELEVATION_LEVELS - 1)),
		1.0 if _water[cell_index] != 0 else 0.0
	))


func _make_diamond_mesh() -> ArrayMesh:
	var half_width := GameConfig.ISO_TILE_WIDTH * 0.5
	var half_height := GameConfig.ISO_TILE_HEIGHT * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, -half_height, 0.0),
		Vector3(half_width, 0.0, 0.0),
		Vector3(0.0, half_height, 0.0),
		Vector3(-half_width, 0.0, 0.0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.5, 0.0), Vector2(1.0, 0.5), Vector2(0.5, 1.0), Vector2(0.0, 0.5),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_tile_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 tile_pixels = vec2(48.0, 24.0);
uniform float flash_duration = 1.0;
varying vec4 tile_data;
varying vec4 tile_color;
void vertex() {
	tile_data = INSTANCE_CUSTOM;
	tile_color = COLOR;
}
void fragment() {
	float diamond_distance = 0.5 - (abs(UV.x - 0.5) + abs(UV.y - 0.5));
	float edge = 1.0 - smoothstep(0.0, 0.032, diamond_distance);
	vec3 color = mix(tile_color.rgb, vec3(0.07, 0.09, 0.12), edge * 0.48);
	vec2 from_center = (UV - vec2(0.5)) * tile_pixels;
	float marker = (1.0 - smoothstep(1.4, 2.1, length(from_center))) * tile_data.g;
	color = mix(color, vec3(0.18, 0.82, 0.72), marker * 0.42);
	float age = TIME - tile_data.r;
	float active = step(0.0, age) * (1.0 - step(flash_duration, age));
	float flash = active * (1.0 - clamp(age / flash_duration, 0.0, 1.0));
	color = mix(color, vec3(1.0), flash * 0.52);
	if (tile_data.a > 0.5) {
		float ripple = 0.035 * sin(TIME * 1.35 + UV.x * 13.0 + UV.y * 9.0);
		color += vec3(0.02, 0.08, 0.10) + ripple;
	}
	COLOR = vec4(color, tile_color.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tile_pixels", Vector2(GameConfig.ISO_TILE_WIDTH, GameConfig.ISO_TILE_HEIGHT))
	material.set_shader_parameter("flash_duration", GameConfig.TERRITORY_FLASH_DURATION)
	return material


func _cell_color(cell: Vector2i, current_ownership: PackedByteArray) -> Color:
	if is_water(cell):
		return GameConfig.COLOR_WATER if (cell.x + cell.y) % 2 == 0 else GameConfig.COLOR_WATER_ALT
	var owner := 1 if cell.y < GameConfig.GRID_ROWS / 2 else 2
	if current_ownership.size() == CELL_COUNT:
		owner = current_ownership[cell.y * GameConfig.GRID_COLUMNS + cell.x]
	var alternate := (cell.x + cell.y) % 2 == 0
	if owner == 2:
		return GameConfig.COLOR_TERRITORY_ALLY if alternate else GameConfig.COLOR_TERRITORY_ALLY_ALT
	return GameConfig.COLOR_TERRITORY_ENEMY if alternate else GameConfig.COLOR_TERRITORY_ENEMY_ALT


func _cell_is_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GameConfig.GRID_COLUMNS and cell.y >= 0 and cell.y < GameConfig.GRID_ROWS


func _elevation_at(cell: Vector2i) -> int:
	if not _cell_is_valid(cell) or _elevation.size() != CELL_COUNT:
		return 0
	return int(_elevation[cell.y * GameConfig.GRID_COLUMNS + cell.x])


func _cell_diamond(cell: Vector2i) -> PackedVector2Array:
	var elevation_level := _elevation_at(cell)
	return PackedVector2Array([
		grid_to_screen_elevated(Vector2(cell.x, cell.y), elevation_level),
		grid_to_screen_elevated(Vector2(cell.x + 1, cell.y), elevation_level),
		grid_to_screen_elevated(Vector2(cell.x + 1, cell.y + 1), elevation_level),
		grid_to_screen_elevated(Vector2(cell.x, cell.y + 1), elevation_level),
	])
