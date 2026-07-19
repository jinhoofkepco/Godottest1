extends SceneTree

const STATIC_CELL := 128
const DRAGON_CELL := 96
const DRAGON_COLUMNS := 16
const DRAGON_ROWS := 8
const DIRECTIONS := 8
const FRAMES_PER_DIRECTION := 16
const STATE_ORDER := ["idle", "fly", "attack", "death"]
const STATE_COUNTS := {"idle": 2, "fly": 6, "attack": 4, "death": 4}
const STATE_OFFSETS := {"idle": 0, "fly": 2, "attack": 8, "death": 12}
const DRAGON_CLIPS := {
	"idle": "DragonArmature|Dragon_Flying",
	"fly": "DragonArmature|Dragon_Flying",
	"attack": "DragonArmature|Dragon_Attack",
	"death": "DragonArmature|Dragon_Death",
}
const STATIC_MODELS := [
	{"name": "blue_hq", "path": "res://assets/source/kaykit_medieval/buildings/blue/building_castle_blue.gltf", "camera": 5.2, "target": 1.0},
	{"name": "red_hq", "path": "res://assets/source/kaykit_medieval/buildings/red/building_castle_red.gltf", "camera": 5.2, "target": 1.0},
	{"name": "blue_melee_spawner", "path": "res://assets/source/kaykit_medieval/buildings/blue/building_barracks_blue.gltf", "camera": 4.4, "target": 0.85},
	{"name": "red_melee_spawner", "path": "res://assets/source/kaykit_medieval/buildings/red/building_barracks_red.gltf", "camera": 4.4, "target": 0.85},
	{"name": "blue_ranged_spawner", "path": "res://assets/source/kaykit_medieval/buildings/blue/building_archeryrange_blue.gltf", "camera": 4.4, "target": 0.85},
	{"name": "red_ranged_spawner", "path": "res://assets/source/kaykit_medieval/buildings/red/building_archeryrange_red.gltf", "camera": 4.4, "target": 0.85},
	{"name": "blue_tower", "path": "res://assets/source/kaykit_medieval/buildings/blue/building_tower_catapult_blue.gltf", "camera": 4.6, "target": 1.0},
	{"name": "red_tower", "path": "res://assets/source/kaykit_medieval/buildings/red/building_tower_catapult_red.gltf", "camera": 4.6, "target": 1.0},
	{"name": "blue_dragon_lair", "path": "res://assets/source/kaykit_medieval/buildings/blue/building_tower_B_blue.gltf", "camera": 4.5, "target": 1.0},
	{"name": "red_dragon_lair", "path": "res://assets/source/kaykit_medieval/buildings/red/building_tower_B_red.gltf", "camera": 4.5, "target": 1.0},
	{"name": "rock_a", "path": "res://assets/source/kaykit_medieval/nature/rock_single_A.gltf", "camera": 1.1, "target": 0.18},
	{"name": "rock_b", "path": "res://assets/source/kaykit_medieval/nature/rock_single_B.gltf", "camera": 1.1, "target": 0.18},
	{"name": "rock_c", "path": "res://assets/source/kaykit_medieval/nature/rock_single_C.gltf", "camera": 1.1, "target": 0.18},
	{"name": "crate", "path": "res://assets/source/kaykit_medieval/props/crate_A_big.gltf", "camera": 1.1, "target": 0.18},
]
const TEAMS := [
	{"name": "blue", "color": Color("287eea")},
	{"name": "red", "color": Color("e24a57")},
]

var _output := "res://assets/world"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		else:
			_fail("usage: bake_world_sprites.gd [--output=res://assets/world]")
			return
	var output_dir := ProjectSettings.globalize_path(_output)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create output directory")
		return
	var rig := _create_capture_rig()
	root.add_child(rig.viewport)
	await process_frame
	var world_atlas := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	world_atlas.fill(Color.TRANSPARENT)
	var sprite_metadata: Dictionary = {}
	for index in STATIC_MODELS.size():
		var spec: Dictionary = STATIC_MODELS[index]
		var frame: Image = await _capture_static(rig, spec)
		if frame == null:
			return
		var destination := Vector2i((index % 4) * STATIC_CELL, (index / 4) * STATIC_CELL)
		world_atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i.ONE * STATIC_CELL), destination)
		sprite_metadata[String(spec.name)] = [destination.x, destination.y, STATIC_CELL, STATIC_CELL]
	var world_error := world_atlas.save_png(output_dir.path_join("world_atlas.png"))
	if world_error != OK:
		_fail("could not save world atlas")
		return
	for team: Dictionary in TEAMS:
		if not await _bake_dragon_team(rig, team, output_dir):
			return
	var metadata := {
		"schema": 1,
		"generator": "tools/sprite_baker/bake_world_sprites.gd",
		"static_cell_size": [STATIC_CELL, STATIC_CELL],
		"world_atlas_size": [512, 512],
		"sprites": sprite_metadata,
		"dragon_source": "res://assets/source/quaternius_monsters/Dragon.fbx",
		"dragon_directions": DIRECTIONS,
		"dragon_frames_per_direction": FRAMES_PER_DIRECTION,
		"dragon_state_order": STATE_ORDER,
		"dragon_state_counts": STATE_COUNTS,
		"dragon_state_offsets": STATE_OFFSETS,
		"dragon_atlas_size": [DRAGON_COLUMNS * DRAGON_CELL, DRAGON_ROWS * DRAGON_CELL],
		"dragon_cell_size": [DRAGON_CELL, DRAGON_CELL],
		"lighting": {"key": "upper-left 45 degrees", "key_energy": 1.55, "ambient_energy": 0.22},
	}
	var metadata_file := FileAccess.open(output_dir.path_join("world_atlas.json"), FileAccess.WRITE)
	if metadata_file == null:
		_fail("could not write world metadata")
		return
	metadata_file.store_string(JSON.stringify(metadata, "\t") + "\n")
	metadata_file.close()
	print("WORLD SPRITE BAKE PASS: 14 static sprites + 2 dragon atlases")
	quit(0)


