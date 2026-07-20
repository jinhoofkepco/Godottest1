extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")

var failures: Array[String] = []


func run_all(tree: SceneTree) -> Array[String]:
	run_siege_contracts()
	await _test_determinism_fixture(tree)
	await _test_legion_production_and_render_flag(tree)
	await _test_board_delta_boundary(tree)
	_test_bulk_boundary_contract()
	return failures


func run_siege_contracts() -> Array[String]:
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_RANGE, 7.0), "SIEGE maximum range is doubled to 7.0 cells")
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_DAMAGE, 55.8), "SIEGE base damage is multiplied by 1.8")
	_expect(is_equal_approx(GameConfig.BARRACKS_PRODUCTION_INTERVAL, 1.2), "all legion roles share the barracks 1.2 second production cadence")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	_expect(renderer_source.contains("atlas_data.a") and renderer_source.contains("1.0 - UV.y"), "shared atlas shader supports a per-instance vertical flip")
	var snapshot_source := FileAccess.get_file_as_string("res://scripts/BattleSimulation.Snapshots.cs")
	_expect(snapshot_source.contains("kind == UnitSiege ? 1f : 0f"), "SIEGE records explicitly opt into the vertical flip")
	return failures


func _test_determinism_fixture(tree: SceneTree) -> void:
	var first = await _new_simulation(tree)
	var second = await _new_simulation(tree)
	var template := {"melee": 4, "ranged": 4, "siege": 1, "dragon": 1}
	for simulation in [first, second]:
		simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 1000})
		simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
		_expect(simulation.call("TryBuildBarracks", 2, Vector2i(6, 35), template, 0), "determinism setup accepts the same barracks input")
		_expect(simulation.call("TryBuildBarracks", 1, Vector2i(15, 8), template, 2), "determinism setup accepts the mirrored enemy barracks")
	for tick in 450:
		first.call("Step", 1.0 / 30.0)
		second.call("Step", 1.0 / 30.0)
	var a: Dictionary = first.call("GetDebugSnapshot")
	var b: Dictionary = second.call("GetDebugSnapshot")
	_expect(a.unit_ids == b.unit_ids and a.unit_kinds == b.unit_kinds and a.unit_legion_ids == b.unit_legion_ids, "same seed and inputs produce identical legion membership after 450 ticks")
	_expect(a.unit_positions == b.unit_positions and a.legion_anchors == b.legion_anchors, "same seed and inputs produce identical unit and legion positions")
	_expect(int(a.ally_gold) == int(b.ally_gold) and is_equal_approx(float(a.ally_occupancy), float(b.ally_occupancy)), "same seed preserves economic and territory state")
	first.queue_free()
	second.queue_free()


func _test_legion_production_and_render_flag(tree: SceneTree) -> void:
	var simulation = await _new_simulation(tree)
	simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	var template := {"melee": 2, "ranged": 1, "siege": 1, "dragon": 0}
	_expect(simulation.call("TryBuildBarracks", 2, Vector2i(8, 35), template, 0), "configured barracks is added")
	for tick in range(37):
		simulation.call("Step", 1.0 / 30.0)
	var after_first: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(_count_units(after_first, 2, 0) == 1, "barracks produces the first template member after 1.2 seconds")
	for tick in range(108):
		simulation.call("Step", 1.0 / 30.0)
	var completed: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(_count_units(completed, 2, 0) == 2 and _count_units(completed, 2, 1) == 1 and _count_units(completed, 2, 3) == 1, "barracks produces the complete role-ordered legion template")
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
	var building_cell := Vector2i(8, 35)
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
