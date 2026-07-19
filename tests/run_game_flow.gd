extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = load("res://tests/test_game_flow.gd").new()
	var failures: Array[String] = await suite.run(self)
	if failures.is_empty():
		print("GAME FLOW TESTS PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GAME FLOW TEST FAILED: %s" % failure)
	quit(1)

