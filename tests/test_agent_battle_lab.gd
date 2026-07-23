extends RefCounted

const SIM_PATH := "res://scripts/agent_lab/AgentBattleSimulation.cs"
const ARENA_WIDTH := 28
const ARENA_HEIGHT := 36
const TEAM_SIZE := 30
const TEST_SEED := 230723

var failures: Array[String] = []


func run() -> Array[String]:
	_expect(ResourceLoader.exists(SIM_PATH), "agent lab C# simulation exists")
	if failures.is_empty():
		var simulation = load(SIM_PATH).new()
		for method in ["ResetExperiment", "Step", "RunTicks", "GetSnapshot", "GetMetrics"]:
			_expect(simulation.has_method(method), "simulation exposes %s" % method)
		if failures.is_empty():
			_test_deterministic_arena(simulation)
			_test_forward_progress_tracking(simulation)
			_test_agent_movement(simulation)
		simulation.free()
	return failures


func _test_deterministic_arena(simulation: Node) -> void:
	simulation.call("ResetExperiment", 1, TEST_SEED)
	var first: Dictionary = simulation.call("GetSnapshot")
	var first_metrics: Dictionary = simulation.call("GetMetrics")
	var first_positions := PackedVector2Array(first.get("positions", PackedVector2Array()))
	var teams := PackedInt32Array(first.get("teams", PackedInt32Array()))
	var blocked_cells := PackedInt32Array(first.get("blocked_cells", PackedInt32Array()))

	_expect(first_positions.size() == TEAM_SIZE * 2, "arena starts with exactly 60 units")
	_expect(teams.size() == TEAM_SIZE * 2, "snapshot exposes one team value per unit")
	_expect(int(first.get("alive_blue", -1)) == TEAM_SIZE, "arena starts with 30 blue units")
	_expect(int(first.get("alive_red", -1)) == TEAM_SIZE, "arena starts with 30 red units")
	_expect(is_zero_approx(float(first.get("time", -1.0))), "reset starts at zero elapsed time")
	_expect(String(first.get("result", "missing")).is_empty(), "reset has no battle result")
	_expect(int(first_metrics.get("unit_count", -1)) == TEAM_SIZE * 2, "metrics report 60 units")
	_expect(int(first_metrics.get("blue_count", -1)) == TEAM_SIZE, "metrics report 30 blue units")
	_expect(int(first_metrics.get("red_count", -1)) == TEAM_SIZE, "metrics report 30 red units")
	_expect(is_zero_approx(float(first_metrics.get("average_tick_ms", -1.0))), "reset average tick time is zero")
	_expect(is_zero_approx(float(first_metrics.get("worst_tick_ms", -1.0))), "reset worst tick time is zero")

	if first_positions.size() == TEAM_SIZE * 2 and teams.size() == TEAM_SIZE * 2:
		for index in TEAM_SIZE:
			var blue := first_positions[index]
			var red := first_positions[index + TEAM_SIZE]
			_expect(teams[index] == 0, "unit %d belongs to blue team" % index)
			_expect(teams[index + TEAM_SIZE] == 1, "unit %d belongs to red team" % (index + TEAM_SIZE))
			_expect(is_equal_approx(blue.x, red.x), "spawn pair %d mirrors on x" % index)
			_expect(is_equal_approx(blue.y + red.y, float(ARENA_HEIGHT)), "spawn pair %d mirrors around arena center" % index)

	_expect(blocked_cells.size() == 40, "central fortification exports 40 blocked cells")
	for cell_index in blocked_cells:
		var x := cell_index % ARENA_WIDTH
		var y := cell_index / ARENA_WIDTH
		_expect(cell_index >= 0 and cell_index < ARENA_WIDTH * ARENA_HEIGHT, "blocked cell %d stays inside the arena" % cell_index)
		_expect(blocked_cells.has((ARENA_HEIGHT - 1 - y) * ARENA_WIDTH + x), "blocked cell %d has a mirrored partner" % cell_index)

	simulation.call("RunTicks", 5)
	simulation.call("ResetExperiment", 1, TEST_SEED)
	var repeated: Dictionary = simulation.call("GetSnapshot")
	var repeated_positions := PackedVector2Array(repeated.get("positions", PackedVector2Array()))
	var repeated_blocked := PackedInt32Array(repeated.get("blocked_cells", PackedInt32Array()))
	_expect(_same_vectors(first_positions, repeated_positions), "repeated reset with the same seed reproduces spawn positions")
	_expect(blocked_cells == repeated_blocked, "repeated reset with the same seed reproduces blocked cells")
	_expect(is_zero_approx(float(repeated.get("time", -1.0))), "repeated reset clears elapsed time")


