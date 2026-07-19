extends SceneTree

const VIEW_SIZE := Vector2i(540, 960)
const OUTPUTS := [
	"res://build/smoke_opening.png",
	"res://build/smoke_advantage.png",
	"res://build/smoke_disadvantage.png",
	"res://build/smoke_cluster.png",
	"res://build/smoke_persistent_flank.png",
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
		if not _stage_scenario(main, scenario):
			_fail("scenario %d did not preserve its required state" % scenario)
			return
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
	print("SMOKE CAPTURE PASS: opening / blue advantage / blue disadvantage / frontline cluster / persistent flank (540x960)")
	quit(0)


func _stage_scenario(main: Node, scenario: int) -> bool:
	var simulation = main.simulation
	if scenario == 0:
		var ally_spawner := Vector2i(6, GameConfig.GRID_ROWS - 8)
		var enemy_spawner := Vector2i(GameConfig.GRID_COLUMNS - 7, 7)
		simulation.try_build_spawner(simulation.TEAM_ALLY, ally_spawner, simulation.UNIT_MELEE)
		simulation.add_building(simulation.TEAM_ENEMY, simulation.BUILDING_SPAWNER, enemy_spawner, simulation.UNIT_RANGED)
		for column in range(1, GameConfig.GRID_COLUMNS, 4):
			_spawn_if_clear(simulation, simulation.TEAM_ENEMY, Vector2i(column, 11), simulation.UNIT_MELEE)
			_spawn_if_clear(simulation, simulation.TEAM_ALLY, Vector2i(column, GameConfig.GRID_ROWS - 12), simulation.UNIT_RANGED)
		main.fx.show_production(ally_spawner, simulation.TEAM_ALLY)
		main.fx.show_production(enemy_spawner, simulation.TEAM_ENEMY)
		_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2), GameConfig.MAP_ZOOM_MIN)
	elif scenario == 1:
		for column in GameConfig.GRID_COLUMNS:
			_spawn_if_clear(simulation, simulation.TEAM_ALLY, Vector2i(column, 8 + column % 2), simulation.UNIT_RANGED if column % 3 == 0 else simulation.UNIT_MELEE)
			if column % 2 == 0:
				_spawn_if_clear(simulation, simulation.TEAM_ENEMY, Vector2i(column, 5), simulation.UNIT_MELEE)
		simulation.recalculate_territory()
		main.fx.show_territory_change(Vector2i(GameConfig.GRID_COLUMNS / 2, 8), simulation.TEAM_ALLY)
		main.fx.show_ranged_shot(Vector2(8.5, 9.5), Vector2(8.5, 5.5), simulation.TEAM_ALLY)
		_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, 8), 1.85)
	elif scenario == 2:
		for column in GameConfig.GRID_COLUMNS:
			_spawn_if_clear(simulation, simulation.TEAM_ENEMY, Vector2i(column, GameConfig.GRID_ROWS - 9 - column % 2), simulation.UNIT_RANGED if column % 3 == 0 else simulation.UNIT_MELEE)
			if column % 2 == 0:
				_spawn_if_clear(simulation, simulation.TEAM_ALLY, Vector2i(column, GameConfig.GRID_ROWS - 6), simulation.UNIT_MELEE)
		simulation.recalculate_territory()
		main.fx.show_hq_hit(Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS - 1), simulation.TEAM_ALLY)
		_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS - 8), 1.85)
	elif scenario == 3:
		_stage_frontline_cluster(main)
	else:
		return _stage_persistent_flank(main)
	return true


func _stage_frontline_cluster(main: Node) -> void:
	var simulation = main.simulation
	for rank in 4:
		for column in range(3, GameConfig.GRID_COLUMNS - 3):
			var enemy_cell := Vector2i(column, GameConfig.GRID_ROWS / 2 - 3 - rank % 2)
			var ally_cell := Vector2i(column, GameConfig.GRID_ROWS / 2 + 2 + rank % 2)
			_spawn_if_clear(simulation, simulation.TEAM_ENEMY, enemy_cell, simulation.UNIT_RANGED if (column + rank) % 3 == 0 else simulation.UNIT_MELEE)
			_spawn_if_clear(simulation, simulation.TEAM_ALLY, ally_cell, simulation.UNIT_RANGED if (column + rank) % 3 == 1 else simulation.UNIT_MELEE)
	for tick_index in 45:
		simulation.tick(1.0 / float(GameConfig.SIM_TICK_RATE))
	simulation.recalculate_territory()
	main.fx.show_hit(Vector2(float(GameConfig.GRID_COLUMNS) * 0.5, float(GameConfig.GRID_ROWS) * 0.5))
	main.fx.show_ranged_shot(Vector2(8.5, 24.5), Vector2(8.5, 20.5), simulation.TEAM_ALLY)
	_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2), 2.15)


func _stage_persistent_flank(main: Node) -> bool:
	var simulation = main.simulation
	var held_cell := Vector2i(5, 10)
	var moved_cell := Vector2i(10, 10)
	var claimant_id: int = simulation.spawn_unit(
		simulation.TEAM_ALLY,
		Vector2(held_cell) + Vector2(0.5, 0.5),
		simulation.UNIT_RANGED
	)
	var claimant_index: int = simulation.unit_ids.find(claimant_id)
	if claimant_index < 0:
		return false
	simulation.unit_positions[claimant_index] = Vector2(held_cell) + Vector2(0.5, 0.5)
	simulation.recalculate_territory()
	var held_index: int = held_cell.y * GameConfig.GRID_COLUMNS + held_cell.x
	if simulation.get_ownership()[held_index] != simulation.TEAM_ALLY:
		return false
	simulation.unit_positions[claimant_index] = Vector2(moved_cell) + Vector2(0.5, 0.5)
	simulation.recalculate_territory()
	var ownership: PackedByteArray = simulation.get_ownership()
	var moved_index: int = moved_cell.y * GameConfig.GRID_COLUMNS + moved_cell.x
	if ownership[held_index] != simulation.TEAM_ALLY or ownership[moved_index] != simulation.TEAM_ALLY:
		return false
	main.fx.show_territory_change(held_cell, simulation.TEAM_ALLY)
	main.hud.show_message("PERSISTENT FLANK HELD", GameConfig.COLOR_TEAL)
	_focus_map(main, Vector2i(7, 15), 1.8)
	return true


func _spawn_if_clear(simulation, team: int, cell: Vector2i, unit_kind: int) -> void:
	if simulation.is_blocked(cell):
		return
	var unit_id: int = simulation.spawn_unit(team, Vector2(cell) + Vector2(0.5, 0.5), unit_kind)
	if unit_id > 0:
		simulation.unit_positions[simulation.unit_ids.size() - 1] = Vector2(cell) + Vector2(0.5, 0.5)


func _focus_map(main: Node, cell: Vector2i, zoom: float) -> void:
	var center: Vector2 = main.map_view.frame_rect.get_center()
	main.map_view.set_zoom_at(zoom, center)
	var target_screen: Vector2 = main.map_view.to_global(main.grid.cell_to_world(cell))
	main.map_view.pan_by(center - target_screen)


func _fail(message: String) -> void:
	push_error("SMOKE CAPTURE FAILED: %s" % message)
	quit(1)
