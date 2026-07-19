extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_values()
	_test_expanded_grid_and_obstacles()
	_test_grid_projection_and_dynamic_building()
	_test_simulation_contract()
	_test_initial_territory()
	_test_build_and_economy()
	_test_ranged_data_and_combat()
	_test_air_targeting_and_hq_defense()
	_test_enemy_ai_kind_funding()
	_test_combat_and_kill_reward()
	_test_cross_column_engagement()
	_test_nearest_hostile_selection()
	_test_ally_separation()
	_test_lunge_state_contract()
	_test_frontline_ownership()
	_test_hq_fallback_and_obstacle_sliding()
	_test_terminal_results()
	_test_balance_paths()
	_test_bucket_search_scale()
	return failures


func _test_grid_projection_and_dynamic_building() -> void:
	var grid_script := load("res://scripts/grid.gd")
	var simulation = _new_simulation()
	if grid_script == null or simulation == null:
		return
	var grid = grid_script.new()
	grid.set_simulation(simulation)
	for cell in [Vector2i(0, 0), Vector2i(11, 22), Vector2i(21, 43), Vector2i(3, 35)]:
		_expect(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "isometric picking round trips %s" % cell)
	_expect(grid.can_build(Vector2i(3, 35), simulation.TEAM_ALLY), "dynamic blue territory is buildable")
	_expect(not grid.can_build(Vector2i(3, 3), simulation.TEAM_ALLY), "dynamic red territory rejects blue build")
	_expect(not grid.can_build(Vector2i(11, 43), simulation.TEAM_ALLY), "blue HQ tile rejects building")
	simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(3.5, 36.5))
	simulation.recalculate_territory()
	_expect(not grid.can_build(Vector2i(3, 35), simulation.TEAM_ALLY), "frontline capture immediately revokes blue build permission")
	grid.free()


func _test_config_values() -> void:
	var config := load("res://scripts/game_config.gd")
	_expect(config != null and config.can_instantiate(), "game config parses")
	if config == null or not config.can_instantiate():
		return
	_expect(config.GRID_COLUMNS == 22 and config.GRID_ROWS == 44, "expanded grid has four times the tiles")
	_expect(config.SIM_TICK_RATE == 30, "simulation runs at fixed 30 Hz")
	_expect(is_equal_approx(config.MATCH_DURATION, 180.0), "match lasts at most 180 seconds")
	_expect(config.SPAWNER_COST == 60, "spawner cost is 60 gold")
	_expect(config.START_GOLD == 180, "blue starts with 180 gold")
	_expect(config.KILL_REWARD == 6, "unit kill reward is 6 gold")
	_expect(is_equal_approx(config.OCCUPANCY_WIN_RATIO, 0.9), "90 percent territory ends the match")
	var constants: Dictionary = config.get_script_constant_map()
	_expect(constants.has("UNIT_DETECT_RANGE"), "config exposes hostile detection range")
	_expect(constants.has("UNIT_SEPARATION_RADIUS"), "config exposes ally separation radius")
	_expect(constants.has("UNIT_SEEK_WEIGHT"), "config exposes seek steering weight")
	_expect(constants.has("UNIT_LUNGE_DURATION"), "config exposes attack lunge duration")
	_expect(constants.get("RANGED_SPAWNER_COST", -1) == 80, "ranged spawner costs 80 gold")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_MAX_HP", -1.0)), 32.0), "ranged unit has 32 HP")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_SPEED", -1.0)), 1.25), "ranged unit speed is 1.25")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_ATTACK_RANGE", -1.0)), 2.40), "ranged unit attack range is 2.40")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_ATTACK_DAMAGE", -1.0)), 1.20), "ranged unit damage is 1.20")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_ATTACK_INTERVAL", -1.0)), 0.90), "ranged unit attack interval is 0.90 seconds")


