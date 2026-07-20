extends SceneTree

const VIEW_SIZE := Vector2i(540, 960)
const OUTPUTS := [
	"res://build/smoke_opening.png",
	"res://build/smoke_advantage.png",
	"res://build/smoke_disadvantage.png",
	"res://build/smoke_cluster.png",
	"res://build/smoke_persistent_flank.png",
	"res://build/smoke_flow_split.png",
	"res://build/smoke_infantry_closeup.png",
	"res://build/smoke_visual_hierarchy.png",
	"res://build/smoke_elevation_overview.png",
	"res://build/smoke_high_ground_combat.png",
	"res://build/smoke_large_army.png",
	"res://build/smoke_siege_impact.png",
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
	print("SMOKE CAPTURE PASS: opening / advantage / disadvantage / cluster / persistent flank / flow split / infantry closeup / visual hierarchy / elevation overview / high-ground combat / 200-unit army / SIEGE impact (540x960)")
	quit(0)


func _stage_scenario(main: Node, scenario: int) -> bool:
	var simulation = main.simulation
	if scenario == 0:
		var ally_spawner := Vector2i(6, GameConfig.GRID_ROWS - 8)
		var enemy_spawner := Vector2i(GameConfig.GRID_COLUMNS - 7, 7)
		simulation.try_build_spawner(simulation.TEAM_ALLY, ally_spawner, simulation.UNIT_MELEE)
		simulation.add_building(simulation.TEAM_ENEMY, simulation.BUILDING_SPAWNER, enemy_spawner, simulation.UNIT_RANGED)
		simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_DEFENSE_TOWER, Vector2i(GameConfig.GRID_COLUMNS / 2 - 2, GameConfig.GRID_ROWS - 3))
		simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_DRAGON_LAIR, Vector2i(GameConfig.GRID_COLUMNS / 2 + 4, GameConfig.GRID_ROWS - 7), simulation.UNIT_DRAGON)
		_spawn_if_clear(simulation, simulation.TEAM_ALLY, Vector2i(GameConfig.GRID_COLUMNS / 2 + 4, GameConfig.GRID_ROWS - 9), simulation.UNIT_DRAGON)
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
	elif scenario == 4:
		return _stage_persistent_flank(main)
	elif scenario == 5:
		return _stage_flow_split(main)
	elif scenario == 6:
		return _stage_infantry_closeup(main)
	elif scenario == 7:
		return _stage_visual_hierarchy(main)
	elif scenario == 8:
		return _stage_elevation_overview(main)
	elif scenario == 9:
		return _stage_high_ground_combat(main)
	elif scenario == 10:
		return _stage_large_army(main)
	else:
		return _stage_siege_impact(main)
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


func _stage_flow_split(main: Node) -> bool:
	var simulation = main.simulation
	var wall_row: int = GameConfig.GRID_ROWS / 2
	simulation.elevation.fill(0)
	for column in GameConfig.GRID_COLUMNS:
		simulation.elevation[wall_row * GameConfig.GRID_COLUMNS + column] = 0 if column in [5, 16] else 2
	for rank in 5:
		for column in range(2, 20, 2):
			_spawn_if_clear(simulation, simulation.TEAM_ALLY, Vector2i(column, wall_row + 3 + rank), simulation.UNIT_MELEE)
	for rank in 4:
		_spawn_if_clear(simulation, simulation.TEAM_ALLY, Vector2i(5, wall_row + 1 + rank), simulation.UNIT_MELEE)
	for column in range(3, 20, 3):
		_spawn_if_clear(simulation, simulation.TEAM_ENEMY, Vector2i(column, wall_row - 4), simulation.UNIT_RANGED)
	simulation.rebuild_flow_fields()
	for tick_index in 90:
		simulation.tick(1.0 / float(GameConfig.SIM_TICK_RATE))
	main.hud.show_message("FLOW SPLIT // CONGESTION REROUTE", GameConfig.COLOR_TEAL)
	main.fx.show_territory_change(Vector2i(16, wall_row), simulation.TEAM_ALLY)
	_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, wall_row), 2.25)
	return simulation.ally_flow.cost_at(Vector2i(11, wall_row + 4)) < INF


