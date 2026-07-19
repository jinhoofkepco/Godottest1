extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_values()
	_test_grid_projection_and_dynamic_building()
	_test_simulation_contract()
	_test_initial_territory()
	_test_build_and_economy()
	_test_combat_and_kill_reward()
	_test_cross_column_engagement()
	_test_ally_separation()
	_test_lunge_state_contract()
	_test_frontline_ownership()
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
	for cell in [Vector2i(0, 0), Vector2i(5, 11), Vector2i(10, 21), Vector2i(3, 17)]:
		_expect(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "isometric picking round trips %s" % cell)
	_expect(grid.can_build(Vector2i(3, 17), simulation.TEAM_ALLY), "dynamic blue territory is buildable")
	_expect(not grid.can_build(Vector2i(3, 3), simulation.TEAM_ALLY), "dynamic red territory rejects blue build")
	_expect(not grid.can_build(Vector2i(5, 21), simulation.TEAM_ALLY), "blue HQ tile rejects building")
	simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(3.5, 18.5))
	simulation.recalculate_territory()
	_expect(not grid.can_build(Vector2i(3, 17), simulation.TEAM_ALLY), "frontline capture immediately revokes blue build permission")
	grid.free()


func _test_config_values() -> void:
	var config := load("res://scripts/game_config.gd")
	_expect(config != null and config.can_instantiate(), "game config parses")
	if config == null or not config.can_instantiate():
		return
	_expect(config.GRID_COLUMNS == 11, "frontline grid has 11 columns")
	_expect(config.GRID_ROWS == 22, "frontline grid has 22 rows")
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
	var unit_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(4.5, 18.5))
	_expect(unit_id > 0 and simulation.unit_ids.size() == 1, "spawn inserts one packed unit")
	_expect(absf(simulation.unit_positions[0].x - 4.5) <= 0.3001 and is_equal_approx(simulation.unit_positions[0].y, 18.5), "spawn applies only bounded lateral variation")
	if property_names.has("unit_speed_scales"):
		_expect(simulation.unit_speed_scales.size() == 1, "speed variation stays index-aligned")
		_expect(simulation.unit_speed_scales[0] >= 0.9 and simulation.unit_speed_scales[0] <= 1.1, "speed variation stays within ten percent")
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_positions[0].y < 18.5, "blue unit advances toward red HQ")
	var building_id: int = simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_SPAWNER, Vector2i(1, 18))
	_expect(building_id > 0, "public building insertion API returns an ID")
	var fixed_simulation = _new_simulation()
	fixed_simulation.spawn_unit(fixed_simulation.TEAM_ALLY, Vector2(4.5, 18.5))
	fixed_simulation.tick(1.0 / 60.0)
	_expect(is_equal_approx(fixed_simulation.unit_positions[0].y, 18.5), "sub-tick delta accumulates without partial simulation")
	fixed_simulation.tick(1.0 / 60.0)
	_expect(fixed_simulation.unit_positions[0].y < 18.5, "two half ticks produce exactly one fixed simulation step")
	var catch_up_simulation = _new_simulation()
	catch_up_simulation.spawn_unit(catch_up_simulation.TEAM_ALLY, Vector2(4.5, 18.5))
	catch_up_simulation.tick(1.0)
	var expected_catch_up_y: float = 18.5 - catch_up_simulation.config.UNIT_SPEED * catch_up_simulation.unit_speed_scales[0] * 8.0 / 30.0
	_expect(is_equal_approx(catch_up_simulation.unit_positions[0].y, expected_catch_up_y), "long frame performs at most eight fixed catch-up ticks")
	_expect(is_equal_approx(catch_up_simulation.time_remaining, 180.0 - 8.0 / 30.0), "clock discards the same excess time as combat")


func _test_initial_territory() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var ownership: PackedByteArray = simulation.get_ownership()
	_expect(ownership.size() == 11 * 22, "ownership has one entry per tile")
	_expect(ownership[0] == simulation.TEAM_ENEMY, "top tile starts red")
	_expect(ownership[10 * 11 + 5] == simulation.TEAM_ENEMY, "upper half ends red")
	_expect(ownership[11 * 11 + 5] == simulation.TEAM_ALLY, "lower half starts blue")
	_expect(ownership[21 * 11 + 10] == simulation.TEAM_ALLY, "bottom tile starts blue")
	_expect(is_equal_approx(simulation.get_occupancy(simulation.TEAM_ALLY), 0.5), "initial blue occupancy is 50 percent")


func _test_build_and_economy() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	_expect(simulation.try_build_spawner(simulation.TEAM_ALLY, Vector2i(5, 18)), "blue builds on blue territory")
	_expect(simulation.ally_gold == 120, "building spends exactly 60 blue gold")
	var gold_after_build: int = simulation.ally_gold
	_expect(not simulation.try_build_spawner(simulation.TEAM_ALLY, Vector2i(5, 18)), "occupied tile rejects another building")
	_expect(not simulation.try_build_spawner(simulation.TEAM_ALLY, Vector2i(5, 3)), "blue cannot build on red territory")
	_expect(not simulation.try_build_spawner(simulation.TEAM_ENEMY, Vector2i(5, 18)), "red cannot build on blue territory")
	_expect(simulation.ally_gold == gold_after_build, "invalid build attempts never spend blue gold")
	var before_income: int = simulation.ally_gold
	for tick_index in 30:
		simulation.tick(1.0 / 30.0)
	_expect(simulation.ally_gold == before_income + 3, "one second grants exact passive income")


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