func _test_expanded_grid_and_obstacles() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var cell_count: int = simulation.config.GRID_COLUMNS * simulation.config.GRID_ROWS
	_expect(simulation.get_ownership().size() == cell_count, "expanded ownership has one entry per tile")
	_expect(simulation.has_method("get_blocked_cells"), "simulation exposes packed blocked terrain")
	_expect(simulation.has_method("is_blocked"), "simulation exposes blocked-cell lookup")
	if not simulation.has_method("get_blocked_cells") or not simulation.has_method("is_blocked"):
		return
	var blocked: PackedByteArray = simulation.get_blocked_cells()
	_expect(blocked.size() == cell_count, "blocked terrain has one entry per tile")
	_expect(blocked.count(1) == simulation.config.OBSTACLE_PAIR_COUNT * 2, "central terrain has sixteen mirrored obstacle pairs")
	var comparison = _new_simulation()
	_expect(comparison != null and comparison.get_blocked_cells() == blocked, "obstacle generation is deterministic")
	var row_counts := PackedInt32Array()
	row_counts.resize(simulation.config.GRID_ROWS)
	for row in simulation.config.GRID_ROWS:
		for column in simulation.config.GRID_COLUMNS:
			var cell := Vector2i(column, row)
			if not simulation.is_blocked(cell):
				continue
			row_counts[row] += 1
			_expect(row >= simulation.config.OBSTACLE_MIN_ROW and row <= simulation.config.OBSTACLE_MAX_ROW, "obstacles stay in the central terrain band")
			var mirrored := Vector2i(simulation.config.GRID_COLUMNS - 1 - column, simulation.config.GRID_ROWS - 1 - row)
			_expect(simulation.is_blocked(mirrored), "every obstacle has a center-mirrored partner")
	for count in row_counts:
		_expect(count <= simulation.config.OBSTACLE_MAX_PER_ROW, "no terrain row exceeds the blocker cap")
	for cell in [
		Vector2i(simulation.config.GRID_COLUMNS / 2, 0),
		Vector2i(simulation.config.GRID_COLUMNS / 2, simulation.config.GRID_ROWS - 1),
		Vector2i(4, simulation.config.GRID_ROWS - 8),
	]:
		_expect(not simulation.is_blocked(cell), "reserved deployment cells stay clear")
	var blocked_index := blocked.find(1)
	if blocked_index >= 0:
		var blocked_cell := Vector2i(blocked_index % simulation.config.GRID_COLUMNS, blocked_index / simulation.config.GRID_COLUMNS)
		var owner: int = simulation.get_ownership()[blocked_index]
		var gold_before: int = simulation.ally_gold if owner == simulation.TEAM_ALLY else simulation.enemy_gold
		_expect(not simulation.try_build_spawner(owner, blocked_cell), "blocked terrain rejects simulation builds")
		var gold_after: int = simulation.ally_gold if owner == simulation.TEAM_ALLY else simulation.enemy_gold
		_expect(gold_after == gold_before, "blocked build rejection never spends gold")
		var grid_script := load("res://scripts/grid.gd")
		var grid = grid_script.new()
		grid.set_simulation(simulation)
		_expect(not grid.can_build(blocked_cell, owner), "blocked terrain rejects grid builds")
		grid.free()
	for row in range(simulation.config.OBSTACLE_MIN_ROW, simulation.config.OBSTACLE_MAX_ROW + 1):
		for column in simulation.config.GRID_COLUMNS:
			var blocker := Vector2i(column, row)
			var approach := Vector2i(column, row + 1)
			if not simulation.is_blocked(blocker) or simulation.is_blocked(approach):
				continue
			simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(column) + 0.5, float(row) + 1.01))
			var unit_index: int = simulation.unit_ids.size() - 1
			simulation.unit_positions[unit_index] = Vector2(float(column) + 0.5, float(row) + 1.01)
			simulation.tick(1.0 / float(simulation.config.SIM_TICK_RATE))
			_expect(unit_index < simulation.unit_positions.size(), "blocker approach keeps its test unit alive")
			if unit_index >= simulation.unit_positions.size():
				return
			var final_cell := Vector2i(floori(simulation.unit_positions[unit_index].x), floori(simulation.unit_positions[unit_index].y))
			_expect(not simulation.is_blocked(final_cell), "movement never leaves a unit inside blocked terrain")
			return
	_expect(false, "deterministic terrain includes a blocker with an open approach")


func _new_simulation():
	var script := load("res://scripts/battle_simulation.gd")
	_expect(script != null, "battle simulation script exists")
	_expect(script != null and script.can_instantiate(), "battle simulation parses")
	if script == null or not script.can_instantiate():
		return null
	var simulation = script.new()
	simulation.reset()
	return simulation


func _test_simulation_contract() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	_expect(simulation is RefCounted and not simulation is Node, "simulation is data-only and not a Node")
	_expect(typeof(simulation.unit_ids) == TYPE_PACKED_INT32_ARRAY, "unit IDs use PackedInt32Array")
	_expect(typeof(simulation.unit_teams) == TYPE_PACKED_INT32_ARRAY, "unit teams use PackedInt32Array")
	_expect(typeof(simulation.unit_positions) == TYPE_PACKED_VECTOR2_ARRAY, "unit positions use PackedVector2Array")
	_expect(typeof(simulation.unit_hp) == TYPE_PACKED_FLOAT32_ARRAY, "unit HP uses PackedFloat32Array")
	var property_names := _property_names(simulation)
	_expect(property_names.has("unit_speed_scales"), "unit speed variation uses one packed array")
	_expect(property_names.has("unit_lunge_timers"), "unit lunge timers use one packed array")
	_expect(property_names.has("unit_lunge_directions"), "unit lunge directions use one packed array")
	var unit_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(4.5, 36.5))
	_expect(unit_id > 0 and simulation.unit_ids.size() == 1, "spawn inserts one packed unit")
	_expect(absf(simulation.unit_positions[0].x - 4.5) <= 0.3001 and is_equal_approx(simulation.unit_positions[0].y, 36.5), "spawn applies only bounded lateral variation")
	if property_names.has("unit_speed_scales"):
		_expect(simulation.unit_speed_scales.size() == 1, "speed variation stays index-aligned")
		_expect(simulation.unit_speed_scales[0] >= 0.9 and simulation.unit_speed_scales[0] <= 1.1, "speed variation stays within ten percent")
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_positions[0].y < 36.5, "blue unit advances toward red HQ")
	var building_id: int = simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_SPAWNER, Vector2i(1, 36))
	_expect(building_id > 0, "public building insertion API returns an ID")
	var fixed_simulation = _new_simulation()
	fixed_simulation.spawn_unit(fixed_simulation.TEAM_ALLY, Vector2(4.5, 36.5))
	fixed_simulation.tick(1.0 / 60.0)
	_expect(is_equal_approx(fixed_simulation.unit_positions[0].y, 36.5), "sub-tick delta accumulates without partial simulation")
	fixed_simulation.tick(1.0 / 60.0)
	_expect(fixed_simulation.unit_positions[0].y < 36.5, "two half ticks produce exactly one fixed simulation step")
	var catch_up_simulation = _new_simulation()
	catch_up_simulation.spawn_unit(catch_up_simulation.TEAM_ALLY, Vector2(4.5, 36.5))
	var catch_up_start: Vector2 = catch_up_simulation.unit_positions[0]
	catch_up_simulation.tick(1.0)
	var maximum_catch_up_distance: float = catch_up_simulation.config.UNIT_SPEED * catch_up_simulation.unit_speed_scales[0] * 8.0 / 30.0
	_expect(catch_up_simulation.unit_positions[0].distance_to(catch_up_start) <= maximum_catch_up_distance + 0.001, "long frame performs at most eight inertial catch-up ticks")
	_expect(is_equal_approx(catch_up_simulation.time_remaining, 180.0 - 8.0 / 30.0), "clock discards the same excess time as combat")


