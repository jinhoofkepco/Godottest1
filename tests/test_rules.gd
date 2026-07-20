extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_values()
	_test_elevation_generation_and_reachability()
	_test_elevation_movement_and_combat()
	_test_expanded_grid_and_terrain()
	_test_grid_projection_and_dynamic_building()
	_test_simulation_contract()
	_test_profiling_contract()
	_test_initial_territory()
	_test_build_and_economy()
	_test_ranged_data_and_combat()
	_test_air_targeting_and_hq_defense()
	_test_enemy_ai_kind_funding()
	_test_combat_and_kill_reward()
	_test_cross_column_engagement()
	_test_nearest_hostile_selection()
	_test_unit_radius_contract()
	_test_siege_rules()
	_test_siege_balance_goals()
	_test_ally_separation()
	_test_lunge_state_contract()
	_test_frontline_ownership()
	_test_hq_fallback_and_obstacle_sliding()
	_test_terminal_results()
	_test_balance_paths()
	_test_bucket_search_scale()
	return failures


func _test_profiling_contract() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var properties := _property_names(simulation)
	for property_name in [
		"profile_target_usec",
		"profile_separation_usec",
		"profile_territory_usec",
		"profile_event_usec",
		"profile_tick_usec",
		"profile_tick_count",
	]:
		_expect(properties.has(property_name), "performance pass exposes %s" % property_name)
	_expect(simulation.has_method("reset_profile_counters"), "performance counters can be reset for repeatable stress samples")


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
	_expect(grid.has_method("get_frontline_segments"), "grid exposes ownership-boundary segments for a highlighted front line")
	if grid.has_method("get_frontline_segments"):
		var split_ownership := PackedByteArray()
		split_ownership.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
		for row in GameConfig.GRID_ROWS:
			for column in GameConfig.GRID_COLUMNS:
				split_ownership[row * GameConfig.GRID_COLUMNS + column] = simulation.TEAM_ENEMY if row < GameConfig.GRID_ROWS / 2 else simulation.TEAM_ALLY
		_expect(grid.get_frontline_segments(split_ownership).size() == GameConfig.GRID_COLUMNS, "straight initial front produces one highlighted edge per column")
	grid.free()


func _test_elevation_generation_and_reachability() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var properties := _property_names(simulation)
	_expect(properties.has("elevation"), "simulation exposes packed elevation terrain")
	if not properties.has("elevation"):
		return
	var heights: PackedByteArray = simulation.elevation
	var cell_count: int = simulation.config.GRID_COLUMNS * simulation.config.GRID_ROWS
	_expect(typeof(heights) == TYPE_PACKED_BYTE_ARRAY and heights.size() == cell_count, "elevation stores one packed byte per grid cell")
	_expect(heights.count(1) > 0 and heights.count(2) > 0, "terrain contains hills and summit cells")
	for index in heights.size():
		_expect(heights[index] <= 2, "terrain elevation remains within 0/1/2")
		var cell := Vector2i(index % simulation.config.GRID_COLUMNS, index / simulation.config.GRID_COLUMNS)
		var mirrored := Vector2i(simulation.config.GRID_COLUMNS - 1 - cell.x, simulation.config.GRID_ROWS - 1 - cell.y)
		_expect(heights[index] == heights[mirrored.y * simulation.config.GRID_COLUMNS + mirrored.x], "terrain is center-mirror symmetric at %s" % cell)
		if heights[index] == 2:
			var has_ramp_neighbor := false
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + offset
				if neighbor.x >= 0 and neighbor.x < simulation.config.GRID_COLUMNS and neighbor.y >= 0 and neighbor.y < simulation.config.GRID_ROWS and heights[neighbor.y * simulation.config.GRID_COLUMNS + neighbor.x] >= 1:
					has_ramp_neighbor = true
			_expect(has_ramp_neighbor, "every elevation-2 build cell has at least one traversable ramp")
	_expect(simulation.elevation_at_cell(Vector2i(simulation.config.GRID_COLUMNS / 2, 0)) == 0, "enemy HQ remains on clear level terrain")
	_expect(simulation.elevation_at_cell(Vector2i(simulation.config.GRID_COLUMNS / 2, simulation.config.GRID_ROWS - 1)) == 0, "ally HQ remains on clear level terrain")
	_expect(simulation.has_method("terrain_paths_valid") and simulation.terrain_paths_valid(), "all deployment candidates retain a traversable path to the opposing HQ")
	var comparison = _new_simulation()
	_expect(comparison != null and comparison.elevation == heights, "seeded elevation generation is deterministic")

	var grid_script := load("res://scripts/grid.gd")
	var grid = grid_script.new()
	grid.set_simulation(simulation)
	var sampled_levels := {}
	for index in heights.size():
		var level := int(heights[index])
		if sampled_levels.has(level):
			continue
		var cell := Vector2i(index % simulation.config.GRID_COLUMNS, index / simulation.config.GRID_COLUMNS)
		sampled_levels[level] = true
		_expect(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "elevated picking round trips level %d at %s" % [level, cell])
	_expect(sampled_levels.size() == 3, "picking fixture covers all three terrain levels")
	grid.free()


