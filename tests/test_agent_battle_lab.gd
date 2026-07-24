extends RefCounted

const SIM_PATH := "res://scripts/agent_lab/AgentBattleSimulation.cs"
const DECISION_PATH := "res://scripts/agent_lab/AgentBattleSimulation.Decision.cs"
const MOVEMENT_PATH := "res://scripts/agent_lab/AgentBattleSimulation.Movement.cs"
const COMBAT_PATH := "res://scripts/agent_lab/AgentBattleSimulation.Combat.cs"
const LAB_SCRIPT_PATH := "res://scripts/agent_battle_lab.gd"
const LAB_SCENE_PATH := "res://scenes/agent_battle_lab.tscn"
const ARENA_WIDTH := 28
const ARENA_HEIGHT := 36
const TEAM_SIZE := 30
const TEST_SEED := 230723
const SCENARIO_NAMES := ["BOTTLENECK", "CORNER_TRAP", "ROUTE_CHOICE", "OPEN_CONTROL"]

var failures: Array[String] = []


func run() -> Array[String]:
	_expect(ResourceLoader.exists(SIM_PATH), "agent lab C# simulation exists")
	if failures.is_empty():
		var simulation = load(SIM_PATH).new()
		for method in ["ResetExperiment", "Step", "RunTicks", "GetSnapshot", "GetMetrics"]:
			_expect(simulation.has_method(method), "simulation exposes %s" % method)
		if failures.is_empty():
			_test_scenario_contract(simulation)
			_test_scenarios_share_decision_and_combat_rules()
			_test_scenario_route_metadata(simulation)
			_test_scenario_metric_contract(simulation)
			_test_target_reservation_cap(simulation)
			_test_route_metrics_use_physical_passages(simulation)
			_test_returned_unit_reacquires_route(simulation)
			_test_open_control_behavior(simulation)
			_test_scenario_passage_behavior(simulation)
			_test_scenario_determinism(simulation)
			_test_deterministic_arena(simulation)
			_test_forward_progress_tracking(simulation)
			_test_retreat_starts_homeward(simulation)
			_test_retreat_preempts_orders(simulation)
			_test_agent_movement(simulation)
			_test_combat_comparison(simulation)
		simulation.free()
	_test_visual_lab_contract()
	return failures


func _test_scenarios_share_decision_and_combat_rules() -> void:
	var decision := FileAccess.get_file_as_string(DECISION_PATH)
	var movement := FileAccess.get_file_as_string(MOVEMENT_PATH)
	var combat := FileAccess.get_file_as_string(COMBAT_PATH)
	for forbidden in [
		"ShouldMaintainCornerTransit",
		"CornerCenterRoutePreference",
		"SynchronizeOpenControlOrders",
		"NormalizeOpenControlPairs",
		"SymmetrizeOpenControlDamage",
	]:
		_expect(
			not decision.contains(forbidden)
				and not movement.contains(forbidden)
				and not combat.contains(forbidden),
			"all scenarios share rules; no %s shortcut" % forbidden
		)


func _test_scenario_contract(simulation: Node) -> void:
	var accepts_scenario := _method_argument_count(simulation, "ResetExperiment") >= 3
	_expect(accepts_scenario, "scenario reset accepts mode, seed, and scenario")
	if not accepts_scenario:
		return

	for scenario in SCENARIO_NAMES.size():
		simulation.call("ResetExperiment", 1, TEST_SEED, scenario)
		var snapshot: Dictionary = simulation.call("GetSnapshot")
		var blocked_cells := PackedInt32Array(snapshot.get("blocked_cells", PackedInt32Array()))
		_expect(int(snapshot.get("scenario_id", -1)) == scenario, "scenario id round-trips")
		_expect(String(snapshot.get("scenario_name", "")) == SCENARIO_NAMES[scenario], "scenario name round-trips")
		_expect(_blocked_geometry_matches(scenario, blocked_cells), "scenario blocked geometry matches")
		_expect(_blocked_geometry_is_vertically_symmetric(blocked_cells), "scenario terrain is mirrored")
		_expect(_both_teams_have_a_reachable_passage(blocked_cells), "scenario keeps mirrored passages reachable")

	simulation.call("ResetExperiment", 1, TEST_SEED, 99)
	var fallback: Dictionary = simulation.call("GetSnapshot")
	_expect(int(fallback.get("scenario_id", -1)) == 0, "invalid scenario falls back to bottleneck")