func _test_initial_territory() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var ownership: PackedByteArray = simulation.get_ownership()
	var columns: int = simulation.config.GRID_COLUMNS
	var rows: int = simulation.config.GRID_ROWS
	_expect(ownership.size() == columns * rows, "ownership has one entry per tile")
	if ownership.size() != columns * rows:
		return
	_expect(ownership[0] == simulation.TEAM_ENEMY, "top tile starts red")
	_expect(ownership[(rows / 2 - 1) * columns + columns / 2] == simulation.TEAM_ENEMY, "upper half ends red")
	_expect(ownership[(rows / 2) * columns + columns / 2] == simulation.TEAM_ALLY, "lower half starts blue")
	_expect(ownership[(rows - 1) * columns + columns - 1] == simulation.TEAM_ALLY, "bottom tile starts blue")
	_expect(is_equal_approx(simulation.get_occupancy(simulation.TEAM_ALLY), 0.5), "initial blue occupancy is 50 percent")


func _test_build_and_economy() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	_expect(simulation.try_build_spawner(simulation.TEAM_ALLY, Vector2i(5, 36)), "blue builds on blue territory")
	_expect(simulation.ally_gold == 120, "building spends exactly 60 blue gold")
	var gold_after_build: int = simulation.ally_gold
	_expect(not simulation.try_build_spawner(simulation.TEAM_ALLY, Vector2i(5, 36)), "occupied tile rejects another building")
	_expect(not simulation.try_build_spawner(simulation.TEAM_ALLY, Vector2i(5, 3)), "blue cannot build on red territory")
	_expect(not simulation.try_build_spawner(simulation.TEAM_ENEMY, Vector2i(5, 36)), "red cannot build on blue territory")
	_expect(simulation.ally_gold == gold_after_build, "invalid build attempts never spend blue gold")
	var before_income: int = simulation.ally_gold
	for tick_index in 30:
		simulation.tick(1.0 / 30.0)
	_expect(simulation.ally_gold == before_income + 3, "one second grants exact passive income")


