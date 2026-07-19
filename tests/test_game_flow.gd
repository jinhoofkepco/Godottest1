extends RefCounted

var failures: Array[String] = []


func run(tree: SceneTree) -> Array[String]:
	var main_scene := load("res://scenes/main.tscn")
	_expect(main_scene != null, "main scene exists")
	if main_scene == null:
		return failures
	await _test_scene_contract(tree, main_scene)
	await _test_dynamic_building(tree, main_scene)
	await _test_production_and_feedback(tree, main_scene)
	await _test_terminal_routes(tree, main_scene)
	return failures


func _test_scene_contract(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	_expect(main.simulation != null and main.simulation is RefCounted, "main owns one data simulation")
	_expect(main.unit_renderer != null, "main owns batched unit renderer")
	_expect(main.unit_renderer.get_multimesh_count() == 2, "renderer uses exactly one MultiMesh per team")
	_expect(main.simulation.unit_ids.is_empty(), "units begin as data, not child nodes")
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(4.5, 16.5))
	main.unit_renderer.sync()
	_expect(main.unit_renderer.get_child_count() == 2, "spawning data never creates a per-unit child node")
	_expect(main.buildings_layer.y_sort_enabled, "low-count building layer uses y sorting")
	_expect(main.fx.z_index > main.unit_renderer.z_index, "FX overlay stays above units and buildings")
	_expect(main.grid.world_to_cell(main.grid.cell_to_world(Vector2i(3, 17))) == Vector2i(3, 17), "isometric center picking remains exact")
	_expect(is_equal_approx(main.hud.last_ally_occupancy, main.simulation.get_occupancy(main.simulation.TEAM_ALLY)), "HUD occupancy mirrors simulation")
	main.queue_free()
	await tree.process_frame


func _test_dynamic_building(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = main.world.to_global(main.grid.cell_to_world(Vector2i(3, 17)))
	main._unhandled_input(tap)
	var placed_cell := Vector2i(main.simulation.buildings.back().cell)
	_expect(placed_cell == Vector2i(3, 17), "screen tap picks and builds the exact isometric tile")
	_expect(main.simulation.ally_gold == 120, "spawner spends 60 from 180 gold")
	_expect(not main.try_build_spawner(Vector2i(3, 3)), "blue cannot build on current red territory")
	_expect(not main.try_build_spawner(Vector2i(3, 17)), "occupied cell rejects another spawner")
	_expect(main.fx.placement_feedback_count == 3, "valid and invalid taps all route placement feedback")
	_expect(main.building_views.size() == 3, "two HQs and one spawner use low-count nodes")
	main.queue_free()
	await tree.process_frame


func _test_production_and_feedback(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.try_build_spawner(Vector2i(5, 18))
	for index in main.simulation.buildings.size():
		if int(main.simulation.buildings[index].kind) == main.simulation.BUILDING_SPAWNER:
			main.simulation.buildings[index].spawn_timer = 0.01
	main.step_simulation(1.0 / 30.0)
	_expect(main.simulation.unit_ids.size() == 1, "spawner produces one packed unit")
	_expect(main.fx.production_feedback_count == 1, "production queues a distinct pulse")
	var red_id: int = main.simulation.spawn_unit(main.simulation.TEAM_ENEMY, Vector2(4.5, 10.2))
	var blue_id: int = main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(4.5, 10.7))
	main.simulation.unit_hp[main.simulation.unit_ids.find(blue_id)] = 1.0
	main.step_simulation(1.0 / 30.0)
	_expect(red_id > 0 and main.fx.hit_feedback_count > 0, "melee strike routes hit spark")
	_expect(main.fx.unit_death_feedback_count > 0, "lethal strike routes death pop")
	main.queue_free()
	await tree.process_frame


func _test_terminal_routes(tree: SceneTree, main_scene: PackedScene) -> void:
	var victory = main_scene.instantiate()
	tree.root.add_child(victory)
	await tree.process_frame
	victory.simulation.apply_building_damage(victory.simulation.enemy_hq_id, 99999.0, victory.simulation.TEAM_ALLY)
	victory.step_simulation(1.0 / 30.0)
	_expect(victory.game_result == "VICTORY", "enemy HQ destruction routes victory")
	_expect(victory.fx.hq_hit_feedback_count == 1, "HQ damage routes strongest flash event")
	_expect(victory.hud.result_overlay.visible, "terminal state reveals restart overlay")
	var enemy_hq_view = victory.building_views[victory.simulation.enemy_hq_id]
	enemy_hq_view._process(0.7)
	_expect(not victory.building_views.has(victory.simulation.enemy_hq_id), "collapsed building view is removed from the ID registry")
	victory.queue_free()
	await tree.process_frame

	var defeat = main_scene.instantiate()
	tree.root.add_child(defeat)
	await tree.process_frame
	defeat.simulation.apply_building_damage(defeat.simulation.ally_hq_id, 99999.0, defeat.simulation.TEAM_ENEMY)
	defeat.step_simulation(1.0 / 30.0)
	_expect(defeat.game_result == "DEFEAT", "blue HQ destruction routes defeat")
	defeat.queue_free()
	await tree.process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
