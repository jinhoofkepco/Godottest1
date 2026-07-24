extends RefCounted

const SIM_PATH := "res://scripts/agent_lab/AgentBattleSimulation.cs"
const TEAM_SIZE := 30
const TEAM_TOTAL_HP := 2400.0
const TICKS_PER_SECOND := 30
const MODE_BASELINE := 0
const MODE_AGENT := 1
const SCENARIO_BOTTLENECK := 0
const SCENARIO_CORNER_TRAP := 1
const SCENARIO_ROUTE_CHOICE := 2
const SCENARIO_OPEN_CONTROL := 3
const ROUTE_CENTER := 0
const ROUTE_LEFT := 1
const ROUTE_RIGHT := 2
const SCENARIO_NAMES := ["BOTTLENECK", "CORNER_TRAP", "ROUTE_CHOICE", "OPEN_CONTROL"]
const SEEDS := [230723, 230724, 230725]
const DURATION_SECONDS := [120, 90, 90, 60]
const REQUIRED_METRICS := [
	"blue_units_ever_attacked",
	"red_units_ever_attacked",
	"blue_remaining_hp",
	"red_remaining_hp",
	"route_crossings",
	"trap_entries_blue",
	"trap_entries_red",
	"trap_escapes_within_12s",
	"trap_escape_ratio",
	"maximum_trap_dwell_seconds",
]

var failures: Array[String] = []
var output_lines: Array[String] = []
var execution_count := 0


func run() -> Array[String]:
	_expect(ResourceLoader.exists(SIM_PATH), "matrix simulation resource exists")
	if not failures.is_empty():
		return failures

	var simulation = load(SIM_PATH).new()
	_test_metric_contract(simulation)
	_test_open_mirrored_traits(simulation)
	for scenario in SCENARIO_NAMES.size():
		for seed in SEEDS:
			var baseline := _execute(simulation, scenario, seed, MODE_BASELINE)
			var agent := _execute(simulation, scenario, seed, MODE_AGENT)
			var repeated := _execute(simulation, scenario, seed, MODE_AGENT, false)
			_assert_agent_determinism(scenario, seed, agent, repeated)
			_assert_acceptance(scenario, seed, baseline.metrics, agent.metrics)
	_expect(output_lines.size() == 24, "matrix prints exactly 24 primary rows")
	_expect(execution_count == 36, "matrix executes 24 primary runs plus 12 Agent repeats")
	simulation.free()
	return failures


func _test_metric_contract(simulation: Node) -> void:
	simulation.call("ResetExperiment", MODE_AGENT, SEEDS[0], SCENARIO_BOTTLENECK)
	var metrics: Dictionary = simulation.call("GetMetrics")
	for key in REQUIRED_METRICS:
		_expect(metrics.has(key), "matrix metrics expose %s" % key)
	var routes := PackedInt32Array(metrics.get("route_crossings", PackedInt32Array()))
	_expect(routes.size() == 3, "route crossings use CENTER/LEFT/RIGHT order")


func _test_open_mirrored_traits(simulation: Node) -> void:
	simulation.call("ResetExperiment", MODE_AGENT, SEEDS[0], SCENARIO_OPEN_CONTROL)
	simulation.call("RunTicks", 90)
	var snapshot: Dictionary = simulation.call("GetSnapshot")
	var positions := PackedVector2Array(snapshot.get("positions", PackedVector2Array()))
	_expect(positions.size() == TEAM_SIZE * 2, "open-control mirror fixture exposes 60 positions")
	if positions.size() != TEAM_SIZE * 2:
		return
	for index in TEAM_SIZE:
		_expect(
			is_equal_approx(positions[index].x, positions[index + TEAM_SIZE].x)
				and is_equal_approx(positions[index].y + positions[index + TEAM_SIZE].y, 36.0),
			"open-control mirrored pair %d shares deterministic movement traits before contact" % index
		)


func _execute(
	simulation: Node,
	scenario: int,
	seed: int,
	mode: int,
	record_output := true
) -> Dictionary:
	simulation.call("ResetExperiment", mode, seed, scenario)
	simulation.call("RunTicks", DURATION_SECONDS[scenario] * TICKS_PER_SECOND)
	execution_count += 1
	var metrics: Dictionary = simulation.call("GetMetrics")
	var snapshot: Dictionary = simulation.call("GetSnapshot")
	if record_output:
		output_lines.append(_format_row(scenario, seed, mode, metrics))
	return {"metrics": metrics, "snapshot": snapshot}