func _capture_static(rig: Dictionary, spec: Dictionary) -> Image:
	var packed := load(String(spec.path)) as PackedScene
	if packed == null:
		_fail("could not load %s" % spec.path)
		return null
	var model := packed.instantiate() as Node3D
	rig.stage.add_child(model)
	_configure_camera(rig.camera, float(spec.camera), float(spec.target))
	await process_frame
	RenderingServer.force_draw(false)
	var frame: Image = rig.viewport.get_texture().get_image()
	if frame == null or frame.is_empty():
		_fail("empty capture for %s" % spec.name)
		return null
	frame.convert(Image.FORMAT_RGBA8)
	frame.resize(STATIC_CELL, STATIC_CELL, Image.INTERPOLATE_LANCZOS)
	model.queue_free()
	await process_frame
	return frame


func _bake_dragon_team(rig: Dictionary, team: Dictionary, output_dir: String) -> bool:
	var packed := load("res://assets/source/quaternius_monsters/Dragon.fbx") as PackedScene
	if packed == null:
		_fail("could not load dragon source")
		return false
	var model := packed.instantiate() as Node3D
	rig.stage.add_child(model)
	_recolor_dragon(model, Color(team.color))
	var player := _first_animation_player(model)
	if player == null:
		_fail("dragon has no AnimationPlayer")
		return false
	_configure_camera(rig.camera, 4.8, 0.9)
	var atlas := Image.create_empty(DRAGON_COLUMNS * DRAGON_CELL, DRAGON_ROWS * DRAGON_CELL, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for state: String in STATE_ORDER:
		var clip_name: String = DRAGON_CLIPS[state]
		if not player.has_animation(clip_name):
			_fail("dragon is missing %s" % clip_name)
			return false
		var animation := player.get_animation(clip_name)
		var frame_count: int = STATE_COUNTS[state]
		for direction_index in DIRECTIONS:
			model.rotation.y = deg_to_rad(float(direction_index) * 360.0 / float(DIRECTIONS))
			for frame_index in frame_count:
				var denominator := frame_count if state in ["idle", "fly"] else maxi(1, frame_count - 1)
				var normalized_time := float(frame_index) / float(denominator)
				if state in ["attack", "death"]:
					normalized_time *= 0.94
				player.play(clip_name)
				player.seek(animation.length * normalized_time, true)
				player.pause()
				await process_frame
				RenderingServer.force_draw(false)
				var frame: Image = rig.viewport.get_texture().get_image()
				if frame == null or frame.is_empty():
					_fail("empty dragon capture")
					return false
				frame.convert(Image.FORMAT_RGBA8)
				frame.resize(DRAGON_CELL, DRAGON_CELL, Image.INTERPOLATE_LANCZOS)
				var linear_index: int = direction_index * FRAMES_PER_DIRECTION + int(STATE_OFFSETS[state]) + frame_index
				var destination := Vector2i((linear_index % DRAGON_COLUMNS) * DRAGON_CELL, (linear_index / DRAGON_COLUMNS) * DRAGON_CELL)
				atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i.ONE * DRAGON_CELL), destination)
	var atlas_path := output_dir.path_join("dragon_%s.png" % String(team.name))
	var save_error := atlas.save_png(atlas_path)
	if save_error != OK:
		_fail("could not save %s" % atlas_path)
		return false
	model.queue_free()
	await process_frame
	print("BAKED %s 1536x768" % atlas_path)
	return true


func _create_capture_rig() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "WorldSpriteBakeViewport"
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	stage.add_child(camera)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key_light.light_energy = 1.55
	stage.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(28.0, 142.0, 0.0)
	fill_light.light_color = Color("9cc8ff")
	fill_light.light_energy = 0.18
	stage.add_child(fill_light)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.TRANSPARENT
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.22
	world_environment.environment = environment
	stage.add_child(world_environment)
	return {"viewport": viewport, "stage": stage, "camera": camera}


func _configure_camera(camera: Camera3D, camera_size: float, target_height: float) -> void:
	camera.size = camera_size
	var pitch := deg_to_rad(30.0)
	var distance := 7.0
	var camera_position := Vector3(distance * cos(pitch), distance * sin(pitch), distance * cos(pitch))
	camera.look_at_from_position(camera_position, Vector3(0.0, target_height, 0.0), Vector3.UP)


func _recolor_dragon(node: Node, team_color: Color) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface_index in node.mesh.get_surface_count():
			var source: Material = node.get_active_material(surface_index)
			if source is BaseMaterial3D:
				var material := source.duplicate() as BaseMaterial3D
				var material_name := material.resource_name.to_lower()
				if material_name == "main":
					material.albedo_color = team_color.darkened(0.12)
				elif material_name == "wings":
					material.albedo_color = team_color.darkened(0.48)
				material.roughness = 0.8
				node.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_recolor_dragon(child, team_color)


func _first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var player := _first_animation_player(child)
		if player != null:
			return player
	return null


func _fail(message: String) -> void:
	push_error("WORLD SPRITE BAKE FAILED: %s" % message)
	quit(1)
