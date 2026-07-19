extends SceneTree

const UNIT_COUNT := 400
const WARMUP_TICKS := 30
const MEASURED_TICKS := 300
const MAX_CANDIDATE_CHECKS := 12000
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
		var unit_kind: int = simulation.UNIT_MELEE if index % 2 == 0 else simulation.UNIT_RANGED
		var lateral_offset := 0.34 + float(index % 3) * 0.16
		simulation.spawn_unit(
			simulation.TEAM_ENEMY,
			Vector2(float(column) + lateral_offset, 11.5 + float(rank) * 0.18),
			unit_kind
		)
		simulation.spawn_unit(
			simulation.TEAM_ALLY,
			Vector2(float(column) + 1.0 - lateral_offset, float(GameConfig.GRID_ROWS) - 11.5 - float(rank) * 0.18),
			unit_kind
		)
	if (
		simulation.unit_ids.size() != UNIT_COUNT
		or simulation.unit_kinds.count(simulation.UNIT_MELEE) != UNIT_COUNT / 2
		or simulation.unit_kinds.count(simulation.UNIT_RANGED) != UNIT_COUNT / 2
	):
		push_error("STRESS FAILED: expanded fixture did not create 400 evenly mixed units")
		quit(1)
		return
	var samples := PackedFloat64Array()
	var maximum_candidate_checks := 0
	for warmup in WARMUP_TICKS:
		simulation.tick(1.0 / 30.0)
	for tick_index in MEASURED_TICKS:
		var started := Time.get_ticks_usec()
		simulation.tick(1.0 / 30.0)
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		maximum_candidate_checks = maxi(maximum_candidate_checks, simulation.target_candidate_checks)
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
	print("STRESS PASS: initial=%d mixed_kinds=true columns=%d remaining=%d warmup=%d ticks=%d avg_ms=%.3f p95_ms=%.3f max_ms=%.3f max_candidates=%d avg_budget_ms=%.3f p95_budget_ms=%.3f" % [
		UNIT_COUNT,
		GameConfig.GRID_COLUMNS,
		simulation.unit_ids.size(),
		WARMUP_TICKS,
		MEASURED_TICKS,
		average_ms,
		p95_ms,
		maximum_ms,
		maximum_candidate_checks,
		tick_budget_ms,
		p95_budget_ms,
	])
	if maximum_candidate_checks >= MAX_CANDIDATE_CHECKS:
		push_error("STRESS FAILED: nearest-target bucket search examined too many candidates")
		quit(1)
		return
	if average_ms >= tick_budget_ms or p95_ms >= p95_budget_ms:
		push_error("STRESS FAILED: simulation work reached avg %.3f / periodic p95 %.3f ms budgets" % [tick_budget_ms, p95_budget_ms])
		quit(1)
		return
	quit(0)
