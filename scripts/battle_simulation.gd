class_name BattleSimulation
extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const config = GameConfig

const TEAM_NONE := 0
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const BUILDING_HQ := 0
const BUILDING_SPAWNER := 1
const UNIT_MELEE := 0
const UNIT_RANGED := 1

var unit_ids := PackedInt32Array()
var unit_teams := PackedInt32Array()
var unit_kinds := PackedInt32Array()
var unit_positions := PackedVector2Array()
var unit_hp := PackedFloat32Array()
var unit_states := PackedInt32Array()
var unit_target_ids := PackedInt32Array()
var unit_cooldowns := PackedFloat32Array()
var unit_last_attacker_teams := PackedInt32Array()
var unit_speed_scales := PackedFloat32Array()
var unit_lunge_timers := PackedFloat32Array()
var unit_lunge_directions := PackedVector2Array()

var buildings: Array[Dictionary] = []
var ownership := PackedByteArray()
var blocked := PackedByteArray()
var ally_gold := GameConfig.START_GOLD
var enemy_gold := GameConfig.ENEMY_START_GOLD
var ally_hq_id := 0
var enemy_hq_id := 0
var time_remaining := GameConfig.MATCH_DURATION
var result := ""
var target_candidate_checks := 0

var _next_unit_id := 1
var _next_building_id := 1
var _tick_accumulator := 0.0
var _ally_income_remainder := 0.0
var _enemy_income_remainder := 0.0
var _enemy_build_timer := GameConfig.ENEMY_BUILD_INTERVAL
var _enemy_build_cursor := 0
var _enemy_next_unit_kind := UNIT_MELEE
var _events: Array[Dictionary] = []
var _enemy_buckets: Array[Array] = []
var _ally_buckets: Array[Array] = []
var _unit_index_by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _found_target_id := 0
var _found_unit_index := -1
var _found_building_index := -1
var _found_target_position := Vector2.ZERO


func reset() -> void:
	unit_ids.clear()
	unit_teams.clear()
	unit_kinds.clear()
	unit_positions.clear()
	unit_hp.clear()
	unit_states.clear()
	unit_target_ids.clear()
	unit_cooldowns.clear()
	unit_last_attacker_teams.clear()
	unit_speed_scales.clear()
	unit_lunge_timers.clear()
	unit_lunge_directions.clear()
	buildings.clear()
	ownership.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	for row in GameConfig.GRID_ROWS:
		var owner := TEAM_ENEMY if row < GameConfig.GRID_ROWS / 2 else TEAM_ALLY
		for column in GameConfig.GRID_COLUMNS:
			ownership[row * GameConfig.GRID_COLUMNS + column] = owner
	blocked.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	blocked.fill(0)
	_generate_blocked_cells()
	ally_gold = GameConfig.START_GOLD
	enemy_gold = GameConfig.ENEMY_START_GOLD
	time_remaining = GameConfig.MATCH_DURATION
	result = ""
	target_candidate_checks = 0
	_next_unit_id = 1
	_next_building_id = 1
	_tick_accumulator = 0.0
	_ally_income_remainder = 0.0
	_enemy_income_remainder = 0.0
	_enemy_build_timer = GameConfig.ENEMY_BUILD_INTERVAL
	_enemy_build_cursor = 0
	_enemy_next_unit_kind = UNIT_MELEE
	_rng.seed = 731942
	_events.clear()
	_enemy_buckets.clear()
	_ally_buckets.clear()
	_unit_index_by_id.clear()
	_enemy_buckets.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	_ally_buckets.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	enemy_hq_id = add_building(TEAM_ENEMY, BUILDING_HQ, Vector2i(GameConfig.GRID_COLUMNS / 2, 0))
	ally_hq_id = add_building(TEAM_ALLY, BUILDING_HQ, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS - 1))
	recalculate_territory(false)


