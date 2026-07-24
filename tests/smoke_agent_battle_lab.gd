extends SceneTree

const LAB_SCENE := "res://scenes/agent_battle_lab.tscn"
const CAPTURE_SIZE := Vector2i(540, 960)
const MAX_CONTACT_TICKS := 3600
const CAPTURES := [
	{
		"path": "res://build/smoke_agent_case_1_gate.png",
		"scenario": 0,
		"mode": 1,
		"attacked": 18,
	},
	{
		"path": "res://build/smoke_agent_case_2_corner.png",
		"scenario": 1,
		"mode": 1,
		"attacked": 18,
	},
	{
		"path": "res://build/smoke_agent_case_3_routes.png",
		"scenario": 2,
		"mode": 1,
		"attacked": 18,
	},
	{
		"path": "res://build/smoke_agent_case_4_open.png",
		"scenario": 3,
		"mode": 1,
		"attacked": 18,
	},
	{
		"path": "res://build/smoke_baseline_case_1_gate.png",
		"scenario": 0,
		"mode": 0,
		"attacked": 6,
	},
]


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

	var absolute_build := ProjectSettings.globalize_path("res://build")
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_build)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create build directory: %s" % error_string(directory_error))
		return

	for capture: Dictionary in CAPTURES:
		var passed: bool = await _capture_case(lab, capture_viewport, capture)
		if not passed:
			return

	print("AGENT BATTLE LAB SMOKE PASSED: 5 deterministic 540x960 RGBA captures")
	quit(0)


func _capture_case(lab: Node, capture_viewport: SubViewport, capture: Dictionary) -> bool:
	var mode := int(capture.mode)
	var scenario := int(capture.scenario)
	var attacked_threshold := int(capture.attacked)
	var capture_path := String(capture.path)
	lab.call("set_mode", mode)
	lab.call("set_scenario", scenario)

	var simulation := lab.get_node("AgentBattleSimulation")
	var found_contact := false
	for _tick in range(0, MAX_CONTACT_TICKS, 3):
		simulation.call("RunTicks", 3)
		var metrics: Dictionary = simulation.call("GetMetrics")
		if int(metrics.get("units_ever_attacked", 0)) < attacked_threshold:
			continue
		var snapshot: Dictionary = simulation.call("GetSnapshot")
		var pulses := PackedFloat32Array(snapshot.get("attack_pulses", PackedFloat32Array()))
		if _has_active_pulse(pulses):
			found_contact = true
			break

	if not found_contact:
		_fail(
			"case %d mode %d did not reach attacked=%d with a visible hit pulse by tick %d"
			% [scenario, mode, attacked_threshold, MAX_CONTACT_TICKS]
		)
		return false

	lab.call("sync_view")
	await process_frame
	await process_frame
	var image := capture_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("%s viewport capture is empty" % capture_path)
		return false
	if Vector2i(image.get_width(), image.get_height()) != CAPTURE_SIZE:
		_fail(
			"%s dimensions are %dx%d, expected 540x960"
			% [capture_path, image.get_width(), image.get_height()]
		)
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		_fail("%s is not RGBA8 (format=%d)" % [capture_path, image.get_format()])
		return false

	var absolute_path := ProjectSettings.globalize_path(capture_path)
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		_fail("could not save %s: %s" % [capture_path, error_string(save_error)])
		return false
	var bytes := FileAccess.get_file_as_bytes(absolute_path)
	if bytes.size() < 4096:
		_fail("%s is unexpectedly small: %d bytes" % [capture_path, bytes.size()])
		return false

	var metrics_text := String(lab.call("get_metrics_text"))
	if metrics_text.is_empty():
		_fail("%s live metric text is empty" % capture_path)
		return false
	print(
		"CAPTURED case=%d mode=%d attacked>=%d path=%s bytes=%d"
		% [scenario, mode, attacked_threshold, capture_path, bytes.size()]
	)
	return true


func _has_active_pulse(values: PackedFloat32Array) -> bool:
	for value in values:
		if value > 0.0:
			return true
	return false


func _fail(message: String) -> void:
	push_error("AGENT BATTLE LAB SMOKE FAILED: %s" % message)
	quit(1)