func _test_elevation_movement_and_combat() -> void:
	var simulation = _new_simulation()
	if simulation == null or not _property_names(simulation).has("elevation"):
		return
	simulation.elevation.fill(0)
	var low := Vector2i(8, 24)
	var slope := Vector2i(8, 23)
	var cliff := Vector2i(9, 24)
	simulation.elevation[slope.y * simulation.config.GRID_COLUMNS + slope.x] = 1
	simulation.elevation[cliff.y * simulation.config.GRID_COLUMNS + cliff.x] = 2
	_expect(simulation.can_ground_step(low, slope), "ground units can traverse a one-level slope")
	_expect(not simulation.can_ground_step(low, cliff), "ground units cannot traverse a two-level cliff")
	_expect(is_equal_approx(simulation.get_ground_speed_multiplier(Vector2(low) + Vector2(0.5, 0.5), Vector2(slope) + Vector2(0.5, 0.5)), simulation.config.UPHILL_SPEED_MULTIPLIER), "uphill motion applies the configured 0.7 speed multiplier")
	_expect(is_equal_approx(simulation.get_ground_speed_multiplier(Vector2(slope) + Vector2(0.5, 0.5), Vector2(low) + Vector2(0.5, 0.5)), 1.0), "downhill motion keeps full speed")
	_expect(simulation._move_without_entering_blocked(Vector2(low) + Vector2(0.5, 0.5), Vector2(0.0, -1.0)).floor() == Vector2(slope), "movement accepts a one-level destination")
	_expect(simulation._move_without_entering_blocked(Vector2(low) + Vector2(0.5, 0.5), Vector2(1.0, 0.0)).floor() == Vector2(low), "movement rejects a cliff destination")

	_expect(is_equal_approx(simulation.get_elevation_damage_multiplier(Vector2(low) + Vector2(0.5, 0.5), Vector2(cliff) + Vector2(0.5, 0.5)), simulation.config.LOW_GROUND_DAMAGE_MULTIPLIER), "low-to-high attacks deal 0.75 damage")
	_expect(is_equal_approx(simulation.get_elevation_damage_multiplier(Vector2(cliff) + Vector2(0.5, 0.5), Vector2(low) + Vector2(0.5, 0.5)), simulation.config.HIGH_GROUND_DAMAGE_MULTIPLIER), "high-to-low attacks deal 1.25 damage")
	_expect(is_equal_approx(simulation.get_elevation_damage_multiplier(Vector2(low) + Vector2(0.5, 0.5), Vector2(low) + Vector2(0.6, 0.5)), 1.0), "equal-elevation attacks keep base damage")
	var ranged_low: float = simulation.get_unit_attack_range(simulation.UNIT_RANGED, Vector2(low) + Vector2(0.5, 0.5))
	var ranged_high: float = simulation.get_unit_attack_range(simulation.UNIT_RANGED, Vector2(slope) + Vector2(0.5, 0.5))
	_expect(is_equal_approx(ranged_high, ranged_low + simulation.config.RANGED_HIGH_GROUND_RANGE_BONUS), "ranged infantry gains exactly 0.5 range on high ground")
	_expect(is_equal_approx(simulation.get_unit_attack_range(simulation.UNIT_MELEE, Vector2(slope) + Vector2(0.5, 0.5)), simulation.config.UNIT_ATTACK_RANGE), "melee range is unchanged on high ground")

	var high_attack = _new_simulation()
	high_attack.elevation.fill(0)
	high_attack.elevation[low.y * high_attack.config.GRID_COLUMNS + low.x] = 2
	var attacker_id: int = high_attack.spawn_unit(high_attack.TEAM_ALLY, Vector2(low) + Vector2(0.5, 0.5), high_attack.UNIT_MELEE)
	var target_cell := Vector2i(8, 25)
	var target_id: int = high_attack.spawn_unit(high_attack.TEAM_ENEMY, Vector2(target_cell) + Vector2(0.5, 0.5), high_attack.UNIT_MELEE)
	var attacker_index: int = high_attack.unit_ids.find(attacker_id)
	var target_index: int = high_attack.unit_ids.find(target_id)
	high_attack.unit_positions[attacker_index] = Vector2(low) + Vector2(0.5, 0.5)
	high_attack.unit_positions[target_index] = Vector2(target_cell) + Vector2(0.5, 0.5)
	var hp_before: float = high_attack.unit_hp[target_index]
	high_attack._attack_target(attacker_index, target_index, -1)
	_expect(is_equal_approx(hp_before - high_attack.unit_hp[target_index], high_attack.config.UNIT_ATTACK_DAMAGE * high_attack.config.HIGH_GROUND_DAMAGE_MULTIPLIER), "actual unit attack applies high-ground damage")
	var hit_event := _event_of_type(high_attack.drain_events(), "hit")
	_expect(bool(hit_event.get("high_ground", false)), "high-ground hit event carries enhanced spark metadata")


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
	_expect(constants.has("UNIT_SEPARATION_SPACING_MULTIPLIER"), "config exposes pair-radius separation multiplier")
	_expect(constants.has("UNIT_SEEK_WEIGHT"), "config exposes seek steering weight")
	_expect(constants.has("UNIT_LUNGE_DURATION"), "config exposes attack lunge duration")
	for terrain_constant in [
		"ELEVATION_LEVELS", "ELEVATION_PIXEL_STEP", "UPHILL_SPEED_MULTIPLIER", "UPHILL_COST",
		"HIGH_GROUND_DAMAGE_MULTIPLIER", "LOW_GROUND_DAMAGE_MULTIPLIER", "RANGED_HIGH_GROUND_RANGE_BONUS",
	]:
		_expect(constants.has(terrain_constant), "config exposes %s" % terrain_constant)
	for stat_contract in [
		["UNIT_MAX_HP", 48.0], ["UNIT_ATTACK_DAMAGE", 10.0], ["UNIT_ATTACK_INTERVAL", 0.65], ["UNIT_ATTACK_RANGE", 0.72], ["UNIT_SPEED", 1.45],
		["RANGED_UNIT_MAX_HP", 34.0], ["RANGED_UNIT_ATTACK_DAMAGE", 8.0], ["RANGED_UNIT_ATTACK_INTERVAL", 0.80], ["RANGED_UNIT_ATTACK_RANGE", 2.2], ["RANGED_UNIT_SPEED", 1.25],
		["SIEGE_UNIT_MAX_HP", 40.0], ["SIEGE_UNIT_ATTACK_DAMAGE", 31.0], ["SIEGE_UNIT_ATTACK_INTERVAL", 3.2], ["SIEGE_UNIT_ATTACK_RANGE", 3.5], ["SIEGE_UNIT_MIN_RANGE", 1.2], ["SIEGE_UNIT_SPEED", 0.8],
		["DRAGON_UNIT_MAX_HP", 260.0], ["DRAGON_UNIT_ATTACK_DAMAGE", 18.0], ["DRAGON_UNIT_ATTACK_INTERVAL", 0.90], ["DRAGON_UNIT_ATTACK_RANGE", 0.9], ["DRAGON_UNIT_SPEED", 1.70],
	]:
		_expect(is_equal_approx(float(constants.get(stat_contract[0], -1.0)), float(stat_contract[1])), "%s matches the locked balance table" % stat_contract[0])
	_expect(constants.get("RANGED_SPAWNER_COST", -1) == 80, "ranged spawner costs 80 gold")
	_expect(constants.get("SIEGE_SPAWNER_COST", -1) == 140, "siege spawner costs 140 gold")
	_expect(is_equal_approx(float(constants.get("SPAWNER_PRODUCTION_INTERVAL", -1.0)), 1.6), "ground spawners produce every 1.6 seconds")
	for radius_contract in [
		["MELEE_UNIT_RADIUS", 0.14],
		["RANGED_UNIT_RADIUS", 0.13],
		["SIEGE_UNIT_RADIUS", 0.26],
		["DRAGON_UNIT_RADIUS", 0.38],
	]:
		_expect(is_equal_approx(float(constants.get(radius_contract[0], -1.0)), float(radius_contract[1])), "%s matches the locked unit-radius table" % radius_contract[0])
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_MAX_HP", -1.0)), 34.0), "ranged unit has 34 HP")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_SPEED", -1.0)), 1.25), "ranged unit speed is 1.25")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_ATTACK_RANGE", -1.0)), 2.2), "ranged unit attack range is 2.2")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_ATTACK_DAMAGE", -1.0)), 8.0), "ranged unit damage is 8")
	_expect(is_equal_approx(float(constants.get("RANGED_UNIT_ATTACK_INTERVAL", -1.0)), 0.80), "ranged unit attack interval is 0.80 seconds")
	_expect(constants.has("COLOR_TERRITORY_ALLY") and constants.has("COLOR_TERRITORY_ENEMY"), "config separates muted territory colors from vivid actor colors")
	if constants.has("COLOR_TERRITORY_ALLY") and constants.has("COLOR_TERRITORY_ENEMY"):
		var ally_ground := Color(constants.COLOR_TERRITORY_ALLY)
		var enemy_ground := Color(constants.COLOR_TERRITORY_ENEMY)
		_expect(ally_ground.s < Color(constants.COLOR_ALLY).s * 0.75 and ally_ground.get_luminance() < Color(constants.COLOR_ALLY).get_luminance() * 0.75, "blue territory is substantially more muted than blue actors")
		_expect(enemy_ground.s < Color(constants.COLOR_ENEMY).s * 0.75 and enemy_ground.get_luminance() < Color(constants.COLOR_ENEMY).get_luminance() * 0.75, "red territory is substantially more muted than red actors")