func spawn_unit(team: int, position: Vector2, unit_kind: int = UNIT_MELEE) -> int:
	if team not in [TEAM_ALLY, TEAM_ENEMY] or unit_kind not in [UNIT_MELEE, UNIT_RANGED]:
		return 0
	var unit_id := _next_unit_id
	_next_unit_id += 1
	unit_ids.append(unit_id)
	unit_teams.append(team)
	unit_kinds.append(unit_kind)
	var varied_position := position
	varied_position.x = clampf(
		varied_position.x + _rng.randf_range(-GameConfig.UNIT_SPAWN_X_VARIATION, GameConfig.UNIT_SPAWN_X_VARIATION),
		0.2,
		float(GameConfig.GRID_COLUMNS) - 0.2
	)
	unit_positions.append(varied_position)
	unit_hp.append(_unit_max_hp(unit_kind))
	unit_states.append(0)
	unit_target_ids.append(0)
	unit_cooldowns.append(0.0)
	unit_last_attacker_teams.append(TEAM_NONE)
	unit_speed_scales.append(_rng.randf_range(1.0 - GameConfig.UNIT_SPEED_VARIATION, 1.0 + GameConfig.UNIT_SPEED_VARIATION))
	unit_lunge_timers.append(0.0)
	unit_lunge_directions.append(Vector2.ZERO)
	_unit_index_by_id[unit_id] = unit_ids.size() - 1
	return unit_id


func add_building(team: int, kind: int, cell: Vector2i, unit_kind: int = UNIT_MELEE) -> int:
	if team not in [TEAM_ALLY, TEAM_ENEMY] or kind not in [BUILDING_HQ, BUILDING_SPAWNER] or unit_kind not in [UNIT_MELEE, UNIT_RANGED] or not _cell_is_valid(cell) or is_blocked(cell):
		return 0
	return _add_building(team, kind, cell, unit_kind)


func tick(delta: float) -> void:
	if result != "" or delta <= 0.0:
		return
	_tick_accumulator += delta
	var fixed_delta := 1.0 / float(GameConfig.SIM_TICK_RATE)
	var catch_up_ticks := 0
	while _tick_accumulator + 0.000001 >= fixed_delta and result == "" and catch_up_ticks < GameConfig.MAX_CATCH_UP_TICKS:
		_tick_accumulator -= fixed_delta
		_step(fixed_delta)
		catch_up_ticks += 1
	if catch_up_ticks == GameConfig.MAX_CATCH_UP_TICKS and _tick_accumulator >= fixed_delta:
		_tick_accumulator = fmod(_tick_accumulator, fixed_delta)
	if result == "":
		_check_terminal_state()


func try_build_spawner(team: int, cell: Vector2i, unit_kind: int = UNIT_MELEE) -> bool:
	if result != "" or unit_kind not in [UNIT_MELEE, UNIT_RANGED] or not _cell_is_valid(cell) or is_blocked(cell):
		return false
	if ownership[_cell_index(cell)] != team or _building_at(cell) != -1:
		return false
	var cost := _spawner_cost(unit_kind)
	if team == TEAM_ALLY:
		if ally_gold < cost:
			return false
		ally_gold -= cost
	elif team == TEAM_ENEMY:
		if enemy_gold < cost:
			return false
		enemy_gold -= cost
	else:
		return false
	var building_id := add_building(team, BUILDING_SPAWNER, cell, unit_kind)
	_events.append({"type": "spawner_built", "team": team, "building_id": building_id, "cell": cell})
	recalculate_territory()
	return true


func get_ownership() -> PackedByteArray:
	return ownership.duplicate()


func is_blocked(cell: Vector2i) -> bool:
	return _cell_is_valid(cell) and blocked[_cell_index(cell)] == 1


func get_blocked_cells() -> PackedByteArray:
	return blocked.duplicate()


func get_occupancy(team: int) -> float:
	if ownership.is_empty():
		return 0.0
	var count := 0
	for owner in ownership:
		if owner == team:
			count += 1
	return float(count) / float(ownership.size())


