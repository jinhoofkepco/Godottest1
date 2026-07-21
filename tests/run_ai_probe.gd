extends SceneTree

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")
const SimulationPreflight = preload("res://tests/simulation_preflight.gd")

func _initialize() -> void:
	if not SimulationPreflight.verify():
		quit(1)
		return
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	simulation.call("ApplyDebugCommand", {"op": "set_seed", "value": 12000})
	for seconds in [30, 60, 120, 150, 180]:
		var debug: Dictionary = simulation.call("GetDebugSnapshot")
		var elapsed := 420.0 - float(debug.time_remaining)
		var remaining_ticks := roundi((float(seconds) - elapsed) * 30.0)
		simulation.call("SetProfilingEnabled", true)
		simulation.call("ResetProfileCounters")
		while remaining_ticks > 0:
			var executed := int(simulation.call("RunHeadlessTicks", mini(30, remaining_ticks)))
			if executed <= 0: break
			remaining_ticks -= executed
		debug = simulation.call("GetDebugSnapshot")
		var enemy_rows: Array[float] = []
		var rallying := 0
		var marching := 0
		for index in PackedInt32Array(debug.unit_teams).size():
			if int(debug.unit_teams[index]) != 1: continue
			enemy_rows.append(Vector2(debug.unit_positions[index]).y)
			rallying += 1 if int(debug.unit_rally_ids[index]) > 0 else 0
			marching += 1 if int(debug.unit_legion_ids[index]) > 0 else 0
		var anchors: PackedVector2Array = debug.legion_anchors
		var min_anchor := 99.0
		var max_anchor := -1.0
		for anchor in anchors:
			min_anchor = minf(min_anchor, anchor.y)
			max_anchor = maxf(max_anchor, anchor.y)
		var rally_summary: Array[String] = []
		for building in Array(debug.buildings):
			if int(building.kind) == 4 and not bool(building.destroyed): rally_summary.append("%s:%d" % [building.cell, int(building.waiting_count)])
		var profile: Dictionary = simulation.call("GetProfileSnapshot")
		var tick_count := maxf(1.0, float(profile.tick_count))
		print("AI PROBE %ds units=%d y=[%.1f,%.1f] rallying=%d grouped=%d legions=%d anchors=[%.1f,%.1f] rallies=%s occ=%.3f hq=%.0f/%.0f avg=%.3fms target=%.3f sep=%.3f territory=%.3f result=%s" % [seconds, enemy_rows.size(), enemy_rows.min() if not enemy_rows.is_empty() else -1.0, enemy_rows.max() if not enemy_rows.is_empty() else -1.0, rallying, marching, int(debug.legion_count), min_anchor, max_anchor, rally_summary, float(debug.ally_occupancy), float(simulation.call("GetHudSnapshot").ally_hq_hp), float(simulation.call("GetHudSnapshot").enemy_hq_hp), float(profile.tick_usec) / tick_count / 1000.0, float(profile.target_usec) / tick_count / 1000.0, float(profile.separation_usec) / tick_count / 1000.0, float(profile.territory_usec) / tick_count / 1000.0, String(debug.result)])
	simulation.free()
	quit(0)
