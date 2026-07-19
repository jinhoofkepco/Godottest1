extends SceneTree

const UNIT_COUNT := 400
const WARMUP_TICKS := 30
const MEASURED_TICKS := 300
const MAX_CANDIDATE_CHECKS := 30000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulation = load("res://scripts/battle_simulation.gd").new()
	simulation.reset()
	for index in UNIT_COUNT / 2:
		var column := index % 11
		var rank := (index / 11) % 5
		simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(float(column) + 0.28 + float(index % 3) * 0.12, 5.5 + float(rank) * 0.42))
		simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(float(column) + 0.28 + float((index + 1) % 3) * 0.12, 16.5 - float(rank) * 0.42))
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
	print("STRESS PASS: initial=%d remaining=%d ticks=%d avg_ms=%.3f p95_ms=%.3f max_ms=%.3f max_candidates=%d" % [
		UNIT_COUNT,
		simulation.unit_ids.size(),
		MEASURED_TICKS,
		average_ms,
		p95_ms,
		maximum_ms,
		maximum_candidate_checks,
	])
	if maximum_candidate_checks >= MAX_CANDIDATE_CHECKS:
		push_error("STRESS FAILED: nearest-target bucket search examined too many candidates")
		quit(1)
		return
	if average_ms >= 16.667 or p95_ms >= 16.667:
		push_error("STRESS FAILED: simulation work exceeded the 60 FPS frame budget")
		quit(1)
		return
	quit(0)