func recalculate_territory(emit_changes: bool = true) -> void:
	var previous := ownership.duplicate()
	var red_fronts := PackedInt32Array()
	var blue_fronts := PackedInt32Array()
	red_fronts.resize(GameConfig.GRID_COLUMNS)
	blue_fronts.resize(GameConfig.GRID_COLUMNS)
	red_fronts.fill(-1)
	blue_fronts.fill(GameConfig.GRID_ROWS)
	for index in unit_ids.size():
		if unit_hp[index] <= 0.0:
			continue
		var column := floori(unit_positions[index].x)
		if column < 0 or column >= GameConfig.GRID_COLUMNS:
			continue
		var row := floori(unit_positions[index].y)
		if unit_teams[index] == TEAM_ENEMY:
			red_fronts[column] = maxi(red_fronts[column], row)
		elif unit_teams[index] == TEAM_ALLY:
			blue_fronts[column] = mini(blue_fronts[column], row)
	for building in buildings:
		if bool(building.get("destroyed", false)):
			continue
		var cell: Vector2i = building.cell
		if int(building.team) == TEAM_ENEMY:
			red_fronts[cell.x] = maxi(red_fronts[cell.x], cell.y)
		elif int(building.team) == TEAM_ALLY:
			blue_fronts[cell.x] = mini(blue_fronts[cell.x], cell.y)
	for column in GameConfig.GRID_COLUMNS:
		var red_front := red_fronts[column]
		var blue_front := blue_fronts[column]
		var has_red := red_front >= 0
		var has_blue := blue_front < GameConfig.GRID_ROWS
		var overlap_midpoint := float(red_front + blue_front) * 0.5
		for row in GameConfig.GRID_ROWS:
			var red_claims := has_red and row <= red_front
			var blue_claims := has_blue and row >= blue_front
			var owner := TEAM_NONE
			if red_claims and blue_claims:
				owner = TEAM_ENEMY if float(row) <= overlap_midpoint else TEAM_ALLY
			elif red_claims:
				owner = TEAM_ENEMY
			elif blue_claims:
				owner = TEAM_ALLY
			if owner != TEAM_NONE:
				ownership[row * GameConfig.GRID_COLUMNS + column] = owner
	if emit_changes:
		for index in ownership.size():
			if previous[index] == ownership[index]:
				continue
			_events.append({
				"type": "territory_changed",
				"cell": Vector2i(index % GameConfig.GRID_COLUMNS, index / GameConfig.GRID_COLUMNS),
				"team": ownership[index],
			})


func apply_building_damage(building_id: int, damage: float, attacker_team: int) -> void:
	var index := _building_index_from_id(building_id)
	if index < 0 or bool(buildings[index].destroyed):
		return
	var building := buildings[index]
	building.hp = maxf(0.0, float(building.hp) - damage)
	buildings[index] = building
	var event_type := "hq_hit" if int(building.kind) == BUILDING_HQ else "spawner_hit"
	_events.append({"type": event_type, "team": int(building.team), "building_id": building_id, "cell": building.cell})
	if float(building.hp) > 0.0:
		return
	building.destroyed = true
	buildings[index] = building
	_events.append({"type": "building_destroyed", "team": int(building.team), "building_id": building_id, "cell": building.cell, "kind": int(building.kind)})
	if int(building.kind) == BUILDING_HQ:
		result = "VICTORY" if attacker_team == TEAM_ALLY else "DEFEAT"
	else:
		recalculate_territory()


func drain_events() -> Array:
	var drained: Array = _events.duplicate(true)
	_events.clear()
	return drained


func _step(delta: float) -> void:
	_apply_income(delta)
	time_remaining = maxf(0.0, time_remaining - delta)
	_update_enemy_ai(delta)
	_update_spawners(delta)
	_rebuild_buckets()
	target_candidate_checks = 0
	for index in unit_ids.size():
		if unit_hp[index] <= 0.0:
			continue
		unit_cooldowns[index] = maxf(0.0, unit_cooldowns[index] - delta)
		unit_lunge_timers[index] = maxf(0.0, unit_lunge_timers[index] - delta)
		_find_target(index)
		unit_target_ids[index] = _found_target_id
		var position := unit_positions[index]
		var attack_range := _unit_attack_range(unit_kinds[index])
		var target_in_attack_range := _found_target_id != 0 and position.distance_squared_to(_found_target_position) <= attack_range * attack_range
		if target_in_attack_range:
			unit_states[index] = 1
			unit_lunge_directions[index] = position.direction_to(_found_target_position)
			if unit_cooldowns[index] <= 0.0:
				_attack_target(index, _found_unit_index, _found_building_index)
		else:
			unit_states[index] = 0
			var advance_direction := Vector2(0.0, -1.0 if unit_teams[index] == TEAM_ALLY else 1.0)
			var seek_direction := Vector2.ZERO
			if _found_target_id != 0:
				seek_direction = position.direction_to(_found_target_position)
			var separation_direction := _calculate_separation(index)
			var obstacle_direction := _calculate_obstacle_repulsion(position)
			var steering := (
				advance_direction * GameConfig.UNIT_ADVANCE_WEIGHT
				+ seek_direction * GameConfig.UNIT_SEEK_WEIGHT
				+ separation_direction * GameConfig.UNIT_SEPARATION_WEIGHT
				+ obstacle_direction * GameConfig.OBSTACLE_REPULSION_WEIGHT
			)
			if steering.length_squared() <= 0.000001:
				steering = advance_direction
			var velocity := steering.normalized() * _unit_speed(unit_kinds[index]) * unit_speed_scales[index]
			unit_positions[index] = _move_without_entering_blocked(position, velocity * delta)
	_remove_dead_units()
	recalculate_territory()
	_check_terminal_state()


