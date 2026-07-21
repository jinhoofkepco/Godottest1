extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")

var failures: Array[String] = []


func run_all(tree: SceneTree) -> Array[String]:
	run_siege_contracts()
	await _test_determinism_fixture(tree)
	await _test_spawner_rally_and_render_flag(tree)
	await _test_board_delta_boundary(tree)
	_test_bulk_boundary_contract()
	return failures


func run_siege_contracts() -> Array[String]:
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_RANGE, 14.0), "SIEGE maximum range is doubled again to 14.0 cells")
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_DAMAGE, 55.8), "SIEGE base damage is multiplied by 1.8")
	_expect(is_equal_approx(GameConfig.SIEGE_BLAST_RADIUS, 1.8), "SIEGE blast radius is doubled to 1.8 cells")
	_expect(is_equal_approx(GameConfig.MATCH_DURATION, 420.0), "the slower match timer is seven minutes")
	_expect(is_equal_approx(GameConfig.OCCUPANCY_WIN_RATIO, 0.92), "territory victory requires ninety-two percent")
	_expect(is_equal_approx(GameConfig.PASSIVE_INCOME_PER_SECOND, 2.25), "passive income is reduced to seventy-five percent")
	_expect(GameConfig.GRID_COLUMNS == 44 and GameConfig.GRID_ROWS == 88, "battlefield is expanded to 44 by 88")
	_expect(is_equal_approx(GameConfig.HQ_MAX_HP, 12000.0), "both HQs use five-times building durability")
	_expect(is_equal_approx(GameConfig.RANGED_UNIT_MAX_HP, 20.4), "RANGED HP is reduced to sixty percent")
	_expect(is_equal_approx(GameConfig.UNIT_SPEED, 1.015) and is_equal_approx(GameConfig.RANGED_UNIT_SPEED, 0.875) and is_equal_approx(GameConfig.SIEGE_UNIT_SPEED, 0.56) and is_equal_approx(GameConfig.DRAGON_UNIT_SPEED, 1.19), "all class speeds are reduced to seventy percent")
	_expect(is_equal_approx(GameConfig.SPAWNER_PRODUCTION_INTERVAL, 5.76), "MELEE and RANGED keep the slowed 5.76-second production interval")
	_expect(absf(GameConfig.SIEGE_PRODUCTION_INTERVAL - 12.342857) <= 0.0001, "SIEGE production is forty percent faster than its prior 17.28-second interval")
	_expect(is_equal_approx(GameConfig.DRAGON_PRODUCTION_INTERVAL, 45.0) and GameConfig.DRAGON_PRODUCTION_BATCH == 2, "DRAGON production emits two units every 45 seconds")
	_expect(is_equal_approx(GameConfig.DRAGON_UNIT_MAX_HP, 520.0) and is_equal_approx(GameConfig.DRAGON_UNIT_ATTACK_DAMAGE, 36.0), "DRAGON HP and damage are doubled")
	_expect(GameConfig.RALLY_LAUNCH_SIZE == 20 and GameConfig.RALLY_DEFENSE_CAPACITY == 28, "rally launch and defense thresholds are doubled")
	_expect(GameConfig.TEAM_UNIT_CAP == 300 and GameConfig.AI_INCOME_LEVEL_DEFAULT == 3, "population cap and enemy economy default are locked")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	_expect(renderer_source.contains("atlas_data.a") and renderer_source.contains("1.0 - UV.y"), "shared atlas shader supports a per-instance vertical flip")
	var snapshot_source := FileAccess.get_file_as_string("res://scripts/BattleSimulation.Snapshots.cs")
	_expect(snapshot_source.contains("kind == UnitSiege ? 1f : 0f"), "SIEGE records explicitly opt into the vertical flip")
	return failures


func _test_determinism_fixture(tree: SceneTree) -> void:
	var first = await _new_simulation(tree)
	var second = await _new_simulation(tree)
	for simulation in [first, second]:
		simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 1000})
		simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
		_expect(simulation.call("TryBuild", 2, Vector2i(12, 70), 0) and simulation.call("TryBuild", 2, Vector2i(12, 64), 5), "determinism setup accepts the same ally spawner and rally")
		_expect(simulation.call("TryBuild", 1, Vector2i(31, 17), 0) and simulation.call("TryBuild", 1, Vector2i(31, 23), 5), "determinism setup accepts the mirrored enemy spawner and rally")
	for tick in 450:
		first.call("Step", 1.0 / 30.0)
		second.call("Step", 1.0 / 30.0)
	var a: Dictionary = first.call("GetDebugSnapshot")
	var b: Dictionary = second.call("GetDebugSnapshot")
	_expect(a.unit_ids == b.unit_ids and a.unit_kinds == b.unit_kinds and a.unit_legion_ids == b.unit_legion_ids and a.unit_rally_ids == b.unit_rally_ids, "same seed and inputs produce identical rally and legion membership after 450 ticks")
	_expect(a.unit_positions == b.unit_positions and a.legion_anchors == b.legion_anchors, "same seed and inputs produce identical unit and legion positions")
	_expect(int(a.ally_gold) == int(b.ally_gold) and is_equal_approx(float(a.ally_occupancy), float(b.ally_occupancy)), "same seed preserves economic and territory state")
	first.queue_free()
	second.queue_free()


