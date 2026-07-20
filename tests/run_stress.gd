extends SceneTree

const UNIT_COUNT := 600
const WARMUP_TICKS := 30
const MEASURED_TICKS := 300
const MAX_CANDIDATE_CHECKS := 30000
const MAX_AOE_CANDIDATES_PER_IMPACT := 300.0
const DEFAULT_TICK_BUDGET_MS := 16.667
const DEFAULT_PERIODIC_P95_BUDGET_MS := 30.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulation = load("res://scripts/battle_simulation.gd").new()
	simulation.reset()
	for index in UNIT_COUNT / 2:
		var column: int = index % GameConfig.GRID_COLUMNS
		var rank: int = (index / GameConfig.GRID_COLUMNS) % 10
		var unit_kind: int = [simulation.UNIT_MELEE, simulation.UNIT_RANGED, simulation.UNIT_SIEGE][index % 3]
		var lateral_offset := 0.34 + float(index % 3) * 0.16
		simulation.spawn_unit(
			simulation.TEAM_ENEMY,
			Vector2(float(column) + lateral_offset, 19.1 + float(rank) * 0.14),
			unit_kind
		)
		simulation.spawn_unit(
			simulation.TEAM_ALLY,
			Vector2(float(column) + 1.0 - lateral_offset, 24.9 - float(rank) * 0.14),
			unit_kind
		)
	if (
		simulation.unit_ids.size() != UNIT_COUNT
		or simulation.unit_kinds.count(simulation.UNIT_MELEE) != UNIT_COUNT / 3
		or simulation.unit_kinds.count(simulation.UNIT_RANGED) != UNIT_COUNT / 3
		or simulation.unit_kinds.count(simulation.UNIT_SIEGE) != UNIT_COUNT / 3
	):
		push_error("STRESS FAILED: expanded fixture did not create 600 evenly mixed units")
		quit(1)
		return
	var samples := PackedFloat64Array()
	var maximum_candidate_checks := 0
	var maximum_aoe_candidate_checks := 0
	var maximum_aoe_candidates_per_impact := 0.0
	var maximum_impacts_in_one_tick := 0
	var siege_projectiles := 0
	var siege_impacts := 0
	for warmup in WARMUP_TICKS:
		simulation.tick(1.0 / 30.0)
		for event in simulation.drain_events():
			siege_projectiles += int(String(event.get("type", "")) == "siege_projectile")
			siege_impacts += int(String(event.get("type", "")) == "siege_impact")
	for tick_index in MEASURED_TICKS:
		var started := Time.get_ticks_usec()
		simulation.tick(1.0 / 30.0)
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		maximum_candidate_checks = maxi(maximum_candidate_checks, simulation.target_candidate_checks)
		maximum_aoe_candidate_checks = maxi(maximum_aoe_candidate_checks, simulation.aoe_candidate_checks)
		maximum_impacts_in_one_tick = maxi(maximum_impacts_in_one_tick, simulation.siege_impacts_resolved_this_tick)
		if simulation.siege_impacts_resolved_this_tick > 0:
			maximum_aoe_candidates_per_impact = maxf(maximum_aoe_candidates_per_impact, float(simulation.aoe_candidate_checks) / float(simulation.siege_impacts_resolved_this_tick))
		for event in simulation.drain_events():
			siege_projectiles += int(String(event.get("type", "")) == "siege_projectile")
			siege_impacts += int(String(event.get("type", "")) == "siege_impact")
	var sorted_samples := Array(samples)
	sorted_samples.sort()
	var total_ms := 0.0
	for sample in samples:
		total_ms += sample
	var average_ms := total_ms / float(samples.size())
	var p95_ms := float(sorted_samples[int(float(sorted_samples.size() - 1) * 0.95)])
	var maximum_ms := float(sorted_samples.back())
	var tick_budget_ms := DEFAULT_TICK_BUDGET_MS
	var p95_budget_ms := DEFAULT_PERIODIC_P95_BUDGET_MS
	var budget_override := OS.get_environment("STRESS_TICK_BUDGET_MS")
	if not budget_override.is_empty():
		tick_budget_ms = maxf(0.001, budget_override.to_float())
		p95_budget_ms = tick_budget_ms
	var p95_budget_override := OS.get_environment("STRESS_P95_BUDGET_MS")
	if not p95_budget_override.is_empty():
		p95_budget_ms = maxf(0.001, p95_budget_override.to_float())
	print("STRESS PASS: initial=%d mixed_kinds=true columns=%d remaining=%d warmup=%d ticks=%d avg_ms=%.3f p95_ms=%.3f max_ms=%.3f max_candidates=%d max_aoe_candidates=%d max_aoe_per_impact=%.1f max_impacts_tick=%d siege_projectiles=%d siege_impacts=%d avg_budget_ms=%.3f p95_budget_ms=%.3f" % [
		UNIT_COUNT,
		GameConfig.GRID_COLUMNS,
		simulation.unit_ids.size(),
		WARMUP_TICKS,
		MEASURED_TICKS,
		average_ms,
		p95_ms,
		maximum_ms,
		maximum_candidate_checks,
		maximum_aoe_candidate_checks,
		maximum_aoe_candidates_per_impact,
		maximum_impacts_in_one_tick,
		siege_projectiles,
		siege_impacts,
		tick_budget_ms,
		p95_budget_ms,
	])
	if maximum_candidate_checks >= MAX_CANDIDATE_CHECKS:
		push_error("STRESS FAILED: nearest-target bucket search examined too many candidates")
		quit(1)
		return
	if maximum_aoe_candidates_per_impact >= MAX_AOE_CANDIDATES_PER_IMPACT or siege_projectiles <= 0 or siege_impacts <= 0:
		push_error("STRESS FAILED: SIEGE impacts were absent or escaped bucket-bounded AoE checks")
		quit(1)
		return
	if average_ms >= tick_budget_ms or p95_ms >= p95_budget_ms:
		push_error("STRESS FAILED: simulation work reached avg %.3f / periodic p95 %.3f ms budgets" % [tick_budget_ms, p95_budget_ms])
		quit(1)
		return
	quit(0)