func _apply_income(delta: float) -> void:
	_ally_income_remainder += delta * GameConfig.PASSIVE_INCOME_PER_SECOND
	_enemy_income_remainder += delta * GameConfig.PASSIVE_INCOME_PER_SECOND
	var ally_income := floori(_ally_income_remainder + 0.000001)
	var enemy_income := floori(_enemy_income_remainder + 0.000001)
	if ally_income > 0:
		ally_gold += ally_income
		_ally_income_remainder -= float(ally_income)
	if enemy_income > 0:
		enemy_gold += enemy_income
		_enemy_income_remainder -= float(enemy_income)


func _update_enemy_ai(delta: float) -> void:
	_enemy_build_timer -= delta
	if _enemy_build_timer > 0.0 or _count_spawners(TEAM_ENEMY) >= GameConfig.ENEMY_MAX_SPAWNERS:
		return
	_enemy_build_timer += GameConfig.ENEMY_BUILD_INTERVAL
	var unit_kind := _enemy_next_unit_kind
	if enemy_gold < _spawner_cost(unit_kind):
		return
	for offset in GameConfig.GRID_COLUMNS:
		var column := (_enemy_build_cursor + offset) % GameConfig.GRID_COLUMNS
		var frontline_row := 0
		for row in GameConfig.GRID_ROWS:
			if ownership[row * GameConfig.GRID_COLUMNS + column] == TEAM_ENEMY:
				frontline_row = row
		for row in range(mini(frontline_row, GameConfig.GRID_ROWS - 2), 0, -1):
			var cell := Vector2i(column, row)
			if try_build_spawner(TEAM_ENEMY, cell, unit_kind):
				_enemy_build_cursor = (column + 3) % GameConfig.GRID_COLUMNS
				_enemy_next_unit_kind = UNIT_RANGED if unit_kind == UNIT_MELEE else UNIT_MELEE
				return


func _update_spawners(delta: float) -> void:
	for index in buildings.size():
		var building := buildings[index]
		if bool(building.destroyed) or int(building.kind) != BUILDING_SPAWNER:
			continue
		building.spawn_timer = float(building.spawn_timer) - delta
		if float(building.spawn_timer) <= 0.0:
			building.spawn_timer = float(building.spawn_timer) + GameConfig.SPAWNER_PRODUCTION_INTERVAL
			var cell: Vector2i = building.cell
			var team := int(building.team)
			var unit_kind := int(building.unit_kind)
			var offset_y := -0.2 if team == TEAM_ALLY else 0.2
			var unit_id := spawn_unit(team, Vector2(cell) + Vector2(0.5, 0.5 + offset_y), unit_kind)
			_events.append({"type": "unit_produced", "team": team, "unit_id": unit_id, "cell": cell, "unit_kind": unit_kind})
		buildings[index] = building


func _rebuild_buckets() -> void:
	for bucket in _enemy_buckets:
		bucket.clear()
	for bucket in _ally_buckets:
		bucket.clear()
	for index in unit_ids.size():
		if unit_hp[index] <= 0.0:
			continue
		var cell := Vector2i(
			clampi(floori(unit_positions[index].x), 0, GameConfig.GRID_COLUMNS - 1),
			clampi(floori(unit_positions[index].y), 0, GameConfig.GRID_ROWS - 1)
		)
		var team_buckets := _enemy_buckets if unit_teams[index] == TEAM_ENEMY else _ally_buckets
		team_buckets[_cell_index(cell)].append(index)


