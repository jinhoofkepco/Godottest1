extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")

var failures: Array[String] = []


func run() -> Array[String]:
	_test_lake_ground_detour_and_dragon_crossing()
	_test_flow_detour()
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
