extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")

var failures: Array[String] = []


func run() -> Array[String]:
	_test_lake_ground_detour_and_dragon_crossing()
	_test_flow_detour()
	_test_diagonal_corner_and_radius_clearance()
	_test_physical_cliff_protrusion_detour()
	_test_legion_cliff_protrusion_detour()
	_test_wait_enter_and_release()
	_test_bulk_boundary_source()
	return failures


func _test_lake_ground_detour_and_dragon_crossing() -> void:
	var simulation = _new_simulation()
	_expect(int(simulation.call("WaterComponentCount")) == 1, "central lake is one connected body")
	_expect(simulation.call("TerrainPathsValid"), "ground flow retains reachable corridors around the lake")
	var shore := Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2 - GameConfig.LAKE_RADIUS_Y - 1)
	var water := shore + Vector2i.DOWN
	_expect(not simulation.call("CanGroundStep", shore, water), "ground movement rejects the lake edge")
	_expect(simulation.call("CanFlyingStep", shore, water), "flying movement ignores the lake edge")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": 2, "kind": 2, "position": Vector2(22.5, 55.5), "exact": true})
	for tick in range(450): simulation.call("Step", 1.0 / 30.0)
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(float(after.unit_positions[0].y) < float(GameConfig.GRID_ROWS / 2), "dragon flies directly across the central lake toward the enemy HQ")
	simulation.free()


func _new_simulation():
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	return simulation


func _test_flow_detour() -> void:
	var simulation = _new_simulation()
	var elevation := PackedByteArray()
	elevation.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	elevation.fill(0)
	var wall_row := GameConfig.GRID_ROWS / 2
	for col in range(GameConfig.GRID_COLUMNS):
		if col != 4 and col != 17:
			elevation[wall_row * GameConfig.GRID_COLUMNS + col] = 2
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	simulation.call("ApplyDebugCommand", {"op": "rebuild_flow"})
	var cost := float(simulation.call("GetFlowCost", 2, Vector2i(10, wall_row + 3)))
	var direction := Vector2(simulation.call("GetFlowDirection", 2, Vector2i(10, wall_row + 3)))
	_expect(cost < INF and direction.length() > 0.5, "flow field routes around a cliff wall through a pass")
	_expect(not simulation.call("CanGroundStep", Vector2i(10, wall_row + 1), Vector2i(10, wall_row)), "cliff wall blocks direct crossing")
	simulation.free()


func _test_diagonal_corner_and_radius_clearance() -> void:
	var simulation = _new_simulation()
	var elevation := PackedByteArray()
	elevation.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	elevation.fill(0)
	elevation[20 * GameConfig.GRID_COLUMNS + 21] = 2
	elevation[19 * GameConfig.GRID_COLUMNS + 20] = 2
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	_expect(not simulation.call("CanGroundStep", Vector2i(20, 20), Vector2i(21, 19)), "diagonal transition requires both orthogonal legs to be passable")
	elevation.fill(0)
	elevation[10 * GameConfig.GRID_COLUMNS + 11] = 2
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	_expect(simulation.call("IsGroundPositionClear", Vector2(10.5, 10.5), 0.14), "infantry radius fits beside a cliff face")
	_expect(not simulation.call("IsGroundPositionClear", Vector2(10.5, 10.5), 0.60), "larger tuned radius requires wider cliff clearance")
	simulation.free()


func _test_physical_cliff_protrusion_detour() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "clear_units"})
	_set_single_cliff(simulation, Vector2i(22, 27))
	_expect(simulation.call("ApplyDebugCommand", {
		"op": "spawn_unit", "team": 2, "kind": 0,
		"position": Vector2(22.5, 30.5), "exact": true,
	}), "physical cliff fixture spawns one exact ground unit")
	var start := Vector2(22.5, 30.5)
	var progress_origin := start
	var stalled_ticks := 0
	var worst_stall_ticks := 0
	var entered_cliff := false
	for tick in range(210):
		simulation.call("Step", 1.0 / 30.0)
		var snapshot: Dictionary = simulation.call("GetDebugSnapshot")
		var position := Vector2(PackedVector2Array(snapshot.unit_positions)[0])
		var cell := Vector2i(floori(position.x), floori(position.y))
		entered_cliff = entered_cliff or cell == Vector2i(22, 27) or simulation.call("IsWaterCell", cell)
		if position.distance_to(progress_origin) >= 0.05:
			progress_origin = position
			stalled_ticks = 0
		else:
			stalled_ticks += 1
			worst_stall_ticks = maxi(worst_stall_ticks, stalled_ticks)
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	var final_position := Vector2(PackedVector2Array(after.unit_positions)[0])
	_expect(not entered_cliff, "physical detour never enters an elevation-2 cliff or water cell")
	_expect(absf(final_position.x - start.x) >= 0.55, "physical detour moves laterally around the protrusion")
	_expect(final_position.y < 26.5, "physical detour crosses beyond the protrusion")
	_expect(worst_stall_ticks <= 60, "physical detour never stalls for more than two seconds")
	simulation.free()


