extends SceneTree

const LAB_SCENE := "res://scenes/agent_battle_lab.tscn"
const CAPTURE_PATH := "res://build/smoke_agent_battle_lab.png"
const CAPTURE_SIZE := Vector2i(540, 960)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var capture_viewport := SubViewport.new()
	capture_viewport.size = CAPTURE_SIZE
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	var packed_scene := load(LAB_SCENE) as PackedScene
	if packed_scene == null:
		_fail("could not load the visual battle lab")
		return

	var lab := packed_scene.instantiate()
	capture_viewport.add_child(lab)
	await process_frame
	await process_frame
	lab.set_process(false)
	lab.call("set_mode", 1)

	var simulation := lab.get_node("AgentBattleSimulation")
	var found_contact := false
	for _batch in 300:
		simulation.call("RunTicks", 3)
		var metrics: Dictionary = simulation.call("GetMetrics")
		if int(metrics.get("units_ever_attacked", 0)) < 18:
			continue
		var snapshot: Dictionary = simulation.call("GetSnapshot")
		var pulses := PackedFloat32Array(snapshot.get("attack_pulses", PackedFloat32Array()))
		if _has_active_pulse(pulses):
			found_contact = true
			break

	if not found_contact:
		_fail("agent mode never reached a visible congested combat contact")
		return

	lab.call("sync_view")
	await process_frame
	await process_frame
	var image := capture_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport capture is empty")
		return
	if Vector2i(image.get_width(), image.get_height()) != CAPTURE_SIZE:
		_fail("capture dimensions are %dx%d, expected 540x960" % [image.get_width(), image.get_height()])
		return

	var absolute_build := ProjectSettings.globalize_path("res://build")
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_build)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create build directory: %s" % error_string(directory_error))
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))
	if save_error != OK:
		_fail("could not save smoke capture: %s" % error_string(save_error))
		return
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(CAPTURE_PATH))
	if bytes.size() < 4096:
		_fail("saved capture is unexpectedly small: %d bytes" % bytes.size())
		return

	var metrics_text := String(lab.call("get_metrics_text"))
	if metrics_text.is_empty():
		_fail("live metric text is empty")
		return
	print("AGENT BATTLE LAB SMOKE PASSED: %s (%d bytes)" % [CAPTURE_PATH, bytes.size()])
	print(metrics_text)
	quit(0)


func _has_active_pulse(values: PackedFloat32Array) -> bool:
	for value in values:
		if value > 0.0:
			return true
	return false


func _fail(message: String) -> void:
	push_error("AGENT BATTLE LAB SMOKE FAILED: %s" % message)
	quit(1)