func _test_spawner_rally_and_render_flag(tree: SceneTree) -> void:
	var simulation = await _new_simulation(tree)
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	_expect(simulation.call("TryBuild", 2, Vector2i(16, 70), 0), "continuous MELEE spawner is added")
	_expect(simulation.call("TryBuild", 2, Vector2i(16, 64), 5), "advance rally is added")
	for tick in range(356):
		simulation.call("Step", 1.0 / 30.0)
	var after_first: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(_count_units(after_first, 2, 0) == 1 and int(after_first.unit_rally_ids[0]) > 0, "completed spawner produces and assigns one member after construction plus 5.76 seconds")
	for index in 20:
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": 2, "kind": index % 2, "position": Vector2(16.2 + float(index % 5) * 0.1, 63.2 + float(index / 5) * 0.1), "exact": true})
	for tick in 8: simulation.call("Step", 1.0 / 30.0)
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": 2, "kind": 1, "cell": Vector2i(22, 70), "unit_kind": 3}), "completed SIEGE spawner fixture is added")
	var siege_building_id := _building_id_at(simulation.call("GetDebugSnapshot").buildings, Vector2i(22, 70))
	simulation.call("ApplyDebugCommand", {"op": "set_building_spawn_timer", "id": siege_building_id, "value": 0.0})
	simulation.call("Step", 1.0 / 30.0)
	var render: Dictionary = simulation.call("GetRenderSnapshot")
	var unit_buffer: PackedFloat32Array = render.infantry_buffer
	var flipped_siege_found := false
	for index in range(int(render.infantry_count)):
		flipped_siege_found = flipped_siege_found or unit_buffer[index * 16 + 15] > 0.5
	_expect(flipped_siege_found, "SIEGE instance carries vertical flip custom data")
	_expect(int(render.legion_banner_count) >= 1, "completed legion publishes a packed banner")
	simulation.queue_free()


func _test_bulk_boundary_contract() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	for forbidden in ["unit_positions", "unit_hp", "unit_states", "unit_target_ids"]:
		_expect(not main_source.contains(forbidden), "main does not pull per-unit field %s" % forbidden)
		_expect(not renderer_source.contains(forbidden), "renderer does not pull per-unit field %s" % forbidden)
	_expect(renderer_source.contains("call(\"GetRenderSnapshot\")"), "renderer consumes one bulk render snapshot")
	_expect(renderer_source.contains("RenderingServer.multimesh_set_buffer"), "renderer uploads packed buffers directly")
	_expect(main_source.contains("call(\"GetBoardVersion\")"), "main probes the cheap board version before requesting board data")
	_expect(main_source.contains("call(\"GetBoardDelta\")"), "main requests a board delta after initial sync")


func _test_board_delta_boundary(tree: SceneTree) -> void:
	var simulation = await _new_simulation(tree)
	_expect(simulation.has_method("GetBoardVersion"), "C# exposes a cheap board version getter")
	_expect(simulation.has_method("GetBoardDelta"), "C# exposes a packed board delta channel")
	if not simulation.has_method("GetBoardVersion") or not simulation.has_method("GetBoardDelta"):
		simulation.queue_free()
		return
	var initial: Dictionary = simulation.call("GetBoardSnapshot")
	var initial_version := int(simulation.call("GetBoardVersion"))
	_expect(int(initial.version) == initial_version, "initial board snapshot and cheap version agree")
	var indices := PackedInt32Array()
	var owners := PackedInt32Array()
	for offset in 30:
		indices.append(5 * GameConfig.GRID_COLUMNS + offset % GameConfig.GRID_COLUMNS + floori(float(offset) / GameConfig.GRID_COLUMNS) * GameConfig.GRID_COLUMNS)
		owners.append(2)
	_expect(simulation.call("ApplyDebugCommand", {"op": "force_ownership_delta", "indices": indices, "owners": owners}), "30-cell territory delta fixture is accepted")
	_expect(int(simulation.call("GetBoardVersion")) == initial_version + 1, "one batch increments the board version once")
	var delta: Dictionary = simulation.call("GetBoardDelta")
	_expect(PackedInt32Array(delta.ownership_indices).size() == 30, "board delta contains exactly 30 changed cell indices")
	_expect(PackedInt32Array(delta.ownership_owners).size() == 30, "board delta contains exactly 30 new owners")
	var drained: Dictionary = simulation.call("GetBoardDelta")
	_expect(PackedInt32Array(drained.ownership_indices).is_empty(), "ownership delta ownership is transferred and drained")
	_expect(PackedInt32Array(drained.ownership_owners).is_empty(), "owner values are drained with their indices")
	var building_cell := Vector2i(8, 70)
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": 2, "kind": 1, "cell": building_cell, "unit_kind": 0}), "building delta fixture is accepted")
	var building_delta: Dictionary = simulation.call("GetBoardDelta")
	_expect(PackedInt32Array(building_delta.blocked_indices) == PackedInt32Array([building_cell.y * GameConfig.GRID_COLUMNS + building_cell.x]), "building delta identifies only its changed blocked cell")
	_expect(PackedInt32Array(building_delta.blocked_values) == PackedInt32Array([1]), "new building marks its tile unavailable")
	simulation.queue_free()


func _new_simulation(tree: SceneTree):
	var simulation = SIMULATION_SCENE.instantiate()
	tree.root.add_child(simulation)
	simulation.call("Reset")
	await tree.process_frame
	return simulation


func _count_units(snapshot: Dictionary, team: int, kind: int) -> int:
	var count := 0
	var teams: PackedInt32Array = snapshot.unit_teams
	var kinds: PackedInt32Array = snapshot.unit_kinds
	for index in range(teams.size()):
		if teams[index] == team and kinds[index] == kind:
			count += 1
	return count


func _building_hp(buildings: Array, building_id: int) -> float:
	for building in buildings:
		if int(building.id) == building_id:
			return float(building.hp)
	return 0.0


func _building_id_at(buildings: Array, cell: Vector2i) -> int:
	for building: Dictionary in buildings:
		if Vector2i(building.cell) == cell:
			return int(building.id)
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
