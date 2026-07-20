extends SceneTree

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var passive := _simulate(false)
	var active := _simulate(true)
	print("BALANCE PATHS: passive=%s %.1fs occupancy=%.3f active=%s %.1fs occupancy=%.3f" % [passive.result, passive.elapsed, passive.occupancy, active.result, active.elapsed, active.occupancy])
	if passive.result != "DEFEAT" or active.result != "VICTORY" or passive.elapsed < 120.0 or active.elapsed < 120.0 or passive.elapsed > 240.0 or active.elapsed > 240.0:
		push_error("BALANCE PATHS FAILED: passive defeat and active victory must finish in 120-240 seconds")
		quit(1)
		return
	quit(0)


func _simulate(active: bool) -> Dictionary:
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	var plans := [
		{"cell": Vector2i(4, 36), "template": {"melee": 7, "ranged": 4, "siege": 1, "dragon": 0}, "formation": 0},
		{"cell": Vector2i(10, 36), "template": {"melee": 4, "ranged": 7, "siege": 1, "dragon": 0}, "formation": 2},
		{"cell": Vector2i(10, 41), "tower": true},
		{"cell": Vector2i(17, 35), "template": {"melee": 9, "ranged": 1, "siege": 1, "dragon": 1}, "formation": 1},
	]
	var next_plan := 0
	var ticks := 0
	while ticks < 240 * 30:
		if active and next_plan < plans.size():
			var plan: Dictionary = plans[next_plan]
			var built: bool = bool(simulation.call("TryBuild", 2, Vector2i(plan.cell), 2)) if bool(plan.get("tower", false)) else bool(simulation.call("TryBuildBarracks", 2, Vector2i(plan.cell), Dictionary(plan.template), int(plan.formation)))
			if built:
				next_plan += 1
		simulation.call("Step", 1.0 / 30.0)
		simulation.call("DrainEvents")
		ticks += 1
		var hud: Dictionary = simulation.call("GetHudSnapshot")
		if String(hud.result) != "":
			simulation.free()
			return {"result": String(hud.result), "elapsed": float(ticks) / 30.0, "occupancy": float(hud.occupancy)}
	var hud: Dictionary = simulation.call("GetHudSnapshot")
	simulation.free()
	return {"result": String(hud.result), "elapsed": 240.0, "occupancy": float(hud.occupancy)}