func _stage_infantry_closeup(main: Node) -> bool:
	var simulation = main.simulation
	var center := Vector2(float(GameConfig.GRID_COLUMNS) * 0.5, float(GameConfig.GRID_ROWS) * 0.5)
	var directions := [Vector2.UP, Vector2(1, -1).normalized(), Vector2.RIGHT, Vector2(1, 1).normalized(), Vector2.DOWN, Vector2(-1, 1).normalized(), Vector2.LEFT, Vector2(-1, -1).normalized()]
	for index in directions.size():
		var team: int = simulation.TEAM_ALLY if index < 4 else simulation.TEAM_ENEMY
		var kind: int = simulation.UNIT_MELEE if index % 2 == 0 else simulation.UNIT_RANGED
		var position := center + Vector2(float(index % 4) - 1.5, float(index / 4) * 1.35 - 0.7)
		var unit_id: int = simulation.spawn_unit(team, position, kind)
		var unit_index: int = simulation.unit_ids.find(unit_id)
		simulation.unit_positions[unit_index] = position
		simulation.unit_velocities[unit_index] = directions[index] * simulation.config.UNIT_SPEED
		simulation.unit_states[unit_index] = simulation.STATE_ADVANCE
	var attacker_index := 1
	simulation.unit_states[attacker_index] = simulation.STATE_ATTACK
	simulation.unit_lunge_directions[attacker_index] = Vector2(1, -1).normalized()
	simulation.unit_lunge_timers[attacker_index] = simulation.config.UNIT_LUNGE_DURATION * 0.55
	main.unit_renderer.queue_death(center + Vector2(2.2, 0.7), simulation.TEAM_ENEMY, simulation.UNIT_MELEE, Vector2.LEFT)
	main.hud.show_message("KAYKIT INFANTRY // 8 DIR + STATE", GameConfig.COLOR_TEAL)
	_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2), 5.2)
	return simulation.unit_ids.size() == 8


func _stage_visual_hierarchy(main: Node) -> bool:
	var simulation = main.simulation
	var middle_row := GameConfig.GRID_ROWS / 2
	var ally_spawner := _nearest_clear_cell(simulation, Vector2i(7, middle_row + 4))
	var enemy_spawner := _nearest_clear_cell(simulation, Vector2i(14, middle_row - 4))
	var ally_tower := _nearest_clear_cell(simulation, Vector2i(5, middle_row + 2), [ally_spawner])
	var enemy_lair := _nearest_clear_cell(simulation, Vector2i(16, middle_row - 2), [enemy_spawner])
	if ally_spawner.x < 0 or enemy_spawner.x < 0 or ally_tower.x < 0 or enemy_lair.x < 0:
		return false
	simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_SPAWNER, ally_spawner, simulation.UNIT_MELEE)
	simulation.add_building(simulation.TEAM_ENEMY, simulation.BUILDING_SPAWNER, enemy_spawner, simulation.UNIT_RANGED)
	simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_DEFENSE_TOWER, ally_tower)
	simulation.add_building(simulation.TEAM_ENEMY, simulation.BUILDING_DRAGON_LAIR, enemy_lair, simulation.UNIT_DRAGON)
	var damaged_ids: Array[int] = []
	for column in range(7, 15, 2):
		var ally_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(column) + 0.5, float(middle_row) + 1.7), simulation.UNIT_MELEE if column % 4 == 3 else simulation.UNIT_RANGED)
		var enemy_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(float(column) + 0.5, float(middle_row) - 1.2), simulation.UNIT_RANGED if column % 4 == 3 else simulation.UNIT_MELEE)
		if column in [9, 13]:
			damaged_ids.append(ally_id)
			damaged_ids.append(enemy_id)
	var dragon_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(12.5, float(middle_row) - 2.8), simulation.UNIT_DRAGON)
	main._sync_building_views()
	main.unit_renderer.sync()
	for unit_id in damaged_ids:
		var unit_index: int = simulation.unit_ids.find(unit_id)
		if unit_index >= 0:
			simulation.unit_hp[unit_index] *= 0.58
	main.unit_renderer.sync()
	main.hud.show_message("MUTED FIELD // SHADED ACTORS", GameConfig.COLOR_TEAL)
	main.fx.show_ranged_shot(Vector2(8.5, middle_row + 1.7), Vector2(10.5, middle_row - 1.2), simulation.TEAM_ALLY)
	_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, middle_row), 3.15)
	return dragon_id > 0 and not damaged_ids.is_empty() and main.unit_renderer.get_hp_bar_alpha(damaged_ids[0]) > 0.0


func _stage_elevation_overview(main: Node) -> bool:
	var simulation = main.simulation
	var heights: PackedByteArray = simulation.get_elevation()
	var summit_index: int = heights.find(2)
	if summit_index < 0:
		return false
	var summit := Vector2i(summit_index % GameConfig.GRID_COLUMNS, summit_index / GameConfig.GRID_COLUMNS)
	for column in range(2, GameConfig.GRID_COLUMNS - 2, 3):
		_spawn_if_clear(simulation, simulation.TEAM_ENEMY, Vector2i(column, GameConfig.GRID_ROWS / 2 - 5), simulation.UNIT_MELEE)
		_spawn_if_clear(simulation, simulation.TEAM_ALLY, Vector2i(column, GameConfig.GRID_ROWS / 2 + 5), simulation.UNIT_RANGED)
	main.grid.queue_redraw()
	main.hud.show_message("ELEVATION 0 / 1 / 2 // CLIFF ROUTES", GameConfig.COLOR_TEAL)
	_focus_map(main, summit, 2.65)
	return heights.count(1) > 0 and heights.count(2) > 0 and simulation.terrain_paths_valid()