func _test_scenario_metric_contract(simulation: Node) -> void:
	simulation.call("ResetExperiment", 1, TEST_SEED, 0)
	var metrics: Dictionary = simulation.call("GetMetrics")
	for key in [
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
	]:
		_expect(metrics.has(key), "metrics expose %s" % key)


func _test_target_reservation_cap(simulation: Node) -> void:
	for scenario in [0, 3]:
		simulation.call("ResetExperiment", 1, TEST_SEED, scenario)
		for tick in 900:
			simulation.call("RunTicks", 1)
			var snapshot: Dictionary = simulation.call("GetSnapshot")
			var hp := PackedFloat32Array(snapshot.get("hp", PackedFloat32Array()))
			var teams := PackedInt32Array(snapshot.get("teams", PackedInt32Array()))
			var targets := PackedInt32Array(snapshot.get("targets", PackedInt32Array()))
			var reservations := PackedInt32Array()
			reservations.resize(TEAM_SIZE * 2)
			for attacker in targets.size():
				var target := targets[attacker]
				if hp[attacker] <= 0.0 \
						or target < 0 \
						or target >= hp.size() \
						or hp[target] <= 0.0 \
						or teams[attacker] == teams[target]:
					continue
				reservations[target] += 1
			var maximum_reservations := 0
			for count in reservations:
				maximum_reservations = maxi(maximum_reservations, count)
			_expect(
				maximum_reservations <= 3,
				"%s tick %d limits every live target to three assigned attackers"
				% [SCENARIO_NAMES[scenario], tick]
			)
			if maximum_reservations > 3:
				return


func _test_route_metrics_use_physical_passages(simulation: Node) -> void:
	const ROUTE_COUNT := 3
	const ROUTE_WAYPOINT_CAPACITY := 5
	simulation.call("ResetExperiment", 1, TEST_SEED, 2)
	simulation.call("RunTicks", 90 * 30)
	var snapshot: Dictionary = simulation.call("GetSnapshot")
	var physical_routes := PackedInt32Array(
		snapshot.get("physical_routes", PackedInt32Array())
	)
	var crossings := PackedVector2Array(
		snapshot.get("route_crossing_positions", PackedVector2Array())
	)
	var blue_routes := PackedVector2Array(
		snapshot.get("route_waypoints_blue", PackedVector2Array())
	)
	var counts := PackedInt32Array(
		snapshot.get("route_waypoint_counts", PackedInt32Array())
	)
	_expect(physical_routes.size() == TEAM_SIZE * 2, "snapshot exposes physical route per unit")
	_expect(crossings.size() == TEAM_SIZE * 2, "snapshot exposes physical crossing positions")
	if physical_routes.size() != TEAM_SIZE * 2 \
			or crossings.size() != TEAM_SIZE * 2 \
			or blue_routes.size() != ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY \
			or counts.size() != ROUTE_COUNT:
		return

	var observed := 0
	for index in physical_routes.size():
		var route := physical_routes[index]
		if route < 0:
			continue
		observed += 1
		var best_route := -1
		var best_distance := INF
		for candidate in ROUTE_COUNT:
			var exit_waypoint := counts[candidate] - 2
			var exit_x := blue_routes[candidate * ROUTE_WAYPOINT_CAPACITY + exit_waypoint].x
			var distance := absf(crossings[index].x - exit_x)
			if distance < best_distance:
				best_distance = distance
				best_route = candidate
		_expect(
			route == best_route,
			"unit %d route metric follows crossing x, not route intent" % index
		)
	_expect(observed >= 12, "physical route fixture records enough crossings")


func _test_returned_unit_reacquires_route(simulation: Node) -> void:
	for seed in [230723, 230724, 230725]:
		simulation.call("ResetExperiment", 1, seed, 1)
		simulation.call("RunTicks", 90 * 30)
		var snapshot: Dictionary = simulation.call("GetSnapshot")
		var positions := PackedVector2Array(snapshot.get("positions", PackedVector2Array()))
		var hp := PackedFloat32Array(snapshot.get("hp", PackedFloat32Array()))
		var actions := PackedInt32Array(snapshot.get("actions", PackedInt32Array()))
		var targets := PackedInt32Array(snapshot.get("targets", PackedInt32Array()))
		var stuck := PackedFloat32Array(snapshot.get("stuck_seconds", PackedFloat32Array()))
		for index in positions.size():
			var inside_unpassed_slab := positions[index].y > 13.65 and positions[index].y < 22.35
			_expect(
				not (
					hp[index] > 0.0
					and inside_unpassed_slab
					and actions[index] == 0
					and targets[index] < 0
					and stuck[index] >= 12.0
				),
				"CORNER_TRAP seed %d unit %d avoids a 12-second no-target ADVANCE stall inside the barrier"
				% [seed, index]
			)