func _test_expanded_grid_and_terrain() -> void:
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
	_expect(blocked.count(1) == 0, "legacy prop blockers are removed in favor of elevation cliffs")
	var comparison = _new_simulation()
	_expect(comparison != null and comparison.get_blocked_cells() == blocked, "empty legacy blocker compatibility is deterministic")
	for cell in [
		Vector2i(simulation.config.GRID_COLUMNS / 2, 0),
		Vector2i(simulation.config.GRID_COLUMNS / 2, simulation.config.GRID_ROWS - 1),
		Vector2i(4, simulation.config.GRID_ROWS - 8),
	]:
		_expect(not simulation.is_blocked(cell), "reserved deployment cells stay clear")
	var high_build_cell := Vector2i(-1, -1)
	for index in simulation.elevation.size():
		if simulation.elevation[index] == 2 and simulation.get_ownership()[index] == simulation.TEAM_ALLY:
			high_build_cell = Vector2i(index % simulation.config.GRID_COLUMNS, index / simulation.config.GRID_COLUMNS)
			break
	_expect(high_build_cell.x >= 0, "terrain provides an allied summit build fixture")
	if high_build_cell.x >= 0:
		simulation.ally_gold = 999
		_expect(simulation.try_build_spawner(simulation.TEAM_ALLY, high_build_cell), "building is allowed on owned elevation-2 terrain")


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
	_expect(property_names.has("unit_siege_target_positions") and typeof(simulation.unit_siege_target_positions) == TYPE_PACKED_VECTOR2_ARRAY, "SIEGE target points use one packed aligned array")
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
	swap_simulation.unit_hp[1] = 0.5
	swap_simulation.tick(1.0 / 30.0)
	_expect(swap_simulation.unit_ids.size() == 2, "lethal hit swap-removes one packed unit")
	_expect(swap_simulation.unit_kinds.size() == swap_simulation.unit_ids.size(), "unit kinds stay size-aligned after removal")
	_expect(swap_simulation.unit_siege_target_positions.size() == swap_simulation.unit_ids.size(), "SIEGE target points stay size-aligned after swap-removal")
	_expect(swap_simulation.unit_ids[1] == survivor_id and swap_simulation.unit_kinds[1] == swap_simulation.UNIT_RANGED, "swap-removal preserves the moved unit kind")

	var melee_simulation = _new_simulation()
	melee_simulation.spawn_unit(melee_simulation.TEAM_ALLY, Vector2(5.5, 12.0), melee_simulation.UNIT_MELEE)
	melee_simulation.spawn_unit(melee_simulation.TEAM_ENEMY, Vector2(5.5, 10.0), melee_simulation.UNIT_MELEE)
	melee_simulation.unit_positions[0] = Vector2(5.5, 12.0)
	melee_simulation.unit_positions[1] = Vector2(5.5, 10.0)
	melee_simulation.tick(1.0 / 30.0)
	_expect(not _has_event(melee_simulation.drain_events(), "hit"), "melee cannot hit at distance 2.0")

	var ranged_simulation = _new_simulation()
	ranged_simulation.spawn_unit(ranged_simulation.TEAM_ALLY, Vector2(5.5, 11.2), ranged_simulation.UNIT_RANGED)
	ranged_simulation.spawn_unit(ranged_simulation.TEAM_ENEMY, Vector2(5.5, 10.0), ranged_simulation.UNIT_MELEE)
	ranged_simulation.unit_positions[0] = Vector2(5.5, 11.2)
	ranged_simulation.unit_positions[1] = Vector2(5.5, 10.0)
	ranged_simulation.tick(1.0 / 30.0)
	var ranged_events: Array = ranged_simulation.drain_events()
	var shot: Dictionary = _event_of_type(ranged_events, "ranged_shot")
	_expect(_has_event(ranged_events, "hit"), "ranged unit keeps shared hit feedback")
	_expect(not shot.is_empty(), "ranged unit emits a ranged shot inside its doubled base range")
	_expect(shot.get("team", 0) == ranged_simulation.TEAM_ALLY, "ranged shot records the attacker team")
	_expect(shot.get("origin", Vector2.ZERO) == Vector2(5.5, 11.2), "ranged shot records its origin")
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

	var high_range_simulation = _new_simulation()
	high_range_simulation.elevation.fill(1)
	var high_ranged_id: int = high_range_simulation.spawn_unit(high_range_simulation.TEAM_ALLY, Vector2(8.5, 22.5), high_range_simulation.UNIT_RANGED)
	var edge_air_id: int = high_range_simulation.spawn_unit(high_range_simulation.TEAM_ENEMY, Vector2(8.5, 19.6), high_range_simulation.UNIT_DRAGON)
	high_range_simulation.unit_positions[high_range_simulation.unit_ids.find(high_ranged_id)] = Vector2(8.5, 22.5)
	high_range_simulation.unit_positions[high_range_simulation.unit_ids.find(edge_air_id)] = Vector2(8.5, 19.6)
	var edge_air_hp: float = high_range_simulation.unit_hp[high_range_simulation.unit_ids.find(edge_air_id)]
	high_range_simulation.tick(1.0 / float(config.SIM_TICK_RATE))
	var edge_air_index: int = high_range_simulation.unit_ids.find(edge_air_id)
	_expect(edge_air_index >= 0 and high_range_simulation.unit_hp[edge_air_index] < edge_air_hp, "high-ground ranged detection covers attack range plus the dragon radius")

	var high_building_simulation = _new_simulation()
	high_building_simulation.elevation.fill(1)
	var edge_building_id: int = high_building_simulation.add_building(high_building_simulation.TEAM_ENEMY, high_building_simulation.BUILDING_SPAWNER, Vector2i(11, 22))
	var building_ranged_id: int = high_building_simulation.spawn_unit(high_building_simulation.TEAM_ALLY, Vector2(8.38, 22.5), high_building_simulation.UNIT_RANGED)
	high_building_simulation.unit_positions[high_building_simulation.unit_ids.find(building_ranged_id)] = Vector2(8.38, 22.5)
	var edge_building_hp: float = _building_hp(high_building_simulation, edge_building_id)
	high_building_simulation.tick(1.0 / float(config.SIM_TICK_RATE))
	_expect(_building_hp(high_building_simulation, edge_building_id) < edge_building_hp, "high-ground ranged detection covers attack range plus the building radius")

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

	var radius_simulation = _new_simulation()
	var edge_dragon_id: int = radius_simulation.spawn_unit(radius_simulation.TEAM_ALLY, Vector2(15.25, 0.5), radius_simulation.UNIT_DRAGON)
	var edge_dragon_index: int = radius_simulation.unit_ids.find(edge_dragon_id)
	radius_simulation.unit_positions[edge_dragon_index] = Vector2(15.25, 0.5)
	var edge_hp_before: float = radius_simulation.unit_hp[edge_dragon_index]
	radius_simulation.tick(1.0 / float(config.SIM_TICK_RATE))
	edge_dragon_index = radius_simulation.unit_ids.find(edge_dragon_id)
	_expect(edge_dragon_index >= 0 and radius_simulation.unit_hp[edge_dragon_index] < edge_hp_before, "static defense range includes the target unit radius")

	var sight_simulation = _new_simulation()
	_expect(sight_simulation != null and sight_simulation.has_method("get_unit_detect_range"), "simulation exposes per-kind detection range")
	if sight_simulation != null and sight_simulation.has_method("get_unit_detect_range"):
		_expect(is_equal_approx(sight_simulation.get_unit_detect_range(sight_simulation.UNIT_DRAGON), sight_simulation.config.UNIT_DETECT_RANGE * 1.5), "dragon detection API returns 1.5 times common sight")
		var scout_id: int = sight_simulation.spawn_unit(sight_simulation.TEAM_ALLY, Vector2(8.5, 23.5), sight_simulation.UNIT_DRAGON)
		var distant_enemy_id: int = sight_simulation.spawn_unit(sight_simulation.TEAM_ENEMY, Vector2(8.5, 20.3), sight_simulation.UNIT_MELEE)
		sight_simulation.tick(1.0 / float(sight_simulation.config.SIM_TICK_RATE))
		var scout_index: int = sight_simulation.unit_ids.find(scout_id)
		_expect(scout_index >= 0 and sight_simulation.unit_target_ids[scout_index] == distant_enemy_id, "dragon acquires an enemy beyond normal sight but inside extended sight")


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

	simulation.enemy_gold = simulation.config.SIEGE_SPAWNER_COST
	simulation._enemy_build_timer = 0.0
	simulation.tick(1.0 / 30.0)
	enemy_spawners = _spawners_for_team(simulation, simulation.TEAM_ENEMY)
	_expect(enemy_spawners.size() == 3 and int(enemy_spawners[2].unit_kind) == simulation.UNIT_SIEGE, "enemy AI mixes SIEGE into its third production lane")
	_expect(simulation.enemy_gold == 0, "enemy SIEGE build charges artillery cost")


