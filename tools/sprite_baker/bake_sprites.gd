extends SceneTree

const DEFAULT_MODELS := [
	{"name": "melee", "path": "res://assets/source/kaykit/Knight.glb"},
	{"name": "ranged", "path": "res://assets/source/kaykit/Rogue_Hooded.glb"},
]
const DEFAULT_ANIMATIONS := [
	{"idle": "Idle", "walk": "Walking_A", "attack": "1H_Melee_Attack_Chop", "death": "Death_A"},
	{"idle": "Idle", "walk": "Walking_A", "attack": "2H_Ranged_Shoot", "death": "Death_A"},
]
const STATE_ORDER := ["idle", "walk", "attack", "death"]
const STATE_COUNTS := {"idle": 2, "walk": 6, "attack": 4, "death": 4}
const STATE_OFFSETS := {"idle": 0, "walk": 2, "attack": 8, "death": 12}

var _options := {
	"models": DEFAULT_MODELS.duplicate(true),
	"animations": DEFAULT_ANIMATIONS.duplicate(true),
	"output": "res://assets/units",
	"directions": 8,
	"pitch": 30.0,
	"cell": 96,
	"raw": 192,
	"camera_size": 2.75,
	"target_height": 0.86,
	"teams": [
		{"name": "blue", "color": Color("62a7ff")},
		{"name": "red", "color": Color("ff6670")},
	],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _parse_arguments(OS.get_cmdline_user_args()):
		quit(2)
		return
	var models: Array = _options.models
	var animations: Array = _options.animations
	var directions: int = int(_options.directions)
	var cell_size: int = int(_options.cell)
	if models.is_empty() or models.size() != animations.size() or directions <= 0:
		push_error("models and animation sets must be non-empty and have the same length")
		quit(2)
		return
	var total_cells := models.size() * directions * 16
	var columns := ceili(sqrt(float(total_cells)))
	while total_cells % columns != 0:
		columns += 1
	var rows := ceili(float(total_cells) / float(columns))
	if columns * cell_size > 2048 or rows * cell_size > 2048:
		push_error("atlas exceeds 2048x2048: %dx%d" % [columns * cell_size, rows * cell_size])
		quit(2)
		return
	var output_dir := ProjectSettings.globalize_path(String(_options.output))
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("could not create output directory: %s" % output_dir)
		quit(2)
		return

	var rig := _create_capture_rig()
	root.add_child(rig.viewport)
	await process_frame
	for team: Dictionary in _options.teams:
		var atlas := Image.create_empty(columns * cell_size, rows * cell_size, false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		for model_index in models.size():
			var model_spec: Dictionary = models[model_index]
			var animation_spec: Dictionary = animations[model_index]
			var packed := load(String(model_spec.path)) as PackedScene
			if packed == null:
				_fail("could not load %s" % model_spec.path)
				return
			var model := packed.instantiate() as Node3D
			rig.stage.add_child(model)
			_recolor_model(model, Color(team.color))
			var player := _first_animation_player(model)
			if player == null:
				_fail("model has no AnimationPlayer: %s" % model_spec.path)
				return
			for state: String in STATE_ORDER:
				var clip_name := String(animation_spec.get(state, ""))
				if not player.has_animation(clip_name):
					_fail("%s is missing animation %s" % [model_spec.path, clip_name])
					return
				var animation := player.get_animation(clip_name)
				var frame_count: int = STATE_COUNTS[state]
				for direction_index in directions:
					model.rotation.y = deg_to_rad(float(direction_index) * 360.0 / float(directions))
					for frame_index in frame_count:
						var normalized_time := float(frame_index) / float(frame_count if state in ["idle", "walk"] else maxi(1, frame_count - 1))
						if state in ["attack", "death"]:
							normalized_time *= 0.94
						player.play(clip_name)
						player.seek(animation.length * normalized_time, true)
						player.pause()
						await process_frame
						RenderingServer.force_draw(false)
						var frame: Image = rig.viewport.get_texture().get_image()
						if frame == null or frame.is_empty():
							_fail("viewport capture returned an empty image")
							return
						frame.convert(Image.FORMAT_RGBA8)
						frame.resize(cell_size, cell_size, Image.INTERPOLATE_LANCZOS)
						var linear_index: int = model_index * directions * 16 + direction_index * 16 + int(STATE_OFFSETS[state]) + frame_index
						var destination := Vector2i((linear_index % columns) * cell_size, (linear_index / columns) * cell_size)
						atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), destination)
			model.queue_free()
			await process_frame
		_tint_team_regions(atlas, Color(team.color), cell_size, columns, directions)
		var atlas_path := output_dir.path_join("infantry_%s.png" % String(team.name))
		var save_error := atlas.save_png(atlas_path)
		if save_error != OK:
			_fail("could not save %s: %s" % [atlas_path, error_string(save_error)])
			return
		print("BAKED %s %dx%d" % [atlas_path, atlas.get_width(), atlas.get_height()])

	var metadata := {
		"schema": 1,
		"generator": "tools/sprite_baker/bake_sprites.gd",
		"models": models,
		"animations": animations,
		"directions": directions,
		"direction_degrees": _direction_degrees(directions),
		"state_order": STATE_ORDER,
		"state_counts": STATE_COUNTS,
		"state_offsets": STATE_OFFSETS,
		"frames_per_direction": 16,
		"cell_size": [cell_size, cell_size],
		"columns": columns,
		"rows": rows,
		"atlas_size": [columns * cell_size, rows * cell_size],
		"camera_pitch_degrees": float(_options.pitch),
		"camera_orthographic_size": float(_options.camera_size),
		"transparent_background": true,
		"teams": _serializable_teams(),
	}
	var metadata_path := output_dir.path_join("infantry_atlas.json")
	var metadata_file := FileAccess.open(metadata_path, FileAccess.WRITE)
	if metadata_file == null:
		_fail("could not write metadata: %s" % metadata_path)
		return
	metadata_file.store_string(JSON.stringify(metadata, "\t") + "\n")
	metadata_file.close()
	print("SPRITE BAKE PASS: %d models x %d directions x 16 frames, %dx%d cells" % [models.size(), directions, columns, rows])
	quit(0)