func _test_scenario_route_metadata(simulation: Node) -> void:
	const ROUTE_COUNT := 3
	const ROUTE_WAYPOINT_CAPACITY := 5
	for scenario in SCENARIO_NAMES.size():
		simulation.call("ResetExperiment", 1, TEST_SEED, scenario)
		var snapshot: Dictionary = simulation.call("GetSnapshot")
		var blue := PackedVector2Array(snapshot.get("route_waypoints_blue", PackedVector2Array()))
		var red := PackedVector2Array(snapshot.get("route_waypoints_red", PackedVector2Array()))
		var nav_blue := PackedVector2Array(
			snapshot.get("route_navigation_waypoints_blue", PackedVector2Array())
		)
		var nav_red := PackedVector2Array(
			snapshot.get("route_navigation_waypoints_red", PackedVector2Array())
		)
		var counts := PackedInt32Array(snapshot.get("route_waypoint_counts", PackedInt32Array()))
		var blocked_cells := PackedInt32Array(
			snapshot.get("blocked_cells", PackedInt32Array())
		)
		var expected := _expected_blue_routes(scenario)

		_expect(
			blue.size() == ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY,
			"%s exposes the fixed blue waypoint buffer" % SCENARIO_NAMES[scenario]
		)
		_expect(
			red.size() == ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY,
			"%s exposes the fixed red waypoint buffer" % SCENARIO_NAMES[scenario]
		)
		_expect(
			nav_blue.size() == ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY
				and nav_red.size() == ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY,
			"%s exposes fixed reachable navigation targets" % SCENARIO_NAMES[scenario]
		)
		_expect(
			counts.size() == ROUTE_COUNT,
			"%s exposes one waypoint count per route" % SCENARIO_NAMES[scenario]
		)
		if blue.size() != ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY \
				or red.size() != ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY \
				or nav_blue.size() != ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY \
				or nav_red.size() != ROUTE_COUNT * ROUTE_WAYPOINT_CAPACITY \
				or counts.size() != ROUTE_COUNT:
			continue

		for route in ROUTE_COUNT:
			var expected_route: PackedVector2Array = expected[route]
			_expect(
				counts[route] == expected_route.size(),
				"%s route %d exposes its active waypoint count" % [SCENARIO_NAMES[scenario], route]
			)
			for waypoint in mini(counts[route], expected_route.size()):
				var flat_index := route * ROUTE_WAYPOINT_CAPACITY + waypoint
				_expect(
					blue[flat_index] == expected_route[waypoint],
					"%s route %d waypoint %d matches the configured path"
					% [SCENARIO_NAMES[scenario], route, waypoint]
				)
				_expect(
					red[flat_index]
					== Vector2(blue[flat_index].x, float(ARENA_HEIGHT) - blue[flat_index].y),
					"%s route %d red waypoint %d is the exact vertical mirror"
					% [SCENARIO_NAMES[scenario], route, waypoint]
				)
				_expect(
					_has_unit_clearance(nav_blue[flat_index], blocked_cells)
						and _has_unit_clearance(nav_red[flat_index], blocked_cells),
					"%s route %d waypoint %d navigation targets are terrain-open"
					% [SCENARIO_NAMES[scenario], route, waypoint]
				)


