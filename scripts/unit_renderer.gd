class_name UnitRenderer
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const BLUE_ATLAS = preload("res://assets/units/infantry_blue.png")
const RED_ATLAS = preload("res://assets/units/infantry_red.png")
const BLUE_DRAGON_ATLAS = preload("res://assets/world/dragon_blue.png")
const RED_DRAGON_ATLAS = preload("res://assets/world/dragon_red.png")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const STATE_ADVANCE := 0
const STATE_ATTACK := 1
const STATE_WAIT := 2
const STATE_OFFSETS := [0, 2, 8, 12]

var _grid: GridBoard
var _simulation
var _infantry_units: MultiMeshInstance2D
var _enemy_dragons: MultiMeshInstance2D
var _ally_dragons: MultiMeshInstance2D
var _shadows: MultiMeshInstance2D
var _death_ghosts: Array[Dictionary] = []
var _animation_clock := 0.0
var _last_hp_by_id: Dictionary = {}
var _hp_bar_time_by_id: Dictionary = {}


func _ready() -> void:
	z_as_relative = false
	z_index = 40
	var infantry_mesh := QuadMesh.new()
	infantry_mesh.size = GameConfig.INFANTRY_RENDER_SIZE
	var dragon_mesh := QuadMesh.new()
	dragon_mesh.size = GameConfig.DRAGON_RENDER_SIZE
	_infantry_units = _make_batch("InfantryUnits", infantry_mesh, true, true)
	_enemy_dragons = _make_batch("EnemyDragons", dragon_mesh, true, true)
	_ally_dragons = _make_batch("AllyDragons", dragon_mesh, true, true)
	_enemy_dragons.z_index = 8
	_ally_dragons.z_index = 8
	_shadows = _make_batch("UnitBlobShadows", _make_ellipse_mesh(18.0, 6.0), true, false)
	_shadows.z_index = 6
	_infantry_units.material = _make_atlas_material(_make_team_texture_array())
	_enemy_dragons.material = _make_single_atlas_material(RED_DRAGON_ATLAS)
	_ally_dragons.material = _make_single_atlas_material(BLUE_DRAGON_ATLAS)


func setup(board: GridBoard, simulation) -> void:
	_grid = board
	_simulation = simulation
	sync()


func advance_visuals(delta: float) -> void:
	_animation_clock += delta
	for unit_id in _hp_bar_time_by_id.keys():
		_hp_bar_time_by_id[unit_id] = maxf(0.0, float(_hp_bar_time_by_id[unit_id]) - delta)
	var index := _death_ghosts.size() - 1
	while index >= 0:
		_death_ghosts[index].remaining = float(_death_ghosts[index].remaining) - delta
		if float(_death_ghosts[index].remaining) <= 0.0:
			_death_ghosts.remove_at(index)
		index -= 1


func queue_death(position: Vector2, team: int, unit_kind: int, direction: Vector2) -> void:
	if unit_kind == UNIT_DRAGON:
		return
	if direction.length_squared() <= 0.000001:
		direction = Vector2.DOWN if team == TEAM_ENEMY else Vector2.UP
	_death_ghosts.append({
		"position": position,
		"team": team,
		"kind": unit_kind,
		"direction": direction.normalized(),
		"remaining": GameConfig.INFANTRY_DEATH_DURATION,
	})


func get_multimesh_count() -> int:
	return (
		int(_infantry_units != null)
		+ int(_enemy_dragons != null)
		+ int(_ally_dragons != null)
	)


func get_shadow_batch_count() -> int:
	return int(_shadows != null)


func sync() -> void:
	if not is_instance_valid(_grid) or _simulation == null or _infantry_units == null:
		return
	_update_hp_bar_visibility()
	_sync_infantry_batch()
	_sync_dragon_batch(_enemy_dragons, TEAM_ENEMY)
	_sync_dragon_batch(_ally_dragons, TEAM_ALLY)
	_sync_shadows()
	queue_redraw()


