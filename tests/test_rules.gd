extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const UNIT_SIEGE := 3
const BUILD_MELEE := 0
const BUILD_RANGED := 1
const BUILD_TOWER := 2
const BUILD_DRAGON := 3
const BUILD_SIEGE := 4
const BUILD_RALLY := 5
const FORMATION_LINE := 0
const FORMATION_WEDGE := 1
const FORMATION_LOOSE := 2
const LEGION_GATHERING := 0
const LEGION_MARCHING := 1
const LEGION_BROKEN := 3

var failures: Array[String] = []


func run() -> Array[String]:
	_test_match_settings_profile()
	_test_tuned_runtime_behavior()
	_test_large_radius_spawner_production()
	_test_siege_detect_range_runtime()
	_test_config_and_initial_state()
	_test_shield_stance_and_heavy_defaults()
	_test_build_and_economy()
	_test_construction_population_and_ai_income()
	_test_elevation_rules()
	_test_cross_column_combat_and_air_targeting()
	_test_radius_and_separation()
	_test_tuned_radius_bucket_horizon()
	_test_siege_rules_and_aoe()
	_test_class_counter_matrix_and_composition()
	_test_legion_slots_and_rotation()
	_test_legion_loose_aoe_geometry()
	_test_spawner_production_and_nearest_rally()
	_test_rally_advance_launch()
	_test_rally_congestion_still_launches()
	_test_rally_defense_overflow_and_destroy_fallback()
	_test_legion_engage_reform()
	_test_ai_continues_after_opening()
	_test_legion_broken_transition()
	_test_territory_cache_and_terminal_result()
	_test_packed_events_and_profile()
	return failures


func _test_match_settings_profile() -> void:
	var first = _new_simulation()
	var second = _new_simulation()
	_expect(first.has_method("GetMatchSettingsSchema") and first.has_method("ConfigureAndReset"), "bulk match settings API exists")
	var defaults: Dictionary = first.call("GetMatchSettings")
	_expect(defaults.has("melee") and defaults.has("ranged") and defaults.has("siege") and defaults.has("dragon"), "settings expose four unit profiles")
	var changed := defaults.duplicate(true)
	changed.ranged.max_hp = 31.5
	var applied: Dictionary = first.call("ConfigureAndReset", changed)
	_expect(bool(applied.ok) and is_equal_approx(float(first.call("GetMatchSettings").ranged.max_hp), 31.5), "settings apply atomically before reset")
	_expect(not is_equal_approx(float(second.call("GetMatchSettings").ranged.max_hp), 31.5), "simulation settings are instance isolated")
	var invalid := changed.duplicate(true)
	invalid.siege.min_range = 20.0
	invalid.siege.attack_range = 10.0
	var rejected: Dictionary = first.call("ConfigureAndReset", invalid)
	_expect(not bool(rejected.ok) and is_equal_approx(float(first.call("GetMatchSettings").ranged.max_hp), 31.5), "invalid payload is rejected without partial mutation")
	first.free()
	second.free()


func _test_tuned_runtime_behavior() -> void:
	var simulation = _new_simulation()
	var tuned: Dictionary = simulation.call("GetMatchSettings")
	tuned.melee.damage = 7.0
	tuned.melee.attack_interval = 1.25
	tuned.melee.attack_range = 2.5
	tuned.melee.detect_range = 2.5
	tuned.melee.speed = 0.4
	tuned.melee.radius = 0.28
	tuned.melee.spawner_cost = 73
	tuned.melee.damage_vs.ranged = 2.0
	var applied: Dictionary = simulation.call("ConfigureAndReset", tuned)
	_expect(bool(applied.ok), "complete tuned runtime fixture applies")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 100, "enemy": 0})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 70), BUILD_MELEE), "tuned spawner cost is accepted by live build logic")
	var built: Dictionary = simulation.call("GetDebugSnapshot")
	var building := _building_by_id(built.buildings, _building_id_at(built.buildings, Vector2i(3, 70)))
	_expect(int(built.ally_gold) == 27 and is_equal_approx(float(building.construction_duration), 7.3), "tuned cost drives gold deduction and construction time")
	var flat := PackedByteArray()
	flat.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	flat.fill(0)
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(10.5, 70.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_RANGED, "position": Vector2(10.5, 68.6), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(30.5, 74.5), "exact": true})
	simulation.call("Step", 1.0 / 30.0)
	var combat: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(is_equal_approx(_unit_hp_by_team_kind(combat, TEAM_ENEMY, UNIT_RANGED), GameConfig.RANGED_UNIT_MAX_HP - 14.0), "tuned damage, class multiplier, and extended range affect a live hit")
	_expect(is_equal_approx(float(combat.unit_cooldowns[0]), 1.25), "tuned attack interval becomes the live cooldown")
	for tick in range(20): simulation.call("Step", 1.0 / 30.0)
	var moving: Dictionary = simulation.call("GetDebugSnapshot")
	var tuned_speed := Vector2(moving.unit_velocities[2]).length()
	_expect(tuned_speed > 0.20 and tuned_speed <= 0.44, "tuned movement speed bounds live velocity")
	var render: Dictionary = simulation.call("GetRenderSnapshot")
	var infantry: PackedFloat32Array = render.infantry_buffer
	var found_tuned_scale := false
	for record in range(int(render.infantry_count)):
		if absf(float(infantry[record * 16]) - 2.0) <= 0.01:
			found_tuned_scale = true
	_expect(found_tuned_scale, "tuned radius drives the bulk render transform scale")
	simulation.free()