func _test_ranged_data_and_combat() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var constants: Dictionary = simulation.get_script().get_script_constant_map()
	var properties := _property_names(simulation)
	_expect(constants.get("UNIT_MELEE", -1) == 0, "simulation exposes melee kind zero")
	_expect(constants.get("UNIT_RANGED", -1) == 1, "simulation exposes ranged kind one")
	_expect(properties.has("unit_kinds"), "unit kinds use an aligned packed array")
	_expect(_method_argument_count(simulation, "spawn_unit") == 3, "spawn accepts a unit kind")
	_expect(_method_argument_count(simulation, "try_build_spawner") == 3, "build accepts a unit kind")
	if constants.get("UNIT_MELEE", -1) != 0 or constants.get("UNIT_RANGED", -1) != 1 or not properties.has("unit_kinds"):
		return

	_expect(typeof(simulation.unit_kinds) == TYPE_PACKED_INT32_ARRAY, "unit kinds use PackedInt32Array")
	for building in simulation.buildings:
		_expect(building.has("unit_kind"), "every building record carries a unit kind")

	var ranged_cell := Vector2i(6, 36)
	_expect(simulation.try_build_spawner(simulation.TEAM_ALLY, ranged_cell, simulation.UNIT_RANGED), "ranged spawner builds")
	_expect(simulation.ally_gold == simulation.config.START_GOLD - simulation.config.RANGED_SPAWNER_COST, "ranged cost is charged")
	var spawner_index: int = simulation.buildings.size() - 1
	_expect(int(simulation.buildings[spawner_index].unit_kind) == simulation.UNIT_RANGED, "spawner stores selected kind")
	var spawner: Dictionary = simulation.buildings[spawner_index]
	spawner.spawn_timer = 0.0
	simulation.buildings[spawner_index] = spawner
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_ids.size() == 1, "ready spawner produces one unit")
	_expect(simulation.unit_kinds[0] == simulation.UNIT_RANGED, "spawner produces selected kind")
	_expect(is_equal_approx(simulation.unit_hp[0], simulation.config.RANGED_UNIT_MAX_HP), "spawn applies ranged max HP")

	var swap_simulation = _new_simulation()
	swap_simulation.spawn_unit(swap_simulation.TEAM_ENEMY, Vector2(5.5, 10.2), swap_simulation.UNIT_MELEE)
	swap_simulation.spawn_unit(swap_simulation.TEAM_ALLY, Vector2(5.5, 10.7), swap_simulation.UNIT_MELEE)
	var survivor_id: int = swap_simulation.spawn_unit(swap_simulation.TEAM_ALLY, Vector2(5.5, 36.0), swap_simulation.UNIT_RANGED)
	swap_simulation.unit_positions[0] = Vector2(5.5, 10.2)
	swap_simulation.unit_positions[1] = Vector2(5.5, 10.7)
	swap_simulation.unit_positions[2] = Vector2(5.5, 36.0)
	swap_simulation.unit_hp[1] = 1.0
	swap_simulation.tick(1.0 / 30.0)
	_expect(swap_simulation.unit_ids.size() == 2, "lethal hit swap-removes one packed unit")
	_expect(swap_simulation.unit_kinds.size() == swap_simulation.unit_ids.size(), "unit kinds stay size-aligned after removal")
	_expect(swap_simulation.unit_ids[1] == survivor_id and swap_simulation.unit_kinds[1] == swap_simulation.UNIT_RANGED, "swap-removal preserves the moved unit kind")

	var melee_simulation = _new_simulation()
	melee_simulation.spawn_unit(melee_simulation.TEAM_ALLY, Vector2(5.5, 12.0), melee_simulation.UNIT_MELEE)
	melee_simulation.spawn_unit(melee_simulation.TEAM_ENEMY, Vector2(5.5, 10.0), melee_simulation.UNIT_MELEE)
	melee_simulation.unit_positions[0] = Vector2(5.5, 12.0)
	melee_simulation.unit_positions[1] = Vector2(5.5, 10.0)
	melee_simulation.tick(1.0 / 30.0)
	_expect(not _has_event(melee_simulation.drain_events(), "hit"), "melee cannot hit at distance 2.0")

	var ranged_simulation = _new_simulation()
	ranged_simulation.spawn_unit(ranged_simulation.TEAM_ALLY, Vector2(5.5, 12.0), ranged_simulation.UNIT_RANGED)
	ranged_simulation.spawn_unit(ranged_simulation.TEAM_ENEMY, Vector2(5.5, 10.0), ranged_simulation.UNIT_MELEE)
	ranged_simulation.unit_positions[0] = Vector2(5.5, 12.0)
	ranged_simulation.unit_positions[1] = Vector2(5.5, 10.0)
	ranged_simulation.tick(1.0 / 30.0)
	var ranged_events: Array = ranged_simulation.drain_events()
	var shot: Dictionary = _event_of_type(ranged_events, "ranged_shot")
	_expect(_has_event(ranged_events, "hit"), "ranged unit keeps shared hit feedback")
	_expect(not shot.is_empty(), "ranged unit emits a ranged shot at distance 2.0")
	_expect(shot.get("team", 0) == ranged_simulation.TEAM_ALLY, "ranged shot records the attacker team")
	_expect(shot.get("origin", Vector2.ZERO) == Vector2(5.5, 12.0), "ranged shot records its origin")
	_expect(shot.get("position", Vector2.ZERO) == Vector2(5.5, 10.0), "ranged shot records its target position")
	_expect(is_equal_approx(ranged_simulation.unit_hp[1], ranged_simulation.config.UNIT_MAX_HP - ranged_simulation.config.RANGED_UNIT_ATTACK_DAMAGE), "ranged hit applies ranged damage")
	_expect(is_equal_approx(ranged_simulation.unit_cooldowns[0], ranged_simulation.config.RANGED_UNIT_ATTACK_INTERVAL), "ranged hit applies ranged interval")


