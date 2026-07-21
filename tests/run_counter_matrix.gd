extends SceneTree

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")
const GameConfig = preload("res://scripts/game_config.gd")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const UNIT_SIEGE := 3
const TRIALS := 20


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var contract_simulation = SIMULATION_SCENE.instantiate()
	contract_simulation.call("Reset")
	var shield_multiplier := float(contract_simulation.call("GetEffectiveClassDamageMultiplier", UNIT_RANGED, UNIT_MELEE, true))
	contract_simulation.free()
	var failed := false
	print("COUNTER CONTRACT: RANGED>SHIELDED_MELEE effective_multiplier=%.3f" % shield_multiplier)
	if not is_equal_approx(shield_multiplier, 0.17):
		push_error("COUNTER MATRIX FAILED: shield-aware RANGED damage must use the effective multiplier")
		failed = true
	var scenarios := [
		{"name": "DRAGON>RANGED", "favored": UNIT_DRAGON, "other": UNIT_RANGED, "favored_count": 4, "other_count": 11},
		{"name": "DRAGON>SIEGE", "favored": UNIT_DRAGON, "other": UNIT_SIEGE, "favored_count": 7, "other_count": 11},
	]
	for scenario: Dictionary in scenarios:
		var wins := 0
		for trial in TRIALS:
			wins += 1 if _trial(scenario, trial) else 0
		var rate := float(wins) / float(TRIALS)
		print("COUNTER MATRIX: %s wins=%d/%d rate=%.2f" % [scenario.name, wins, TRIALS, rate])
		if rate < 0.75:
			push_error("COUNTER MATRIX FAILED: %s must reach 75 percent" % scenario.name)
			failed = true
	quit(1 if failed else 0)


func _trial(scenario: Dictionary, trial: int) -> bool:
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	simulation.call("ApplyDebugCommand", {"op": "set_seed", "value": 9000 + trial})
	simulation.call("ApplyDebugCommand", {"op": "clear_units"})
	var elevation := PackedByteArray()
	elevation.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	elevation.fill(0)
	simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	var favored_team := TEAM_ALLY if trial % 2 == 0 else TEAM_ENEMY
	var other_team := TEAM_ENEMY if favored_team == TEAM_ALLY else TEAM_ALLY
	_spawn_group(simulation, favored_team, int(scenario.favored), int(scenario.favored_count), 23.1 if favored_team == TEAM_ALLY else 20.9)
	_spawn_group(simulation, other_team, int(scenario.other), int(scenario.other_count), 23.1 if other_team == TEAM_ALLY else 20.9)
	var snapshot: Dictionary = {}
	for step in range(340):
		simulation.call("Step", 8.0 / 30.0)
		simulation.call("DrainEvents")
		if step % 4 == 0:
			snapshot = simulation.call("GetDebugSnapshot")
			if _team_count(snapshot, favored_team) == 0 or _team_count(snapshot, other_team) == 0:
				break
	if snapshot.is_empty(): snapshot = simulation.call("GetDebugSnapshot")
	var favored_hp := _team_hp(snapshot, favored_team)
	var other_hp := _team_hp(snapshot, other_team)
	if trial == 0:
		print("COUNTER TRACE: %s favored_hp=%.1f other_hp=%.1f favored_units=%d other_units=%d" % [scenario.name, favored_hp, other_hp, _team_count(snapshot, favored_team), _team_count(snapshot, other_team)])
	simulation.free()
	return favored_hp > other_hp


func _spawn_group(simulation, team: int, kind: int, count: int, y: float) -> void:
	for index in count:
		var column := index % 6
		var rank := index / 6
		var position := Vector2(7.75 + float(column) * 0.65, y + (float(rank) * 0.45 if team == TEAM_ALLY else -float(rank) * 0.45))
		simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": team, "kind": kind, "position": position, "exact": true})


func _team_hp(snapshot: Dictionary, team: int) -> float:
	var total := 0.0
	for index in PackedInt32Array(snapshot.unit_teams).size():
		if int(snapshot.unit_teams[index]) == team:
			total += float(snapshot.unit_hp[index])
	return total


func _team_count(snapshot: Dictionary, team: int) -> int:
	var total := 0
	for unit_team in PackedInt32Array(snapshot.unit_teams):
		total += 1 if int(unit_team) == team else 0
	return total
