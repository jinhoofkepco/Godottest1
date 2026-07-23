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


func _same_vectors(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
