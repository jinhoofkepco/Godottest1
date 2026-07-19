extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_contract()
	_test_flow_detour_and_congestion()
	_test_wait_enter_and_release()
	_test_defense_tower_rules_and_attack()
	_test_dragon_lair_and_flight()
	return failures


func _new_simulation():
	var script := load("res://scripts/battle_simulation.gd")
	if script == null or not script.can_instantiate():
		_expect(false, "battle simulation parses for flow feature tests")
		return null
	var simulation = script.new()
	simulation.reset()
	return simulation


func _test_config_contract() -> void:
	var config := load("res://scripts/game_config.gd")
	var constants: Dictionary = config.get_script_constant_map()
	for name in [
		"CONGESTION_COST_WEIGHT", "CONGESTION_REBUILD_INTERVAL", "UNIT_TURN_RATE",
		"WAIT_CHECK_RADIUS", "FLOW_NOISE_DEGREES", "DEFENSE_TOWER_COST", "DRAGON_LAIR_COST",
	]:
		_expect(constants.has(name), "config exposes %s" % name)
	_expect(float(constants.get("MAP_ZOOM_MAX", 0.0)) >= 16.0, "map supports extreme 16x zoom")


func _test_flow_detour_and_congestion() -> void:
	var flow_script := load("res://scripts/flow_field.gd")
	_expect(flow_script != null and flow_script.can_instantiate(), "data-only flow field helper parses")
	if flow_script == null or not flow_script.can_instantiate():
		return
	var width := 7
	var height := 7
	var blocked := PackedByteArray()
	blocked.resize(width * height)
	for row in height:
		if row != 5:
			blocked[row * width + 3] = 1
	var density := PackedInt32Array()
	density.resize(width * height)
	var flow = flow_script.new(width, height)
	_expect(typeof(flow.costs) == TYPE_PACKED_FLOAT32_ARRAY, "integration costs use PackedFloat32Array")
	_expect(typeof(flow.directions) == TYPE_PACKED_VECTOR2_ARRAY, "flow directions use PackedVector2Array")
	flow.rebuild(Vector2i(6, 0), blocked, density, 0.0)
	_expect(flow.cost_at(Vector2i(1, 1)) < INF, "flow reaches goal around a closed-column wall through its gap")
	_expect(flow.direction_at(Vector2i(1, 1)).y > 0.0, "flow initially detours downward toward the only wall opening")

	blocked.fill(0)
	for column in width:
		if column not in [1, 5]:
			blocked[3 * width + column] = 1
	for row in range(3, 7):
		density[row * width + 1] = 8
	flow.rebuild(Vector2i(3, 0), blocked, density, 2.0)
	_expect(flow.direction_at(Vector2i(3, 0)) == Vector2.ZERO, "flow goal has no direction away from itself")
	_expect(flow.cost_at(Vector2i(5, 3)) < flow.cost_at(Vector2i(1, 3)), "congestion makes the second opening cheaper")
	_expect(flow.direction_at(Vector2i(3, 5)).x > 0.0, "congested approach steers toward the alternate opening")
	_expect(_flow_directions_are_weighted(flow, blocked, Vector2i(3, 0), width, height), "cached directions preserve weighted cardinal/diagonal Dijkstra choices")


func _test_wait_enter_and_release() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	simulation.blocked.fill(0)
	var leader_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(10.5, 29.5))
	var follower_id: int = simulation.spawn_unit(simulation.TEAM_ALLY, Vector2(10.5, 29.88))
	var leader: int = simulation.unit_ids.find(leader_id)
	var follower: int = simulation.unit_ids.find(follower_id)
	simulation.unit_positions[leader] = Vector2(10.5, 29.5)
	simulation.unit_positions[follower] = Vector2(10.5, 29.88)
	simulation.unit_velocities[leader] = Vector2.ZERO
	simulation.rebuild_flow_fields()
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_states[follower] == simulation.STATE_WAIT, "slow ally ahead puts follower into WAIT")
	simulation.unit_positions[leader] = Vector2(13.5, 29.5)
	simulation.rebuild_flow_fields()
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_states[follower] != simulation.STATE_WAIT, "cleared lane releases WAIT immediately")


func _test_defense_tower_rules_and_attack() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	var hq_cell := Vector2i(simulation.config.GRID_COLUMNS / 2, simulation.config.GRID_ROWS - 1)
	var valid_cell := hq_cell + Vector2i(-2, -2)
	var invalid_cell := hq_cell + Vector2i(-3, -2)
	simulation.ally_gold = 999
	_expect(simulation.try_build(simulation.TEAM_ALLY, valid_cell, simulation.BUILD_DEFENSE_TOWER), "tower builds inside HQ 5x5")
	var gold_after_valid: int = simulation.ally_gold
	_expect(not simulation.try_build(simulation.TEAM_ALLY, invalid_cell, simulation.BUILD_DEFENSE_TOWER), "tower rejects outside HQ 5x5")
	_expect(simulation.ally_gold == gold_after_valid, "rejected tower spends no gold")
	_expect(not simulation.try_build_spawner(simulation.TEAM_ALLY, invalid_cell, simulation.UNIT_DRAGON), "legacy spawner API rejects non-ground unit kinds")
	_expect(simulation.ally_gold == gold_after_valid, "invalid legacy spawner kind spends no gold")
	var target_id: int = simulation.spawn_unit(simulation.TEAM_ENEMY, Vector2(valid_cell) + Vector2(0.5, -1.0))
	var target_index: int = simulation.unit_ids.find(target_id)
	simulation.unit_positions[target_index] = Vector2(valid_cell) + Vector2(0.5, -1.0)
	var hp_before: float = simulation.unit_hp[target_index]
	for step in 40:
		simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_hp[target_index] < hp_before, "defense tower damages a hostile in range")