func _test_large_radius_spawner_production() -> void:
	var simulation = _new_simulation()
	var tuned: Dictionary = simulation.call("GetMatchSettings")
	tuned.melee.radius = 2.0
	var applied: Dictionary = simulation.call("ConfigureAndReset", tuned)
	_expect(bool(applied.ok), "the maximum 2.0-cell unit radius remains a valid match setting")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	var flat := PackedByteArray()
	flat.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	flat.fill(0)
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 1, "cell": Vector2i(10, 70), "unit_kind": UNIT_MELEE}), "large-radius production fixture builds")
	var spawner_id := _building_id_at(simulation.call("GetDebugSnapshot").buildings, Vector2i(10, 70))
	simulation.call("ApplyDebugCommand", {"op": "set_building_spawn_timer", "id": spawner_id, "value": 0.0})
	simulation.call("Step", 1.0 / 30.0)
	var produced: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(int(produced.ally_unit_count) == 1, "a valid large-radius unit spawns outside its production building")
	if int(produced.ally_unit_count) == 1:
		var position := Vector2(produced.unit_positions[0])
		_expect(simulation.call("IsGroundPositionClear", position, 2.0), "large-radius production chooses a collision-free ground position")
	simulation.free()


func _test_siege_detect_range_runtime() -> void:
	var simulation = _new_simulation()
	var tuned: Dictionary = simulation.call("GetMatchSettings")
	tuned.siege.attack_range = 3.0
	tuned.siege.detect_range = 8.0
	tuned.siege.min_range = 1.0
	var applied: Dictionary = simulation.call("ConfigureAndReset", tuned)
	_expect(bool(applied.ok), "extended SIEGE detection fixture applies")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	var flat := PackedByteArray()
	flat.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	flat.fill(0)
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_SIEGE, "position": Vector2(10.5, 70.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(16.5, 70.5), "exact": true})
	simulation.call("Step", 1.0 / 30.0)
	var detected: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(int(detected.unit_target_ids[0]) != 0, "SIEGE detect_range acquires an enemy outside attack_range for approach")
	_expect(not _has_event(simulation.call("DrainEvents").events, "siege_projectile"), "SIEGE does not fire until the detected enemy enters attack_range")
	simulation.free()


func _new_simulation():
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	return simulation


func _test_config_and_initial_state() -> void:
	var simulation = _new_simulation()
	var config: Dictionary = simulation.call("GetConfigSnapshot")
	var debug: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(int(config.grid_columns) == 44 and int(config.grid_rows) == 88, "map expands to the 44x88 battlefield")
	_expect(is_equal_approx(float(config.siege_range), 14.0), "SIEGE range is 14.0 cells")
	_expect(is_equal_approx(float(config.siege_damage), 55.8), "SIEGE damage is 55.8")
	_expect(is_equal_approx(float(config.match_duration), 420.0) and is_equal_approx(float(config.occupancy_win_ratio), 0.92), "match tempo exposes seven minutes and ninety-two percent occupancy")
	_expect(is_equal_approx(float(config.passive_income_per_second), 2.25) and is_equal_approx(float(config.hq_max_hp), 12000.0), "population-scaled economy and five-times HQ durability are exposed by C#")
	_expect(is_equal_approx(float(config.ranged_hp), 20.4), "RANGED HP is nerfed to sixty percent")
	_expect(is_equal_approx(float(config.spawner_production_interval), 5.76), "unit production interval is doubled")
	_expect(int(config.rally_launch_size) == 20 and int(config.rally_defense_capacity) == 28, "rally launch and defense capacity are doubled")
	_expect(int(config.team_unit_cap) == 300 and int(config.ai_income_level) == 3, "team unit cap and default AI income level are exposed")
	_expect(int(debug.unit_count) == 0, "match starts without unit Nodes or unit objects")
	_expect(is_equal_approx(float(debug.ally_occupancy), 0.5), "initial territory is split 50/50")
	_expect(simulation.call("TerrainPathsValid"), "seeded symmetric elevation map is reachable")
	var elevation: PackedByteArray = debug.elevation
	var water: PackedByteArray = debug.water
	_expect(water.size() == GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS, "board exposes one water flag per cell")
	_expect(water[(GameConfig.GRID_ROWS / 2) * GameConfig.GRID_COLUMNS + GameConfig.GRID_COLUMNS / 2] == 1, "one large lake occupies the battlefield center")
	for row in range(GameConfig.GRID_ROWS / 2):
		for col in range(GameConfig.GRID_COLUMNS):
			var mirror := (GameConfig.GRID_ROWS - 1 - row) * GameConfig.GRID_COLUMNS + (GameConfig.GRID_COLUMNS - 1 - col)
			_expect(elevation[row * GameConfig.GRID_COLUMNS + col] == elevation[mirror], "terrain elevation is point-mirrored for fairness")
			_expect(water[row * GameConfig.GRID_COLUMNS + col] == water[mirror], "central lake is point-mirrored for fairness")
	_expect(not simulation.call("CanGroundStep", Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2 - 10), Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2 - 9)), "ground units cannot step into the lake")
	simulation.free()