func _test_ally_separation() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.5, 15.0))
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(5.5, 15.0))
	simulation.unit_positions[0] = Vector2(5.5, 15.0)
	simulation.unit_positions[1] = Vector2(5.5, 15.0)
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
	var before: float = simulation.get_occupancy(simulation.TEAM_ALLY)
	simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(2.5, 16.5))
	simulation.recalculate_territory()
	var ownership: PackedByteArray = simulation.get_ownership()
	_expect(ownership[17 * 11 + 2] == simulation.TEAM_ENEMY, "forward red unit moves its column boundary downward")
	_expect(simulation.get_occupancy(simulation.TEAM_ALLY) < before, "red advance reduces actual blue occupancy")
	simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(8.5, 3.5))
	simulation.recalculate_territory()
	ownership = simulation.get_ownership()
	_expect(ownership[4 * 11 + 8] == simulation.TEAM_ALLY, "forward blue unit moves its column boundary upward")


func _test_terminal_results() -> void:
	var hq_sim = _new_simulation()
	if hq_sim == null:
		return
	hq_sim.apply_building_damage(hq_sim.enemy_hq_id, hq_sim.config.HQ_MAX_HP, hq_sim.TEAM_ALLY)
	_expect(hq_sim.result == "VICTORY", "destroying red HQ wins immediately")

	var territory_sim = _new_simulation()
	for column in 11:
		territory_sim.spawn_unit(territory_sim.TEAM_ALLY, Vector2(float(column) + 0.5, 1.2))
	territory_sim.tick(1.0 / 30.0)
	_expect(territory_sim.get_occupancy(territory_sim.TEAM_ALLY) >= 0.9, "blue formation can reach 90 percent territory")
	_expect(territory_sim.result == "VICTORY", "90 percent blue territory wins immediately")

	var timeout_sim = _new_simulation()
	for column in 11:
		timeout_sim.spawn_unit(timeout_sim.TEAM_ENEMY, Vector2(float(column) + 0.5, 17.5))
	timeout_sim.time_remaining = 0.01
	timeout_sim.tick(1.0 / 30.0)
	_expect(timeout_sim.result == "DEFEAT", "timeout awards the match to the territory leader")


func _test_balance_paths() -> void:
	var passive_simulation = _new_simulation()
	var passive_elapsed := _run_complete_match(passive_simulation)
	_expect(passive_simulation.result == "DEFEAT", "building no blue spawner lets red AI win")
	var active_simulation = _new_simulation()
	for column in [3, 5, 7]:
		_expect(active_simulation.try_build_spawner(active_simulation.TEAM_ALLY, Vector2i(column, 18)), "balance fixture spends starting gold on three blue spawners")
	var active_elapsed := _run_complete_match(active_simulation)
	_expect(active_simulation.result == "VICTORY", "three starting blue spawners can push through and win")
	_expect(passive_elapsed >= 120.0 and passive_elapsed <= 180.1, "unopposed red advance remains a two-to-three minute match (%.1fs)" % passive_elapsed)
	_expect(active_elapsed >= 120.0 and active_elapsed <= 180.1, "reinforced blue victory remains a two-to-three minute match (%.1fs)" % active_elapsed)
	print("BALANCE PATHS: no_spawner=%.1fs %s blue_share=%.2f blue_hq=%.0f three_spawners=%.1fs %s blue_share=%.2f red_hq=%.0f" % [
		passive_elapsed,
		passive_simulation.result,
		passive_simulation.get_occupancy(passive_simulation.TEAM_ALLY),
		_building_hp(passive_simulation, passive_simulation.ally_hq_id),
		active_elapsed,
		active_simulation.result,
		active_simulation.get_occupancy(active_simulation.TEAM_ALLY),
		_building_hp(active_simulation, active_simulation.enemy_hq_id),
	])


func _run_complete_match(simulation) -> float:
	var fixed_delta := 1.0 / 30.0
	for step in int(181.0 / fixed_delta):
		if simulation.result != "":
			return simulation.config.MATCH_DURATION - simulation.time_remaining
		simulation.tick(fixed_delta)
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
		simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(float(index % 11) + 0.5, 2.0 + float(index % 3) * 0.1))
		simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(index % 11) + 0.5, 19.0 - float(index % 3) * 0.1))
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_ids.size() == 360, "stress fixture keeps 360 data-only units")
	_expect(simulation.target_candidate_checks < 50000, "bucket target checks stay far below all-pairs work")


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if String(event.get("type", "")) == event_type:
			return true
	return false


func _property_names(value: Object) -> Array[String]:
	var names: Array[String] = []
	for property in value.get_property_list():
		names.append(String(property.name))
	return names


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
