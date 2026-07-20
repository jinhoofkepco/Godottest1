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

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_and_initial_state()
	_test_build_and_economy()
	_test_elevation_rules()
	_test_cross_column_combat_and_air_targeting()
	_test_radius_and_separation()
	_test_siege_rules_and_aoe()
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
	_expect(is_equal_approx(float(config.siege_production_interval), 4.8), "SIEGE production interval is 4.8 seconds")
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
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 35), BUILD_MELEE), "ally can build on owned territory")
	var hud: Dictionary = simulation.call("GetHudSnapshot")
	_expect(int(hud.ally_gold) == GameConfig.START_GOLD - GameConfig.SPAWNER_COST, "melee build deducts exactly its cost")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 35), BUILD_MELEE), "occupied building cell rejects a duplicate")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 4), BUILD_MELEE), "enemy territory rejects allied construction")
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(9, 41), BUILD_TOWER), "defense tower builds inside allied HQ 5x5")
	_expect(not simulation.call("TryBuild", TEAM_ALLY, Vector2i(3, 30), BUILD_TOWER), "defense tower rejects cells outside HQ 5x5")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(16, 35), BUILD_DRAGON), "dragon lair builds on owned territory")
	_expect(simulation.call("TryBuild", TEAM_ALLY, Vector2i(18, 35), BUILD_SIEGE), "SIEGE spawner builds on owned territory")
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
	_expect(is_equal_approx(float(air.unit_hp[1]), GameConfig.DRAGON_UNIT_MAX_HP), "basic melee units cannot attack flying dragons")
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


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