func _expected_blue_routes(scenario: int) -> Array[PackedVector2Array]:
	match scenario:
		0:
			return [
				PackedVector2Array([Vector2(14.0, 19.3), Vector2(14.0, 16.55), Vector2(13.5, 0.7)]),
				PackedVector2Array([Vector2(1.45, 19.45), Vector2(1.45, 16.45), Vector2(13.5, 0.7)]),
				PackedVector2Array([Vector2(26.55, 19.45), Vector2(26.55, 16.45), Vector2(13.5, 0.7)]),
			]
		1:
			return [
				PackedVector2Array([
					Vector2(12.25, 22.1),
					Vector2(12.25, 18.7),
					Vector2(15.25, 17.0),
					Vector2(15.25, 13.7),
					Vector2(13.5, 0.7),
				]),
				PackedVector2Array([Vector2(1.45, 19.45), Vector2(1.45, 16.45), Vector2(13.5, 0.7)]),
				PackedVector2Array([Vector2(26.55, 19.45), Vector2(26.55, 16.45), Vector2(13.5, 0.7)]),
			]
		2:
			return [
				PackedVector2Array([Vector2(13.5, 20.45), Vector2(13.5, 15.55), Vector2(13.5, 0.7)]),
				PackedVector2Array([Vector2(4.5, 20.45), Vector2(4.5, 15.55), Vector2(13.5, 0.7)]),
				PackedVector2Array([Vector2(22.5, 20.45), Vector2(22.5, 15.55), Vector2(13.5, 0.7)]),
			]
		3:
			return [
				PackedVector2Array([Vector2(13.5, 0.7)]),
				PackedVector2Array([Vector2(13.5, 0.7)]),
				PackedVector2Array([Vector2(13.5, 0.7)]),
			]
	return []


func _has_unit_clearance(point: Vector2, blocked_cells: PackedInt32Array) -> bool:
	const UNIT_RADIUS := 0.27
	if point.x < UNIT_RADIUS or point.x > float(ARENA_WIDTH) - UNIT_RADIUS \
			or point.y < UNIT_RADIUS or point.y > float(ARENA_HEIGHT) - UNIT_RADIUS:
		return false
	for cell in blocked_cells:
		var x := float(cell % ARENA_WIDTH)
		var y := float(cell / ARENA_WIDTH)
		var nearest := Vector2(
			clampf(point.x, x, x + 1.0),
			clampf(point.y, y, y + 1.0)
		)
		if point.distance_squared_to(nearest) < UNIT_RADIUS * UNIT_RADIUS:
			return false
	return true


func _test_open_control_behavior(simulation: Node) -> void:
	simulation.call("ResetExperiment", 1, TEST_SEED, 3)
	simulation.call("RunTicks", 900)
	var metrics: Dictionary = simulation.call("GetMetrics")
	_expect(int(metrics.get("flank_decisions", -1)) == 0, "OPEN_CONTROL does not invent flank decisions")
	_expect(int(metrics.get("side_crossings", -1)) == 0, "OPEN_CONTROL does not invent side crossings")
	_expect(int(metrics.get("units_ever_attacked", 0)) > 0, "OPEN_CONTROL reaches combat")
	_expect(int(metrics.get("overlap_violations", -1)) == 0, "OPEN_CONTROL preserves minimum separation")


func _test_scenario_passage_behavior(simulation: Node) -> void:
	for scenario in [2, 1]:
		simulation.call("ResetExperiment", 1, TEST_SEED, scenario)
		simulation.call("RunTicks", 2700)
		var metrics: Dictionary = simulation.call("GetMetrics")
		var name: String = SCENARIO_NAMES[scenario]
		_expect(int(metrics.get("units_ever_attacked", 0)) > 0, "%s reaches combat" % name)
		_expect(int(metrics.get("crossed_center", 0)) > 0, "%s crosses the scenario barrier" % name)
		_expect(
			float(metrics.get("maximum_stuck_seconds", INF)) < 30.0,
			"%s keeps maximum stuck time below 30 seconds" % name
		)
		_expect(int(metrics.get("overlap_violations", -1)) == 0, "%s preserves minimum separation" % name)


func _test_scenario_determinism(simulation: Node) -> void:
	for scenario in SCENARIO_NAMES.size():
		simulation.call("ResetExperiment", 1, TEST_SEED, scenario)
		simulation.call("RunTicks", 900)
		var first: Dictionary = simulation.call("GetSnapshot")
		var first_positions := PackedVector2Array(first.get("positions", PackedVector2Array()))
		var first_actions := PackedInt32Array(first.get("actions", PackedInt32Array()))
		var first_routes := PackedInt32Array(first.get("route_intents", PackedInt32Array()))

		simulation.call("ResetExperiment", 1, TEST_SEED, scenario)
		simulation.call("RunTicks", 900)
		var repeated: Dictionary = simulation.call("GetSnapshot")
		var repeated_positions := PackedVector2Array(repeated.get("positions", PackedVector2Array()))
		var repeated_actions := PackedInt32Array(repeated.get("actions", PackedInt32Array()))
		var repeated_routes := PackedInt32Array(repeated.get("route_intents", PackedInt32Array()))
		var name: String = SCENARIO_NAMES[scenario]
		_expect(_same_vectors(first_positions, repeated_positions), "%s reproduces positions after 900 ticks" % name)
		_expect(first_actions == repeated_actions, "%s reproduces actions after 900 ticks" % name)
		_expect(first_routes == repeated_routes, "%s reproduces route intents after 900 ticks" % name)


