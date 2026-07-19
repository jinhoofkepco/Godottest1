class_name BattleSimulation
extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const config = GameConfig

const TEAM_NONE := 0
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const BUILDING_HQ := 0
const BUILDING_SPAWNER := 1

var unit_ids := PackedInt32Array()
var unit_teams := PackedInt32Array()
var unit_positions := PackedVector2Array()
var unit_hp := PackedFloat32Array()
var unit_states := PackedInt32Array()
var unit_target_ids := PackedInt32Array()
var unit_cooldowns := PackedFloat32Array()
var unit_last_attacker_teams := PackedInt32Array()

var buildings: Array[Dictionary] = []
var ownership := PackedByteArray()
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
var _events: Array[Dictionary] = []
var _buckets: Array[Array] = []


func reset() -> void:
	unit_ids.clear()
	unit_teams.clear()
	unit_positions.clear()
	unit_hp.clear()
	unit_states.clear()
	unit_target_ids.clear()
	unit_cooldowns.clear()
	unit_last_attacker_teams.clear()
	buildings.clear()
	ownership.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	ownership.fill(TEAM_NONE)
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
	_events.clear()
	_buckets.clear()
	_buckets.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	enemy_hq_id = _add_building(TEAM_ENEMY, BUILDING_HQ, Vector2i(GameConfig.GRID_COLUMNS / 2, 0))
	ally_hq_id = _add_building(TEAM_ALLY, BUILDING_HQ, Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS - 1))
	recalculate_territory(false)


func spawn_unit(team: int, position: Vector2) -> int:
	var unit_id := _next_unit_id
	_next_unit_id += 1
	unit_ids.append(unit_id)
	unit_teams.append(team)
	unit_positions.append(position)
	unit_hp.append(GameConfig.UNIT_MAX_HP)
	unit_states.append(0)
	unit_target_ids.append(0)
	unit_cooldowns.append(0.0)
	unit_last_attacker_teams.append(TEAM_NONE)
	return unit_id


func tick(delta: float) -> void:
	if result != "" or delta <= 0.0:
		return
	_apply_income(delta)
	time_remaining = maxf(0.0, time_remaining - delta)
	_tick_accumulator += delta
	var fixed_delta := 1.0 / float(GameConfig.SIM_TICK_RATE)
	while _tick_accumulator + 0.000001 >= fixed_delta and result == "":
		_tick_accumulator -= fixed_delta
		_step(fixed_delta)
	if result == "":
		_check_terminal_state()


func try_build_spawner(team: int, cell: Vector2i) -> bool:
	if result != "" or not _cell_is_valid(cell):
		return false
	if ownership[_cell_index(cell)] != team or _building_at(cell) != -1:
		return false
	if team == TEAM_ALLY:
		if ally_gold < GameConfig.SPAWNER_COST:
			return false
		ally_gold -= GameConfig.SPAWNER_COST
	elif team == TEAM_ENEMY:
		if enemy_gold < GameConfig.SPAWNER_COST:
			return false
		enemy_gold -= GameConfig.SPAWNER_COST
	else:
		return false
	var building_id := _add_building(team, BUILDING_SPAWNER, cell)
	_events.append({"type": "spawner_built", "team": team, "building_id": building_id, "cell": cell})
	recalculate_territory()
	return true


func get_ownership() -> PackedByteArray:
	return ownership.duplicate()


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
	for column in GameConfig.GRID_COLUMNS:
		var red_front := 0.0
		var blue_front := float(GameConfig.GRID_ROWS - 1)
		for index in unit_ids.size():
			var position := unit_positions[index]
			if floori(position.x) != column or unit_hp[index] <= 0.0:
				continue
			if unit_teams[index] == TEAM_ENEMY:
				red_front = maxf(red_front, position.y)
			elif unit_teams[index] == TEAM_ALLY:
				blue_front = minf(blue_front, position.y)
		for building in buildings:
			if bool(building.get("destroyed", false)):
				continue
			var cell: Vector2i = building.cell
			if cell.x != column:
				continue
			if int(building.team) == TEAM_ENEMY:
				red_front = maxf(red_front, float(cell.y))
			elif int(building.team) == TEAM_ALLY:
				blue_front = minf(blue_front, float(cell.y))
		var boundary := (red_front + blue_front) * 0.5
		for row in GameConfig.GRID_ROWS:
			var owner := TEAM_ENEMY if float(row) + 0.5 <= boundary else TEAM_ALLY
			var index := row * GameConfig.GRID_COLUMNS + column
			ownership[index] = owner
			if emit_changes and previous.size() == ownership.size() and previous[index] != owner:
				_events.append({"type": "territory_changed", "cell": Vector2i(column, row), "team": owner})


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
		_award_kill(attacker_team)
		recalculate_territory()


func drain_events() -> Array:
	var drained: Array = _events.duplicate(true)
	_events.clear()
	return drained


func _step(delta: float) -> void:
	_update_enemy_ai(delta)
	_update_spawners(delta)
	_rebuild_buckets()
	target_candidate_checks = 0
	for index in unit_ids.size():
		if unit_hp[index] <= 0.0:
			continue
		unit_cooldowns[index] = maxf(0.0, unit_cooldowns[index] - delta)
		var target := _find_target(index)
		unit_target_ids[index] = int(target.id)
		if int(target.id) != 0:
			unit_states[index] = 1
			if unit_cooldowns[index] <= 0.0:
				_attack_target(index, target)
		else:
			unit_states[index] = 0
			var direction := -1.0 if unit_teams[index] == TEAM_ALLY else 1.0
			var position := unit_positions[index]
			position.y = clampf(position.y + direction * GameConfig.UNIT_SPEED * delta, 0.5, float(GameConfig.GRID_ROWS) - 0.5)
			unit_positions[index] = position
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
	for offset in GameConfig.GRID_COLUMNS:
		var column := (_enemy_build_cursor + offset) % GameConfig.GRID_COLUMNS
		for row in range(1, GameConfig.GRID_ROWS - 1):
			var cell := Vector2i(column, row)
			if try_build_spawner(TEAM_ENEMY, cell):
				_enemy_build_cursor = (column + 3) % GameConfig.GRID_COLUMNS
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
			var offset_y := -0.2 if team == TEAM_ALLY else 0.2
			var unit_id := spawn_unit(team, Vector2(cell) + Vector2(0.5, 0.5 + offset_y))
			_events.append({"type": "unit_produced", "team": team, "unit_id": unit_id, "cell": cell})
		buildings[index] = building