func _find_target(unit_index: int) -> void:
	var position := unit_positions[unit_index]
	var team := unit_teams[unit_index]
	var cell := Vector2i(floori(position.x), floori(position.y))
	var best_distance_sq := _seed_retained_target(unit_target_ids[unit_index], team, position)
	var target_buckets := _ally_buckets if team == TEAM_ENEMY else _enemy_buckets
	var bucket_radius := ceili(GameConfig.UNIT_DETECT_RANGE)
	for row in range(maxi(0, cell.y - bucket_radius), mini(GameConfig.GRID_ROWS - 1, cell.y + bucket_radius) + 1):
		for column in range(maxi(0, cell.x - bucket_radius), mini(GameConfig.GRID_COLUMNS - 1, cell.x + bucket_radius) + 1):
			if not _bucket_can_contain_nearer_target(position, column, row, best_distance_sq):
				continue
			for candidate_index in target_buckets[row * GameConfig.GRID_COLUMNS + column]:
				target_candidate_checks += 1
				if unit_hp[candidate_index] <= 0.0:
					continue
				var distance_sq := position.distance_squared_to(unit_positions[candidate_index])
				if distance_sq <= best_distance_sq:
					best_distance_sq = distance_sq
					_found_target_id = unit_ids[candidate_index]
					_found_unit_index = candidate_index
					_found_building_index = -1
					_found_target_position = unit_positions[candidate_index]
	for building_index in buildings.size():
		var building := buildings[building_index]
		if bool(building.destroyed) or int(building.team) == team:
			continue
		var building_position := Vector2(building.cell) + Vector2(0.5, 0.5)
		var distance_sq := position.distance_squared_to(building_position)
		if distance_sq <= best_distance_sq:
			best_distance_sq = distance_sq
			_found_target_id = -int(building.id)
			_found_unit_index = -1
			_found_building_index = building_index
			_found_target_position = building_position
	if _found_target_id == 0:
		_assign_hq_fallback(team, position)


func _seed_retained_target(target_id: int, team: int, position: Vector2) -> float:
	var maximum_distance_sq := GameConfig.UNIT_DETECT_RANGE * GameConfig.UNIT_DETECT_RANGE
	_found_target_id = 0
	_found_unit_index = -1
	_found_building_index = -1
	_found_target_position = Vector2.ZERO
	if target_id > 0 and _unit_index_by_id.has(target_id):
		var index := int(_unit_index_by_id[target_id])
		var distance_sq := position.distance_squared_to(unit_positions[index])
		if unit_hp[index] > 0.0 and unit_teams[index] != team and distance_sq <= maximum_distance_sq:
			_found_target_id = target_id
			_found_unit_index = index
			_found_target_position = unit_positions[index]
			return distance_sq
	elif target_id < 0:
		var building_index := _building_index_from_id(-target_id)
		if building_index >= 0:
			var building := buildings[building_index]
			var building_position := Vector2(building.cell) + Vector2(0.5, 0.5)
			var distance_sq := position.distance_squared_to(building_position)
			if not bool(building.destroyed) and int(building.team) != team and distance_sq <= maximum_distance_sq:
				_found_target_id = target_id
				_found_building_index = building_index
				_found_target_position = building_position
				return distance_sq
	return maximum_distance_sq


func _bucket_can_contain_nearer_target(position: Vector2, column: int, row: int, best_distance_sq: float) -> bool:
	# Buckets are rebuilt before movement, so expand by one maximum fixed-tick step.
	var movement_slop := GameConfig.UNIT_SPEED * (1.0 + GameConfig.UNIT_SPEED_VARIATION) / float(GameConfig.SIM_TICK_RATE)
	var minimum := Vector2(float(column), float(row)) - Vector2.ONE * movement_slop
	var maximum := Vector2(float(column + 1), float(row + 1)) + Vector2.ONE * movement_slop
	var closest := position.clamp(minimum, maximum)
	return position.distance_squared_to(closest) <= best_distance_sq


