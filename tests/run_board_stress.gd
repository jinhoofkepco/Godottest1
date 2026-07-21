extends SceneTree

const GameConfig = preload("res://scripts/game_config.gd")
const MAIN_SCENE = preload("res://scenes/main.tscn")
const FLIP_COUNT := 30
const WARMUP_ROUNDS := 3
const MEASURED_ROUNDS := 18


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var optimized: bool = main.grid.has_method("apply_board_delta") and main.simulation.has_method("GetBoardDelta")
	var samples := PackedFloat64Array()
	var boundary_samples := PackedFloat64Array()
	var update_samples := PackedFloat64Array()
	var baseline_samples := PackedFloat64Array()
	for baseline_index in WARMUP_ROUNDS + MEASURED_ROUNDS:
		var baseline_started := Time.get_ticks_usec()
		RenderingServer.force_draw(false)
		if baseline_index >= WARMUP_ROUNDS:
			baseline_samples.append(float(Time.get_ticks_usec() - baseline_started) / 1000.0)
	for round_index in WARMUP_ROUNDS + MEASURED_ROUNDS:
		var started := Time.get_ticks_usec()
		var boundary_started := started
		var update_started := started
		if optimized:
			var arrays := _flip_arrays(round_index)
			main.simulation.call("ApplyDebugCommand", {"op": "force_ownership_delta", "indices": arrays.indices, "owners": arrays.owners})
			boundary_started = Time.get_ticks_usec()
			var version: int = main.simulation.call("GetBoardVersion")
			var delta: Dictionary = main.simulation.call("GetBoardDelta")
			boundary_samples.append(float(Time.get_ticks_usec() - boundary_started) / 1000.0)
			update_started = Time.get_ticks_usec()
			main.grid.apply_board_delta(delta)
			main._last_board_version = version
		else:
			var snapshot: Dictionary = main.simulation.call("GetBoardSnapshot").duplicate(true)
			var ownership: PackedByteArray = snapshot.ownership.duplicate()
			var arrays := _flip_arrays(round_index)
			for index in FLIP_COUNT:
				ownership[arrays.indices[index]] = arrays.owners[index]
			snapshot.ownership = ownership
			snapshot.version = int(snapshot.version) + round_index + 1
			boundary_samples.append(float(Time.get_ticks_usec() - boundary_started) / 1000.0)
			update_started = Time.get_ticks_usec()
			main.grid.sync_board(snapshot)
			for index in FLIP_COUNT:
				var cell_index: int = arrays.indices[index]
				main.fx.show_territory_change(Vector2i(cell_index % GameConfig.GRID_COLUMNS, cell_index / GameConfig.GRID_COLUMNS), arrays.owners[index])
		RenderingServer.force_draw(false)
		var update_ms := float(Time.get_ticks_usec() - update_started) / 1000.0
		var total_ms := float(Time.get_ticks_usec() - started) / 1000.0
		if round_index >= WARMUP_ROUNDS:
			update_samples.append(update_ms)
			samples.append(total_ms)
	var render_p95 := _percentile(update_samples, 0.95)
	var baseline_p95 := _percentile(baseline_samples, 0.95)
	var flip_spike_p95 := maxf(0.0, render_p95 - baseline_p95)
	if optimized and flip_spike_p95 > _environment_budget("BOARD_FLIP_BUDGET_MS", 2.0):
		push_error("BOARD FLIP TARGET MISS: incremental p95 %.3f ms" % flip_spike_p95)
		quit(1)
		return
	print("BOARD FLIP STRESS: mode=%s cells=%d total_avg=%.3f total_p95=%.3f boundary_avg=%.3f render_avg=%.3f render_p95=%.3f baseline_p95=%.3f spike_p95=%.3f" % [
		"delta_multimesh" if optimized else "full_draw_fx", FLIP_COUNT, _average(samples), _percentile(samples, 0.95), _average(boundary_samples), _average(update_samples), render_p95, baseline_p95, flip_spike_p95,
	])
	main.queue_free()
	quit(0)


func _flip_arrays(round_index: int) -> Dictionary:
	var indices := PackedInt32Array()
	var owners := PackedInt32Array()
	for offset in FLIP_COUNT:
		var column := offset % GameConfig.GRID_COLUMNS
		var row := 5 + floori(float(offset) / GameConfig.GRID_COLUMNS)
		indices.append(row * GameConfig.GRID_COLUMNS + column)
		owners.append(2 if (round_index + offset) % 2 == 0 else 1)
	return {"indices": indices, "owners": owners}


func _average(samples: PackedFloat64Array) -> float:
	var total := 0.0
	for sample in samples:
		total += sample
	return total / maxf(1.0, float(samples.size()))


func _percentile(samples: PackedFloat64Array, ratio: float) -> float:
	var sorted := Array(samples)
	sorted.sort()
	return float(sorted[clampi(ceili(float(sorted.size()) * ratio) - 1, 0, sorted.size() - 1)])


func _environment_budget(name: String, fallback: float) -> float:
	var value := OS.get_environment(name)
	return maxf(0.001, value.to_float()) if not value.is_empty() else fallback
