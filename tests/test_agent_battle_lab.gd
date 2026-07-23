extends RefCounted

const SIM_PATH := "res://scripts/agent_lab/AgentBattleSimulation.cs"

var failures: Array[String] = []


func run() -> Array[String]:
	_expect(ResourceLoader.exists(SIM_PATH), "agent lab C# simulation exists")
	if failures.is_empty():
		var simulation = load(SIM_PATH).new()
		for method in ["ResetExperiment", "Step", "RunTicks", "GetSnapshot", "GetMetrics"]:
			_expect(simulation.has_method(method), "simulation exposes %s" % method)
		simulation.free()
	return failures


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