func _test_shield_stance_and_heavy_defaults() -> void:
	var simulation = _new_simulation()
	var config: Dictionary = simulation.call("GetConfigSnapshot")
	_expect(absf(float(config.siege_production_interval) - 12.342857) <= 0.0001, "SIEGE production throughput is forty percent faster")
	_expect(is_equal_approx(float(config.siege_range), 14.0) and is_equal_approx(float(config.siege_blast_radius), 1.8), "SIEGE range and blast radius are doubled")
	_expect(is_equal_approx(float(config.siege_damage), 55.8), "SIEGE keeps its current damage while gaining range and throughput")
	_expect(is_equal_approx(float(config.dragon_hp), 520.0) and is_equal_approx(float(config.dragon_damage), 36.0) and int(config.dragon_production_batch) == 2, "DRAGON batch HP and damage are doubled")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	var flat := PackedByteArray()
	flat.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	flat.fill(0)
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	# Spawn the shooter first so its decision group attacks on the first fixed tick.
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_RANGED, "position": Vector2(10.5, 20.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(10.5, 22.0), "exact": true})
	simulation.call("Step", 1.0 / 30.0)
	var first_hit: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(first_hit.has("unit_shield_modes"), "debug snapshot exposes packed shield stance flags")
	if first_hit.has("unit_shield_modes"):
		_expect(int(first_hit.unit_shield_modes[1]) == 1, "the first hostile RANGED hit raises the MELEE shield before damage")
	_expect(is_equal_approx(_unit_hp_by_team_kind(first_hit, TEAM_ALLY, UNIT_MELEE), 48.0 - 8.0 * 1.7 * 0.1), "shield mode reduces only incoming RANGED damage by ninety percent")
	# Hysteresis keeps the shield active until every hostile RANGED is beyond 3.0 cells.
	simulation.call("ApplyDebugCommand", {"op": "set_unit", "index": 0, "position": Vector2(10.5, 26.0), "cooldown": 10.0})
	for tick in range(4): simulation.call("Step", 1.0 / 30.0)
	var released: Dictionary = simulation.call("GetDebugSnapshot")
	if released.has("unit_shield_modes"):
		_expect(int(released.unit_shield_modes[1]) == 0, "MELEE leaves shield mode after hostile RANGED clears the release radius")
	simulation.free()

	var speed_sim = _new_simulation()
	speed_sim.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	speed_sim.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	speed_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(10.5, 24.0), "exact": true})
	speed_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_RANGED, "position": Vector2(10.5, 21.6), "exact": true})
	for tick in range(12): speed_sim.call("Step", 1.0 / 30.0)
	var guarded: Dictionary = speed_sim.call("GetDebugSnapshot")
	if guarded.has("unit_shield_modes"):
		_expect(int(guarded.unit_shield_modes[0]) == 1, "hostile RANGED inside 2.5 cells activates shield stance without waiting for a hit")
	_expect(Vector2(guarded.unit_velocities[0]).length() <= 1.015 * 1.1 * 0.20 + 0.001, "shield stance limits MELEE movement to twenty percent speed")
	var shield_render: Dictionary = speed_sim.call("GetRenderSnapshot")
	var shield_buffer: PackedFloat32Array = shield_render.infantry_buffer
	var has_shield_rim_flag := false
	for record in range(int(shield_render.infantry_count)):
		has_shield_rim_flag = has_shield_rim_flag or float(shield_buffer[record * 16 + 10]) > 0.5
	_expect(has_shield_rim_flag, "bulk infantry buffer carries shield stance in the instance blue channel")
	speed_sim.free()

	var transition_sim = _new_simulation()
	transition_sim.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	transition_sim.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	transition_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(5.5, 70.5), "exact": true})
	transition_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_RANGED, "position": Vector2(40.5, 4.5), "exact": true})
	for tick in range(45): transition_sim.call("Step", 1.0 / 30.0)
	var running: Dictionary = transition_sim.call("GetDebugSnapshot")
	_expect(Vector2(running.unit_velocities[0]).length() > 0.6, "MELEE reaches normal travel speed before the shield transition fixture")
	var running_position := Vector2(running.unit_positions[0])
	transition_sim.call("ApplyDebugCommand", {"op": "set_unit", "index": 1, "position": running_position + Vector2(0.0, -2.4), "cooldown": 10.0})
	transition_sim.call("Step", 1.0 / 30.0)
	var braked: Dictionary = transition_sim.call("GetDebugSnapshot")
	_expect(int(braked.unit_shield_modes[0]) == 1, "a moving MELEE enters shield mode as soon as hostile RANGED crosses 2.5 cells")
	_expect(Vector2(braked.unit_velocities[0]).length() <= 1.015 * 1.1 * 0.20 + 0.001, "shield transition clamps existing momentum to the effective twenty-percent cap on the same tick")
	transition_sim.free()

	var melee_sim = _new_simulation()
	melee_sim.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	melee_sim.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	melee_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(10.5, 20.5), "exact": true})
	melee_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(10.5, 21.0), "exact": true})
	melee_sim.call("Step", 1.0 / 30.0)
	_expect(is_equal_approx(_unit_hp_by_team_kind(melee_sim.call("GetDebugSnapshot"), TEAM_ALLY, UNIT_MELEE), 38.0), "shield protection never reduces incoming MELEE damage")
	melee_sim.free()

	var production_sim = _new_simulation()
	production_sim.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	_expect(production_sim.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 3, "cell": Vector2i(5, 70), "unit_kind": UNIT_DRAGON}), "completed DRAGON lair fixture builds")
	_expect(production_sim.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 1, "cell": Vector2i(10, 70), "unit_kind": UNIT_SIEGE}), "completed SIEGE spawner fixture builds")
	var dragon_lair_id := _building_id_at(production_sim.call("GetDebugSnapshot").buildings, Vector2i(5, 70))
	var siege_spawner_id := _building_id_at(production_sim.call("GetDebugSnapshot").buildings, Vector2i(10, 70))
	production_sim.call("ApplyDebugCommand", {"op": "set_building_spawn_timer", "id": dragon_lair_id, "value": 0.0})
	production_sim.call("ApplyDebugCommand", {"op": "set_building_spawn_timer", "id": siege_spawner_id, "value": 0.0})
	production_sim.call("Step", 1.0 / 30.0)
	var produced: Dictionary = production_sim.call("GetDebugSnapshot")
	var production_events: Dictionary = production_sim.call("DrainEvents")
	_expect(PackedInt32Array(produced.unit_kinds).count(UNIT_SIEGE) == 1, "one completed SIEGE production cycle emits one unit")
	_expect(PackedInt32Array(produced.unit_kinds).count(UNIT_DRAGON) == 2, "one DRAGON production cycle emits a two-unit batch")
	_expect(_count_event(production_events.events, "unit_produced") == 3, "batched production emits one event per successful unit")
	production_sim.call("ApplyDebugCommand", {"op": "clear_units"})
	for index in range(GameConfig.TEAM_UNIT_CAP - 1):
		production_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(2.5, 70.5), "exact": true})
	production_sim.call("ApplyDebugCommand", {"op": "set_building_spawn_timer", "id": dragon_lair_id, "value": 0.0})
	production_sim.call("Step", 1.0 / 30.0)
	var partial: Dictionary = production_sim.call("GetDebugSnapshot")
	var partial_events: Dictionary = production_sim.call("DrainEvents")
	_expect(int(partial.ally_unit_count) == GameConfig.TEAM_UNIT_CAP, "DRAGON batch fills but never exceeds the exact team population cap")
	_expect(_count_event(partial_events.events, "unit_produced") == 1, "a 299-unit team produces one DRAGON and one production event")
	production_sim.call("ApplyDebugCommand", {"op": "set_building_spawn_timer", "id": dragon_lair_id, "value": 0.0})
	production_sim.call("Step", 1.0 / 30.0)
	var capped: Dictionary = production_sim.call("GetDebugSnapshot")
	var capped_events: Dictionary = production_sim.call("DrainEvents")
	_expect(int(capped.ally_unit_count) == GameConfig.TEAM_UNIT_CAP, "a completed DRAGON lair at 300 population produces zero additional units")
	_expect(_count_event(capped_events.events, "unit_produced") == 0, "a full-cap DRAGON cycle emits zero false production events")
	production_sim.free()