func _method_argument_count(instance: Object, method_name: String) -> int:
	var maximum := -1
	for method: Dictionary in instance.get_method_list():
		if String(method.get("name", "")) == method_name:
			maximum = maxi(maximum, Array(method.get("args", [])).size())
	return maximum


func _blocked_geometry_matches(scenario: int, blocked_cells: PackedInt32Array) -> bool:
	var expected := {}
	match scenario:
		0:
			for y in range(17, 19):
				for x in range(3, 25):
					if x < 13 or x > 14:
						expected[y * ARENA_WIDTH + x] = true
		1:
			for y in range(17, 19):
				for x in range(3, 25):
					if x < 11 or x > 16:
						expected[y * ARENA_WIDTH + x] = true
			for y in range(14, 17):
				for x in range(11, 14):
					expected[y * ARENA_WIDTH + x] = true
			for y in range(19, 22):
				for x in range(14, 17):
					expected[y * ARENA_WIDTH + x] = true
		2:
			for y in range(16, 20):
				for x in ARENA_WIDTH:
					var is_gate := (x >= 3 and x <= 6) \
						or (x >= 13 and x <= 14) \
						or (x >= 21 and x <= 24)
					if not is_gate:
						expected[y * ARENA_WIDTH + x] = true
		3:
			pass
		_:
			return false

	if blocked_cells.size() != expected.size():
		return false
	var seen := {}
	for cell in blocked_cells:
		if not expected.has(cell) or seen.has(cell):
			return false
		seen[cell] = true
	return true


func _blocked_geometry_is_vertically_symmetric(blocked_cells: PackedInt32Array) -> bool:
	var blocked := {}
	for cell in blocked_cells:
		blocked[cell] = true
	for cell in blocked_cells:
		var x := cell % ARENA_WIDTH
		var y := cell / ARENA_WIDTH
		var mirrored := (ARENA_HEIGHT - 1 - y) * ARENA_WIDTH + (ARENA_WIDTH - 1 - x)
		if not blocked.has(mirrored):
			return false
	return true


func _both_teams_have_a_reachable_passage(blocked_cells: PackedInt32Array) -> bool:
	var blocked := {}
	for cell in blocked_cells:
		blocked[cell] = true
	return _has_reachable_passage(blocked, ARENA_HEIGHT - 2, 1) \
		and _has_reachable_passage(blocked, 1, ARENA_HEIGHT - 2)


func _has_reachable_passage(blocked: Dictionary, start_y: int, goal_y: int) -> bool:
	var pending: Array[int] = []
	var visited := {}
	for x in ARENA_WIDTH:
		var cell := start_y * ARENA_WIDTH + x
		if not blocked.has(cell):
			pending.append(cell)
			visited[cell] = true

	var read_index := 0
	while read_index < pending.size():
		var cell := pending[read_index]
		read_index += 1
		var x := cell % ARENA_WIDTH
		var y := cell / ARENA_WIDTH
		if y == goal_y:
			return true
		for offset in [-ARENA_WIDTH, ARENA_WIDTH, -1, 1]:
			var neighbor: int = cell + offset
			if neighbor < 0 or neighbor >= ARENA_WIDTH * ARENA_HEIGHT:
				continue
			if (offset == -1 or offset == 1) and neighbor / ARENA_WIDTH != y:
				continue
			if blocked.has(neighbor) or visited.has(neighbor):
				continue
			visited[neighbor] = true
			pending.append(neighbor)
	return false


