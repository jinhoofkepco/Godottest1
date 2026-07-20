extends SceneTree


func _initialize() -> void:
	var suite = load("res://tests/test_dotnet_port.gd").new()
	var failures: Array[String] = await suite.run_all(self)
	if failures.is_empty():
		print("DOTNET PORT CONTRACTS PASS")
		quit(0)
		return
	for failure in failures:
		push_error("DOTNET PORT CONTRACT FAILED: %s" % failure)
	quit(1)
