extends SceneTree

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const DEFAULT_MATCHES := 50
const MAX_SECONDS := 420.0
const FORCED_GOLD := 320


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var matches := DEFAULT_MATCHES
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--matches="): matches = maxi(1, int(argument.trim_prefix("--matches=")))
	var passive_wins := 0
	var passive_duration := 0.0
	var stalled_matches := 0
	for match_index in matches:
		var result := _simulate(match_index, false)
		passive_wins += 1 if result.result == "DEFEAT" else 0
		passive_duration += float(result.elapsed)
		stalled_matches += 1 if bool(result.stalled) else 0
	var ally_wins := 0
	var ai_draws := 0
	var ally_score := 0.0
	var ai_duration := 0.0
	for match_index in matches:
		var result := _simulate(1000 + match_index, true)
		if matches <= 10: print("AI MATCH %d: %s %.1fs" % [match_index, result.result, result.elapsed])
		ally_wins += 1 if result.result == "VICTORY" else 0
		var time_draw := float(result.elapsed) >= MAX_SECONDS - 0.2
		ai_draws += 1 if time_draw else 0
		ally_score += 0.5 if time_draw else (1.0 if result.result == "VICTORY" else 0.0)
		ai_duration += float(result.elapsed)
		stalled_matches += 1 if bool(result.stalled) else 0
	var ally_rate := float(ally_wins) / float(matches)
	var ally_score_rate := ally_score / float(matches)
	var passive_average := passive_duration / float(matches)
	var ai_average := ai_duration / float(matches)
	print("AI HEALTH: passive_defeats=%d/%d passive_avg=%.1fs ai_blue_wins=%d draws=%d/%d raw_rate=%.2f score_rate=%.2f ai_avg=%.1fs stalled=%d" % [passive_wins, matches, passive_average, ally_wins, ai_draws, matches, ally_rate, ally_score_rate, ai_average, stalled_matches])
	var enforce_rate := matches >= DEFAULT_MATCHES
	var failed := passive_wins != matches or enforce_rate and (ally_score_rate < 0.40 or ally_score_rate > 0.60) or ai_average < 300.0 or ai_average > 420.0 or stalled_matches > 0
	if failed:
		push_error("AI HEALTH FAILED: passive 50/50, AI blue draw-adjusted score 40-60 percent, 300-420 second average, and zero stalls required")
	quit(1 if failed else 0)


func _simulate(seed_value: int, mirror_ai: bool) -> Dictionary:
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	simulation.call("ApplyDebugCommand", {"op": "set_seed", "value": 12000 + seed_value})
	simulation.call("SetAiEnabled", TEAM_ENEMY, true)
	simulation.call("SetAiEnabled", TEAM_ALLY, mirror_ai)
	if mirror_ai:
		simulation.call("SetAiIncomeLevel", 1)
		simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 180, "enemy": 180})
	var elapsed := 0.0
	var last_enemy_builds := 0
	var last_ally_builds := 0
	var enemy_stall_seconds := 0.0
	var ally_stall_seconds := 0.0
	var stalled := false
	var next_health_check := 30.0
	while elapsed < MAX_SECONDS:
		var executed := int(simulation.call("RunHeadlessTicks", 150))
		elapsed += float(executed) / 30.0
		var hud: Dictionary = simulation.call("GetHudSnapshot")
		if String(hud.result) != "": break
		if elapsed + 0.001 >= next_health_check:
			next_health_check += 30.0
			var debug: Dictionary = simulation.call("GetDebugSnapshot")
			var enemy_builds := int(debug.enemy_ai_builds)
			var ally_builds := int(debug.ally_ai_builds)
			enemy_stall_seconds = enemy_stall_seconds + 30.0 if int(debug.enemy_gold) > FORCED_GOLD and enemy_builds == last_enemy_builds else 0.0
			ally_stall_seconds = ally_stall_seconds + 30.0 if mirror_ai and int(debug.ally_gold) > FORCED_GOLD and ally_builds == last_ally_builds else 0.0
			last_enemy_builds = enemy_builds
			last_ally_builds = ally_builds
			stalled = stalled or enemy_stall_seconds >= 60.0 or ally_stall_seconds >= 60.0
	if elapsed >= MAX_SECONDS: simulation.call("RunHeadlessTicks", 1)
	var final_hud: Dictionary = simulation.call("GetHudSnapshot")
	var final_debug: Dictionary = simulation.call("GetDebugSnapshot")
	var result := {"result": String(final_hud.result), "elapsed": elapsed, "stalled": stalled,
		"units": int(final_hud.unit_count), "enemy_builds": int(final_debug.enemy_ai_builds), "ally_builds": int(final_debug.ally_ai_builds),
		"enemy_gold": int(final_debug.enemy_gold), "ally_gold": int(final_debug.ally_gold), "occupancy": float(final_hud.occupancy)}
	if seed_value == 0 or seed_value == 1000:
		print("AI TRACE: mirror=%s %s" % [mirror_ai, result])
	simulation.free()
	return result