func _test_build_and_economy() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 70), BUILD_MELEE), "MELEE spawner builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(8, 70), BUILD_RANGED), "RANGED spawner builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(13, 70), BUILD_SIEGE), "SIEGE spawner builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(18, 70), BUILD_DRAGON), "DRAGON lair builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(24, 68), BUILD_RALLY), "RALLY_POINT builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(22, 86), BUILD_TOWER), "defense tower builds inside allied HQ 5x5")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(30, 70), BUILD_TOWER), "defense tower rejects cells outside HQ 5x5")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(24, 68), BUILD_RALLY), "occupied rally cell rejects a duplicate")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 4), BUILD_RALLY), "enemy territory rejects allied rally construction")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2), BUILD_RALLY), "central lake rejects construction")
	simulation.free()


func _test_construction_population_and_ai_income() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 0})
	var cell := Vector2i(5, 70)
	_expect(simulation.call("TryBuild", TEAM_ALLY, cell, BUILD_MELEE), "construction fixture places a MELEE spawner")
	var built: Dictionary = simulation.call("GetDebugSnapshot")
	var building_id := _building_id_at(built.buildings, cell)
	var building := _building_by_id(built.buildings, building_id)
	_expect(not bool(building.complete) and is_equal_approx(float(building.construction_duration), 6.0), "construction time equals building cost times 0.1 seconds")
	_expect(is_equal_approx(float(building.hp), GameConfig.SPAWNER_MAX_HP * 0.2), "construction starts at twenty percent building HP")
	for tick in range(180): simulation.call("Step", 1.0 / 30.0)
	building = _building_by_id(simulation.call("GetDebugSnapshot").buildings, building_id)
	_expect(bool(building.complete), "building activates after its full construction duration")
	simulation.call("ApplyDebugCommand", {"op": "clear_units"})
	for index in range(GameConfig.TEAM_UNIT_CAP + 1):
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(5.5, 70.5), "exact": true})
	var capped: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(int(capped.ally_unit_count) == GameConfig.TEAM_UNIT_CAP, "each team is capped at three hundred living units")
	_expect(is_equal_approx(float(simulation.call("GetIncomeMultiplier", TEAM_ALLY)), 0.0), "three hundred units reduce incoming player money to zero")
	simulation.call("ApplyDebugCommand", {"op": "clear_units"})
	for index in range(30):
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(5.5, 70.5), "exact": true})
	_expect(is_equal_approx(float(simulation.call("GetIncomeMultiplier", TEAM_ALLY)), 0.9), "each complete thirty-unit block reduces income by ten percent")
	simulation.call("SetAiIncomeLevel", 5)
	_expect(int(simulation.call("GetAiIncomeLevel")) == 5 and is_equal_approx(float(simulation.call("GetIncomeMultiplier", TEAM_ENEMY)), 2.0), "AI income level five maps to two-times player base income")
	simulation.free()


func _test_legion_slots_and_rotation() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("GetFormationSlots"):
		_expect(false, "C# simulation exposes legion formation slot geometry")
		simulation.free()
		return
	var template := {"melee": 6, "ranged": 3, "siege": 1, "dragon": 0}
	var north: PackedVector2Array = simulation.call("GetFormationSlots", template, FORMATION_LINE, Vector2.UP)
	var east: PackedVector2Array = simulation.call("GetFormationSlots", template, FORMATION_LINE, Vector2.RIGHT)
	_expect(north.size() == 10 and east.size() == 10, "LINE emits exactly one slot per template member")
	if north.size() == 10 and east.size() == 10:
		var last_melee := INF
		var first_support := -INF
		for index in 6: last_melee = minf(last_melee, north[index].dot(Vector2.UP))
		for index in range(6, 10): first_support = maxf(first_support, north[index].dot(Vector2.UP))
		_expect(last_melee > first_support, "LINE places every melee rank ahead of ranged and siege ranks")
		var expected_east := Vector2(-north[0].y, north[0].x)
		_expect(east[0].distance_to(expected_east) < 0.001, "heading rotation rotates the complete slot layout")
	var large: PackedVector2Array = simulation.call("GetFormationSlots", {"melee": 18, "ranged": 8, "siege": 2, "dragon": 0}, FORMATION_LINE, Vector2.UP)
	var maximum_width := 0.0
	for slot in large: maximum_width = maxf(maximum_width, absf(Vector2(slot).x))
	_expect(large.size() == 28 and maximum_width < 3.2, "twenty-eight-member LINE uses bounded ranks instead of one screen-wide row")
	simulation.free()