func _make_batch(node_name: String, mesh: Mesh, use_colors: bool, use_custom_data: bool) -> MultiMeshInstance2D:
	var instance := MultiMeshInstance2D.new()
	instance.name = node_name
	instance.z_as_relative = false
	instance.z_index = 7
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = use_colors
	multimesh.use_custom_data = use_custom_data
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	instance.multimesh = multimesh
	add_child(instance)
	return instance


func _make_team_texture_array() -> Texture2DArray:
	var atlas := Texture2DArray.new()
	var error := atlas.create_from_images([BLUE_ATLAS.get_image(), RED_ATLAS.get_image()])
	assert(error == OK, "could not create infantry team texture array")
	return atlas


func _make_atlas_material(atlas: Texture2DArray) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2DArray atlas : source_color, filter_linear;
uniform vec2 atlas_grid = vec2(16.0);
uniform vec2 cell_pixels = vec2(96.0);
varying vec4 atlas_data;
varying vec4 instance_data;
void vertex() {
	atlas_data = INSTANCE_CUSTOM;
	instance_data = COLOR;
}
void fragment() {
	vec2 cell = floor(atlas_data.rg * (atlas_grid - vec2(1.0)) + vec2(0.5));
	vec2 inset_uv = (UV * (cell_pixels - vec2(2.0)) + vec2(1.0)) / cell_pixels;
	vec4 sample_color = texture(atlas, vec3((cell + inset_uv) / atlas_grid, instance_data.r));
	COLOR = vec4(sample_color.rgb * instance_data.g, sample_color.a * instance_data.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("atlas_grid", Vector2(GameConfig.INFANTRY_ATLAS_COLUMNS, GameConfig.INFANTRY_ATLAS_ROWS))
	material.set_shader_parameter("cell_pixels", Vector2.ONE * GameConfig.INFANTRY_ATLAS_CELL_SIZE)
	return material


func _make_single_atlas_material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D atlas : source_color, filter_linear;
uniform vec2 atlas_grid = vec2(16.0, 8.0);
uniform vec2 cell_pixels = vec2(96.0);
varying vec4 atlas_data;
varying vec4 instance_data;
void vertex() {
	atlas_data = INSTANCE_CUSTOM;
	instance_data = COLOR;
}
void fragment() {
	vec2 cell = floor(atlas_data.rg * (atlas_grid - vec2(1.0)) + vec2(0.5));
	vec2 inset_uv = (UV * (cell_pixels - vec2(2.0)) + vec2(1.0)) / cell_pixels;
	vec4 sample_color = texture(atlas, (cell + inset_uv) / atlas_grid);
	COLOR = vec4(sample_color.rgb * instance_data.rgb, sample_color.a * instance_data.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("atlas_grid", Vector2(GameConfig.DRAGON_ATLAS_COLUMNS, GameConfig.DRAGON_ATLAS_ROWS))
	material.set_shader_parameter("cell_pixels", Vector2.ONE * GameConfig.DRAGON_ATLAS_CELL_SIZE)
	return material


func _make_ellipse_mesh(width: float, height: float) -> ArrayMesh:
	var points := PackedVector2Array()
	for index in 16:
		var angle := TAU * float(index) / 16.0
		points.append(Vector2(cos(angle) * width * 0.5, sin(angle) * height * 0.5))
	return _make_mesh(points)


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


func _sync_infantry_batch() -> void:
	var entries: Array[Dictionary] = []
	for index in _simulation.unit_ids.size():
		if _simulation.unit_kinds[index] != UNIT_DRAGON and _simulation.unit_hp[index] > 0.0:
			entries.append({"unit_index": index, "y": _grid.grid_to_screen(_simulation.unit_positions[index]).y})
	for ghost_index in _death_ghosts.size():
		var ghost: Dictionary = _death_ghosts[ghost_index]
		entries.append({"ghost_index": ghost_index, "y": _grid.grid_to_screen(Vector2(ghost.position)).y})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	_infantry_units.multimesh.instance_count = entries.size()
	for draw_index in entries.size():
		var entry := entries[draw_index]
		var screen_position := Vector2.ZERO
		var direction := Vector2.ZERO
		var state_index := 0
		var animation_frame := 0
		var brightness := 1.0
		var alpha := 1.0
		var team := TEAM_ALLY
		var unit_kind := UNIT_MELEE
		if entry.has("unit_index"):
			var unit_index := int(entry.unit_index)
			team = int(_simulation.unit_teams[unit_index])
			unit_kind = int(_simulation.unit_kinds[unit_index])
			screen_position = get_unit_render_position(unit_index)
			direction = _simulation.unit_velocities[unit_index]
			var unit_state := int(_simulation.unit_states[unit_index])
			if unit_state == STATE_ATTACK:
				state_index = 2
				direction = _simulation.unit_lunge_directions[unit_index]
				var interval := GameConfig.RANGED_UNIT_ATTACK_INTERVAL if unit_kind == UNIT_RANGED else GameConfig.UNIT_ATTACK_INTERVAL
				var attack_progress := 1.0 - clampf(_simulation.unit_cooldowns[unit_index] / interval, 0.0, 1.0)
				animation_frame = mini(3, floori(attack_progress * 4.0))
			elif unit_state == STATE_ADVANCE and direction.length_squared() > 0.01:
				state_index = 1
				animation_frame = (floori(_animation_clock * GameConfig.INFANTRY_WALK_FPS) + int(_simulation.unit_ids[unit_index])) % 6
			else:
				state_index = 0
				animation_frame = (floori(_animation_clock * GameConfig.INFANTRY_IDLE_FPS) + int(_simulation.unit_ids[unit_index])) % 2
			var maximum_hp := GameConfig.RANGED_UNIT_MAX_HP if unit_kind == UNIT_RANGED else GameConfig.UNIT_MAX_HP
			brightness = lerpf(0.58, 1.0, clampf(_simulation.unit_hp[unit_index] / maximum_hp, 0.0, 1.0))
			if unit_state == STATE_WAIT:
				brightness *= 0.76
		else:
			var ghost: Dictionary = _death_ghosts[int(entry.ghost_index)]
			team = int(ghost.team)
			unit_kind = int(ghost.kind)
			screen_position = _grid.grid_to_screen(Vector2(ghost.position)) + Vector2(0, GameConfig.INFANTRY_FOOT_ANCHOR_Y)
			direction = Vector2(ghost.direction)
			state_index = 3
			var death_progress := 1.0 - clampf(float(ghost.remaining) / GameConfig.INFANTRY_DEATH_DURATION, 0.0, 1.0)
			animation_frame = mini(3, floori(death_progress * 4.0))
			alpha = clampf(float(ghost.remaining) / (GameConfig.INFANTRY_DEATH_DURATION * 0.28), 0.0, 1.0)
		var direction_index: int = get_direction_index(direction, team)
		var linear_index: int = unit_kind * GameConfig.INFANTRY_CLASS_FRAME_COUNT + direction_index * GameConfig.INFANTRY_FRAMES_PER_DIRECTION + int(STATE_OFFSETS[state_index]) + animation_frame
		var cell_x: int = linear_index % GameConfig.INFANTRY_ATLAS_COLUMNS
		var cell_y: int = linear_index / GameConfig.INFANTRY_ATLAS_COLUMNS
		_infantry_units.multimesh.set_instance_transform_2d(draw_index, Transform2D(0.0, screen_position))
		_infantry_units.multimesh.set_instance_custom_data(draw_index, Color(float(cell_x) / float(GameConfig.INFANTRY_ATLAS_COLUMNS - 1), float(cell_y) / float(GameConfig.INFANTRY_ATLAS_ROWS - 1), 0.0, 1.0))
		_infantry_units.multimesh.set_instance_color(draw_index, Color(1.0 if team == TEAM_ENEMY else 0.0, brightness, 0.0, alpha))


func _sync_dragon_batch(instance: MultiMeshInstance2D, team: int) -> void:
	var indices: Array[int] = []
	for index in _simulation.unit_ids.size():
		if _simulation.unit_teams[index] == team and _simulation.unit_kinds[index] == UNIT_DRAGON and _simulation.unit_hp[index] > 0.0:
			indices.append(index)
	indices.sort_custom(func(a: int, b: int) -> bool: return _grid.grid_to_screen(_simulation.unit_positions[a]).y < _grid.grid_to_screen(_simulation.unit_positions[b]).y)
	instance.multimesh.instance_count = indices.size()
	for draw_index in indices.size():
		var unit_index := indices[draw_index]
		var direction: Vector2 = _simulation.unit_velocities[unit_index]
		var unit_state: int = _simulation.unit_states[unit_index]
		var state_offset := 2
		var animation_frame := (floori(_animation_clock * GameConfig.INFANTRY_WALK_FPS) + int(_simulation.unit_ids[unit_index])) % 6
		if unit_state == STATE_ATTACK:
			direction = _simulation.unit_lunge_directions[unit_index]
			state_offset = 8
			var attack_progress := 1.0 - clampf(_simulation.unit_cooldowns[unit_index] / GameConfig.DRAGON_UNIT_ATTACK_INTERVAL, 0.0, 1.0)
			animation_frame = mini(3, floori(attack_progress * 4.0))
		elif direction.length_squared() <= 0.01:
			state_offset = 0
			animation_frame = (floori(_animation_clock * GameConfig.INFANTRY_IDLE_FPS) + int(_simulation.unit_ids[unit_index])) % 2
		var direction_index := get_direction_index(direction, team)
		var linear_index := direction_index * GameConfig.DRAGON_FRAMES_PER_DIRECTION + state_offset + animation_frame
		var cell_x: int = linear_index % GameConfig.DRAGON_ATLAS_COLUMNS
		var cell_y: int = linear_index / GameConfig.DRAGON_ATLAS_COLUMNS
		var hp_ratio := clampf(_simulation.unit_hp[unit_index] / GameConfig.DRAGON_UNIT_MAX_HP, 0.0, 1.0)
		var brightness := lerpf(0.62, 1.0, hp_ratio)
		instance.multimesh.set_instance_transform_2d(draw_index, Transform2D(0.0, get_unit_render_position(unit_index)))
		instance.multimesh.set_instance_custom_data(draw_index, Color(float(cell_x) / float(GameConfig.DRAGON_ATLAS_COLUMNS - 1), float(cell_y) / float(GameConfig.DRAGON_ATLAS_ROWS - 1), 0.0, 1.0))
		instance.multimesh.set_instance_color(draw_index, Color(brightness, brightness, brightness, 1.0))


func _sync_shadows() -> void:
	var positions: Array[Dictionary] = []
	for index in _simulation.unit_ids.size():
		if _simulation.unit_hp[index] <= 0.0:
			continue
		positions.append({"position": _simulation.unit_positions[index], "dragon": _simulation.unit_kinds[index] == UNIT_DRAGON})
	for ghost in _death_ghosts:
		positions.append({"position": ghost.position, "dragon": false})
	_shadows.multimesh.instance_count = positions.size()
	for index in positions.size():
		var entry: Dictionary = positions[index]
		var scale := Vector2(1.28, 1.0) if bool(entry.dragon) else Vector2.ONE
		var at := _grid.grid_to_screen(Vector2(entry.position)) + Vector2(0, 2)
		_shadows.multimesh.set_instance_transform_2d(index, Transform2D(0.0, scale, 0.0, at))
		_shadows.multimesh.set_instance_color(index, Color(0.02, 0.03, 0.05, 0.24 if bool(entry.dragon) else 0.35))


func get_direction_index(direction: Vector2, team: int) -> int:
	if direction.length_squared() <= 0.000001:
		direction = Vector2.DOWN if team == TEAM_ENEMY else Vector2.UP
	var angle := atan2(direction.x, direction.y)
	return posmod(roundi(angle / TAU * float(GameConfig.INFANTRY_ATLAS_DIRECTIONS)), GameConfig.INFANTRY_ATLAS_DIRECTIONS)


func get_unit_color(team: int, unit_kind: int, unit_state: int) -> Color:
	var color := GameConfig.COLOR_ALLY.lightened(0.28) if team == TEAM_ALLY else GameConfig.COLOR_ENEMY.lightened(0.18)
	if unit_kind == UNIT_RANGED:
		color = color.lerp(GameConfig.COLOR_TEAL, 0.38).lightened(0.08)
	elif unit_kind == UNIT_DRAGON:
		color = color.lerp(GameConfig.COLOR_ORANGE, 0.48).lightened(0.14)
	if unit_state == STATE_ADVANCE:
		color = color.darkened(0.12)
	elif unit_state == STATE_WAIT:
		color = color.darkened(0.34)
	return color


func get_unit_render_position(unit_index: int) -> Vector2:
	var lunge_offset := Vector2.ZERO
	if _simulation.unit_lunge_timers[unit_index] > 0.0:
		var remaining_ratio: float = clampf(_simulation.unit_lunge_timers[unit_index] / GameConfig.UNIT_LUNGE_DURATION, 0.0, 1.0)
		var lunge_envelope := sin((1.0 - remaining_ratio) * PI)
		lunge_offset = _simulation.unit_lunge_directions[unit_index] * GameConfig.UNIT_LUNGE_DISTANCE * lunge_envelope
	var anchor_y := GameConfig.DRAGON_FOOT_ANCHOR_Y if _simulation.unit_kinds[unit_index] == UNIT_DRAGON else GameConfig.INFANTRY_FOOT_ANCHOR_Y
	return _grid.grid_to_screen(_simulation.unit_positions[unit_index] + lunge_offset) + Vector2(0, anchor_y)


func _update_hp_bar_visibility() -> void:
	var living_ids: Dictionary = {}
	for index in _simulation.unit_ids.size():
		var unit_id: int = _simulation.unit_ids[index]
		living_ids[unit_id] = true
		var current_hp: float = _simulation.unit_hp[index]
		var maximum_hp := GameConfig.UNIT_MAX_HP
		if _simulation.unit_kinds[index] == UNIT_RANGED:
			maximum_hp = GameConfig.RANGED_UNIT_MAX_HP
		elif _simulation.unit_kinds[index] == UNIT_DRAGON:
			maximum_hp = GameConfig.DRAGON_UNIT_MAX_HP
		var previous_hp: float = float(_last_hp_by_id.get(unit_id, maximum_hp))
		if current_hp + 0.0001 < previous_hp:
			_hp_bar_time_by_id[unit_id] = GameConfig.UNIT_HP_BAR_VISIBLE_SECONDS
		elif current_hp >= maximum_hp - 0.0001:
			_hp_bar_time_by_id[unit_id] = 0.0
		_last_hp_by_id[unit_id] = current_hp
	for unit_id in _last_hp_by_id.keys():
		if not living_ids.has(unit_id):
			_last_hp_by_id.erase(unit_id)
			_hp_bar_time_by_id.erase(unit_id)


func get_hp_bar_alpha(unit_id: int) -> float:
	var remaining: float = float(_hp_bar_time_by_id.get(unit_id, 0.0))
	return clampf(remaining / GameConfig.UNIT_HP_BAR_FADE_SECONDS, 0.0, 1.0)


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
		var alpha := get_hp_bar_alpha(_simulation.unit_ids[index])
		if ratio >= 0.995 or alpha <= 0.0:
			continue
		var bar_y := -76.0 if _simulation.unit_kinds[index] == UNIT_DRAGON else -53.0
		var at := _grid.grid_to_screen(_simulation.unit_positions[index]) + Vector2(-9, bar_y)
		draw_rect(Rect2(at, Vector2(18, 2)), Color(0.04, 0.05, 0.08, 0.86 * alpha))
		var color := GameConfig.COLOR_ALLY if _simulation.unit_teams[index] == TEAM_ALLY else GameConfig.COLOR_ENEMY
		draw_rect(Rect2(at + Vector2(1, 0.5), Vector2(16.0 * ratio, 1)), Color(color.lightened(0.25), alpha))
