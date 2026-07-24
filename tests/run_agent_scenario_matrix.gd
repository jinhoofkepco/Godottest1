extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = load("res://tests/test_agent_scenario_matrix.gd").new()
	var failures: Array[String] = suite.run()
	for line in suite.output_lines:
		print(line)
	if failures.is_empty():
		print("AGENT SCENARIO MATRIX PASS")
		quit(0)
		return
	for failure in failures:
		push_error("AGENT SCENARIO MATRIX FAILED: %s" % failure)
	quit(1)