func _test_legion_loose_aoe_geometry() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("GetFormationSlots"):
		_expect(false, "C# simulation exposes LOOSE formation geometry")
		simulation.free()
		return
	var template := {"melee": 6, "ranged": 4, "siege": 2, "dragon": 0}
	var line: PackedVector2Array = simulation.call("GetFormationSlots", template, FORMATION_LINE, Vector2.UP)
	var loose: PackedVector2Array = simulation.call("GetFormationSlots", template, FORMATION_LOOSE, Vector2.UP)
	var line_exposure := 0.0
	var loose_exposure := 0.0
	for slot in line:
		line_exposure += float(simulation.call("GetSiegeDamageAtDistance", Vector2(slot).length(), GameConfig.MELEE_UNIT_RADIUS, 1.0))
	for slot in loose:
		loose_exposure += float(simulation.call("GetSiegeDamageAtDistance", Vector2(slot).length(), GameConfig.MELEE_UNIT_RADIUS, 1.0))
	_expect(loose_exposure < line_exposure, "LOOSE geometry lowers aggregate SIEGE blast exposure without a stat modifier")
	simulation.free()


func _test_spawner_production_and_nearest_rally() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("ConfigureRally"):
		_expect(false, "C# simulation exposes rally configuration")
		simulation.free()
		return
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 0})
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 1, "cell": Vector2i(10, 70), "unit_kind": UNIT_MELEE}), "continuous production fixture adds a completed MELEE spawner")
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 4, "cell": Vector2i(8, 64), "unit_kind": UNIT_MELEE}), "first completed rally is added")
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 4, "cell": Vector2i(28, 64), "unit_kind": UNIT_MELEE}), "second completed rally is added")
	for tick in range(174): simulation.call("Step", 1.0 / 30.0)
	var produced: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(int(produced.unit_count) == 1 and int(produced.unit_kinds[0]) == UNIT_MELEE, "MELEE spawner produces one ungrouped unit after 5.76 seconds")
	_expect(int(produced.unit_rally_ids[0]) == _building_id_at(produced.buildings, Vector2i(8, 64)), "produced unit selects the nearest friendly rally")
	simulation.free()


func _test_rally_advance_launch() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("ConfigureRally"):
		_expect(false, "advance rally API exists")
		simulation.free()
		return
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 4, "cell": Vector2i(20, 64), "unit_kind": UNIT_MELEE}), "advance rally fixture is complete")
	var rally_id := _building_id_at(simulation.call("GetDebugSnapshot").buildings, Vector2i(20, 64))
	_expect(simulation.call("ConfigureRally", rally_id, 0, FORMATION_WEDGE), "rally selects ADVANCE and WEDGE")
	for offset in range(20):
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": offset % 4, "position": Vector2(20.2 + float(offset % 5) * 0.12, 63.2 + float(offset / 5) * 0.10), "exact": true})
	for tick in range(8): simulation.call("Step", 1.0 / 30.0)
	var launched: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(launched.legion_states).has(LEGION_MARCHING), "ADVANCE rally launches at twenty waiting units")
	_expect(PackedInt32Array(launched.legion_formations).has(FORMATION_WEDGE), "launched legion uses the rally formation")
	_expect(PackedInt32Array(launched.unit_legion_ids).count(-1) == 0, "all twenty launch members receive a legion ID")
	simulation.free()


func _test_rally_congestion_still_launches() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 0})
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 1, "cell": Vector2i(6, 74), "unit_kind": UNIT_MELEE}), "left congestion fixture spawner builds")
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 1, "cell": Vector2i(36, 74), "unit_kind": UNIT_MELEE}), "right congestion fixture spawner builds")
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 4, "cell": Vector2i(21, 64), "unit_kind": UNIT_MELEE}), "congestion fixture rally builds")
	for tick in range(2400):
		simulation.call("Step", 1.0 / 30.0)
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(after.legion_states).has(LEGION_MARCHING), "converging rally traffic launches instead of stalling below twenty")
	simulation.free()


func _test_rally_defense_overflow_and_destroy_fallback() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("ConfigureRally"):
		_expect(false, "defense rally API exists")
		simulation.free()
		return
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 4, "cell": Vector2i(20, 64), "unit_kind": UNIT_MELEE}), "defense rally fixture builds")
	var before: Dictionary = simulation.call("GetDebugSnapshot")
	var rally_id := _building_id_at(before.buildings, Vector2i(20, 64))
	_expect(simulation.call("ConfigureRally", rally_id, 1, FORMATION_LINE), "rally selects DEFEND and LINE")
	for offset in range(30):
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(20.1 + float(offset % 6) * 0.10, 63.2 + float(offset / 6) * 0.10), "exact": true})
	for tick in range(8): simulation.call("Step", 1.0 / 30.0)
	var defended: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(defended.legion_states).has(LEGION_GATHERING), "DEFEND rally holds a garrison in formation")
	_expect(PackedInt32Array(defended.legion_states).has(LEGION_MARCHING), "DEFEND overflow launches automatically")
	_expect(_max_int(PackedInt32Array(defended.legion_member_counts)) == GameConfig.RALLY_DEFENSE_CAPACITY, "defense garrison is capped at twenty-eight")
	simulation.call("ApplyDebugCommand", {"op": "damage_building", "id": rally_id, "damage": 9999.0, "team": TEAM_ENEMY})
	simulation.call("Step", 1.0 / 30.0)
	var destroyed: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(destroyed.legion_states).has(LEGION_BROKEN), "destroyed rally breaks its defending legion")
	_expect(PackedInt32Array(destroyed.unit_legion_ids).count(-1) >= GameConfig.RALLY_DEFENSE_CAPACITY, "destroyed rally returns waiting defenders to individual behavior")
	simulation.free()


