extends SceneTree

const SimulationPreflight = preload("res://tests/simulation_preflight.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not SimulationPreflight.verify():
		quit(1)
		return
	var suite = load("res://tests/test_rules.gd").new()
	var failures: Array[String] = suite.run()
	var flow_suite = load("res://tests/test_flow_features.gd").new()
	failures.append_array(flow_suite.run())
	if failures.is_empty():
		print("RULE TESTS PASS")
		quit(0)
		return
	for failure in failures:
		push_error("RULE TEST FAILED: %s" % failure)
	quit(1)
