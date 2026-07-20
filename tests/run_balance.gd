extends SceneTree

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var passive := _simulate(false)
	var active := _simulate(true)
	print("BALANCE PATHS: passive=%s %.1fs occupancy=%.3f active=%s %.1fs occupancy=%.3f" % [passive.result, passive.elapsed, passive.occupancy, active.result, active.elapsed, active.occupancy])
	if passive.result != "DEFEAT" or active.result != "VICTORY" or passive.elapsed < 120.0 or passive.elapsed > 240.0 or active.elapsed < 300.0 or active.elapsed > 420.0:
		push_error("BALANCE PATHS FAILED: passive defeat must take 2-4 minutes and a fully responding match must end in blue victory within 5-7 minutes")
		quit(1)
		return
	quit(0)


func _simulate(active: bool) -> Dictionary:
	var simulation = SIMULATION_SCENE.instantiate()
	simulation.call("Reset")
	simulation.call("ApplyDebugCommand", {"op": "set_seed", "value": 13004 if active else 12000})
	if active:
		simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 180, "enemy": 180})
		simulation.call("SetAiEnabled", TEAM_ENEMY, true)
		simulation.call("SetAiEnabled", TEAM_ALLY, true)
	var elapsed := 0.0
	while elapsed < 420.0:
		var executed := int(simulation.call("RunHeadlessTicks", 150))
		elapsed += float(executed) / 30.0
		var hud: Dictionary = simulation.call("GetHudSnapshot")
		if String(hud.result) != "":
			var result := {"result": String(hud.result), "elapsed": elapsed, "occupancy": float(hud.occupancy)}
			simulation.free()
			return result
	if elapsed >= 420.0: simulation.call("RunHeadlessTicks", 1)
	var hud: Dictionary = simulation.call("GetHudSnapshot")
	var result := {"result": String(hud.result), "elapsed": elapsed, "occupancy": float(hud.occupancy)}
	simulation.free()
	return result
