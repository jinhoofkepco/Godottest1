extends SceneTree

const SimulationPreflight = preload("res://tests/simulation_preflight.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not SimulationPreflight.verify():
		quit(1)
		return
	var suite = load("res://tests/test_game_flow.gd").new()
	var failures: Array[String] = await suite.run(self)
	if failures.is_empty():
		print("GAME FLOW TESTS PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GAME FLOW TEST FAILED: %s" % failure)
	quit(1)
