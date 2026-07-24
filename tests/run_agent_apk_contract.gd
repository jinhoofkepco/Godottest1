extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = load("res://tests/test_agent_apk_contract.gd").new()
	var failures: Array[String] = suite.run()
	if failures.is_empty():
		print("AGENT APK CONTRACT PASS")
		quit(0)
		return
	for failure in failures:
		push_error("AGENT APK CONTRACT FAILED: %s" % failure)
	quit(1)
