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
	_test_config_and_initial_state()
	_test_build_and_economy()
	_test_elevation_rules()
	_test_cross_column_combat_and_air_targeting()
	_test_radius_and_separation()
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


func _new_simulation():
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	return simulation


func _test_config_and_initial_state() -> void:
	var simulation = _new_simulation()
	var config: Dictionary = simulation.call("GetConfigSnapshot")
	var debug: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(int(config.grid_columns) == 22 and int(config.grid_rows) == 44, "map remains the four-times 22x44 battlefield")
	_expect(is_equal_approx(float(config.siege_range), 7.0), "SIEGE range is 7.0 cells")
	_expect(is_equal_approx(float(config.siege_damage), 55.8), "SIEGE damage is 55.8")
	_expect(is_equal_approx(float(config.match_duration), 420.0) and is_equal_approx(float(config.occupancy_win_ratio), 0.92), "match tempo exposes seven minutes and ninety-two percent occupancy")
	_expect(is_equal_approx(float(config.passive_income_per_second), 2.25) and is_equal_approx(float(config.hq_max_hp), 2400.0), "slower economy and HQ durability are exposed by C#")
	_expect(int(debug.unit_count) == 0, "match starts without unit Nodes or unit objects")
	_expect(is_equal_approx(float(debug.ally_occupancy), 0.5), "initial territory is split 50/50")
	_expect(simulation.call("TerrainPathsValid"), "seeded symmetric elevation map is reachable")
	var elevation: PackedByteArray = debug.elevation
	for row in range(GameConfig.GRID_ROWS / 2):
		for col in range(GameConfig.GRID_COLUMNS):
			var mirror := (GameConfig.GRID_ROWS - 1 - row) * GameConfig.GRID_COLUMNS + (GameConfig.GRID_COLUMNS - 1 - col)
			_expect(elevation[row * GameConfig.GRID_COLUMNS + col] == elevation[mirror], "terrain elevation is point-mirrored for fairness")
	simulation.free()


func _test_build_and_economy() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 35), BUILD_MELEE), "MELEE spawner builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(6, 35), BUILD_RANGED), "RANGED spawner builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(12, 35), BUILD_SIEGE), "SIEGE spawner builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(15, 35), BUILD_DRAGON), "DRAGON lair builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(9, 34), BUILD_RALLY), "RALLY_POINT builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(9, 41), BUILD_TOWER), "defense tower builds inside allied HQ 5x5")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 30), BUILD_TOWER), "defense tower rejects cells outside HQ 5x5")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(9, 34), BUILD_RALLY), "occupied rally cell rejects a duplicate")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 4), BUILD_RALLY), "enemy territory rejects allied rally construction")
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
	var line_hits := 0
	var loose_hits := 0
	for slot in line:
		if Vector2(slot).length() <= GameConfig.SIEGE_BLAST_RADIUS + GameConfig.MELEE_UNIT_RADIUS: line_hits += 1
	for slot in loose:
		if Vector2(slot).length() <= GameConfig.SIEGE_BLAST_RADIUS + GameConfig.MELEE_UNIT_RADIUS: loose_hits += 1
	_expect(loose_hits < line_hits, "LOOSE geometry lowers average SIEGE blast exposure without a stat modifier")
	simulation.free()


func _test_spawner_production_and_nearest_rally() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("ConfigureRally"):
		_expect(false, "C# simulation exposes rally configuration")
		simulation.free()
		return
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 0})
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(5, 35), BUILD_MELEE), "continuous production fixture builds a MELEE spawner")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(4, 32), BUILD_RALLY), "first rally builds")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(14, 32), BUILD_RALLY), "second rally builds")
	for tick in range(88): simulation.call("Step", 1.0 / 30.0)
	var produced: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(int(produced.unit_count) == 1 and int(produced.unit_kinds[0]) == UNIT_MELEE, "MELEE spawner produces one ungrouped unit after 2.88 seconds")
	_expect(int(produced.unit_rally_ids[0]) == _building_id_at(produced.buildings, Vector2i(4, 32)), "produced unit selects the nearest friendly rally")
	simulation.free()


func _test_rally_advance_launch() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("ConfigureRally"):
		_expect(false, "advance rally API exists")
		simulation.free()
		return
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(10, 32), BUILD_RALLY), "advance rally fixture builds")
	var rally_id := _building_id_at(simulation.call("GetDebugSnapshot").buildings, Vector2i(10, 32))
	_expect(simulation.call("ConfigureRally", rally_id, 0, FORMATION_WEDGE), "rally selects ADVANCE and WEDGE")
	for offset in range(10):
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": offset % 4, "position": Vector2(10.2 + float(offset % 3) * 0.12, 31.8 + float(offset / 3) * 0.10), "exact": true})
	for tick in range(8): simulation.call("Step", 1.0 / 30.0)
	var launched: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(launched.legion_states).has(LEGION_MARCHING), "ADVANCE rally launches at ten waiting units")
	_expect(PackedInt32Array(launched.legion_formations).has(FORMATION_WEDGE), "launched legion uses the rally formation")
	_expect(PackedInt32Array(launched.unit_legion_ids).count(-1) == 0, "all ten launch members receive a legion ID")
	simulation.free()


func _test_rally_congestion_still_launches() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 0})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 37), BUILD_MELEE), "left congestion fixture spawner builds")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(18, 37), BUILD_MELEE), "right congestion fixture spawner builds")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(10, 32), BUILD_RALLY), "congestion fixture rally builds")
	for tick in range(1800):
		simulation.call("Step", 1.0 / 30.0)
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(after.legion_states).has(LEGION_MARCHING), "converging rally traffic launches instead of stalling below ten")
	simulation.free()


func _test_rally_defense_overflow_and_destroy_fallback() -> void:
	var simulation = _new_simulation()
	if not simulation.has_method("ConfigureRally"):
		_expect(false, "defense rally API exists")
		simulation.free()
		return
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(10, 32), BUILD_RALLY), "defense rally fixture builds")
	var before: Dictionary = simulation.call("GetDebugSnapshot")
	var rally_id := _building_id_at(before.buildings, Vector2i(10, 32))
	_expect(simulation.call("ConfigureRally", rally_id, 1, FORMATION_LINE), "rally selects DEFEND and LINE")
	for offset in range(16):
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(10.1 + float(offset % 4) * 0.10, 31.7 + float(offset / 4) * 0.10), "exact": true})
	for tick in range(8): simulation.call("Step", 1.0 / 30.0)
	var defended: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(defended.legion_states).has(LEGION_GATHERING), "DEFEND rally holds a garrison in formation")
	_expect(PackedInt32Array(defended.legion_states).has(LEGION_MARCHING), "DEFEND overflow launches automatically")
	_expect(_max_int(PackedInt32Array(defended.legion_member_counts)) == GameConfig.RALLY_DEFENSE_CAPACITY, "defense garrison is capped at fourteen")
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


func _test_siege_rules_and_aoe() -> void:
	var simulation = _new_simulation()
	_expect(is_zero_approx(float(simulation.call("GetSiegeDamageAtDistance", 1.04, 0.13, 55.8))), "SIEGE AoE rejects targets outside blast plus target radius")
	var center_damage := float(simulation.call("GetSiegeDamageAtDistance", 0.0, 0.13, 55.8))
	var edge_damage := float(simulation.call("GetSiegeDamageAtDistance", 0.9, 0.13, 55.8))
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


func _building_id_at(buildings: Array, cell: Vector2i) -> int:
	for building: Dictionary in buildings:
		if Vector2i(building.cell) == cell:
			return int(building.id)
	return -1


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