func _test_deterministic_arena(simulation: Node) -> void:
	simulation.call("ResetExperiment", 1, TEST_SEED)
	var first: Dictionary = simulation.call("GetSnapshot")
	var first_metrics: Dictionary = simulation.call("GetMetrics")
	var first_positions := PackedVector2Array(first.get("positions", PackedVector2Array()))
	var teams := PackedInt32Array(first.get("teams", PackedInt32Array()))
	var blocked_cells := PackedInt32Array(first.get("blocked_cells", PackedInt32Array()))
	var attack_pulses := PackedFloat32Array(first.get("attack_pulses", PackedFloat32Array()))

	_expect(first_positions.size() == TEAM_SIZE * 2, "arena starts with exactly 60 units")
	_expect(teams.size() == TEAM_SIZE * 2, "snapshot exposes one team value per unit")
	_expect(attack_pulses.size() == TEAM_SIZE * 2, "snapshot exposes one truthful attack pulse timer per unit")
	_expect(_sum_floats(attack_pulses) <= 0.0001, "attack pulse timers start inactive")
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
	var hp := PackedFloat32Array(first.get("hp", PackedFloat32Array()))
	var alive_count := 0
	for value in hp:
		if value > 0.0:
			alive_count += 1

	_expect(action_counts.size() == 8, "metrics expose one population count for every utility action")
	_expect(_sum_ints(action_counts) == alive_count, "action population counts include living agents only")
	_expect(int(metrics.get("flank_decisions", 0)) > 0, "agents independently choose a flank")
	_expect(int(metrics.get("yield_decisions", 0)) > 0, "blocked agents negotiate passage")
	_expect(int(metrics.get("yield_decisions", 0)) <= TEAM_SIZE * 2, "yield metric counts unique agents with verified blocking")
	_expect(int(metrics.get("side_crossings", 0)) > 0, "agents use a viable side route")
	_expect(float(metrics.get("maximum_stuck_seconds", 999.0)) < 12.0, "no agent remains permanently stuck")
	_expect(int(metrics.get("overlap_violations", -1)) == 0, "position correction preserves minimum separation")
	_expect(metrics.has("idle_agent_seconds"), "metrics expose accumulated pathological idle time")
	var wounded_alive := 0
	for index in hp.size():
		if hp[index] > 0.0 and hp[index] < 20.0:
			wounded_alive += 1
			_expect(first_actions[index] == 7, "critically wounded unit %d prioritizes retreat" % index)
	_expect(wounded_alive > 0, "combat fixture includes a critically wounded survivor")
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
	if float(metrics.get("maximum_stuck_seconds", 0.0)) >= 12.0:
		print(
			"  PEAK unit=%d pos=%s action=%d"
			% [
				int(metrics.get("maximum_stuck_unit", -1)),
				Vector2(metrics.get("maximum_stuck_position", Vector2.ZERO)),
				int(metrics.get("maximum_stuck_action", -1)),
			]
		)
	simulation.call("ResetExperiment", 1, TEST_SEED)
	simulation.call("RunTicks", RUN_TICKS)
	var repeated: Dictionary = simulation.call("GetSnapshot")
	var repeated_positions := PackedVector2Array(repeated.get("positions", PackedVector2Array()))
	var repeated_actions := PackedInt32Array(repeated.get("actions", PackedInt32Array()))
	_expect(_same_vectors(first_positions, repeated_positions), "same seed and ticks reproduce every agent position")
	_expect(first_actions == repeated_actions, "same seed and ticks reproduce every agent action")