func _format_row(scenario: int, seed: int, mode: int, metrics: Dictionary) -> String:
	var routes := PackedInt32Array(metrics.get("route_crossings", PackedInt32Array()))
	var center := routes[ROUTE_CENTER] if routes.size() > ROUTE_CENTER else 0
	var left := routes[ROUTE_LEFT] if routes.size() > ROUTE_LEFT else 0
	var right := routes[ROUTE_RIGHT] if routes.size() > ROUTE_RIGHT else 0
	var attacked := int(metrics.get("blue_units_ever_attacked", 0)) \
		+ int(metrics.get("red_units_ever_attacked", 0))
	var result := String(metrics.get("result", ""))
	if result.is_empty():
		result = "RUNNING"
	return (
		"CASE=%s SEED=%d MODE=%s attacked=%d idle=%.1f stuck=%.1f "
		+ "routes=%d/%d/%d trap=%d/%d escape=%.2f dwell=%.1f overlap=%d "
		+ "alive=%d/%d hp=%.1f/%.1f "
		+ "avg=%.3fms worst=%.3fms result=%s"
	) % [
		SCENARIO_NAMES[scenario],
		seed,
		"AGENT" if mode == MODE_AGENT else "BASELINE",
		attacked,
		float(metrics.get("pathological_idle_seconds", 0.0)),
		float(metrics.get("maximum_stuck_seconds", 0.0)),
		center,
		left,
		right,
		int(metrics.get("trap_entries_blue", 0)),
		int(metrics.get("trap_entries_red", 0)),
		float(metrics.get("trap_escape_ratio", 0.0)),
		float(metrics.get("maximum_trap_dwell_seconds", 0.0)),
		int(metrics.get("overlap_violations", 0)),
		int(metrics.get("blue_count", 0)),
		int(metrics.get("red_count", 0)),
		float(metrics.get("blue_remaining_hp", 0.0)),
		float(metrics.get("red_remaining_hp", 0.0)),
		float(metrics.get("average_tick_ms", 0.0)),
		float(metrics.get("worst_tick_ms", 0.0)),
		result,
	]


func _assert_agent_determinism(
	scenario: int,
	seed: int,
	first: Dictionary,
	repeated: Dictionary
) -> void:
	var prefix := "%s seed %d Agent determinism" % [SCENARIO_NAMES[scenario], seed]
	var first_metrics: Dictionary = first.metrics
	var repeated_metrics: Dictionary = repeated.metrics
	var first_snapshot: Dictionary = first.snapshot
	var repeated_snapshot: Dictionary = repeated.snapshot
	_expect(
		String(first_metrics.get("result", "")) == String(repeated_metrics.get("result", "")),
		"%s reproduces result" % prefix
	)
	_expect(
		int(first_metrics.get("blue_count", -1)) == int(repeated_metrics.get("blue_count", -2))
			and int(first_metrics.get("red_count", -1)) == int(repeated_metrics.get("red_count", -2)),
		"%s reproduces alive counts" % prefix
	)
	_expect(
		PackedVector2Array(first_snapshot.get("positions", PackedVector2Array()))
			== PackedVector2Array(repeated_snapshot.get("positions", PackedVector2Array())),
		"%s reproduces positions" % prefix
	)
	_expect(
		PackedInt32Array(first_snapshot.get("actions", PackedInt32Array()))
			== PackedInt32Array(repeated_snapshot.get("actions", PackedInt32Array())),
		"%s reproduces actions" % prefix
	)
	_expect(
		PackedInt32Array(first_snapshot.get("route_intents", PackedInt32Array()))
			== PackedInt32Array(repeated_snapshot.get("route_intents", PackedInt32Array())),
		"%s reproduces route intents" % prefix
	)


