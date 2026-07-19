extends SceneTree

const VIEW_SIZE := Vector2i(540, 960)
const CAPTURE_PATH := "res://build/smoke_capture.png"
const MAX_ACTION_FRAMES := 240


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.borderless = true
	root.size = VIEW_SIZE
	root.content_scale_size = VIEW_SIZE
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main scene could not be loaded")
		return
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var placements := [Vector2i(3, 5), Vector2i(5, 5), Vector2i(7, 5)]
	for cell in placements:
		if not main.try_place_tower(cell):
			_fail("tower placement failed at %s" % cell)
			return
	main.wave_manager.spawn_interval = 0.03
	main.start_next_wave()
	if main.wave_manager.current_wave != 1 or not main.wave_manager.wave_active:
		_fail("wave one did not start")
		return

	var staged := false
	var action_visible := false
	for frame in MAX_ACTION_FRAMES:
		await physics_frame
		await process_frame
		if not staged and main.enemies.get_child_count() >= placements.size():
			_stage_enemies(main)
			staged = true
		if staged and _has_visible_action(main):
			action_visible = true
			break
	if not action_visible:
		_fail("no tower shot or projectile became visible after %d frames" % MAX_ACTION_FRAMES)
		return

	await process_frame
	RenderingServer.force_draw(false)
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		_fail("active rendering backend has no viewport texture")
		return
	var image := viewport_texture.get_image()
	if image == null:
		_fail("active rendering backend cannot read viewport pixels")
		return
	if image.is_empty() or image.get_size() != VIEW_SIZE:
		_fail("capture size was %s instead of %s" % [image.get_size(), VIEW_SIZE])
		return
	var output_directory := ProjectSettings.globalize_path("res://build")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create capture directory: %s" % error_string(directory_error))
		return
	var output_path := ProjectSettings.globalize_path(CAPTURE_PATH)
	var save_error := image.save_png(output_path)
	if save_error != OK:
		_fail("could not save capture: %s" % error_string(save_error))
		return
	print("SMOKE CAPTURE PASS: %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	main.queue_free()
	await process_frame
	quit(0)


func _stage_enemies(main: Node) -> void:
	var staged_rows := [3.65, 3.85, 4.05]
	for index in staged_rows.size():
		var enemy = main.enemies.get_child(index)
		enemy.grid_position = Vector2(float(index * 2 + 3) + 0.5, staged_rows[index])
		enemy.move_speed = 0.0


func _has_visible_action(main: Node) -> bool:
	if main.projectiles.get_child_count() == 0:
		return false
	for tower in main.towers.get_children():
		if tower.shot_feedback_count > 0:
			return true
	return false


func _fail(message: String) -> void:
	push_error("SMOKE CAPTURE FAILED: %s" % message)
	quit(1)