func _calculate_separation(unit_index: int) -> Vector2:
	var position := unit_positions[unit_index]
	var team := unit_teams[unit_index]
	var cell := Vector2i(floori(position.x), floori(position.y))
	var separation := Vector2.ZERO
	var radius_squared := GameConfig.UNIT_SEPARATION_RADIUS * GameConfig.UNIT_SEPARATION_RADIUS
	var team_buckets := _enemy_buckets if team == TEAM_ENEMY else _ally_buckets
	for row in range(maxi(0, cell.y - 1), mini(GameConfig.GRID_ROWS - 1, cell.y + 1) + 1):
		for column in range(maxi(0, cell.x - 1), mini(GameConfig.GRID_COLUMNS - 1, cell.x + 1) + 1):
			for candidate_index in team_buckets[row * GameConfig.GRID_COLUMNS + column]:
				if candidate_index == unit_index or unit_hp[candidate_index] <= 0.0:
					continue
				var offset := position - unit_positions[candidate_index]
				var distance_squared := offset.length_squared()
				if distance_squared >= radius_squared:
					continue
				if distance_squared <= 0.000001:
					var pair_direction := 1.0 if unit_ids[unit_index] < unit_ids[candidate_index] else -1.0
					separation += Vector2(pair_direction, 0.0)
				else:
					var distance := sqrt(distance_squared)
					separation += offset / distance * (1.0 - distance / GameConfig.UNIT_SEPARATION_RADIUS)
	return separation.normalized() if separation.length_squared() > 0.000001 else Vector2.ZERO


func _calculate_obstacle_repulsion(position: Vector2) -> Vector2:
	var cell := Vector2i(floori(position.x), floori(position.y))
	var radius := GameConfig.OBSTACLE_REPULSION_RADIUS
	var cell_radius := ceili(radius)
	var repulsion := Vector2.ZERO
	for row in range(maxi(0, cell.y - cell_radius), mini(GameConfig.GRID_ROWS - 1, cell.y + cell_radius) + 1):
		for column in range(maxi(0, cell.x - cell_radius), mini(GameConfig.GRID_COLUMNS - 1, cell.x + cell_radius) + 1):
			var obstacle_cell := Vector2i(column, row)
			if not is_blocked(obstacle_cell):
				continue
			var offset := position - (Vector2(obstacle_cell) + Vector2(0.5, 0.5))
			var distance := offset.length()
			if distance >= radius:
				continue
			if distance <= 0.000001:
				repulsion += Vector2.RIGHT
			else:
				repulsion += offset / distance * (1.0 - distance / radius)
	return repulsion.normalized() if repulsion.length_squared() > 0.000001 else Vector2.ZERO


func _move_without_entering_blocked(position: Vector2, motion: Vector2) -> Vector2:
	var candidate_motions: Array[Vector2] = [motion, Vector2(motion.x, 0.0), Vector2(0.0, motion.y)]
	for candidate_motion in candidate_motions:
		var candidate: Vector2 = position + candidate_motion
		candidate.x = clampf(candidate.x, 0.2, float(GameConfig.GRID_COLUMNS) - 0.2)
		candidate.y = clampf(candidate.y, 0.5, float(GameConfig.GRID_ROWS) - 0.5)
		var cell := Vector2i(floori(candidate.x), floori(candidate.y))
		if not is_blocked(cell):
			return candidate
	return position


func _assign_hq_fallback(team: int, position: Vector2) -> void:
	var reached_terminal_band := (
		team == TEAM_ALLY and position.y <= GameConfig.HQ_FALLBACK_BAND
		or team == TEAM_ENEMY and position.y >= float(GameConfig.GRID_ROWS) - GameConfig.HQ_FALLBACK_BAND
	)
	if not reached_terminal_band:
		return
	var hq_id := enemy_hq_id if team == TEAM_ALLY else ally_hq_id
	var building_index := _building_index_from_id(hq_id)
	if building_index < 0 or bool(buildings[building_index].destroyed):
		return
	_found_target_id = -hq_id
	_found_unit_index = -1
	_found_building_index = building_index
	_found_target_position = Vector2(buildings[building_index].cell) + Vector2(0.5, 0.5)