func _test_legion_broken_transition() -> void:
	var simulation = _new_simulation()
	var template := {"melee": 10, "ranged": 0, "siege": 0, "dragon": 0}
	var created := bool(simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": TEAM_ALLY, "formation": FORMATION_WEDGE, "template": template, "anchor": Vector2(10.5, 30.5)}))
	_expect(created, "debug fixture creates one deployed legion")
	if not created:
		simulation.free()
		return
	var before: Dictionary = simulation.call("GetDebugSnapshot")
	var ids: PackedInt32Array = before.unit_ids
	for index in 8:
		simulation.call("ApplyDebugCommand", {"op": "damage_unit", "id": ids[index], "damage": 9999.0, "team": TEAM_ENEMY})
	simulation.call("Step", 1.0 / 30.0)
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(after.legion_states).has(LEGION_BROKEN), "legion transitions to BROKEN below thirty percent survivors")
	for legion_id in PackedInt32Array(after.unit_legion_ids):
		_expect(legion_id == -1, "BROKEN survivors return to ungrouped fallback behavior")
	simulation.free()


func _test_legion_engage_reform() -> void:
	var simulation = _new_simulation()
	var template := {"melee": 4, "ranged": 2, "siege": 0, "dragon": 0}
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": TEAM_ALLY, "formation": FORMATION_WEDGE, "template": template, "anchor": Vector2(10.5, 23.5)})
	simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": TEAM_ENEMY, "formation": FORMATION_LINE, "template": template, "anchor": Vector2(10.5, 20.8)})
	simulation.call("Step", 1.0 / 30.0)
	var engaged: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(engaged.legion_states).count(2) == 2, "nearby hostile legions enter ENGAGED together")
	var ids: PackedInt32Array = engaged.unit_ids
	var teams: PackedInt32Array = engaged.unit_teams
	for index in ids.size():
		if teams[index] == TEAM_ENEMY: simulation.call("ApplyDebugCommand", {"op": "damage_unit", "id": ids[index], "damage": 9999.0, "team": TEAM_ALLY})
	for tick in 45: simulation.call("Step", 1.0 / 30.0)
	var reformed: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(reformed.legion_states)[0] == LEGION_MARCHING, "surviving legion reforms and resumes MARCHING after combat clears")
	simulation.free()


func _test_ai_continues_after_opening() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("SetAiEnabled"):
		_expect(false, "simulation exposes one AI controller API for either team")
		simulation.free()
		return
	simulation.call("SetAiEnabled", TEAM_ALLY, false)
	simulation.call("SetAiEnabled", TEAM_ENEMY, true)
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "enemy": 1600})
	for tick in range(2400): simulation.call("Step", 1.0 / 30.0)
	var snapshot: Dictionary = simulation.call("GetDebugSnapshot")
	var enemy_spawners := 0
	var enemy_rallies := 0
	for building: Dictionary in snapshot.buildings:
		if int(building.team) != TEAM_ENEMY or bool(building.destroyed): continue
		if int(building.kind) in [1, 3]: enemy_spawners += 1
		if int(building.kind) == 4: enemy_rallies += 1
	_expect(enemy_spawners > 3 and enemy_rallies >= 1, "AI keeps spending after its first three producers and maintains a rally")
	_expect(int(snapshot.enemy_ai_decisions) > 3 and int(snapshot.enemy_ai_builds) >= enemy_spawners + enemy_rallies, "AI exposes continuing decision and successful-build diagnostics")
	simulation.free()


func _test_elevation_rules() -> void:
	var simulation = _new_simulation()
	var elevation := PackedByteArray()
	elevation.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	elevation.fill(0)
	elevation[10 * GameConfig.GRID_COLUMNS + 5] = 1
	elevation[10 * GameConfig.GRID_COLUMNS + 6] = 2
	_expect(simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation}), "debug elevation fixture is accepted")
	_expect(simulation.call("CanGroundStep", Vector2i(4, 10), Vector2i(5, 10)), "one-level slope is passable")
	_expect(not simulation.call("CanGroundStep", Vector2i(4, 10), Vector2i(6, 10)), "two-level cliff is impassable")
	_expect(is_equal_approx(float(simulation.call("GetGroundSpeedMultiplier", Vector2(4.5, 10.5), Vector2(5.5, 10.5))), GameConfig.UPHILL_SPEED_MULTIPLIER), "uphill movement uses 0.7 speed")
	_expect(is_equal_approx(float(simulation.call("GetElevationDamageMultiplier", Vector2(6.5, 10.5), Vector2(4.5, 10.5))), 1.25), "high-to-low damage is 1.25x")
	_expect(is_equal_approx(float(simulation.call("GetElevationDamageMultiplier", Vector2(4.5, 10.5), Vector2(6.5, 10.5))), 0.75), "low-to-high damage is 0.75x")
	var low_range := float(simulation.call("GetUnitAttackRange", UNIT_RANGED, Vector2(4.5, 10.5)))
	var high_range := float(simulation.call("GetUnitAttackRange", UNIT_RANGED, Vector2(5.5, 10.5)))
	_expect(is_equal_approx(high_range - low_range, 0.5), "ranged high ground adds 0.5 cell range")
	simulation.free()


func _test_cross_column_combat_and_air_targeting() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(5.3, 22.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(6.2, 22.0), "exact": true})
	var before: Dictionary = simulation.call("GetDebugSnapshot")
	for tick in range(90): simulation.call("Step", 1.0 / 30.0)
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(_sum_hp(after) < _sum_hp(before), "units in adjacent columns seek and engage")
	simulation.call("Reset")
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(8.5, 22.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_DRAGON, "position": Vector2(8.5, 22.9), "exact": true})
	for tick in range(90): simulation.call("Step", 1.0 / 30.0)
	var air: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(is_equal_approx(_unit_hp_by_team_kind(air, TEAM_ENEMY, UNIT_DRAGON), GameConfig.DRAGON_UNIT_MAX_HP), "basic melee units cannot attack flying dragons")
	simulation.free()