func _stage_high_ground_combat(main: Node) -> bool:
	var simulation = main.simulation
	simulation.elevation.fill(0)
	var center := Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2)
	for row in range(center.y - 3, center.y + 2):
		for column in range(center.x - 3, center.x + 4):
			simulation.elevation[row * GameConfig.GRID_COLUMNS + column] = 1
	for row in range(center.y - 2, center.y):
		for column in range(center.x - 1, center.x + 2):
			simulation.elevation[row * GameConfig.GRID_COLUMNS + column] = 2
	var high_position := Vector2(center.x + 0.5, center.y - 1.5)
	var low_position := Vector2(center.x + 0.5, center.y + 1.5)
	var ranged_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, high_position, simulation.UNIT_RANGED)
	var enemy_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, low_position, simulation.UNIT_MELEE)
	var ranged_index: int = simulation.unit_ids.find(ranged_id)
	var enemy_index: int = simulation.unit_ids.find(enemy_id)
	simulation.unit_positions[ranged_index] = high_position
	simulation.unit_positions[enemy_index] = low_position
	simulation.unit_states[ranged_index] = simulation.STATE_ATTACK
	simulation.unit_lunge_directions[ranged_index] = high_position.direction_to(low_position)
	simulation.unit_lunge_timers[ranged_index] = GameConfig.UNIT_LUNGE_DURATION * 0.5
	simulation.unit_hp[enemy_index] *= 0.62
	main.grid.queue_redraw()
	main.unit_renderer.sync()
	main.fx.show_ranged_shot(high_position, low_position, simulation.TEAM_ALLY)
	main.fx.show_hit(low_position, true)
	main.hud.show_message("HIGH GROUND +25% // RANGED +0.5", GameConfig.COLOR_ORANGE)
	_focus_map(main, center, 4.8)
	return simulation.elevation_at_position(high_position) == 2 and simulation.elevation_at_position(low_position) == 1


func _stage_large_army(main: Node) -> bool:
	var simulation = main.simulation
	var middle := float(GameConfig.GRID_ROWS) * 0.5
	for index in 100:
		var column := index % GameConfig.GRID_COLUMNS
		var rank := index / GameConfig.GRID_COLUMNS
		var enemy_kind: int = [simulation.UNIT_MELEE, simulation.UNIT_RANGED, simulation.UNIT_SIEGE][index % 3]
		var ally_kind: int = [simulation.UNIT_RANGED, simulation.UNIT_MELEE, simulation.UNIT_SIEGE][index % 3]
		var enemy_position := Vector2(float(column) + 0.28 + float(index % 3) * 0.16, middle - 4.0 - float(rank) * 0.48)
		var ally_position := Vector2(float(column) + 0.72 - float(index % 3) * 0.16, middle + 4.0 + float(rank) * 0.48)
		var enemy_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, enemy_position, enemy_kind)
		var ally_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, ally_position, ally_kind)
		simulation.unit_positions[simulation.unit_ids.find(enemy_id)] = enemy_position
		simulation.unit_positions[simulation.unit_ids.find(ally_id)] = ally_position
	main.unit_renderer.sync()
	main.hud.show_message("100+ PER SIDE // ARMY SCALE", GameConfig.COLOR_TEAL)
	_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2), 1.72)
	return simulation.unit_ids.size() == 200 and simulation.unit_kinds.count(simulation.UNIT_SIEGE) >= 60


func _stage_siege_impact(main: Node) -> bool:
	var simulation = main.simulation
	var center := Vector2(float(GameConfig.GRID_COLUMNS) * 0.5, float(GameConfig.GRID_ROWS) * 0.5)
	for index in 3:
		var siege_position := center + Vector2(-1.2 + float(index) * 1.2, 3.0)
		var siege_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, siege_position, simulation.UNIT_SIEGE)
		simulation.unit_positions[simulation.unit_ids.find(siege_id)] = siege_position
	for index in 9:
		var victim_position := center + Vector2((float(index % 3) - 1.0) * 0.42, -0.45 + float(index / 3) * 0.38)
		var victim_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, victim_position, simulation.UNIT_MELEE)
		simulation.unit_positions[simulation.unit_ids.find(victim_id)] = victim_position
	main.unit_renderer.sync()
	main.fx.show_siege_projectile(center + Vector2(-1.2, 3.0), center, simulation.TEAM_ALLY, GameConfig.SIEGE_FLIGHT_SECONDS)
	main.fx.show_siege_impact(center + Vector2(1.3, 0.2), simulation.TEAM_ALLY, GameConfig.SIEGE_BLAST_RADIUS)
	main.hud.show_message("SIEGE // TELEGRAPH + ARC + BLAST", GameConfig.COLOR_ORANGE)
	_focus_map(main, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2), 3.4)
	return simulation.unit_kinds.count(simulation.UNIT_SIEGE) == 3 and main.fx.siege_impact_feedback_count == 1


func _nearest_clear_cell(simulation, desired: Vector2i, excluded: Array = []) -> Vector2i:
	for radius in 6:
		for y_offset in range(-radius, radius + 1):
			for x_offset in range(-radius, radius + 1):
				var cell := desired + Vector2i(x_offset, y_offset)
				if cell.x < 0 or cell.x >= GameConfig.GRID_COLUMNS or cell.y < 0 or cell.y >= GameConfig.GRID_ROWS:
					continue
				if not simulation.is_blocked(cell) and cell not in excluded:
					return cell
	return Vector2i(-1, -1)


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