func _attack_target(attacker_index: int, target_unit_index: int, building_index: int) -> void:
	var unit_kind := unit_kinds[attacker_index]
	unit_cooldowns[attacker_index] = _unit_attack_interval(unit_kind)
	unit_lunge_timers[attacker_index] = GameConfig.UNIT_LUNGE_DURATION
	var attacker_team := unit_teams[attacker_index]
	if target_unit_index >= 0 and target_unit_index < unit_ids.size():
		if unit_kind == UNIT_RANGED:
			_events.append({"type": "ranged_shot", "team": attacker_team, "origin": unit_positions[attacker_index], "position": unit_positions[target_unit_index]})
		unit_hp[target_unit_index] -= _unit_attack_damage(unit_kind)
		unit_last_attacker_teams[target_unit_index] = attacker_team
		_events.append({"type": "hit", "team": unit_teams[target_unit_index], "position": unit_positions[target_unit_index]})
		return
	if building_index >= 0 and building_index < buildings.size():
		if unit_kind == UNIT_RANGED:
			_events.append({"type": "ranged_shot", "team": attacker_team, "origin": unit_positions[attacker_index], "position": Vector2(buildings[building_index].cell) + Vector2(0.5, 0.5)})
		apply_building_damage(int(buildings[building_index].id), _unit_attack_damage(unit_kind), attacker_team)


func _remove_dead_units() -> void:
	var index := unit_ids.size() - 1
	var removed_any := false
	while index >= 0:
		if unit_hp[index] <= 0.0:
			var dead_position := unit_positions[index]
			var dead_team := unit_teams[index]
			var killer_team := unit_last_attacker_teams[index]
			_events.append({"type": "unit_death", "team": dead_team, "position": dead_position})
			_award_kill(killer_team)
			_remove_unit_at(index)
			removed_any = true
		index -= 1
	if removed_any:
		_rebuild_unit_index()


func _remove_unit_at(index: int) -> void:
	var last := unit_ids.size() - 1
	if index != last:
		unit_ids[index] = unit_ids[last]
		unit_teams[index] = unit_teams[last]
		unit_kinds[index] = unit_kinds[last]
		unit_positions[index] = unit_positions[last]
		unit_hp[index] = unit_hp[last]
		unit_states[index] = unit_states[last]
		unit_target_ids[index] = unit_target_ids[last]
		unit_cooldowns[index] = unit_cooldowns[last]
		unit_last_attacker_teams[index] = unit_last_attacker_teams[last]
		unit_speed_scales[index] = unit_speed_scales[last]
		unit_lunge_timers[index] = unit_lunge_timers[last]
		unit_lunge_directions[index] = unit_lunge_directions[last]
	unit_ids.resize(last)
	unit_teams.resize(last)
	unit_kinds.resize(last)
	unit_positions.resize(last)
	unit_hp.resize(last)
	unit_states.resize(last)
	unit_target_ids.resize(last)
	unit_cooldowns.resize(last)
	unit_last_attacker_teams.resize(last)
	unit_speed_scales.resize(last)
	unit_lunge_timers.resize(last)
	unit_lunge_directions.resize(last)


func _rebuild_unit_index() -> void:
	_unit_index_by_id.clear()
	for unit_index in unit_ids.size():
		_unit_index_by_id[unit_ids[unit_index]] = unit_index


func _add_building(team: int, kind: int, cell: Vector2i, unit_kind: int) -> int:
	var building_id := _next_building_id
	_next_building_id += 1
	var maximum_hp := GameConfig.HQ_MAX_HP if kind == BUILDING_HQ else GameConfig.SPAWNER_MAX_HP
	buildings.append({
		"id": building_id,
		"team": team,
		"kind": kind,
		"unit_kind": unit_kind,
		"cell": cell,
		"hp": maximum_hp,
		"max_hp": maximum_hp,
		"spawn_timer": GameConfig.SPAWNER_PRODUCTION_INTERVAL,
		"destroyed": false,
	})
	return building_id


func _spawner_cost(unit_kind: int) -> int:
	return GameConfig.RANGED_SPAWNER_COST if unit_kind == UNIT_RANGED else GameConfig.SPAWNER_COST


func _unit_max_hp(unit_kind: int) -> float:
	return GameConfig.RANGED_UNIT_MAX_HP if unit_kind == UNIT_RANGED else GameConfig.UNIT_MAX_HP


func _unit_speed(unit_kind: int) -> float:
	return GameConfig.RANGED_UNIT_SPEED if unit_kind == UNIT_RANGED else GameConfig.UNIT_SPEED


func _unit_attack_range(unit_kind: int) -> float:
	return GameConfig.RANGED_UNIT_ATTACK_RANGE if unit_kind == UNIT_RANGED else GameConfig.UNIT_ATTACK_RANGE


func _unit_attack_damage(unit_kind: int) -> float:
	return GameConfig.RANGED_UNIT_ATTACK_DAMAGE if unit_kind == UNIT_RANGED else GameConfig.UNIT_ATTACK_DAMAGE


