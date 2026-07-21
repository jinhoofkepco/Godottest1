extends RefCounted

const SIMULATION_SCENE = preload("res://scenes/battle_simulation.tscn")


static func verify() -> bool:
	var probe = SIMULATION_SCENE.instantiate()
	var methods := ["Reset", "Step", "GetDebugSnapshot"]
	for method in methods:
		if not probe.has_method(method):
			push_error("BattleSimulation C# class failed to load: missing %s" % method)
			probe.free()
			return false
	probe.call("Reset")
	probe.call("Step", 0.0)
	var snapshot: Variant = probe.call("GetDebugSnapshot")
	probe.free()
	if not snapshot is Dictionary or not snapshot.has("unit_count"):
		push_error("BattleSimulation C# preflight returned an invalid debug snapshot")
		return false
	return true
