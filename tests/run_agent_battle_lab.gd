extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = load("res://tests/test_agent_battle_lab.gd").new()
	var failures: Array[String] = suite.run()
	if failures.is_empty():
		print("AGENT BATTLE LAB TESTS PASS")
		quit(0)
		return
	for failure in failures:
		push_error("AGENT BATTLE LAB TEST FAILED: %s" % failure)
	quit(1)