func _test_forward_progress_tracking(simulation: Node) -> void:
	const SAMPLE_TICKS := 15
	const SAMPLE_COUNT := 24
	simulation.call("ResetExperiment", 1, TEST_SEED)
	var previous: Dictionary = simulation.call("GetSnapshot")
	var previous_positions := PackedVector2Array(previous.get("positions", PackedVector2Array()))
	var previous_stuck := PackedFloat32Array(previous.get("stuck_seconds", PackedFloat32Array()))
	_expect(previous_stuck.size() == TEAM_SIZE * 2, "snapshot exposes per-agent forward-progress stalls")
	if previous_stuck.size() != TEAM_SIZE * 2:
		return

	var found_lateral_sample := false
	var lateral_sample_accumulated_stuck := false
	for _sample in SAMPLE_COUNT:
		simulation.call("RunTicks", SAMPLE_TICKS)
		var current: Dictionary = simulation.call("GetSnapshot")
		var current_positions := PackedVector2Array(current.get("positions", PackedVector2Array()))
		var current_stuck := PackedFloat32Array(current.get("stuck_seconds", PackedFloat32Array()))
		var actions := PackedInt32Array(current.get("actions", PackedInt32Array()))
		var routes := PackedInt32Array(current.get("route_intents", PackedInt32Array()))
		for index in TEAM_SIZE * 2:
			var forward_sign := -1.0 if index < TEAM_SIZE else 1.0
			var delta := current_positions[index] - previous_positions[index]
			var forward_progress := delta.y * forward_sign
			var congestion_action := actions[index] == 5 or actions[index] == 6 or routes[index] != 0
			if congestion_action and absf(delta.x) > 0.18 and forward_progress < 0.08:
				found_lateral_sample = true
				if current_stuck[index] >= previous_stuck[index] + 0.4:
					lateral_sample_accumulated_stuck = true
		previous_positions = current_positions
		previous_stuck = current_stuck

	_expect(found_lateral_sample, "fixture includes a lateral congestion-avoidance sample")
	_expect(lateral_sample_accumulated_stuck, "lateral or PBD movement does not erase a forward-progress stall")


func _test_agent_movement(simulation: Node) -> void:
	const RUN_TICKS := 45 * 30
	simulation.call("ResetExperiment", 1, TEST_SEED)
	simulation.call("RunTicks", RUN_TICKS)
	var first: Dictionary = simulation.call("GetSnapshot")
	var metrics: Dictionary = simulation.call("GetMetrics")
	var first_positions := PackedVector2Array(first.get("positions", PackedVector2Array()))
	var first_actions := PackedInt32Array(first.get("actions", PackedInt32Array()))
	var action_counts := PackedInt32Array(metrics.get("action_counts", PackedInt32Array()))

	_expect(action_counts.size() == 8, "metrics expose one population count for every utility action")
	_expect(_sum_ints(action_counts) == TEAM_SIZE * 2, "action population counts include all 60 agents")
	_expect(int(metrics.get("flank_decisions", 0)) > 0, "agents independently choose a flank")
	_expect(int(metrics.get("yield_decisions", 0)) > 0, "blocked agents negotiate passage")
	_expect(int(metrics.get("yield_decisions", 0)) <= TEAM_SIZE * 2, "yield metric counts unique agents with verified blocking")
	_expect(int(metrics.get("side_crossings", 0)) > 0, "agents use a viable side route")
	_expect(float(metrics.get("maximum_stuck_seconds", 999.0)) < 12.0, "no agent remains permanently stuck")
	_expect(int(metrics.get("overlap_violations", -1)) == 0, "position correction preserves minimum separation")
	_expect(metrics.has("idle_agent_seconds"), "metrics expose accumulated pathological idle time")
	print(
		"AGENT MOVEMENT 45S flank=%d yield=%d side=%d idle=%.2f max_stuck=%.2f overlap=%d avg=%.3fms"
		% [
			int(metrics.get("flank_decisions", 0)),
			int(metrics.get("yield_decisions", 0)),
			int(metrics.get("side_crossings", 0)),
			float(metrics.get("idle_agent_seconds", 0.0)),
			float(metrics.get("maximum_stuck_seconds", 0.0)),
			int(metrics.get("overlap_violations", -1)),
			float(metrics.get("average_tick_ms", -1.0)),
		]
	)

	simulation.call("ResetExperiment", 1, TEST_SEED)
	simulation.call("RunTicks", RUN_TICKS)
	var repeated: Dictionary = simulation.call("GetSnapshot")
	var repeated_positions := PackedVector2Array(repeated.get("positions", PackedVector2Array()))
	var repeated_actions := PackedInt32Array(repeated.get("actions", PackedInt32Array()))
	_expect(_same_vectors(first_positions, repeated_positions), "same seed and ticks reproduce every agent position")
	_expect(first_actions == repeated_actions, "same seed and ticks reproduce every agent action")


func _same_vectors(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]):
			return false
	return true


func _sum_ints(values: PackedInt32Array) -> int:
	var total := 0
	for value in values:
		total += value
	return total


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