func _test_combat_and_kill_reward() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var red_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(5.5, 10.2))
	var blue_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.5, 10.7))
	simulation.unit_positions[0] = Vector2(5.5, 10.2)
	simulation.unit_positions[1] = Vector2(5.5, 10.7)
	_expect(red_id != blue_id, "units receive unique IDs")
	simulation.unit_hp[1] = 0.5
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


func _test_unit_radius_contract() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	_expect(simulation.has_method("get_unit_radius"), "simulation exposes unit radius as the single size source")
	if not simulation.has_method("get_unit_radius"):
		return
	_expect(is_equal_approx(simulation.get_unit_radius(simulation.UNIT_MELEE), 0.14), "melee simulation radius is 0.14")
	_expect(is_equal_approx(simulation.get_unit_radius(simulation.UNIT_RANGED), 0.13), "ranged simulation radius is 0.13")
	var constants: Dictionary = simulation.get_script().get_script_constant_map()
	var siege_kind := int(constants.get("UNIT_SIEGE", -1))
	_expect(siege_kind >= 0 and is_equal_approx(simulation.get_unit_radius(siege_kind), 0.26), "siege simulation radius is 0.26")
	_expect(is_equal_approx(simulation.get_unit_radius(simulation.UNIT_DRAGON), 0.38), "dragon simulation radius is 0.38")
	_expect(simulation.has_method("get_separation_distance"), "simulation exposes pair-radius separation distance")
	if simulation.has_method("get_separation_distance") and siege_kind >= 0:
		_expect(is_equal_approx(simulation.get_separation_distance(simulation.UNIT_MELEE, siege_kind), (0.14 + 0.26) * 1.2), "melee/siege separation is radius sum times 1.2")


