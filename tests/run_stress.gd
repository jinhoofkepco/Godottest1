extends SceneTree

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")
const SimulationPreflight = preload("res://tests/simulation_preflight.gd")
const GameConfig = preload("res://scripts/game_config.gd")
const COUNTS := [600, 1500, 3000]
const WARMUP_TICKS := 30
const MEASURED_TICKS := 180


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not SimulationPreflight.verify():
		quit(1)
		return
	var failed := false
	var budget_600 := _environment_budget("STRESS_600_BUDGET_MS", 2.0)
	var budget_3000 := _environment_budget("STRESS_3000_BUDGET_MS", 9.0)
	var capped := _measure(600, "spawn_capped_stress")
	print("CAPPED STRESS: ally=%d enemy=%d tick_avg=%.3f ms snapshot_avg=%.3f ms" % [capped.ally_units, capped.enemy_units, capped.tick_avg, capped.snapshot_avg])
	if int(capped.ally_units) != 300 or int(capped.enemy_units) != 300:
		push_error("CAPPED STRESS FIXTURE FAILED: expected 300 living units per team")
		failed = true
	print("DOTNET STRESS: units | tick_avg | tick_p95 | tick_worst | snapshot_avg | target | separation | territory | events | GC(0/1/2)")
	for unit_count in COUNTS:
		var result := _measure(int(unit_count))
		print("DOTNET STRESS: %d | %.3f ms | %.3f ms | %.3f ms | %.3f ms | %.3f ms | %.3f ms | %.3f ms | %.3f ms | %d/%d/%d" % [
			unit_count, result.tick_avg, result.tick_p95, result.tick_worst, result.snapshot_avg,
			result.target_avg, result.separation_avg, result.territory_avg, result.event_avg,
			result.gc0, result.gc1, result.gc2,
		])
		if unit_count == 600 and float(result.tick_avg) > budget_600:
			push_error("STRESS TARGET MISS: 600-unit average %.3f ms exceeds %.3f ms" % [result.tick_avg, budget_600])
			failed = true
		if unit_count == 3000 and float(result.tick_avg) > budget_3000:
			push_error("STRESS TARGET MISS: 3000-unit average %.3f ms exceeds %.3f ms" % [result.tick_avg, budget_3000])
			failed = true
	var legion_result := _measure_legions()
	print("LEGION STRESS: legions=%d units=%d tick_avg=%.3f ms tick_p95=%.3f ms snapshot_avg=%.3f ms" % [legion_result.legions, legion_result.units, legion_result.tick_avg, legion_result.tick_p95, legion_result.snapshot_avg])
	if int(legion_result.legions) != 20 or int(legion_result.units) != 240:
		push_error("LEGION STRESS FIXTURE FAILED: expected 20 legions / 240 units")
		failed = true
	var board_delta := _measure_board_delta()
	print("BOARD DELTA STRESS: cells=%d boundary_avg=%.3f ms boundary_p95=%.3f ms" % [board_delta.cells, board_delta.average, board_delta.p95])
	if int(board_delta.cells) != 30:
		push_error("BOARD DELTA TARGET MISS: expected 30 changed cells, received %d" % board_delta.cells)
		failed = true
	if float(board_delta.p95) > _environment_budget("BOARD_DELTA_BUDGET_MS", 0.25):
		push_error("BOARD DELTA TARGET MISS: p95 %.3f ms exceeds boundary budget" % board_delta.p95)
		failed = true
	quit(1 if failed else 0)