func _test_legion_cliff_protrusion_detour() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "clear_units"})
	_set_single_cliff(simulation, Vector2i(22, 27))
	_expect(simulation.call("ApplyDebugCommand", {
		"op": "spawn_legion", "team": 2, "formation": 0,
		"anchor": Vector2(22.5, 30.5),
		"template": {"melee": 6, "ranged": 0, "siege": 0, "dragon": 0},
	}), "physical cliff fixture spawns a six-member LINE legion")
	var entered_cliff := false
	var progress_origins: Dictionary = {}
	var stalled_ticks: Dictionary = {}
	var worst_stall_ticks := 0
	for tick in range(210):
		simulation.call("Step", 1.0 / 30.0)
		var snapshot: Dictionary = simulation.call("GetDebugSnapshot")
		var ids := PackedInt32Array(snapshot.unit_ids)
		var positions := PackedVector2Array(snapshot.unit_positions)
		for index in range(ids.size()):
			var id := ids[index]
			var position := positions[index]
			var cell := Vector2i(floori(position.x), floori(position.y))
			entered_cliff = entered_cliff or cell == Vector2i(22, 27) or simulation.call("IsWaterCell", cell)
			if not progress_origins.has(id):
				progress_origins[id] = position
				stalled_ticks[id] = 0
			elif position.distance_to(Vector2(progress_origins[id])) >= 0.05:
				progress_origins[id] = position
				stalled_ticks[id] = 0
			else:
				stalled_ticks[id] = int(stalled_ticks[id]) + 1
				worst_stall_ticks = maxi(worst_stall_ticks, int(stalled_ticks[id]))
	var after: Dictionary = simulation.call("GetDebugSnapshot")
	var crossed := 0
	for position in PackedVector2Array(after.unit_positions):
		if position.y < 26.5: crossed += 1
	_expect(not entered_cliff, "LINE legion members never enter an elevation-2 cliff or water cell")
	_expect(crossed >= 5, "at least five LINE legion members cross the cliff protrusion")
	_expect(worst_stall_ticks <= 60, "LINE legion members never stall for more than two seconds")
	simulation.free()


func _set_single_cliff(simulation, cell: Vector2i) -> void:
	var elevation := PackedByteArray()
	elevation.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	elevation.fill(0)
	elevation[cell.y * GameConfig.GRID_COLUMNS + cell.x] = 2
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	simulation.call("ApplyDebugCommand", {"op": "rebuild_flow"})


func _test_wait_enter_and_release() -> void:
	var simulation = _new_simulation()
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": 2, "kind": 0, "position": Vector2(10.5, 29.88), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": 2, "kind": 0, "position": Vector2(10.5, 29.5), "exact": true})
	simulation.call("ApplyDebugCommand", {"op": "set_unit", "index": 1, "velocity": Vector2.ZERO})
	simulation.call("Step", 1.0 / 30.0)
	var waiting: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(PackedInt32Array(waiting.unit_states).has(2), "blocked follower enters WAIT without lateral vibration")
	simulation.call("ApplyDebugCommand", {"op": "set_unit", "index": 1, "position": Vector2(13.0, 27.0)})
	for tick in range(6): simulation.call("Step", 1.0 / 30.0)
	var released: Dictionary = simulation.call("GetDebugSnapshot")
	_expect(not PackedInt32Array(released.unit_states).has(2), "WAIT releases after the lane clears")
	simulation.free()


func _test_bulk_boundary_source() -> void:
	var renderer := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	var simulation := FileAccess.get_file_as_string("res://scripts/BattleSimulation.cs")
	_expect(renderer.contains("RenderingServer.multimesh_set_buffer"), "renderer performs one packed MultiMesh buffer upload per batch")
	_expect(simulation.contains("private const int MaxUnits = 8192"), "C# core owns a fixed-capacity unit pool")
	_expect(not FileAccess.file_exists("res://scripts/enemy.gd"), "unit-per-Node legacy enemy script remains removed")


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