func _unit_attack_interval(unit_kind: int) -> float:
	return GameConfig.RANGED_UNIT_ATTACK_INTERVAL if unit_kind == UNIT_RANGED else GameConfig.UNIT_ATTACK_INTERVAL


func _building_at(cell: Vector2i) -> int:
	for index in buildings.size():
		if not bool(buildings[index].destroyed) and Vector2i(buildings[index].cell) == cell:
			return index
	return -1


func _building_index_from_id(building_id: int) -> int:
	for index in buildings.size():
		if int(buildings[index].id) == building_id:
			return index
	return -1


func _count_spawners(team: int) -> int:
	var count := 0
	for building in buildings:
		if not bool(building.destroyed) and int(building.team) == team and int(building.kind) == BUILDING_SPAWNER:
			count += 1
	return count


func _award_kill(team: int) -> void:
	if team == TEAM_ALLY:
		ally_gold += GameConfig.KILL_REWARD
	elif team == TEAM_ENEMY:
		enemy_gold += GameConfig.KILL_REWARD


func _check_terminal_state() -> void:
	if result != "":
		return
	var ally_occupancy := get_occupancy(TEAM_ALLY)
	if ally_occupancy >= GameConfig.OCCUPANCY_WIN_RATIO:
		result = "VICTORY"
		return
	if ally_occupancy <= 1.0 - GameConfig.OCCUPANCY_WIN_RATIO:
		result = "DEFEAT"
		return
	if time_remaining > 0.0:
		return
	var enemy_occupancy := 1.0 - ally_occupancy
	if not is_equal_approx(ally_occupancy, enemy_occupancy):
		result = "VICTORY" if ally_occupancy > enemy_occupancy else "DEFEAT"
		return
	var ally_hq_ratio := _building_hp_ratio(ally_hq_id)
	var enemy_hq_ratio := _building_hp_ratio(enemy_hq_id)
	if not is_equal_approx(ally_hq_ratio, enemy_hq_ratio):
		result = "VICTORY" if ally_hq_ratio > enemy_hq_ratio else "DEFEAT"
		return
	var ally_army_hp := 0.0
	var enemy_army_hp := 0.0
	for index in unit_ids.size():
		if unit_teams[index] == TEAM_ALLY:
			ally_army_hp += unit_hp[index]
		else:
			enemy_army_hp += unit_hp[index]
	result = "VICTORY" if ally_army_hp > enemy_army_hp else "DEFEAT"


func _building_hp_ratio(building_id: int) -> float:
	var index := _building_index_from_id(building_id)
	if index < 0:
		return 0.0
	return float(buildings[index].hp) / float(buildings[index].max_hp)


func _cell_is_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GameConfig.GRID_COLUMNS and cell.y >= 0 and cell.y < GameConfig.GRID_ROWS


func _cell_index(cell: Vector2i) -> int:
	return cell.y * GameConfig.GRID_COLUMNS + cell.x


func _generate_blocked_cells() -> void:
	var obstacle_rng := RandomNumberGenerator.new()
	obstacle_rng.seed = GameConfig.OBSTACLE_SEED
	var row_counts := PackedInt32Array()
	row_counts.resize(GameConfig.GRID_ROWS)
	var pairs_added := 0
	while pairs_added < GameConfig.OBSTACLE_PAIR_COUNT:
		var cell := Vector2i(
			obstacle_rng.randi_range(0, GameConfig.GRID_COLUMNS - 1),
			obstacle_rng.randi_range(GameConfig.OBSTACLE_MIN_ROW, GameConfig.OBSTACLE_MAX_ROW)
		)
		var mirrored := Vector2i(GameConfig.GRID_COLUMNS - 1 - cell.x, GameConfig.GRID_ROWS - 1 - cell.y)
		if is_blocked(cell) or is_blocked(mirrored):
			continue
		if row_counts[cell.y] >= GameConfig.OBSTACLE_MAX_PER_ROW or row_counts[mirrored.y] >= GameConfig.OBSTACLE_MAX_PER_ROW:
			continue
		blocked[_cell_index(cell)] = 1
		blocked[_cell_index(mirrored)] = 1
		row_counts[cell.y] += 1
		row_counts[mirrored.y] += 1
		pairs_added += 1
