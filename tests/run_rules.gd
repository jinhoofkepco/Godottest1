extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = load("res://tests/test_rules.gd").new()
	var failures: Array[String] = suite.run()
	if failures.is_empty():
		print("RULE TESTS PASS")
		quit(0)
		return
	for failure in failures:
		push_error("RULE TEST FAILED: %s" % failure)
	quit(1)

