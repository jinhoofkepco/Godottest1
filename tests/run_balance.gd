extends SceneTree

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var passive := _simulate(false)
	var active := _simulate(true)
	print("BALANCE PATHS: passive=%s %.1fs occupancy=%.3f active=%s %.1fs occupancy=%.3f" % [passive.result, passive.elapsed, passive.occupancy, active.result, active.elapsed, active.occupancy])
	if passive.result != "DEFEAT" or active.result != "VICTORY" or passive.elapsed < 100.0 or active.elapsed < 100.0:
		push_error("BALANCE PATHS FAILED: passive must lose and reinforced route must win after at least 100 seconds")
		quit(1)
		return
	quit(0)


func _simulate(active: bool) -> Dictionary:
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	var plans := [
		{"cell": Vector2i(4, 36), "kind": 0},
		{"cell": Vector2i(8, 36), "kind": 1},
		{"cell": Vector2i(14, 36), "kind": 0},
		{"cell": Vector2i(18, 36), "kind": 4},
		{"cell": Vector2i(10, 41), "kind": 2},
		{"cell": Vector2i(16, 35), "kind": 3},
	]
	var next_plan := 0
	var ticks := 0
	while ticks < 180 * 30:
		if active and next_plan < plans.size():
			var plan: Dictionary = plans[next_plan]
			if simulation.call("TryBuild", 2, Vector2i(plan.cell), int(plan.kind)):
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
	return {"result": String(hud.result), "elapsed": 180.0, "occupancy": float(hud.occupancy)}
