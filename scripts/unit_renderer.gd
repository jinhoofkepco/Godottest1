class_name UnitRenderer
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const BLUE_ATLAS = preload("res://assets/units/infantry_blue.png")
const RED_ATLAS = preload("res://assets/units/infantry_red.png")
const BLUE_SIEGE_ATLAS = preload("res://assets/units/siege_blue.png")
const RED_SIEGE_ATLAS = preload("res://assets/units/siege_red.png")
const BLUE_DRAGON_ATLAS = preload("res://assets/world/dragon_blue.png")
const RED_DRAGON_ATLAS = preload("res://assets/world/dragon_red.png")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const UNIT_SIEGE := 3
const STATE_ADVANCE := 0
const STATE_ATTACK := 1
const STATE_WAIT := 2

var _grid: GridBoard
var _simulation
var _infantry_units: MultiMeshInstance2D
var _enemy_dragons: MultiMeshInstance2D
var _ally_dragons: MultiMeshInstance2D
var _shadows: MultiMeshInstance2D
var _last_snapshot: Dictionary = {}
var bulk_upload_count := 0
var last_sync_usec := 0


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


func advance_visuals(_delta: float) -> void:
	# Animation, death ghosts, lunges, and HP timers advance inside the C# core.
	pass


func queue_death(_position: Vector2, _team: int, _unit_kind: int, _direction: Vector2) -> void:
	# Compatibility hook for old smoke helpers; live deaths are part of get_render_snapshot().
	pass


func note_damage(_unit_id: int) -> void:
	# Damage visibility is event-driven inside the C# core.
	pass


func get_multimesh_count() -> int:
	return int(_infantry_units != null) + int(_enemy_dragons != null) + int(_ally_dragons != null)


func get_shadow_batch_count() -> int:
	return int(_shadows != null)


func reset_bulk_upload_count() -> void:
	bulk_upload_count = 0


func sync() -> void:
	if _simulation == null or _infantry_units == null:
		return
	var started := Time.get_ticks_usec()
	_last_snapshot = _simulation.call("GetRenderSnapshot")
	_upload_multimesh(_infantry_units.multimesh, int(_last_snapshot.get("infantry_count", 0)), _last_snapshot.get("infantry_buffer", PackedFloat32Array()))
	_upload_multimesh(_enemy_dragons.multimesh, int(_last_snapshot.get("enemy_dragon_count", 0)), _last_snapshot.get("enemy_dragon_buffer", PackedFloat32Array()))
	_upload_multimesh(_ally_dragons.multimesh, int(_last_snapshot.get("ally_dragon_count", 0)), _last_snapshot.get("ally_dragon_buffer", PackedFloat32Array()))
	_upload_multimesh(_shadows.multimesh, int(_last_snapshot.get("shadow_count", 0)), _last_snapshot.get("shadow_buffer", PackedFloat32Array()))
	queue_redraw()
	last_sync_usec = Time.get_ticks_usec() - started


func _upload_multimesh(multimesh: MultiMesh, count: int, buffer: PackedFloat32Array) -> void:
	multimesh.instance_count = count
	if count > 0:
		RenderingServer.multimesh_set_buffer(multimesh.get_rid(), buffer)
	bulk_upload_count += 1


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
	multimesh.custom_aabb = AABB(Vector3(-2048.0, -2048.0, -1.0), Vector3(4096.0, 4096.0, 2.0))
	multimesh.instance_count = 0
	instance.multimesh = multimesh
	add_child(instance)
	return instance


func _make_team_texture_array() -> Texture2DArray:
	var atlas := Texture2DArray.new()
	var error := atlas.create_from_images([BLUE_ATLAS.get_image(), RED_ATLAS.get_image(), BLUE_SIEGE_ATLAS.get_image(), RED_SIEGE_ATLAS.get_image()])
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
	vec2 frame_uv = vec2(UV.x, atlas_data.a > 0.5 ? 1.0 - UV.y : UV.y);
	vec2 inset_uv = (frame_uv * (cell_pixels - vec2(2.0)) + vec2(1.0)) / cell_pixels;
	vec4 sample_color = texture(atlas, vec3((cell + inset_uv) / atlas_grid, atlas_data.b * 3.0));
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
	vec2 frame_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 inset_uv = (frame_uv * (cell_pixels - vec2(2.0)) + vec2(1.0)) / cell_pixels;
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
	var vertices := PackedVector3Array()
	for point in points:
		vertices.append(Vector3(point.x, point.y, 0.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(points)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func get_direction_index(direction: Vector2, team: int) -> int:
	if direction.length_squared() <= 0.000001:
		direction = Vector2.DOWN if team == TEAM_ENEMY else Vector2.UP
	return posmod(roundi(atan2(direction.x, direction.y) / TAU * float(GameConfig.INFANTRY_ATLAS_DIRECTIONS)), GameConfig.INFANTRY_ATLAS_DIRECTIONS)


func get_unit_color(team: int, unit_kind: int, unit_state: int) -> Color:
	var color := GameConfig.COLOR_ALLY.lightened(0.28) if team == TEAM_ALLY else GameConfig.COLOR_ENEMY.lightened(0.18)
	if unit_kind == UNIT_RANGED:
		color = color.lerp(GameConfig.COLOR_TEAL, 0.38).lightened(0.08)
	elif unit_kind == UNIT_DRAGON:
		color = color.lerp(GameConfig.COLOR_ORANGE, 0.48).lightened(0.14)
	elif unit_kind == UNIT_SIEGE:
		color = color.lerp(GameConfig.COLOR_ORANGE, 0.32)
	if unit_state == STATE_ADVANCE:
		color = color.darkened(0.12)
	elif unit_state == STATE_WAIT:
		color = color.darkened(0.34)
	return color


func get_unit_render_size(unit_kind: int) -> Vector2:
	var radius := GameConfig.DRAGON_UNIT_RADIUS if unit_kind == UNIT_DRAGON else (GameConfig.SIEGE_UNIT_RADIUS if unit_kind == UNIT_SIEGE else (GameConfig.RANGED_UNIT_RADIUS if unit_kind == UNIT_RANGED else GameConfig.MELEE_UNIT_RADIUS))
	var width: float = radius * GameConfig.UNIT_RENDER_PIXELS_PER_RADIUS
	return Vector2(width, width * (1.12 if unit_kind == UNIT_DRAGON else (1.0 if unit_kind == UNIT_SIEGE else 1.30)))


func get_atlas_layer(unit_kind: int, team: int) -> int:
	if unit_kind == UNIT_SIEGE:
		return 3 if team == TEAM_ENEMY else 2
	return 1 if team == TEAM_ENEMY else 0


func get_hp_bar_alpha(_unit_id: int) -> float:
	return 0.0


func _draw() -> void:
	var bars: PackedFloat32Array = _last_snapshot.get("hp_bars", PackedFloat32Array())
	var count := int(_last_snapshot.get("hp_bar_count", 0))
	for index in count:
		var offset := index * 8
		var at := Vector2(bars[offset], bars[offset + 1])
		var width := bars[offset + 2]
		var ratio := bars[offset + 3]
		var team := int(bars[offset + 4])
		var alpha := bars[offset + 5]
		draw_rect(Rect2(at, Vector2(width, 2)), Color(0.04, 0.05, 0.08, 0.86 * alpha))
		var color := GameConfig.COLOR_ALLY if team == TEAM_ALLY else GameConfig.COLOR_ENEMY
		draw_rect(Rect2(at + Vector2(1, 0.5), Vector2((width - 2.0) * ratio, 1)), Color(color.lightened(0.25), alpha))