func _measure(unit_count: int, fixture_op := "spawn_stress") -> Dictionary:
	var simulation = SIMULATION_SCENE.instantiate()
	root.add_child(simulation)
	simulation.call("Reset")
	if not simulation.call("ApplyDebugCommand", {"op": fixture_op, "count": unit_count}):
		push_error("STRESS FIXTURE FAILED: could not spawn %d units" % unit_count)
		return {}
	simulation.call("SetProfilingEnabled", true)
	for tick in WARMUP_TICKS:
		simulation.call("Step", 1.0 / 30.0)
		simulation.call("GetRenderSnapshot")
		simulation.call("DrainEvents")
	simulation.call("ResetProfileCounters")
	var before_gc: Dictionary = simulation.call("GetProfileSnapshot")
	var tick_samples := PackedFloat64Array()
	var snapshot_samples := PackedFloat64Array()
	for tick in MEASURED_TICKS:
		var started := Time.get_ticks_usec()
		simulation.call("Step", 1.0 / 30.0)
		tick_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		simulation.call("GetRenderSnapshot")
		snapshot_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		simulation.call("DrainEvents")
	var after_gc: Dictionary = simulation.call("GetProfileSnapshot")
	var ticks := maxf(1.0, float(after_gc.tick_count))
	var result := {
		"ally_units": int(simulation.call("GetDebugSnapshot").ally_unit_count),
		"enemy_units": int(simulation.call("GetDebugSnapshot").enemy_unit_count),
		"tick_avg": _average(tick_samples),
		"tick_p95": _percentile(tick_samples, 0.95),
		"tick_worst": _percentile(tick_samples, 1.0),
		"snapshot_avg": _average(snapshot_samples),
		"target_avg": float(after_gc.target_usec) / ticks / 1000.0,
		"separation_avg": float(after_gc.separation_usec) / ticks / 1000.0,
		"territory_avg": float(after_gc.territory_usec) / ticks / 1000.0,
		"event_avg": float(after_gc.event_usec) / ticks / 1000.0,
		"gc0": int(after_gc.gc_gen0) - int(before_gc.gc_gen0),
		"gc1": int(after_gc.gc_gen1) - int(before_gc.gc_gen1),
		"gc2": int(after_gc.gc_gen2) - int(before_gc.gc_gen2),
	}
	simulation.queue_free()
	return result


func _measure_board_delta() -> Dictionary:
	var simulation = SIMULATION_SCENE.instantiate()
	root.add_child(simulation)
	simulation.call("Reset")
	simulation.call("GetBoardSnapshot")
	var indices := PackedInt32Array()
	for offset in 30:
		var column := offset % GameConfig.GRID_COLUMNS
		var row := 5 + floori(float(offset) / GameConfig.GRID_COLUMNS)
		indices.append(row * GameConfig.GRID_COLUMNS + column)
	var samples := PackedFloat64Array()
	var last_count := 0
	for round_index in 121:
		var owners := PackedInt32Array()
		for offset in 30:
			owners.append(2 if (round_index + offset) % 2 == 0 else 1)
		simulation.call("ApplyDebugCommand", {"op": "force_ownership_delta", "indices": indices, "owners": owners})
		var started := Time.get_ticks_usec()
		simulation.call("GetBoardVersion")
		var delta: Dictionary = simulation.call("GetBoardDelta")
		if round_index > 0:
			samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
			last_count = PackedInt32Array(delta.ownership_indices).size()
	simulation.queue_free()
	return {"cells": last_count, "average": _average(samples), "p95": _percentile(samples, 0.95)}


func _measure_legions() -> Dictionary:
	var simulation = SIMULATION_SCENE.instantiate()
	root.add_child(simulation)
	simulation.call("Reset")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	var template := {"melee": 5, "ranged": 4, "siege": 2, "dragon": 1}
	for index in 20:
		var team := 1 if index < 10 else 2
		var local := index if team == 1 else index - 10
		var anchor := Vector2(1.5 + float(local % 10) * 2.0, 14.5 if team == 1 else 29.5)
		simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": team, "formation": index % 3, "template": template, "anchor": anchor})
	var initial: Dictionary = simulation.call("GetDebugSnapshot")
	simulation.call("SetProfilingEnabled", true)
	for tick in WARMUP_TICKS:
		simulation.call("Step", 1.0 / 30.0)
		simulation.call("GetRenderSnapshot")
		simulation.call("DrainEvents")
	simulation.call("ResetProfileCounters")
	var tick_samples := PackedFloat64Array()
	var snapshot_samples := PackedFloat64Array()
	for tick in MEASURED_TICKS:
		var started := Time.get_ticks_usec()
		simulation.call("Step", 1.0 / 30.0)
		tick_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		simulation.call("GetRenderSnapshot")
		snapshot_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		simulation.call("DrainEvents")
	var result := {"legions": int(initial.legion_count), "units": int(initial.unit_count), "tick_avg": _average(tick_samples), "tick_p95": _percentile(tick_samples, 0.95), "snapshot_avg": _average(snapshot_samples)}
	simulation.queue_free()
	return result


func _average(samples: PackedFloat64Array) -> float:
	var total := 0.0
	for sample in samples: total += sample
	return total / maxf(1.0, float(samples.size()))


func _percentile(samples: PackedFloat64Array, ratio: float) -> float:
	var sorted := Array(samples)
	sorted.sort()
	return float(sorted[clampi(ceili(float(sorted.size()) * ratio) - 1, 0, sorted.size() - 1)])


func _environment_budget(name: String, fallback: float) -> float:
	var value := OS.get_environment(name)
	return maxf(0.001, value.to_float()) if not value.is_empty() else fallback