func _test_air_targeting_and_hq_defense() -> void:
	var config := load("res://scripts/game_config.gd")
	_expect(config.HQ_ATTACK_DAMAGE == config.DEFENSE_TOWER_DAMAGE * 3.0, "HQ attack is exactly three defense towers")
	_expect(config.HQ_ATTACK_RANGE == config.DEFENSE_TOWER_RANGE, "HQ and tower use the same defense range")
	_expect(config.HQ_ATTACK_INTERVAL == config.DEFENSE_TOWER_ATTACK_INTERVAL, "HQ and tower use the same fire interval")

	var melee_simulation = _new_simulation()
	if melee_simulation == null:
		return
	var melee_id: int = melee_simulation.spawn_unit(melee_simulation.TEAM_ALLY, Vector2(8.5, 22.5), melee_simulation.UNIT_MELEE)
	var dragon_id: int = melee_simulation.spawn_unit(melee_simulation.TEAM_ENEMY, Vector2(8.5, 22.9), melee_simulation.UNIT_DRAGON)
	melee_simulation.unit_positions[melee_simulation.unit_ids.find(melee_id)] = Vector2(8.5, 22.5)
	melee_simulation.unit_positions[melee_simulation.unit_ids.find(dragon_id)] = Vector2(8.5, 22.9)
	melee_simulation.unit_target_ids[melee_simulation.unit_ids.find(melee_id)] = dragon_id
	var dragon_hp_before: float = melee_simulation.unit_hp[melee_simulation.unit_ids.find(dragon_id)]
	melee_simulation.tick(1.0 / float(config.SIM_TICK_RATE))
	var melee_index: int = melee_simulation.unit_ids.find(melee_id)
	var dragon_index: int = melee_simulation.unit_ids.find(dragon_id)
	_expect(melee_index >= 0 and melee_simulation.unit_target_ids[melee_index] != dragon_id, "melee infantry drops even a retained flying dragon target")
	_expect(dragon_index >= 0 and is_equal_approx(melee_simulation.unit_hp[dragon_index], dragon_hp_before), "melee infantry cannot damage a flying dragon")

	var ranged_simulation = _new_simulation()
	var ranged_id: int = ranged_simulation.spawn_unit(ranged_simulation.TEAM_ALLY, Vector2(8.5, 22.5), ranged_simulation.UNIT_RANGED)
	var ranged_dragon_id: int = ranged_simulation.spawn_unit(ranged_simulation.TEAM_ENEMY, Vector2(8.5, 22.9), ranged_simulation.UNIT_DRAGON)
	ranged_simulation.unit_positions[ranged_simulation.unit_ids.find(ranged_id)] = Vector2(8.5, 22.5)
	ranged_simulation.unit_positions[ranged_simulation.unit_ids.find(ranged_dragon_id)] = Vector2(8.5, 22.9)
	var ranged_dragon_hp: float = ranged_simulation.unit_hp[ranged_simulation.unit_ids.find(ranged_dragon_id)]
	ranged_simulation.tick(1.0 / float(config.SIM_TICK_RATE))
	var ranged_dragon_index: int = ranged_simulation.unit_ids.find(ranged_dragon_id)
	_expect(ranged_dragon_index >= 0 and ranged_simulation.unit_hp[ranged_dragon_index] < ranged_dragon_hp, "ranged infantry can attack a flying dragon")

	var hq_simulation = _new_simulation()
	var attacker_id: int = hq_simulation.spawn_unit(hq_simulation.TEAM_ALLY, Vector2(11.5, 2.5), hq_simulation.UNIT_DRAGON)
	var attacker_index: int = hq_simulation.unit_ids.find(attacker_id)
	hq_simulation.unit_positions[attacker_index] = Vector2(11.5, 2.5)
	var hp_before: float = hq_simulation.unit_hp[attacker_index]
	hq_simulation.tick(1.0 / float(config.SIM_TICK_RATE))
	attacker_index = hq_simulation.unit_ids.find(attacker_id)
	_expect(attacker_index >= 0 and is_equal_approx(hq_simulation.unit_hp[attacker_index], hp_before - config.HQ_ATTACK_DAMAGE), "HQ fires one triple-strength tower shot at air targets")
	var saw_hq_shot := false
	for event in hq_simulation.drain_events():
		if String(event.get("type", "")) == "hq_shot":
			saw_hq_shot = true
	_expect(saw_hq_shot, "HQ attack emits a distinct tracer event")


func _test_enemy_ai_kind_funding() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var constants: Dictionary = simulation.get_script().get_script_constant_map()
	if constants.get("UNIT_MELEE", -1) != 0 or constants.get("UNIT_RANGED", -1) != 1 or not _property_names(simulation).has("unit_kinds"):
		_expect(false, "enemy kind funding fixture requires ranged interfaces")
		return
	for row in simulation.config.GRID_ROWS:
		simulation.ownership[row * simulation.config.GRID_COLUMNS] = simulation.TEAM_ALLY
	simulation._enemy_build_timer = 0.0
	simulation.tick(1.0 / 30.0)
	var enemy_spawners := _spawners_for_team(simulation, simulation.TEAM_ENEMY)
	_expect(enemy_spawners.size() == 1 and Vector2i(enemy_spawners[0].cell).x == 1, "enemy AI skips a starting cursor column without owned placement cells")
	_expect(enemy_spawners.size() == 1 and int(enemy_spawners[0].unit_kind) == simulation.UNIT_MELEE, "enemy AI first successful build is melee")
	_expect(simulation.enemy_gold == simulation.config.ENEMY_START_GOLD - simulation.config.SPAWNER_COST, "enemy melee build charges melee cost")

	simulation.enemy_gold = simulation.config.RANGED_SPAWNER_COST - 1
	simulation._enemy_build_timer = 0.0
	simulation.tick(1.0 / 30.0)
	_expect(_spawners_for_team(simulation, simulation.TEAM_ENEMY).size() == 1, "enemy AI waits when alternating ranged kind is unaffordable")
	_expect(simulation.enemy_gold == simulation.config.RANGED_SPAWNER_COST - 1, "failed enemy ranged build spends no gold")

	simulation.enemy_gold = simulation.config.RANGED_SPAWNER_COST
	simulation._enemy_build_timer = 0.0
	simulation.tick(1.0 / 30.0)
	enemy_spawners = _spawners_for_team(simulation, simulation.TEAM_ENEMY)
	_expect(enemy_spawners.size() == 2 and int(enemy_spawners[1].unit_kind) == simulation.UNIT_RANGED, "enemy AI alternates successful builds independently from skipped placement columns")
	_expect(simulation.enemy_gold == 0, "enemy ranged build charges ranged cost")