func _test_retreat_starts_homeward(simulation: Node) -> void:
	const RUN_TICKS := 45 * 30
	const ACTION_RETREAT := 7
	const BARRIER_TOP_Y := 17.0
	const BARRIER_BOTTOM_Y := 19.0
	var previous_actions := PackedInt32Array()
	var found_passage_retreat := false
	simulation.call("ResetExperiment", 1, TEST_SEED, 0)
	previous_actions = PackedInt32Array(simulation.call("GetSnapshot").get("actions", PackedInt32Array()))

	for _tick in RUN_TICKS:
		simulation.call("RunTicks", 1)
		var snapshot: Dictionary = simulation.call("GetSnapshot")
		var positions := PackedVector2Array(snapshot.get("positions", PackedVector2Array()))
		var teams := PackedInt32Array(snapshot.get("teams", PackedInt32Array()))
		var hp := PackedFloat32Array(snapshot.get("hp", PackedFloat32Array()))
		var actions := PackedInt32Array(snapshot.get("actions", PackedInt32Array()))
		for index in actions.size():
			if hp[index] <= 0.0 \
					or actions[index] != ACTION_RETREAT \
					or previous_actions[index] == ACTION_RETREAT:
				continue
			var inside_passage := positions[index].y > BARRIER_TOP_Y \
				and positions[index].y < BARRIER_BOTTOM_Y
			if not inside_passage:
				continue

			var before := positions[index]
			simulation.call("RunTicks", 1)
			var moved: Dictionary = simulation.call("GetSnapshot")
			var moved_positions := PackedVector2Array(moved.get("positions", PackedVector2Array()))
			var moved_hp := PackedFloat32Array(moved.get("hp", PackedFloat32Array()))
			var moved_actions := PackedInt32Array(moved.get("actions", PackedInt32Array()))
			if moved_hp[index] <= 0.0 or moved_actions[index] != ACTION_RETREAT:
				continue

			var homeward_delta := moved_positions[index].y - before.y
			if teams[index] == 1:
				homeward_delta = -homeward_delta
			_expect(
				homeward_delta >= -0.00001,
				"critically wounded unit %d never begins retreat by moving enemyward" % index
			)
			found_passage_retreat = true
			break
		if found_passage_retreat:
			break
		previous_actions = actions

	_expect(found_passage_retreat, "retreat direction fixture finds a wounded unit inside the passage")


func _test_retreat_preempts_orders(simulation: Node) -> void:
	const RUN_TICKS := 45 * 30
	const RETREAT_HP := 20.0
	const MAX_DECISION_LATENCY_TICKS := 6
	var wounded_since: Array[int] = []
	wounded_since.resize(TEAM_SIZE * 2)
	wounded_since.fill(-1)
	var found_wounded := false
	simulation.call("ResetExperiment", 1, TEST_SEED)
	for tick in RUN_TICKS:
		simulation.call("RunTicks", 1)
		var snapshot: Dictionary = simulation.call("GetSnapshot")
		var hp := PackedFloat32Array(snapshot.get("hp", PackedFloat32Array()))
		var actions := PackedInt32Array(snapshot.get("actions", PackedInt32Array()))
		for index in hp.size():
			if hp[index] <= 0.0 or hp[index] >= RETREAT_HP:
				wounded_since[index] = -1
				continue
			found_wounded = true
			if wounded_since[index] < 0:
				wounded_since[index] = tick
			elif tick - wounded_since[index] >= MAX_DECISION_LATENCY_TICKS:
				_expect(
					actions[index] == 7,
					"critically wounded unit %d retreats within its staggered decision window" % index
				)
	_expect(found_wounded, "retreat priority fixture produces a critically wounded survivor")


func _test_combat_comparison(simulation: Node) -> void:
	const RUN_TICKS := 120 * 30
	simulation.call("ResetExperiment", 0, TEST_SEED)
	simulation.call("RunTicks", RUN_TICKS)
	var baseline: Dictionary = simulation.call("GetMetrics")

	simulation.call("ResetExperiment", 1, TEST_SEED)
	simulation.call("RunTicks", RUN_TICKS)
	var agent: Dictionary = simulation.call("GetMetrics")

	for metric in [
		"units_ever_attacked",
		"frontline_replacements",
		"crossed_center",
		"intentional_hold_seconds",
		"elapsed_seconds",
		"active_participation_ratio",
		"result",
	]:
		_expect(agent.has(metric), "combat metrics expose %s" % metric)

	_expect(float(baseline.get("idle_agent_seconds", 0.0)) > 0.0, "baseline reproduces central idle congestion")
	_expect(
		float(agent.get("idle_agent_seconds", INF)) < float(baseline.get("idle_agent_seconds", 0.0)),
		"agent decisions reduce pathological idle time"
	)
	_expect(
		int(agent.get("units_ever_attacked", 0)) >= int(baseline.get("units_ever_attacked", 0)),
		"autonomous agents match or exceed the saturated baseline participation count"
	)
	_expect(int(agent.get("frontline_replacements", 0)) > 0, "rear agents replace fallen front fighters")
	_expect(not String(agent.get("result", "")).is_empty(), "agent battle resolves or scores at the fixed timeout")
	_expect(
		float(agent.get("active_participation_ratio", 0.0)) >= 0.70,
		"agent mode keeps at least 70 percent purposefully active"
	)

	print(
		"BASELINE 120S result=%s elapsed=%.1f alive=%d/%d attacked=%d replacements=%d crossed=%d idle=%.1f hold=%.1f active=%.2f"
		% [
			String(baseline.get("result", "")),
			float(baseline.get("elapsed_seconds", 0.0)),
			int(baseline.get("blue_count", 0)),
			int(baseline.get("red_count", 0)),
			int(baseline.get("units_ever_attacked", 0)),
			int(baseline.get("frontline_replacements", 0)),
			int(baseline.get("crossed_center", 0)),
			float(baseline.get("idle_agent_seconds", 0.0)),
			float(baseline.get("intentional_hold_seconds", 0.0)),
			float(baseline.get("active_participation_ratio", 0.0)),
		]
	)
	print(
		"AGENT 120S result=%s elapsed=%.1f alive=%d/%d attacked=%d replacements=%d crossed=%d idle=%.1f hold=%.1f active=%.2f"
		% [
			String(agent.get("result", "")),
			float(agent.get("elapsed_seconds", 0.0)),
			int(agent.get("blue_count", 0)),
			int(agent.get("red_count", 0)),
			int(agent.get("units_ever_attacked", 0)),
			int(agent.get("frontline_replacements", 0)),
			int(agent.get("crossed_center", 0)),
			float(agent.get("idle_agent_seconds", 0.0)),
			float(agent.get("intentional_hold_seconds", 0.0)),
			float(agent.get("active_participation_ratio", 0.0)),
		]
	)


