extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")

var failures: Array[String] = []


func run_all(tree: SceneTree) -> Array[String]:
	run_siege_contracts()
	await _test_determinism_fixture(tree)
	await _test_siege_production_and_render_flag(tree)
	_test_bulk_boundary_contract()
	return failures


func run_siege_contracts() -> Array[String]:
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_RANGE, 7.0), "SIEGE maximum range is doubled to 7.0 cells")
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_DAMAGE, 55.8), "SIEGE base damage is multiplied by 1.8")
	_expect(is_equal_approx(GameConfig.SIEGE_PRODUCTION_INTERVAL, GameConfig.SPAWNER_PRODUCTION_INTERVAL * 3.0), "SIEGE production rate is one third of normal")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	_expect(renderer_source.contains("atlas_data.a") and renderer_source.contains("1.0 - UV.y"), "shared atlas shader supports a per-instance vertical flip")
	var snapshot_source := FileAccess.get_file_as_string("res://scripts/BattleSimulation.Snapshots.cs")
	_expect(snapshot_source.contains("kind == UnitSiege ? 1f : 0f"), "SIEGE records explicitly opt into the vertical flip")
	return failures


func _test_determinism_fixture(tree: SceneTree) -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/gdscript_determinism.json"))
	_expect(int(expected.seed) == 731942, "GDScript golden fixture uses the C# reset seed")
	var simulation = await _new_simulation(tree)
	for building: Dictionary in expected.inputs:
		var coordinates: Array = building.cell
		_expect(simulation.call("ApplyDebugCommand", {
			"op": "add_building",
			"team": int(building.team),
			"kind": 1,
			"cell": Vector2i(int(coordinates[0]), int(coordinates[1])),
			"unit_kind": int(building.kind),
		}), "determinism setup building is accepted")
	var elapsed_ticks := 0
	for checkpoint: Dictionary in expected.checkpoints:
		var target_tick := int(checkpoint.tick)
		while elapsed_ticks < target_tick:
			simulation.call("Step", 1.0 / 30.0)
			elapsed_ticks += 1
		var actual: Dictionary = simulation.call("GetDebugSnapshot")
		var counts: Array = checkpoint.counts
		_expect(_count_units(actual, 1, 0) == int(counts[0]), "tick %d enemy melee count matches GDScript golden" % target_tick)
		_expect(_count_units(actual, 1, 1) == int(counts[1]), "tick %d enemy ranged count matches GDScript golden" % target_tick)
		_expect(_count_units(actual, 2, 0) == int(counts[4]), "tick %d ally melee count matches GDScript golden" % target_tick)
		_expect(_count_units(actual, 2, 1) == int(counts[5]), "tick %d ally ranged count matches GDScript golden" % target_tick)
		_expect(int(actual.ally_gold) == int(checkpoint.ally_gold), "tick %d ally gold matches GDScript golden" % target_tick)
		_expect(int(actual.enemy_gold) == int(checkpoint.enemy_gold), "tick %d enemy gold matches GDScript golden" % target_tick)
		_expect(abs(float(actual.ally_occupancy) - float(checkpoint.ally_occupancy)) <= 0.0001, "tick %d occupancy matches GDScript golden" % target_tick)
		_expect(abs(float(actual.time_remaining) - float(checkpoint.time_remaining)) <= 0.002, "tick %d timer matches GDScript golden" % target_tick)
		_expect(abs(_building_hp(actual.buildings, int(actual.ally_hq_id)) - float(checkpoint.ally_hq_hp)) <= 0.001, "tick %d allied HQ HP matches GDScript golden" % target_tick)
		_expect(abs(_building_hp(actual.buildings, int(actual.enemy_hq_id)) - float(checkpoint.enemy_hq_hp)) <= 0.001, "tick %d enemy HQ HP matches GDScript golden" % target_tick)
		_expect(String(actual.result) == String(checkpoint.result), "tick %d terminal result matches GDScript golden" % target_tick)
	simulation.queue_free()


func _test_siege_production_and_render_flag(tree: SceneTree) -> void:
	var simulation = await _new_simulation(tree)
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": 2, "kind": 1, "cell": Vector2i(8, 35), "unit_kind": 0}), "normal spawner is added")
	_expect(simulation.call("ApplyDebugCommand", {"op": "add_building", "team": 2, "kind": 1, "cell": Vector2i(13, 35), "unit_kind": 3}), "SIEGE spawner is added")
	for tick in range(49):
		simulation.call("Step", 1.0 / 30.0)
	var after_normal: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(_count_units(after_normal, 2, 0) == 1, "normal spawner produces once after 1.6 seconds")
	_expect(_count_units(after_normal, 2, 3) == 0, "SIEGE spawner has not produced at the normal interval")
	for tick in range(96):
		simulation.call("Step", 1.0 / 30.0)
	var after_siege: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(_count_units(after_siege, 2, 3) == 1, "SIEGE spawner produces once after triple interval")
	var render: Dictionary = simulation.call("GetRenderSnapshot")
	var unit_buffer: PackedFloat32Array = render.infantry_buffer
	var flipped_siege_found := false
	for index in range(int(render.infantry_count)):
		flipped_siege_found = flipped_siege_found or unit_buffer[index * 16 + 15] > 0.5
	_expect(flipped_siege_found, "SIEGE instance carries vertical flip custom data")
	simulation.queue_free()


func _test_bulk_boundary_contract() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	for forbidden in ["unit_positions", "unit_hp", "unit_states", "unit_target_ids"]:
		_expect(not main_source.contains(forbidden), "main does not pull per-unit field %s" % forbidden)
		_expect(not renderer_source.contains(forbidden), "renderer does not pull per-unit field %s" % forbidden)
	_expect(renderer_source.contains("call(\"GetRenderSnapshot\")"), "renderer consumes one bulk render snapshot")
	_expect(renderer_source.contains("RenderingServer.multimesh_set_buffer"), "renderer uploads packed buffers directly")


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
