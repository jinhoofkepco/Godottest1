extends RefCounted

var failures: Array[String] = []


func run(tree: SceneTree) -> Array[String]:
	var main_scene := load("res://scenes/main.tscn")
	_expect(main_scene != null, "main scene exists")
	if main_scene == null:
		return failures
	await _test_economy_and_victory(tree, main_scene)
	await _test_defeat(tree, main_scene)
	return failures


func _test_economy_and_victory(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	_expect(main.gold == 150, "match starts with 150 gold")
	_expect(main.try_place_tower(Vector2i(2, 8)), "first tower placement succeeds")
	_expect(main.try_place_tower(Vector2i(4, 8)), "second tower placement succeeds")
	_expect(main.try_place_tower(Vector2i(6, 8)), "third tower placement succeeds")
	_expect(main.gold == 0, "three towers spend all starting gold")
	_expect(not main.try_place_tower(Vector2i(3, 9)), "placement fails without gold")
	main.wave_manager.spawn_interval = 0.001
	main.fx.hit_stop_duration = 0.0
	for wave in 5:
		main.start_next_wave()
		var frames := 0
		while main.wave_manager.wave_active and frames < 1800:
			await tree.process_frame
			for enemy in main.enemies.get_children():
				enemy.take_damage(9999.0)
			frames += 1
		_expect(frames < 1800, "wave %d completes in accelerated test" % (wave + 1))
	_expect(main.game_result == "VICTORY", "clearing wave five reaches victory")
	main.queue_free()
	await tree.process_frame


func _test_defeat(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	for hit in 20:
		main.damage_core(1)
	_expect(main.core_hp == 0, "twenty hits deplete core")
	_expect(main.game_result == "DEFEAT", "zero core HP reaches defeat")
	main.queue_free()
	await tree.process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

