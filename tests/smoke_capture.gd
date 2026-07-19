extends SceneTree

const VIEW_SIZE := Vector2i(540, 960)
const OUTPUTS := [
	"res://build/smoke_opening.png",
	"res://build/smoke_advantage.png",
	"res://build/smoke_disadvantage.png",
	"res://build/smoke_cluster.png",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.borderless = true
	root.size = VIEW_SIZE
	root.content_scale_size = VIEW_SIZE
	var output_directory := ProjectSettings.globalize_path("res://build")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create capture directory")
		return
	for scenario in OUTPUTS.size():
		var main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		_stage_scenario(main, scenario)
		main.step_simulation(0.0001)
		await process_frame
		await process_frame
		RenderingServer.force_draw(false)
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.get_size() != VIEW_SIZE:
			_fail("scenario %d did not render at 540x960" % scenario)
			return
		var save_error := image.save_png(ProjectSettings.globalize_path(OUTPUTS[scenario]))
		if save_error != OK:
			_fail("scenario %d could not save: %s" % [scenario, error_string(save_error)])
			return
		main.queue_free()
		await process_frame
	print("SMOKE CAPTURE PASS: opening / blue advantage / blue disadvantage / frontline cluster (540x960)")
	quit(0)


func _stage_scenario(main: Node, scenario: int) -> void:
	var simulation = main.simulation
	if scenario == 0:
		simulation.try_build_spawner(simulation.TEAM_ALLY, Vector2i(5, 18))
		simulation.add_building(simulation.TEAM_ENEMY, simulation.BUILDING_SPAWNER, Vector2i(5, 7))
		for column in range(1, 11, 2):
			simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(float(column) + 0.5, 8.5 + float(column % 3) * 0.25))
			simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(column) + 0.5, 13.5 - float(column % 3) * 0.25))
		main.fx.show_production(Vector2i(5, 18), simulation.TEAM_ALLY)
		main.fx.show_production(Vector2i(5, 7), simulation.TEAM_ENEMY)
	elif scenario == 1:
		for column in 11:
			simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(column) + 0.5, 4.2 + float(column % 2) * 0.25))
			if column % 2 == 0:
				simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(float(column) + 0.5, 2.0))
		simulation.recalculate_territory()
		main.fx.show_territory_change(Vector2i(5, 4), simulation.TEAM_ALLY)
	elif scenario == 2:
		for column in 11:
			simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(float(column) + 0.5, 17.4 - float(column % 2) * 0.25))
			if column % 2 == 0:
				simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(column) + 0.5, 19.5))
		simulation.recalculate_territory()
		main.fx.show_hq_hit(Vector2i(5, 21), simulation.TEAM_ALLY)
	else:
		_stage_frontline_cluster(main)


func _stage_frontline_cluster(main: Node) -> void:
	var simulation = main.simulation
	for rank in 4:
		for column in range(1, 10):
			var lane_shift := 0.42 if column % 2 == 0 else -0.42
			simulation.spawn_unit(
				simulation.TEAM_ENEMY,
				Vector2(float(column) + 0.5 + lane_shift, 9.2 + float(rank) * 0.28)
			)
			simulation.spawn_unit(
				simulation.TEAM_ALLY,
				Vector2(float(column) + 0.5 - lane_shift, 12.8 - float(rank) * 0.28)
			)
	for tick_index in 75:
		simulation.tick(1.0 / float(GameConfig.SIM_TICK_RATE))
	simulation.recalculate_territory()
	main.fx.show_hit(Vector2(5.5, 11.0))


func _fail(message: String) -> void:
	push_error("SMOKE CAPTURE FAILED: %s" % message)
	quit(1)