func _test_dragon_lair_and_flight() -> void:
	var simulation = _new_simulation()
	if simulation == null:
		return
	simulation.ally_gold = 999
	var lair_cell := Vector2i(4, simulation.config.GRID_ROWS - 8)
	_expect(simulation.try_build(simulation.TEAM_ALLY, lair_cell, simulation.BUILD_DRAGON_LAIR), "expensive dragon lair builds on owned territory")
	var lair: Dictionary = simulation.buildings.back()
	_expect(int(lair.kind) == simulation.BUILDING_DRAGON_LAIR, "dragon build records a distinct lair kind")
	var lair_index: int = simulation.buildings.size() - 1
	lair.spawn_timer = 0.0
	simulation.buildings[lair_index] = lair
	simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_kinds.has(simulation.UNIT_DRAGON), "dragon lair produces a flying unit")
	var blocked_index: int = simulation.blocked.find(1)
	_expect(blocked_index >= 0, "dragon obstacle fixture exists")
	if blocked_index < 0:
		return
	var dragon_index: int = simulation.unit_kinds.find(simulation.UNIT_DRAGON)
	var blocker := Vector2i(blocked_index % simulation.config.GRID_COLUMNS, blocked_index / simulation.config.GRID_COLUMNS)
	simulation.unit_positions[dragon_index] = Vector2(blocker) + Vector2(0.5, 1.02)
	var before_y: float = simulation.unit_positions[dragon_index].y
	for step in 30:
		simulation.tick(1.0 / 30.0)
	_expect(simulation.unit_positions[dragon_index].y < float(blocker.y) + 0.5, "flying dragon crosses a blocked cell")
	_expect(simulation.unit_positions[dragon_index].y < before_y, "dragon advances toward enemy HQ")
	_expect(simulation.unit_velocities.size() == simulation.unit_ids.size(), "velocity packed array stays aligned")
	_expect(simulation.unit_flow_bias_radians.size() == simulation.unit_ids.size(), "flow bias packed array stays aligned")
	_expect(typeof(simulation.unit_velocities) == TYPE_PACKED_VECTOR2_ARRAY, "unit velocities stay data-oriented")
	_expect(typeof(simulation.unit_flow_bias_radians) == TYPE_PACKED_FLOAT32_ARRAY, "unit flow bias stays data-oriented")
	simulation._rebuild_buckets()
	var dragon_cell := Vector2i(floori(simulation.unit_positions[dragon_index].x), floori(simulation.unit_positions[dragon_index].y))
	var ally_density: PackedInt32Array = simulation._density_from_buckets(simulation._ally_buckets)
	_expect(ally_density[dragon_cell.y * simulation.config.GRID_COLUMNS + dragon_cell.x] == 0, "flying dragons do not add ground congestion")

	var surrounded = _new_simulation()
	surrounded.blocked.fill(0)
	var producer_cell := Vector2i(10, 30)
	var producer_id: int = surrounded.add_building(surrounded.TEAM_ALLY, surrounded.BUILDING_SPAWNER, producer_cell)
	var producer_index: int = surrounded._building_index_from_id(producer_id)
	for offset in [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var cell: Vector2i = producer_cell + offset
		surrounded.blocked[cell.y * surrounded.config.GRID_COLUMNS + cell.x] = 1
	var producer: Dictionary = surrounded.buildings[producer_index]
	producer.spawn_timer = 0.0
	surrounded.buildings[producer_index] = producer
	surrounded.tick(1.0 / 30.0)
	_expect(surrounded.unit_ids.is_empty(), "fully surrounded ground spawner waits instead of spawning inside itself")


func _flow_directions_are_weighted(flow, blocked: PackedByteArray, goal: Vector2i, width: int, height: int) -> bool:
	var offsets := [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]
	for row in height:
		for column in width:
			var cell := Vector2i(column, row)
			var index := row * width + column
			if cell == goal or blocked[index] != 0 or is_inf(flow.cost_at(cell)):
				continue
			var direction: Vector2 = flow.direction_at(cell)
			if direction == Vector2.ZERO:
				return false
			var chosen := cell + Vector2i(roundi(direction.x), roundi(direction.y))
			var chosen_score: float = flow.cost_at(chosen) + (1.41421356 if chosen.x != cell.x and chosen.y != cell.y else 1.0)
			var best_score: float = INF
			for offset: Vector2i in offsets:
				var neighbor := cell + offset
				if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height:
					continue
				var neighbor_index := neighbor.y * width + neighbor.x
				if neighbor != goal and blocked[neighbor_index] != 0:
					continue
				if offset.x != 0 and offset.y != 0:
					var side_a := Vector2i(cell.x + offset.x, cell.y)
					var side_b := Vector2i(cell.x, cell.y + offset.y)
					var side_a_blocked := side_a != goal and blocked[side_a.y * width + side_a.x] != 0
					var side_b_blocked := side_b != goal and blocked[side_b.y * width + side_b.x] != 0
					if side_a_blocked and side_b_blocked:
						continue
				best_score = minf(best_score, flow.cost_at(neighbor) + (1.41421356 if offset.x != 0 and offset.y != 0 else 1.0))
			if chosen_score > best_score + 0.001:
				return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
