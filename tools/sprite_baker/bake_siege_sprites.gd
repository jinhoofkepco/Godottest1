extends SceneTree

const CELL := 96
const COLUMNS := 16
const ROWS := 16
const DIRECTIONS := 8
const FRAMES_PER_DIRECTION := 16
const STATE_ORDER := ["idle", "walk", "attack", "death"]
const STATE_COUNTS := {"idle": 2, "walk": 6, "attack": 4, "death": 4}
const STATE_OFFSETS := {"idle": 0, "walk": 2, "attack": 8, "death": 12}
const SOURCES := [
	{"name": "blue", "path": "res://assets/source/kaykit_medieval/buildings/blue/building_tower_catapult_blue.gltf"},
	{"name": "red", "path": "res://assets/source/kaykit_medieval/buildings/red/building_tower_catapult_red.gltf"},
]

var _output := "res://assets/units"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		else:
			_fail("usage: bake_siege_sprites.gd [--output=res://assets/units]")
			return
	var output_dir := ProjectSettings.globalize_path(_output)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create output directory")
		return
	var rig := _create_capture_rig()
	root.add_child(rig.viewport)
	await process_frame
	for source: Dictionary in SOURCES:
		if not await _bake_team(rig, source, output_dir):
			return
	var metadata := {
		"schema": 1,
		"generator": "tools/sprite_baker/bake_siege_sprites.gd",
		"license": "KayKit Medieval Hexagon Pack, CC0 1.0",
		"sources": SOURCES,
		"directions": DIRECTIONS,
		"direction_degrees": [0, 45, 90, 135, 180, 225, 270, 315],
		"frames_per_direction": FRAMES_PER_DIRECTION,
		"state_order": STATE_ORDER,
		"state_counts": STATE_COUNTS,
		"state_offsets": STATE_OFFSETS,
		"cell_size": [CELL, CELL],
		"columns": COLUMNS,
		"rows": ROWS,
		"atlas_size": [COLUMNS * CELL, ROWS * CELL],
		"transparent_background": true,
		"lighting": {"key": "upper-left 45 degrees", "key_energy": 1.55, "ambient_energy": 0.22},
	}
	var metadata_file := FileAccess.open(output_dir.path_join("siege_atlas.json"), FileAccess.WRITE)
	if metadata_file == null:
		_fail("could not write SIEGE metadata")
		return
	metadata_file.store_string(JSON.stringify(metadata, "\t") + "\n")
	metadata_file.close()
	print("SIEGE SPRITE BAKE PASS: 2 teams x 8 directions x 16 frames, 1536x1536")
	quit(0)


func _bake_team(rig: Dictionary, source: Dictionary, output_dir: String) -> bool:
	var packed := load(String(source.path)) as PackedScene
	if packed == null:
		_fail("could not load %s" % source.path)
		return false
	var model := packed.instantiate() as Node3D
	rig.stage.add_child(model)
	var arm := _find_named_node(model, "catapult_arm")
	var arm_base_rotation := arm.rotation if arm != null else Vector3.ZERO
	var atlas := Image.create_empty(COLUMNS * CELL, ROWS * CELL, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for state: String in STATE_ORDER:
		var frame_count: int = STATE_COUNTS[state]
		for direction_index in DIRECTIONS:
			model.rotation = Vector3(0.0, deg_to_rad(float(direction_index) * 45.0), 0.0)
			for frame_index in frame_count:
				var phase := float(frame_index) / float(maxi(1, frame_count - 1))
				model.position.y = sin(phase * TAU) * (0.035 if state == "walk" else 0.012)
				model.rotation.z = deg_to_rad(phase * 12.0) if state == "death" else 0.0
				if arm != null:
					arm.rotation = arm_base_rotation
					if state == "attack":
						arm.rotation.x += lerpf(-0.62, 0.34, phase)
				await process_frame
				RenderingServer.force_draw(false)
				var frame: Image = rig.viewport.get_texture().get_image()
				if frame == null or frame.is_empty():
					_fail("empty SIEGE capture")
					return false
				frame.convert(Image.FORMAT_RGBA8)
				frame.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
				var linear_index: int = direction_index * FRAMES_PER_DIRECTION + int(STATE_OFFSETS[state]) + frame_index
				var destination := Vector2i((linear_index % COLUMNS) * CELL, (linear_index / COLUMNS) * CELL)
				atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i.ONE * CELL), destination)
	var save_path := output_dir.path_join("siege_%s.png" % String(source.name))
	if atlas.save_png(save_path) != OK:
		_fail("could not save %s" % save_path)
		return false
	model.queue_free()
	await process_frame
	print("BAKED %s 1536x1536" % save_path)
	return true


func _create_capture_rig() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "SiegeBakeViewport"
	viewport.size = Vector2i(192, 192)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.6
	camera.current = true
	var pitch := deg_to_rad(30.0)
	var distance := 7.0
	camera.look_at_from_position(Vector3(distance * cos(pitch), distance * sin(pitch), distance * cos(pitch)), Vector3(0.0, 1.0, 0.0), Vector3.UP)
	stage.add_child(camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key.light_energy = 1.55
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(28.0, 142.0, 0.0)
	fill.light_color = Color("9cc8ff")
	fill.light_energy = 0.18
	stage.add_child(fill)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.TRANSPARENT
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.22
	world_environment.environment = environment
	stage.add_child(world_environment)
	return {"viewport": viewport, "stage": stage}


func _find_named_node(node: Node, fragment: String) -> Node3D:
	if node is Node3D and fragment in node.name.to_lower():
		return node
	for child in node.get_children():
		var match_node := _find_named_node(child, fragment)
		if match_node != null:
			return match_node
	return null


func _fail(message: String) -> void:
	push_error("SIEGE SPRITE BAKE FAILED: %s" % message)
	quit(1)