func _create_capture_rig() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "SpriteBakeViewport"
	viewport.size = Vector2i(int(_options.raw), int(_options.raw))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var stage := Node3D.new()
	stage.name = "Stage"
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(_options.camera_size)
	var pitch := deg_to_rad(float(_options.pitch))
	var distance := 6.0
	var camera_position := Vector3(distance * cos(pitch), distance * sin(pitch), distance * cos(pitch))
	camera.look_at_from_position(camera_position, Vector3(0.0, float(_options.target_height), 0.0), Vector3.UP)
	camera.current = true
	stage.add_child(camera)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key_light.light_energy = 1.55
	key_light.shadow_enabled = false
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
	return {"viewport": viewport, "stage": stage}


func _recolor_model(node: Node, _team_color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source := mesh_instance.get_active_material(surface_index)
				if source is BaseMaterial3D:
					var material := source.duplicate() as BaseMaterial3D
					material.roughness = 0.78
					mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_recolor_model(child, _team_color)


func _tint_team_regions(atlas: Image, team_color: Color, cell_size: int, columns: int, directions: int) -> void:
	var frames_per_model := directions * 16
	for y in atlas.get_height():
		for x in atlas.get_width():
			var pixel := atlas.get_pixel(x, y)
			if pixel.a <= 0.05 or pixel.s < 0.58:
				continue
			var cell_index := (y / cell_size) * columns + x / cell_size
			var model_index := cell_index / frames_per_model
			var is_team_pixel := pixel.h <= 0.16 or pixel.h >= 0.92 if model_index == 0 else pixel.h >= 0.25 and pixel.h <= 0.58
			if not is_team_pixel:
				continue
			var saturation := clampf(maxf(pixel.s * 0.82, team_color.s * 0.76), 0.0, 1.0)
			atlas.set_pixel(x, y, Color.from_hsv(team_color.h, saturation, pixel.v, pixel.a))


func _first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var player := _first_animation_player(child)
		if player != null:
			return player
	return null


func _parse_arguments(arguments: PackedStringArray) -> bool:
	for argument in arguments:
		if argument == "--help":
			print("usage: godot --path . -s tools/sprite_baker/bake_sprites.gd -- [--models=name:path,name:path] [--animations=idle,walk,attack,death;...] [--teams=name:rrggbb,name:rrggbb] [--output=res://assets/units] [--directions=8] [--pitch=30] [--cell=96]")
			return false
		if not argument.begins_with("--") or argument.find("=") < 0:
			push_error("invalid argument: %s" % argument)
			return false
		var separator := argument.find("=")
		var key := argument.substr(2, separator - 2)
		var value := argument.substr(separator + 1)
		match key:
			"models":
				var models: Array = []
				for entry in value.split(",", false):
					var parts := entry.split(":", true, 1)
					if parts.size() != 2:
						push_error("model entries must be name:path")
						return false
					models.append({"name": parts[0], "path": parts[1]})
				_options.models = models
			"animations":
				var sets: Array = []
				for entry in value.split(";", false):
					var clips := entry.split(",", false)
					if clips.size() != 4:
						push_error("each animation set must contain idle,walk,attack,death")
						return false
					sets.append({"idle": clips[0], "walk": clips[1], "attack": clips[2], "death": clips[3]})
				_options.animations = sets
			"teams":
				var teams: Array = []
				for entry in value.split(",", false):
					var parts := entry.split(":", false, 1)
					if parts.size() != 2:
						push_error("team entries must be name:rrggbb")
						return false
					var team_color := Color.from_string(parts[1], Color.TRANSPARENT)
					if team_color.a <= 0.0:
						push_error("team colors must be opaque HTML colors")
						return false
					teams.append({"name": parts[0], "color": team_color})
				if teams.is_empty():
					push_error("at least one team color is required")
					return false
				_options.teams = teams
			"output": _options.output = value
			"directions": _options.directions = value.to_int()
			"pitch": _options.pitch = value.to_float()
			"cell": _options.cell = value.to_int()
			"raw": _options.raw = value.to_int()
			"camera-size": _options.camera_size = value.to_float()
			"target-height": _options.target_height = value.to_float()
			_:
				push_error("unknown option: --%s" % key)
				return false
	return true


func _direction_degrees(count: int) -> Array[int]:
	var values: Array[int] = []
	for index in count:
		values.append(roundi(float(index) * 360.0 / float(count)))
	return values


func _serializable_teams() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for team: Dictionary in _options.teams:
		values.append({"name": String(team.name), "color": Color(team.color).to_html(false)})
	return values


func _fail(message: String) -> void:
	push_error("SPRITE BAKE FAILED: %s" % message)
	quit(1)