func _test_combat_and_kill_reward() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var red_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(5.5, 10.2))
	var blue_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.5, 10.7))
	simulation.unit_positions[0] = Vector2(5.5, 10.2)
	simulation.unit_positions[1] = Vector2(5.5, 10.7)
	_expect(red_id != blue_id, "units receive unique IDs")
	simulation.unit_hp[1] = 1.0
	var red_gold_before: int = simulation.enemy_gold
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_ids.size() == 1, "lethal melee hit swap-removes dead unit")
	_expect(simulation.enemy_gold == red_gold_before + 6, "killer team receives exact unit reward")
	var events: Array = simulation.drain_events()
	_expect(_has_event(events, "hit"), "combat queues a hit event")
	_expect(_has_event(events, "unit_death"), "combat queues a unit death event")


func _test_cross_column_engagement() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(4.35, 10.0))
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.65, 10.1))
	simulation.unit_positions[0] = Vector2(4.35, 10.0)
	simulation.unit_positions[1] = Vector2(5.65, 10.1)
	var hit_seen := false
	for tick_index in 120:
		simulation.tick(1.0 / 30.0)
		if _has_event(simulation.drain_events(), "hit"):
			hit_seen = true
			break
	_expect(hit_seen, "units spawned in different columns pursue and strike each other")
	_expect(simulation.unit_positions[0].x > 4.35 or simulation.unit_positions[1].x < 5.65, "hostile seek changes logical x")


func _test_nearest_hostile_selection() -> void:
	var retarget_simulation = _new_simulation()
	if retarget_simulation == null:
		return
	retarget_simulation.spawn_unit(retarget_simulation.TEAM_ALLY, Vector2(5.5, 12.0))
	var far_enemy_id: int = retarget_simulation.spawn_unit(retarget_simulation.TEAM_ENEMY, Vector2(4.0, 10.6))
	retarget_simulation.unit_positions[0] = Vector2(5.5, 12.0)
	retarget_simulation.unit_positions[1] = Vector2(4.0, 10.6)
	retarget_simulation.tick(1.0 / 30.0)
	_expect(retarget_simulation.unit_target_ids[0] == far_enemy_id, "unit initially acquires the only detected hostile")
	var near_enemy_id: int = retarget_simulation.spawn_unit(retarget_simulation.TEAM_ENEMY, Vector2(5.8, 11.8))
	retarget_simulation.unit_positions[2] = Vector2(5.8, 11.8)
	retarget_simulation.tick(1.0 / 30.0)
	_expect(retarget_simulation.unit_target_ids[0] == near_enemy_id, "unit switches to a newly detected nearer hostile")

	var building_simulation = _new_simulation()
	building_simulation.spawn_unit(building_simulation.TEAM_ALLY, Vector2(5.5, 11.4))
	building_simulation.spawn_unit(building_simulation.TEAM_ENEMY, Vector2(7.0, 11.4))
	building_simulation.unit_positions[0] = Vector2(5.5, 11.4)
	building_simulation.unit_positions[1] = Vector2(7.0, 11.4)
	var near_building_id: int = building_simulation.add_building(
		building_simulation.TEAM_ENEMY,
		building_simulation.BUILDING_SPAWNER,
		Vector2i(5, 10)
	)
	building_simulation.tick(1.0 / 30.0)
	_expect(building_simulation.unit_target_ids[0] == -near_building_id, "nearest hostile building wins over a farther hostile unit")


func _test_ally_separation() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.5, 32.0))
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.5, 32.0))
	simulation.unit_positions[0] = Vector2(5.5, 32.0)
	simulation.unit_positions[1] = Vector2(5.5, 32.0)
	for tick_index in 30:
		simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_positions[0].distance_to(simulation.unit_positions[1]) >= 0.20, "overlapping allies separate into individually readable positions")


func _test_lunge_state_contract() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var property_names := _property_names(simulation)
	if not property_names.has("unit_lunge_timers") or not property_names.has("unit_lunge_directions"):
		_expect(false, "lunge packed arrays exist before attack contract can run")
		return
	simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(5.2, 10.2))
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.7, 10.5))
	simulation.unit_positions[0] = Vector2(5.2, 10.2)
	simulation.unit_positions[1] = Vector2(5.7, 10.5)
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_states[0] == 1, "in-range unit stops in attack state")
	_expect(simulation.unit_lunge_timers[0] > 0.0, "successful attack starts batched lunge timer")
	_expect(simulation.unit_lunge_directions[0].x > 0.0, "lunge direction faces the attacked target")