func _test_siege_rules() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var constants: Dictionary = simulation.get_script().get_script_constant_map()
	var siege_kind := int(constants.get("UNIT_SIEGE", -1))
	var siege_build_kind := int(constants.get("BUILD_SIEGE_SPAWNER", -1))
	_expect(siege_kind >= 0 and siege_build_kind >= 0, "simulation exposes SIEGE unit and build kinds")
	_expect(simulation.has_method("get_siege_target_point"), "SIEGE exposes deterministic bucket-density targeting")
	_expect(simulation.has_method("schedule_siege_impact") and simulation.has_method("advance_siege_impacts"), "SIEGE exposes delayed data-only impacts")
	_expect(simulation.has_method("get_siege_damage_at_distance"), "SIEGE exposes radius-aware linear blast falloff")
	_expect(simulation.has_method("get_siege_flight_seconds"), "SIEGE exposes range-proportional projectile flight time")
	if siege_kind < 0 or siege_build_kind < 0 or not simulation.has_method("get_siege_target_point") or not simulation.has_method("schedule_siege_impact") or not simulation.has_method("advance_siege_impacts") or not simulation.has_method("get_siege_damage_at_distance") or not simulation.has_method("get_siege_flight_seconds"):
		return
	_expect(simulation.get_siege_flight_seconds(simulation.config.SIEGE_UNIT_MIN_RANGE) < simulation.config.SIEGE_FLIGHT_SECONDS, "minimum-range SIEGE flight is shorter than the nominal 0.9 seconds")
	_expect(simulation.get_siege_flight_seconds(simulation.config.SIEGE_UNIT_ATTACK_RANGE) > simulation.config.SIEGE_FLIGHT_SECONDS, "maximum-range SIEGE flight is longer than the nominal 0.9 seconds")

	simulation.ally_gold = 200
	_expect(simulation.try_build(simulation.TEAM_ALLY, Vector2i(3, 35), siege_build_kind), "ally can build a SIEGE spawner on owned territory")
	_expect(simulation.ally_gold == 60, "SIEGE spawner spends 140 gold")
	var siege_building: Dictionary = simulation.buildings.back()
	_expect(int(siege_building.unit_kind) == siege_kind, "SIEGE spawner stores the produced packed kind")

	var targeting = _new_simulation()
	var siege_id: int = targeting.spawn_unit(targeting.TEAM_ALLY, Vector2(10.5, 24.5), siege_kind)
	var close_id: int = targeting.spawn_unit(targeting.TEAM_ENEMY, Vector2(10.5, 23.7), targeting.UNIT_MELEE)
	for index in 5:
		targeting.spawn_unit(targeting.TEAM_ENEMY, Vector2(12.15 + float(index % 2) * 0.12, 23.2 + float(index / 2) * 0.10), targeting.UNIT_MELEE)
	targeting._rebuild_buckets()
	var siege_index: int = targeting.unit_ids.find(siege_id)
	var target_point: Vector2 = targeting.get_siege_target_point(siege_index)
	_expect(target_point.distance_to(targeting.unit_positions[siege_index]) >= targeting.config.SIEGE_UNIT_MIN_RANGE, "SIEGE ignores enemies inside its 1.2 minimum range")
	_expect(absf(target_point.x - 12.2) < absf(target_point.x - targeting.unit_positions[targeting.unit_ids.find(close_id)].x), "SIEGE chooses the densest hostile area instead of the nearest unit")
	_expect(close_id > 0, "minimum-range fixture includes a live close enemy")
	var lateral = _new_simulation()
	var lateral_siege_id: int = lateral.spawn_unit(lateral.TEAM_ALLY, Vector2(10.5, 25.5), siege_kind)
	for index in 4:
		var lateral_enemy_id: int = lateral.spawn_unit(lateral.TEAM_ENEMY, Vector2(11.7 + float(index % 2) * 0.12, 23.4 + float(index / 2) * 0.1), lateral.UNIT_MELEE)
		var lateral_enemy_index: int = lateral.unit_ids.find(lateral_enemy_id)
		lateral.unit_positions[lateral_enemy_index] = Vector2(11.7 + float(index % 2) * 0.12, 23.4 + float(index / 2) * 0.1)
		lateral.unit_velocities[lateral_enemy_index] = Vector2.RIGHT * lateral.config.UNIT_SPEED
	lateral._rebuild_buckets()
	var lateral_point: Vector2 = lateral.get_siege_target_point(lateral.unit_ids.find(lateral_siege_id))
	_expect(lateral_point.x > 12.4, "SIEGE density scoring predicts the cluster's actual lateral motion instead of applying a fixed vertical offset")
	targeting.tick(1.0 / float(targeting.config.SIM_TICK_RATE))
	var target_searches_after_launch: int = int(targeting.get("siege_target_searches"))
	targeting.tick(1.0 / float(targeting.config.SIM_TICK_RATE))
	_expect(target_searches_after_launch > 0 and int(targeting.get("siege_target_searches")) == target_searches_after_launch, "SIEGE reuses its target point while reloading instead of rescanning every tick")

	var blast = _new_simulation()
	var impact_point := Vector2(10.5, 20.5)
	var victim_ids: Array[int] = []
	for offset in [Vector2.ZERO, Vector2(0.25, 0.0), Vector2(-0.25, 0.0), Vector2(0.0, 0.28), Vector2(0.0, -0.28)]:
		victim_ids.append(blast.spawn_unit(blast.TEAM_ENEMY, impact_point + offset, blast.UNIT_MELEE))
	var edge_id: int = blast.spawn_unit(blast.TEAM_ENEMY, impact_point + Vector2(blast.config.SIEGE_BLAST_RADIUS + blast.config.MELEE_UNIT_RADIUS - 0.01, 0.0), blast.UNIT_MELEE)
	var ally_id: int = blast.spawn_unit(blast.TEAM_ALLY, impact_point, blast.UNIT_MELEE)
	var building_id: int = blast.add_building(blast.TEAM_ENEMY, blast.BUILDING_SPAWNER, Vector2i(10, 20), blast.UNIT_MELEE)
	blast._rebuild_buckets()
	var hp_before: Dictionary = {}
	for victim_id in victim_ids + [edge_id, ally_id]:
		var victim_index: int = blast.unit_ids.find(victim_id)
		hp_before[victim_id] = blast.unit_hp[victim_index]
	var building_hp_before := float(blast.buildings[blast._building_index_from_id(building_id)].hp)
	blast.schedule_siege_impact(blast.TEAM_ALLY, Vector2(10.5, 24.0), impact_point, blast.config.SIEGE_UNIT_ATTACK_DAMAGE, 0.9)
	blast.advance_siege_impacts(0.45)
	for victim_id in victim_ids:
		var victim_index: int = blast.unit_ids.find(victim_id)
		_expect(is_equal_approx(blast.unit_hp[victim_index], float(hp_before[victim_id])), "SIEGE does not damage clustered targets before flight completes")
	blast.advance_siege_impacts(0.46)
	for victim_id in victim_ids:
		var victim_index: int = blast.unit_ids.find(victim_id)
		_expect(blast.unit_hp[victim_index] < float(hp_before[victim_id]), "SIEGE blast damages every unit in the five-target cluster")
	var edge_index: int = blast.unit_ids.find(edge_id)
	_expect(blast.unit_hp[edge_index] < float(hp_before[edge_id]), "AoE includes a target whose radius overlaps the blast edge")
	var ally_index: int = blast.unit_ids.find(ally_id)
	_expect(is_equal_approx(blast.unit_hp[ally_index], float(hp_before[ally_id])), "SIEGE blast never damages allies")
	_expect(float(blast.buildings[blast._building_index_from_id(building_id)].hp) < building_hp_before, "SIEGE blast damages hostile buildings")
	var center_damage: float = blast.get_siege_damage_at_distance(0.0, blast.config.MELEE_UNIT_RADIUS, 26.0)
	var edge_damage: float = blast.get_siege_damage_at_distance(blast.config.SIEGE_BLAST_RADIUS + blast.config.MELEE_UNIT_RADIUS, blast.config.MELEE_UNIT_RADIUS, 26.0)
	_expect(is_equal_approx(center_damage, 26.0), "SIEGE blast center deals 100 percent damage")
	_expect(is_equal_approx(edge_damage, 26.0 * blast.config.SIEGE_EDGE_DAMAGE_MULTIPLIER), "SIEGE blast edge deals 40 percent damage")
	var events: Array = blast.drain_events()
	_expect(_has_event(events, "siege_projectile") and _has_event(events, "siege_impact"), "SIEGE launch and impact emit distinct readable events")