func _test_radius_and_separation() -> void:
	var simulation = _new_simulation()
	_expect(is_equal_approx(float(simulation.call("GetUnitRadius", UNIT_MELEE)), 0.14), "melee radius is authoritative")
	_expect(is_equal_approx(float(simulation.call("GetUnitRadius", UNIT_SIEGE)), 0.26), "SIEGE radius is authoritative")
	_expect(is_equal_approx(float(simulation.call("GetSeparationDistance", UNIT_MELEE, UNIT_SIEGE)), (0.14 + 0.26) * 1.2), "separation distance derives from both radii")
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(8.5, 30.0), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(8.5, 30.0), "exact": true})
	for tick in range(45): simulation.call("Step", 1.0 / 30.0)
	var snapshot: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(Vector2(snapshot.unit_positions[0]).distance_to(Vector2(snapshot.unit_positions[1])) > 0.08, "overlapping allies separate into individually visible units")
	simulation.free()


func _test_tuned_radius_bucket_horizon() -> void:
	var simulation = _new_simulation()
	var tuned: Dictionary = simulation.call("GetMatchSettings")
	tuned.melee.radius = 1.2
	var applied: Dictionary = simulation.call("ConfigureAndReset", tuned)
	_expect(bool(applied.ok), "large-radius separation fixture accepts a valid runtime profile")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "add_building", "team": TEAM_ALLY, "kind": 4, "cell": Vector2i(6, 64), "unit_kind": UNIT_MELEE})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(5.3, 70.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(7.4, 70.5), "exact": true})
	var before: Dictionary = simulation.call("GetDebugSnapshot")
	var initial_distance := Vector2(before.unit_positions[0]).distance_to(Vector2(before.unit_positions[1]))
	for tick in range(30): simulation.call("Step", 1.0 / 30.0)
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	var final_distance := Vector2(after.unit_positions[0]).distance_to(Vector2(after.unit_positions[1]))
	_expect(final_distance > initial_distance + 0.05, "tuned radii separate allies across more than one spatial bucket")
	simulation.free()


func _test_siege_rules_and_aoe() -> void:
	var minimum_sim = _new_simulation()
	minimum_sim.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	var flat := PackedByteArray()
	flat.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	flat.fill(0)
	minimum_sim.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	minimum_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_SIEGE, "position": Vector2(10.5, 20.5), "exact": true})
	minimum_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(10.5, 21.0), "exact": true})
	minimum_sim.call("Step", 1.0 / 30.0)
	_expect(not _has_event(minimum_sim.call("DrainEvents").events, "siege_projectile"), "SIEGE emits no shot when every real hostile is inside minimum range")
	minimum_sim.free()

	var midpoint_sim = _new_simulation()
	var midpoint_settings: Dictionary = midpoint_sim.call("GetMatchSettings")
	midpoint_settings.melee.speed = 0.05
	midpoint_settings.siege.damage = 10.0
	midpoint_settings.siege.flight_seconds = 0.05
	_expect(bool(midpoint_sim.call("ConfigureAndReset", midpoint_settings).ok), "SIEGE midpoint fixture accepts deterministic low-speed settings")
	midpoint_sim.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	midpoint_sim.call("ApplyDebugCommand", {"op": "set_elevation", "values": flat})
	midpoint_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_SIEGE, "position": Vector2(11.5, 24.5), "exact": true})
	midpoint_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(10.3, 20.0), "exact": true})
	midpoint_sim.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(13.3, 20.0), "exact": true})
	midpoint_sim.call("Step", 1.0 / 30.0)
	var launch_events: Array = midpoint_sim.call("DrainEvents").events
	var impact_target := Vector2(-1.0, -1.0)
	for event: Dictionary in launch_events:
		if String(event.get("type", "")) == "siege_projectile":
			impact_target = Vector2(event.position)
	_expect(impact_target.is_equal_approx(Vector2(11.5, 20.5)), "SIEGE selects the empty highest-density cell shared by separated targets")
	for tick in range(2): midpoint_sim.call("Step", 1.0 / 30.0)
	var midpoint_hit: Dictionary = midpoint_sim.call("GetDebugSnapshot")
	var wounded_targets := 0
	for index in PackedInt32Array(midpoint_hit.unit_teams).size():
		if int(midpoint_hit.unit_teams[index]) == TEAM_ENEMY and int(midpoint_hit.unit_kinds[index]) == UNIT_MELEE and float(midpoint_hit.unit_hp[index]) < GameConfig.UNIT_MAX_HP:
			wounded_targets += 1
	_expect(wounded_targets == 2, "SIEGE midpoint impact damages both targets contributing to the dense aim cell")
	midpoint_sim.free()

	var simulation = _new_simulation()
	_expect(is_zero_approx(float(simulation.call("GetSiegeDamageAtDistance", 1.94, 0.13, 55.8))), "SIEGE AoE rejects targets outside blast plus target radius")
	var center_damage := float(simulation.call("GetSiegeDamageAtDistance", 0.0, 0.13, 55.8))
	var edge_damage := float(simulation.call("GetSiegeDamageAtDistance", 1.8, 0.13, 55.8))
	_expect(is_equal_approx(center_damage, 55.8), "SIEGE center hit deals full damage")
	_expect(edge_damage >= 55.8 * 0.4 - 0.01 and edge_damage < center_damage, "SIEGE edge damage linearly falls toward 40 percent")
	for offset in [Vector2.ZERO, Vector2(0.25, 0.0), Vector2(-0.25, 0.0), Vector2(0.0, 0.25), Vector2(0.0, -0.25)]:
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(10.5, 20.5) + offset, "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "schedule_siege", "team": TEAM_ALLY, "origin": Vector2(10.5, 24.0), "target": Vector2(10.5, 20.5), "damage": 55.8, "duration": 0.01})
	simulation.call("Step", 1.0 / 30.0)
	var events: Dictionary = simulation.call("DrainEvents")
	_expect(PackedVector2Array(events.hit_positions).size() == 5, "one SIEGE impact damages all five clustered enemies through spatial buckets")
	_expect(_has_event(events.events, "siege_impact"), "SIEGE impact emits its distinct major FX event")
	simulation.free()