func _test_frontline_ownership() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(4.5, 10.5))
	simulation.unit_positions[0] = Vector2(4.5, 10.5)
	simulation.recalculate_territory()
	var ownership: PackedByteArray = simulation.get_ownership()
	var claimed_index: int = 10 * simulation.config.GRID_COLUMNS + 4
	_expect(ownership[claimed_index] == simulation.TEAM_ALLY, "forward blue unit claims its supply line")
	simulation.unit_positions[0] = Vector2(5.5, 10.5)
	simulation.recalculate_territory()
	ownership = simulation.get_ownership()
	_expect(ownership[claimed_index] == simulation.TEAM_ALLY, "captured supply line persists after its unit changes columns")
	simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(4.5, 10.5))
	simulation.unit_positions[1] = Vector2(4.5, 10.5)
	simulation.recalculate_territory()
	ownership = simulation.get_ownership()
	_expect(ownership[claimed_index] == simulation.TEAM_ENEMY, "enemy advance recaptures a persistent supply cell")


func _test_hq_fallback_and_obstacle_sliding() -> void:
	var edge_simulation = _new_simulation()
	if edge_simulation == null:
		return
	edge_simulation.spawn_unit(edge_simulation.TEAM_ALLY, Vector2(0.5, 0.5))
	edge_simulation.unit_positions[0] = Vector2(0.5, 0.5)
	edge_simulation.tick(1.0 / 30.0)
	_expect(edge_simulation.unit_target_ids[0] == -edge_simulation.enemy_hq_id, "edge breakthrough targets the opposing HQ")
	_expect(edge_simulation.unit_positions[0].x > 0.5, "edge breakthrough steers laterally toward the opposing HQ")

	var slide_simulation = _new_simulation()
	var fixture_found := false
	for row in range(slide_simulation.config.OBSTACLE_MIN_ROW, slide_simulation.config.OBSTACLE_MAX_ROW + 1):
		for column in range(0, slide_simulation.config.GRID_COLUMNS - 2):
			var blocker := Vector2i(column, row)
			var approach := Vector2i(column, row + 1)
			var hostile_cell := Vector2i(column + 2, row - 1)
			if (
				not slide_simulation.is_blocked(blocker)
				or slide_simulation.is_blocked(approach)
				or slide_simulation.is_blocked(hostile_cell)
			):
				continue
			slide_simulation.spawn_unit(slide_simulation.TEAM_ALLY, Vector2(float(column) + 0.5, float(row) + 1.01))
			slide_simulation.spawn_unit(slide_simulation.TEAM_ENEMY, Vector2(float(column) + 2.0, float(row) - 0.5))
			slide_simulation.unit_positions[0] = Vector2(float(column) + 0.5, float(row) + 1.01)
			slide_simulation.unit_positions[1] = Vector2(float(column) + 2.0, float(row) - 0.5)
			fixture_found = true
			break
		if fixture_found:
			break
	_expect(fixture_found, "deterministic terrain includes a safe slide fixture")
	if not fixture_found or slide_simulation.unit_positions.size() < 2:
		return
	var before_x: float = slide_simulation.unit_positions[0].x
	slide_simulation.tick(1.0 / float(slide_simulation.config.SIM_TICK_RATE))
	_expect(not slide_simulation.unit_positions.is_empty(), "obstacle slide keeps its test unit alive")
	if slide_simulation.unit_positions.is_empty():
		return
	var final_position: Vector2 = slide_simulation.unit_positions[0]
	var final_cell := Vector2i(floori(final_position.x), floori(final_position.y))
	_expect(not slide_simulation.is_blocked(final_cell), "obstacle slide keeps the final logical cell clear")
	_expect(final_position.x > before_x, "blocked diagonal movement slides along an open axis")


func _test_terminal_results() -> void:
	var hq_sim = _new_simulation()
	if hq_sim == null:
		return
	hq_sim.apply_building_damage(hq_sim.enemy_hq_id, hq_sim.config.HQ_MAX_HP, hq_sim.TEAM_ALLY)
	_expect(hq_sim.result == "VICTORY", "destroying red HQ wins immediately")

	var territory_sim = _new_simulation()
	for column in territory_sim.config.GRID_COLUMNS:
		territory_sim.spawn_unit(territory_sim.TEAM_ALLY, Vector2(float(column) + 0.5, 1.2))
	territory_sim.tick(1.0 / 30.0)
	_expect(territory_sim.get_occupancy(territory_sim.TEAM_ALLY) >= 0.9, "blue formation can reach 90 percent territory")
	_expect(territory_sim.result == "VICTORY", "90 percent blue territory wins immediately")

	var timeout_sim = _new_simulation()
	for column in timeout_sim.config.GRID_COLUMNS:
		timeout_sim.spawn_unit(timeout_sim.TEAM_ENEMY, Vector2(float(column) + 0.5, 35.5))
	timeout_sim.time_remaining = 0.01
	timeout_sim.tick(1.0 / 30.0)
	_expect(timeout_sim.result == "DEFEAT", "timeout awards the match to the territory leader")


