extends SceneTree

const SimulationScript = preload("res://scripts/battle_simulation.gd")
const OUTPUT_PATH := "res://tests/fixtures/gdscript_determinism.json"
const CHECKPOINT_TICKS := [0, 30, 60, 120, 180]


func _initialize() -> void:
	var simulation = SimulationScript.new()
	simulation.reset()
	simulation.add_building(simulation.TEAM_ENEMY, simulation.BUILDING_SPAWNER, Vector2i(8, 8), simulation.UNIT_MELEE)
	simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_SPAWNER, Vector2i(13, 35), simulation.UNIT_MELEE)
	simulation.add_building(simulation.TEAM_ENEMY, simulation.BUILDING_SPAWNER, Vector2i(14, 8), simulation.UNIT_RANGED)
	simulation.add_building(simulation.TEAM_ALLY, simulation.BUILDING_SPAWNER, Vector2i(7, 35), simulation.UNIT_RANGED)
	var checkpoints: Array[Dictionary] = []
	for tick_index in range(CHECKPOINT_TICKS[-1] + 1):
		if tick_index in CHECKPOINT_TICKS:
			checkpoints.append(_checkpoint(simulation, tick_index))
		if tick_index < CHECKPOINT_TICKS[-1]:
			simulation.tick(1.0 / 30.0)
	var payload := {
		"schema": 1,
		"seed": 731942,
		"fixed_delta": 1.0 / 30.0,
		"inputs": [
			{"team": simulation.TEAM_ENEMY, "kind": simulation.UNIT_MELEE, "cell": [8, 8]},
			{"team": simulation.TEAM_ALLY, "kind": simulation.UNIT_MELEE, "cell": [13, 35]},
			{"team": simulation.TEAM_ENEMY, "kind": simulation.UNIT_RANGED, "cell": [14, 8]},
			{"team": simulation.TEAM_ALLY, "kind": simulation.UNIT_RANGED, "cell": [7, 35]},
		],
		"checkpoints": checkpoints,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/fixtures"))
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not write GDScript golden fixture")
		quit(1)
		return
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.close()
	print("GDSCRIPT GOLDEN WRITTEN: %s" % OUTPUT_PATH)
	quit(0)


func _checkpoint(simulation, tick_index: int) -> Dictionary:
	var counts := PackedInt32Array()
	counts.resize(8)
	for index in simulation.unit_ids.size():
		var offset := 0 if simulation.unit_teams[index] == simulation.TEAM_ENEMY else 4
		counts[offset + simulation.unit_kinds[index]] += 1
	return {
		"tick": tick_index,
		"counts": Array(counts),
		"ally_hq_hp": _building_hp(simulation, simulation.ally_hq_id),
		"enemy_hq_hp": _building_hp(simulation, simulation.enemy_hq_id),
		"ally_gold": simulation.ally_gold,
		"enemy_gold": simulation.enemy_gold,
		"ally_occupancy": simulation.get_occupancy(simulation.TEAM_ALLY),
		"time_remaining": simulation.time_remaining,
		"result": simulation.result,
	}


func _building_hp(simulation, building_id: int) -> float:
	for building in simulation.buildings:
		if int(building.id) == building_id:
			return float(building.hp)
	return 0.0