func _test_class_counter_matrix_and_composition() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("GetClassDamageMultiplier"):
		_expect(false, "C# exposes the class counter multiplier table")
		simulation.free()
		return
	var expected := {
		Vector2i(UNIT_RANGED, UNIT_MELEE): 1.7,
		Vector2i(UNIT_MELEE, UNIT_SIEGE): 1.6,
		Vector2i(UNIT_MELEE, UNIT_RANGED): 1.2,
		Vector2i(UNIT_RANGED, UNIT_SIEGE): 0.7,
		Vector2i(UNIT_RANGED, UNIT_DRAGON): 1.2,
		Vector2i(UNIT_DRAGON, UNIT_RANGED): 1.7,
		Vector2i(UNIT_DRAGON, UNIT_SIEGE): 1.5,
		Vector2i(UNIT_MELEE, UNIT_DRAGON): 0.6,
		Vector2i(UNIT_SIEGE, UNIT_MELEE): 1.5,
	}
	for pair: Vector2i in expected:
		_expect(is_equal_approx(float(simulation.call("GetClassDamageMultiplier", pair.x, pair.y)), float(expected[pair])), "class counter %d to %d matches the locked table" % [pair.x, pair.y])
	var elevation := PackedByteArray()
	elevation.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	elevation.fill(0)
	elevation[20 * GameConfig.GRID_COLUMNS + 10] = 1
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(10.5, 20.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_RANGED, "position": Vector2(10.5, 21.0), "exact": true})
	simulation.call("Step", 1.0 / 30.0)
	var hit: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(is_equal_approx(_unit_hp_by_team_kind(hit, TEAM_ENEMY, UNIT_RANGED), GameConfig.RANGED_UNIT_MAX_HP - GameConfig.UNIT_ATTACK_DAMAGE * 1.2 * 1.25), "class and high-ground damage multipliers compose multiplicatively")
	var events: Dictionary = simulation.call("DrainEvents")
	_expect(PackedByteArray(events.hit_high_ground).size() > 0 and (int(events.hit_high_ground[0]) & 2) != 0, "favorable counter hits carry the strong-hit packed flag")
	simulation.free()


func _test_territory_cache_and_terminal_result() -> void:
	var simulation = _new_simulation()
	simulation.call("SetProfilingEnabled", true)
	var initial: Dictionary = simulation.call("GetHudSnapshot")
	var initial_version := int(initial.board_version)
	for tick in range(5): simulation.call("Step", 1.0 / 30.0)
	var before_interval: Dictionary = simulation.call("GetHudSnapshot")
	_expect(int(before_interval.board_version) == initial_version, "territory snapshot is not rebuilt every fixed tick")
	simulation.call("Step", 1.0 / 30.0)
	var profile: Dictionary = simulation.call("GetProfileSnapshot")
	_expect(int(profile.tick_count) >= 6, "fixed-step core accounts for all simulation ticks")
	var debug: Dictionary = simulation.call("GetDebugSnapshot")
	var board_version_before_hit := int(simulation.call("GetHudSnapshot").board_version)
	simulation.call("ApplyDebugCommand", {"op": "damage_building", "id": int(debug.enemy_hq_id), "damage": 10.0, "team": TEAM_ALLY})
	var damaged_board: Dictionary = simulation.call("GetBoardSnapshot")
	_expect(int(damaged_board.version) > board_version_before_hit, "nonlethal building damage invalidates the cached board snapshot")
	simulation.call("ApplyDebugCommand", {"op": "damage_building", "id": int(debug.enemy_hq_id), "damage": 99999.0, "team": TEAM_ALLY})
	var won: Dictionary = simulation.call("GetHudSnapshot")
	_expect(String(won.result) == "VICTORY", "destroying enemy HQ ends the match immediately")
	simulation.free()


func _test_packed_events_and_profile() -> void:
	var simulation = _new_simulation()
	simulation.call("SetProfilingEnabled", true)
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_RANGED, "position": Vector2(8.5, 22.8), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_MELEE, "position": Vector2(8.5, 21.6), "exact": true})
	for tick in range(30): simulation.call("Step", 1.0 / 30.0)
	var channels: Dictionary = simulation.call("DrainEvents")
	_expect(channels.hit_positions is PackedVector2Array, "hit channel crosses the language boundary as PackedVector2Array")
	_expect(channels.shot_origins is PackedVector2Array, "shot channel crosses the language boundary as PackedVector2Array")
	var profile: Dictionary = simulation.call("GetProfileSnapshot")
	_expect(int(profile.tick_count) == 30 and int(profile.worst_tick_usec) >= 0, "C# profiling exposes tick and worst timing in one snapshot")
	simulation.free()


func _sum_hp(snapshot: Dictionary) -> float:
	var total := 0.0
	for hp in snapshot.unit_hp: total += float(hp)
	return total


func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if String(event.get("type", "")) == event_type: return true
	return false


func _count_event(events: Array, event_type: String) -> int:
	var count := 0
	for event in events:
		if String(event.get("type", "")) == event_type: count += 1
	return count


func _building_id_at(buildings: Array, cell: Vector2i) -> int:
	for building: Dictionary in buildings:
		if Vector2i(building.cell) == cell:
			return int(building.id)
	return -1


func _building_by_id(buildings: Array, building_id: int) -> Dictionary:
	for building: Dictionary in buildings:
		if int(building.id) == building_id:
			return building
	return {}


func _max_int(values: PackedInt32Array) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result


func _unit_hp_by_team_kind(snapshot: Dictionary, team: int, kind: int) -> float:
	for index in PackedInt32Array(snapshot.unit_teams).size():
		if int(snapshot.unit_teams[index]) == team and int(snapshot.unit_kinds[index]) == kind:
			return float(snapshot.unit_hp[index])
	return -1.0


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