func _assert_acceptance(
	scenario: int,
	seed: int,
	baseline: Dictionary,
	agent: Dictionary
) -> void:
	var prefix := "%s seed %d" % [SCENARIO_NAMES[scenario], seed]
	var attacked := int(agent.get("blue_units_ever_attacked", 0)) \
		+ int(agent.get("red_units_ever_attacked", 0))
	var routes := PackedInt32Array(agent.get("route_crossings", PackedInt32Array()))
	var center := routes[ROUTE_CENTER] if routes.size() > ROUTE_CENTER else 0
	var left := routes[ROUTE_LEFT] if routes.size() > ROUTE_LEFT else 0
	var right := routes[ROUTE_RIGHT] if routes.size() > ROUTE_RIGHT else 0
	var route_total := center + left + right
	var agent_idle := float(agent.get("pathological_idle_seconds", INF))
	var baseline_idle := float(baseline.get("pathological_idle_seconds", 0.0))

	_expect(
		float(agent.get("average_tick_ms", INF)) < 1.0,
		"%s Agent average tick stays below 1 ms on the development machine" % prefix
	)
	match scenario:
		SCENARIO_BOTTLENECK:
			_expect(attacked >= 48, "%s at least 48 units actually attack" % prefix)
			_expect(left + right >= 20, "%s records at least 20 side-route crossings" % prefix)
			_expect(
				agent_idle <= baseline_idle * 0.25,
				"%s pathological idle is at most 25 percent of Baseline" % prefix
			)
			_expect(
				int(agent.get("frontline_replacements", 0)) >= 4,
				"%s records at least four frontline replacements" % prefix
			)
			_expect(
				float(agent.get("maximum_stuck_seconds", INF)) < 15.0,
				"%s maximum continuous stuck time is below 15 seconds" % prefix
			)
			_expect(
				int(agent.get("overlap_violations", -1)) == 0,
				"%s has zero overlap violations" % prefix
			)
		SCENARIO_CORNER_TRAP:
			var blue_entries := int(agent.get("trap_entries_blue", 0))
			var red_entries := int(agent.get("trap_entries_red", 0))
			_expect(blue_entries + red_entries >= 12, "%s records at least 12 trap entries" % prefix)
			_expect(blue_entries >= 4, "%s records at least four blue trap entries" % prefix)
			_expect(red_entries >= 4, "%s records at least four red trap entries" % prefix)
			_expect(
				float(agent.get("trap_escape_ratio", 0.0)) > 0.0,
				"%s records at least one timely physical trap escape" % prefix
			)
			_expect(
				agent_idle < 20.0,
				"%s non-purposeful idle stays below 20 agent-seconds" % prefix
			)
			_expect(
				float(agent.get("maximum_stuck_seconds", INF)) < 6.0,
				"%s maximum no-progress interval stays below six seconds" % prefix
			)
			_expect(attacked >= 36, "%s at least 36 units actually attack" % prefix)
			_expect(
				int(agent.get("overlap_violations", -1)) == 0,
				"%s has zero overlap violations" % prefix
			)
		SCENARIO_ROUTE_CHOICE:
			_expect(route_total >= 24, "%s records at least 24 route crossings" % prefix)
			_expect(left >= 4, "%s records at least four left-route crossings" % prefix)
			_expect(right >= 4, "%s records at least four right-route crossings" % prefix)
			_expect(
				route_total > 0 and float(maxi(center, maxi(left, right))) / float(route_total) <= 0.70,
				"%s keeps every route at or below 70 percent of crossings" % prefix
			)
			_expect(
				agent_idle <= baseline_idle * 0.40,
				"%s pathological idle is at most 40 percent of Baseline" % prefix
			)
			_expect(attacked >= 42, "%s at least 42 units actually attack" % prefix)
			_expect(
				int(agent.get("overlap_violations", -1)) == 0,
				"%s has zero overlap violations" % prefix
			)
		SCENARIO_OPEN_CONTROL:
			_expect(
				int(agent.get("flank_decisions", -1)) <= 2,
				"%s makes at most two flank decisions" % prefix
			)
			_expect(left + right == 0, "%s records zero side-route crossings" % prefix)
			_expect(attacked >= 48, "%s at least 48 units actually attack" % prefix)
			_expect(agent_idle < 60.0, "%s pathological idle stays below 60 agent-seconds" % prefix)
			_expect(
				float(agent.get("maximum_stuck_seconds", INF)) < 4.0,
				"%s maximum continuous stuck time is below four seconds" % prefix
			)
			_expect(
				absi(int(agent.get("blue_count", 0)) - int(agent.get("red_count", 0))) <= 2,
				"%s surviving-unit difference is at most two" % prefix
			)
			_expect(
				absf(
					float(agent.get("blue_remaining_hp", 0.0))
					- float(agent.get("red_remaining_hp", 0.0))
				) / TEAM_TOTAL_HP <= 0.08,
				"%s remaining-HP difference is at most eight percent of 2400" % prefix
			)
			_expect(
				int(agent.get("overlap_violations", -1)) == 0,
				"%s has zero overlap violations" % prefix
			)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