func _test_siege_balance_goals() -> void:
	var clustered = _new_simulation()
	clustered.elevation.fill(0)
	clustered.blocked.fill(0)
	var clustered_ids: Array[int] = [
		clustered.spawn_unit(clustered.TEAM_ENEMY, Vector2(10.4, 20.5), clustered.UNIT_MELEE),
		clustered.spawn_unit(clustered.TEAM_ENEMY, Vector2(10.6, 20.5), clustered.UNIT_MELEE),
	]
	clustered._rebuild_buckets()
	clustered.schedule_siege_impact(clustered.TEAM_ALLY, Vector2(10.5, 24.0), Vector2(10.5, 20.5), clustered.config.SIEGE_UNIT_ATTACK_DAMAGE, 0.1)
	clustered.advance_siege_impacts(0.11)
	var clustered_damage := 0.0
	for unit_id in clustered_ids:
		clustered_damage += clustered.config.UNIT_MAX_HP - clustered.unit_hp[clustered.unit_ids.find(unit_id)]
	_expect(clustered_damage > clustered.config.SIEGE_UNIT_MAX_HP, "near-equal-cost clustered melee takes a SIEGE-favorable damage trade before contact")

	var spread = _new_simulation()
	spread.elevation.fill(0)
	spread.blocked.fill(0)
	var spread_ids: Array[int] = [
		spread.spawn_unit(spread.TEAM_ENEMY, Vector2(9.0, 20.5), spread.UNIT_MELEE),
		spread.spawn_unit(spread.TEAM_ENEMY, Vector2(12.0, 20.5), spread.UNIT_MELEE),
	]
	spread._rebuild_buckets()
	spread.schedule_siege_impact(spread.TEAM_ALLY, Vector2(9.0, 24.0), Vector2(9.0, 20.5), spread.config.SIEGE_UNIT_ATTACK_DAMAGE, 0.1)
	spread.advance_siege_impacts(0.11)
	var spread_damage := 0.0
	for unit_id in spread_ids:
		spread_damage += spread.config.UNIT_MAX_HP - spread.unit_hp[spread.unit_ids.find(unit_id)]
	_expect(spread_damage < spread.config.SIEGE_UNIT_MAX_HP, "spread melee keeps the favorable damage trade against one SIEGE shell")

	var close = _new_simulation()
	close.elevation.fill(0)
	close.blocked.fill(0)
	close._enemy_build_timer = 999.0
	close.spawn_unit(close.TEAM_ALLY, Vector2(10.5, 23.0), close.UNIT_SIEGE)
	var melee_id: int = close.spawn_unit(close.TEAM_ENEMY, Vector2(10.5, 22.4), close.UNIT_MELEE)
	for tick_index in 360:
		close.tick(1.0 / float(close.config.SIM_TICK_RATE))
	_expect(close.unit_ids.find(melee_id) >= 0 and close.unit_kinds.count(close.UNIT_SIEGE) == 0, "melee inside minimum range defeats SIEGE")

	var air = _new_simulation()
	air.elevation.fill(0)
	air.blocked.fill(0)
	air._enemy_build_timer = 999.0
	var dragon_id: int = air.spawn_unit(air.TEAM_ALLY, Vector2(10.5, 24.5), air.UNIT_DRAGON)
	air.spawn_unit(air.TEAM_ENEMY, Vector2(10.5, 21.5), air.UNIT_SIEGE)
	for tick_index in 34:
		air.tick(1.0 / float(air.config.SIM_TICK_RATE))
	var dragon_index: int = air.unit_ids.find(dragon_id)
	_expect(dragon_index >= 0 and air.unit_hp[dragon_index] < air.config.DRAGON_UNIT_MAX_HP, "dragon is caught by the opening SIEGE splash")
	for tick_index in 416:
		air.tick(1.0 / float(air.config.SIM_TICK_RATE))
	_expect(air.unit_ids.find(dragon_id) >= 0 and air.unit_kinds.count(air.UNIT_SIEGE) == 0, "dragon wins the one-to-one exchange against SIEGE")


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
	slide_simulation.elevation.fill(0)
	var start := Vector2(8.5, 24.5)
	var diagonal_cliff := Vector2i(9, 23)
	slide_simulation.elevation[diagonal_cliff.y * slide_simulation.config.GRID_COLUMNS + diagonal_cliff.x] = 2
	var final_position: Vector2 = slide_simulation._move_without_entering_blocked(start, Vector2(1.0, -1.0))
	_expect(final_position.x > start.x and is_equal_approx(final_position.y, start.y), "cliff-blocked diagonal movement slides along the open level axis")
	_expect(slide_simulation.elevation_at_position(final_position) == 0, "cliff slide keeps the final logical cell on traversable terrain")


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
