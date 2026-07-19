extends RefCounted

var failures: Array[String] = []


func run(tree: SceneTree) -> Array[String]:
	var main_scene := load("res://scenes/main.tscn")
	_expect(main_scene != null, "main scene exists")
	if main_scene == null:
		return failures
	await _test_economy_and_victory(tree, main_scene)
	await _test_defeat(tree, main_scene)
	await _test_final_enemy_core_race(tree, main_scene)
	await _test_final_wave_reward(tree, main_scene)
	await _test_feedback_routing(tree, main_scene)
	await _test_enemy_death_lifecycle(tree)
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


func _test_final_enemy_core_race(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.core_hp = 1
	main.core.set_hp(1)
	main.wave_manager.current_wave = 5
	main.wave_manager.wave_active = true
	main.wave_manager.set("_remaining_to_spawn", 0)
	main.wave_manager.set("_living_enemies", 1)
	main._on_enemy_reached_core(Vector2.ZERO)
	_expect(main.core_hp == 0, "lethal final enemy depletes core before wave resolution")
	_expect(main.game_result == "DEFEAT", "lethal final enemy resolves as defeat, not victory")
	main.queue_free()
	await tree.process_frame


func _test_final_wave_reward(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.gold = 100
	main._on_wave_cleared(5)
	_expect(main.gold == 125, "final wave clear grants the locked +25 reward")
	_expect(main.game_result == "VICTORY", "final wave clear resolves as victory")
	main.queue_free()
	await tree.process_frame


func _test_feedback_routing(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	_expect(main.try_place_tower(Vector2i(2, 8)), "feedback test placement succeeds")
	_expect(main.fx.last_placement_valid and main.fx.placement_feedback_count == 1, "successful placement routes teal diamond feedback")
	main.gold = 0
	_expect(not main.try_place_tower(Vector2i(3, 8)), "feedback test unaffordable placement fails")
	_expect(not main.fx.last_placement_valid and main.fx.placement_feedback_count == 2, "unaffordable placement still routes red invalid X")
	main.start_next_wave()
	_expect(main.hud.banner_wave == 1 and main.hud.banner_time_left > 0.0, "wave start routes a screen-space WAVE 1 banner")
	var leak_count_before: int = main.fx.leak_feedback_count
	main._on_enemy_reached_core(Vector2(4.5, 13.0))
	_expect(main.fx.leak_feedback_count == leak_count_before + 1, "core arrival routes red leak slash feedback")
	_expect(main.core.damage_flash_count == 1, "core arrival routes a red core flash")
	main.queue_free()
	await tree.process_frame


func _test_enemy_death_lifecycle(tree: SceneTree) -> void:
	var grid_script := load("res://scripts/grid.gd")
	var enemy_scene := load("res://scenes/enemy.tscn")
	var grid = grid_script.new()
	var enemy = enemy_scene.instantiate()
	tree.root.add_child(grid)
	tree.root.add_child(enemy)
	enemy.death_shrink_duration = 0.03
	enemy.setup(grid, 2, 0.0, 10.0)
	enemy.take_damage(10.0, enemy.grid_position - Vector2.RIGHT)
	_expect(enemy.death_shrink_left > 0.0 and not enemy.is_queued_for_deletion(), "lethal in-tree enemy starts shrink before deletion")
	var frames := 0
	while is_instance_valid(enemy) and frames < 30:
		await tree.process_frame
		frames += 1
	_expect(not is_instance_valid(enemy), "in-tree enemy is freed after death shrink expires")
	grid.queue_free()
	await tree.process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