func _test_balance_paths() -> void:
	var passive_simulation = _new_simulation()
	var passive_elapsed := _run_complete_match(passive_simulation)
	_expect(passive_simulation.result == "DEFEAT", "building no blue spawner lets red AI win")
	var active_simulation = _new_simulation()
	var build_row: int = active_simulation.config.GRID_ROWS - 8
	for column in [7, 11, 15]:
		_expect(active_simulation.try_build_spawner(active_simulation.TEAM_ALLY, Vector2i(column, build_row), active_simulation.UNIT_MELEE), "reinforced route opens with three melee spawners")
	var active_elapsed := _run_complete_match(active_simulation, [
		{"cell": Vector2i(18, active_simulation.config.GRID_ROWS - 3), "build_kind": active_simulation.BUILD_RANGED_SPAWNER},
		{"cell": Vector2i(4, active_simulation.config.GRID_ROWS - 3), "build_kind": active_simulation.BUILD_DRAGON_LAIR},
	])
	_expect(active_simulation.result == "VICTORY", "reinforced ground spawners plus a dragon lair can push through and win")
	_expect(passive_elapsed >= 120.0 and passive_elapsed <= 180.1, "unopposed red advance remains a two-to-three minute match (%.1fs)" % passive_elapsed)
	_expect(active_elapsed >= 120.0 and active_elapsed <= 180.1, "reinforced blue victory remains a two-to-three minute match (%.1fs)" % active_elapsed)
	print("BALANCE PATHS: no_spawner=%.1fs %s blue_share=%.2f blue_hq=%.0f mixed_spawners=%.1fs %s blue_share=%.2f red_hq=%.0f dragons=%d" % [
		passive_elapsed,
		passive_simulation.result,
		passive_simulation.get_occupancy(passive_simulation.TEAM_ALLY),
		_building_hp(passive_simulation, passive_simulation.ally_hq_id),
		active_elapsed,
		active_simulation.result,
		active_simulation.get_occupancy(active_simulation.TEAM_ALLY),
		_building_hp(active_simulation, active_simulation.enemy_hq_id),
		active_simulation.unit_kinds.count(active_simulation.UNIT_DRAGON),
	])


func _run_complete_match(simulation, delayed_builds: Array = []) -> float:
	var fixed_delta := 1.0 / float(simulation.config.SIM_TICK_RATE)
	var next_build := 0
	for step in int(181.0 / fixed_delta):
		if simulation.result != "":
			return simulation.config.MATCH_DURATION - simulation.time_remaining
		simulation.tick(fixed_delta)
		if next_build < delayed_builds.size():
			var build: Dictionary = delayed_builds[next_build]
			var build_kind: int = int(build.get("build_kind", simulation.BUILD_RANGED_SPAWNER if int(build.get("unit_kind", simulation.UNIT_MELEE)) == simulation.UNIT_RANGED else simulation.BUILD_MELEE_SPAWNER))
			var cost: int = simulation._build_cost(build_kind)
			if simulation.ally_gold >= cost and simulation.try_build(simulation.TEAM_ALLY, Vector2i(build.cell), build_kind):
				next_build += 1
	return simulation.config.MATCH_DURATION - simulation.time_remaining


func _building_hp(simulation, building_id: int) -> float:
	for building in simulation.buildings:
		if int(building.id) == building_id:
			return float(building.hp)
	return 0.0


func _test_bucket_search_scale() -> void:
	var acquire_simulation = _new_simulation()
	acquire_simulation.spawn_unit(acquire_simulation.TEAM_ENEMY, Vector2(5.1, 10.1))
	acquire_simulation.spawn_unit(acquire_simulation.TEAM_ALLY, Vector2(5.5, 10.5))
	acquire_simulation.tick(1.0 / 30.0)
	_expect(acquire_simulation.unit_target_ids[0] > 0, "adjacent bucket search acquires an enemy target")
	var simulation = _new_simulation()
	if simulation == null:
		return
	for index in 180:
		simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(float(index % simulation.config.GRID_COLUMNS) + 0.5, 4.0 + float(index % 3) * 0.1))
		simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(index % simulation.config.GRID_COLUMNS) + 0.5, 40.0 - float(index % 3) * 0.1))
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_ids.size() == 360, "stress fixture keeps 360 data-only units")
	_expect(simulation.target_candidate_checks < 50000, "bucket target checks stay far below all-pairs work")


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if String(event.get("type", "")) == event_type:
			return true
	return false


func _event_of_type(events: Array, event_type: String) -> Dictionary:
	for event in events:
		if String(event.get("type", "")) == event_type:
			return event
	return {}


func _spawners_for_team(simulation, team: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building in simulation.buildings:
		if int(building.team) == team and int(building.kind) == simulation.BUILDING_SPAWNER and not bool(building.destroyed):
			result.append(building)
	return result


func _method_argument_count(value: Object, method_name: String) -> int:
	for method in value.get_method_list():
		if String(method.name) == method_name:
			return method.args.size()
	return -1


func _property_names(value: Object) -> Array[String]:
	var names: Array[String] = []
	for property in value.get_property_list():
		names.append(String(property.name))
	return names


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