func _test_visual_lab_contract() -> void:
	_expect(ResourceLoader.exists(LAB_SCRIPT_PATH), "visual lab presenter exists")
	_expect(ResourceLoader.exists(LAB_SCENE_PATH), "visual lab scene exists")
	if not ResourceLoader.exists(LAB_SCENE_PATH):
		return

	var lab = load(LAB_SCENE_PATH).instantiate()
	for method in ["set_scenario", "set_mode", "reset_lab", "get_metrics_text"]:
		_expect(lab.has_method(method), "visual lab exposes %s" % method)
	for path in [
		"Interface/ScenarioControls/Gate",
		"Interface/ScenarioControls/Corner",
		"Interface/ScenarioControls/Routes",
		"Interface/ScenarioControls/Open",
	]:
		var button: Node = lab.get_node_or_null(path)
		_expect(
			button is Button and button.custom_minimum_size.y >= 44.0,
			"%s is touch-sized" % path
		)
	var title := lab.get_node_or_null("Interface/Header/Title") as Label
	_expect(
		title != null and title.text == "MINI BATTLE AI LAB // 30 vs 30 SHIELDS",
		"visual lab has an unmistakable experiment title"
	)
	_expect(_count_simulation_nodes(lab) == 1, "visual lab owns exactly one bulk C# simulation node")
	_expect(
		String(ProjectSettings.get_setting("application/run/main_scene", "")) == LAB_SCENE_PATH,
		"project starts in the individual AI battle lab"
	)
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 540, "lab viewport width is 540")
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 960, "lab viewport height is 960")
	if lab.has_method("set_scenario") \
			and lab.get_node_or_null("Interface/ScenarioControls/Gate") != null:
		Engine.get_main_loop().root.add_child(lab)
		for scenario in SCENARIO_NAMES.size():
			var scenario_button: Button = lab.get_node([
				"Interface/ScenarioControls/Gate",
				"Interface/ScenarioControls/Corner",
				"Interface/ScenarioControls/Routes",
				"Interface/ScenarioControls/Open",
			][scenario])
			scenario_button.pressed.emit()
			var snapshot: Dictionary = lab.get_node("AgentBattleSimulation").call("GetSnapshot")
			var header_text := String(lab.get_node("Interface/Header/Mode").text)
			_expect(
				int(snapshot.get("scenario_id", -1)) == scenario,
				"scenario button %d resets the selected case" % (scenario + 1)
			)
			_expect(
				header_text.contains(SCENARIO_NAMES[scenario]),
				"scenario button %d updates the header case name" % (scenario + 1)
			)
			_expect(scenario_button.disabled, "selected scenario button %d is highlighted" % (scenario + 1))
		lab.queue_free()
	else:
		lab.free()


func _count_simulation_nodes(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var node_script: Variant = node.get_script()
		if node_script != null and String(node_script.resource_path) == SIM_PATH:
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


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


func _sum_floats(values: PackedFloat32Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