func _rebuild_buckets() -> void:
	for bucket in _buckets:
		bucket.clear()
	for index in unit_ids.size():
		if unit_hp[index] <= 0.0:
			continue
		var cell := Vector2i(
			clampi(floori(unit_positions[index].x), 0, GameConfig.GRID_COLUMNS - 1),
			clampi(floori(unit_positions[index].y), 0, GameConfig.GRID_ROWS - 1)
		)
		_buckets[_cell_index(cell)].append(index)


func _find_target(unit_index: int) -> Dictionary:
	var position := unit_positions[unit_index]
	var team := unit_teams[unit_index]
	var cell := Vector2i(floori(position.x), floori(position.y))
	var best_distance_sq := GameConfig.UNIT_ATTACK_RANGE * GameConfig.UNIT_ATTACK_RANGE
	var best_id := 0
	var best_index := -1
	for row in range(maxi(0, cell.y - 1), mini(GameConfig.GRID_ROWS - 1, cell.y + 1) + 1):
		for column in range(maxi(0, cell.x - 1), mini(GameConfig.GRID_COLUMNS - 1, cell.x + 1) + 1):
			for candidate_index in _buckets[row * GameConfig.GRID_COLUMNS + column]:
				target_candidate_checks += 1
				if candidate_index == unit_index or unit_teams[candidate_index] == team or unit_hp[candidate_index] <= 0.0:
					continue
				var distance_sq := position.distance_squared_to(unit_positions[candidate_index])
				if distance_sq <= best_distance_sq:
					best_distance_sq = distance_sq
					best_id = unit_ids[candidate_index]
					best_index = candidate_index
	if best_id != 0:
		return {"id": best_id, "unit_index": best_index, "building_index": -1}
	for building_index in buildings.size():
		var building := buildings[building_index]
		if bool(building.destroyed) or int(building.team) == team:
			continue
		var building_position := Vector2(building.cell) + Vector2(0.5, 0.5)
		var distance_sq := position.distance_squared_to(building_position)
		if distance_sq <= best_distance_sq:
			best_distance_sq = distance_sq
			best_id = -int(building.id)
			best_index = building_index
	return {"id": best_id, "unit_index": -1, "building_index": best_index}


func _attack_target(attacker_index: int, target: Dictionary) -> void:
	unit_cooldowns[attacker_index] = GameConfig.UNIT_ATTACK_INTERVAL
	var attacker_team := unit_teams[attacker_index]
	var target_unit_index := int(target.unit_index)
	if target_unit_index >= 0 and target_unit_index < unit_ids.size():
		unit_hp[target_unit_index] -= GameConfig.UNIT_ATTACK_DAMAGE
		unit_last_attacker_teams[target_unit_index] = attacker_team
		_events.append({"type": "hit", "team": unit_teams[target_unit_index], "position": unit_positions[target_unit_index]})
		return
	var building_index := int(target.building_index)
	if building_index >= 0 and building_index < buildings.size():
		apply_building_damage(int(buildings[building_index].id), GameConfig.UNIT_ATTACK_DAMAGE, attacker_team)


func _remove_dead_units() -> void:
	var index := unit_ids.size() - 1
	while index >= 0:
		if unit_hp[index] <= 0.0:
			var dead_position := unit_positions[index]
			var dead_team := unit_teams[index]
			var killer_team := unit_last_attacker_teams[index]
			_events.append({"type": "unit_death", "team": dead_team, "position": dead_position})
			_award_kill(killer_team)
			_remove_unit_at(index)
		index -= 1


func _remove_unit_at(index: int) -> void:
	var last := unit_ids.size() - 1
	if index != last:
		unit_ids[index] = unit_ids[last]
		unit_teams[index] = unit_teams[last]
		unit_positions[index] = unit_positions[last]
		unit_hp[index] = unit_hp[last]
		unit_states[index] = unit_states[last]
		unit_target_ids[index] = unit_target_ids[last]
		unit_cooldowns[index] = unit_cooldowns[last]
		unit_last_attacker_teams[index] = unit_last_attacker_teams[last]
	unit_ids.resize(last)
	unit_teams.resize(last)
	unit_positions.resize(last)
	unit_hp.resize(last)
	unit_states.resize(last)
	unit_target_ids.resize(last)
	unit_cooldowns.resize(last)
	unit_last_attacker_teams.resize(last)


func _add_building(team: int, kind: int, cell: Vector2i) -> int:
	var building_id := _next_building_id
	_next_building_id += 1
	var maximum_hp := GameConfig.HQ_MAX_HP if kind == BUILDING_HQ else GameConfig.SPAWNER_MAX_HP
	buildings.append({
		"id": building_id,
		"team": team,
		"kind": kind,
		"cell": cell,
		"hp": maximum_hp,
		"max_hp": maximum_hp,
		"spawn_timer": GameConfig.SPAWNER_PRODUCTION_INTERVAL,
		"destroyed": false,
	})
	return building_id


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
