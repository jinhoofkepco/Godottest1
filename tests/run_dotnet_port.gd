extends SceneTree

const SimulationPreflight = preload("res://tests/simulation_preflight.gd")


func _initialize() -> void:
	if not SimulationPreflight.verify():
		quit(1)
		return
	var suite = load("res://tests/test_dotnet_port.gd").new()
	var failures: Array[String] = await suite.run_all(self)
	if failures.is_empty():
		print("DOTNET PORT CONTRACTS PASS")
		quit(0)
		return
	for failure in failures:
		push_error("DOTNET PORT CONTRACT FAILED: %s" % failure)
	quit(1)
