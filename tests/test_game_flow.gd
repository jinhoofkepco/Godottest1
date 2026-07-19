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
	await _test_ranged_presentation(tree, main_scene)
	await _test_batched_lunge(tree, main_scene)
	await _test_zero_screen_shake(tree, main_scene)
	await _test_terminal_routes(tree, main_scene)
	return failures


func _test_scene_contract(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	_expect(main.simulation != null and main.simulation is RefCounted, "main owns one data simulation")
	_expect(main.unit_renderer != null, "main owns batched unit renderer")
	_expect(main.unit_renderer.get_multimesh_count() == 4, "renderer uses four team-by-kind MultiMesh batches")
	_expect(main.simulation.unit_ids.is_empty(), "units begin as data, not child nodes")
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(4.5, 16.5))
	main.unit_renderer.sync()
	_expect(main.unit_renderer.get_child_count() == 4, "spawning data never creates a per-unit child node")
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
	var build_cell := Vector2i(4, 36)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = main.world.to_global(main.grid.cell_to_world(build_cell))
	main._unhandled_input(tap)
	var placed_cell := Vector2i(main.simulation.buildings.back().cell)
	_expect(placed_cell == build_cell, "screen tap picks and builds the exact isometric tile")
	_expect(main.simulation.ally_gold == 120, "spawner spends 60 from 180 gold")
	_expect(not main.try_build_spawner(Vector2i(3, 3)), "blue cannot build on current red territory")
	_expect(not main.try_build_spawner(build_cell), "occupied cell rejects another spawner")
	_expect(main.fx.placement_feedback_count == 3, "valid and invalid taps all route placement feedback")
	_expect(main.building_views.size() == 3, "two HQs and one spawner use low-count nodes")
	main.queue_free()
	await tree.process_frame


func _test_production_and_feedback(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.try_build_spawner(Vector2i(4, 36))
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


func _test_ranged_presentation(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.simulation.spawn_unit(main.simulation.TEAM_ENEMY, Vector2(4.5, 8.5), main.simulation.UNIT_MELEE)
	main.simulation.spawn_unit(main.simulation.TEAM_ENEMY, Vector2(5.5, 8.5), main.simulation.UNIT_RANGED)
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(4.5, 15.5), main.simulation.UNIT_MELEE)
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(5.5, 15.5), main.simulation.UNIT_RANGED)
	main.unit_renderer.sync()
	var expected_batches := ["EnemyMeleeUnits", "EnemyRangedUnits", "AllyMeleeUnits", "AllyRangedUnits"]
	for batch_name in expected_batches:
		var batch = main.unit_renderer.get_node_or_null(NodePath(batch_name))
		_expect(batch is MultiMeshInstance2D, "%s is a MultiMesh batch" % batch_name)
		if batch is MultiMeshInstance2D:
			_expect(batch.multimesh.instance_count == 1, "%s receives only its matching packed unit" % batch_name)
	var enemy_melee = main.unit_renderer.get_node_or_null("EnemyMeleeUnits")
	var enemy_ranged = main.unit_renderer.get_node_or_null("EnemyRangedUnits")
	if enemy_melee is MultiMeshInstance2D and enemy_ranged is MultiMeshInstance2D:
		_expect(enemy_melee.multimesh.mesh != enemy_ranged.multimesh.mesh, "ranged soldiers use a distinct procedural silhouette")
		_expect(
			main.unit_renderer.get_unit_color(main.simulation.TEAM_ENEMY, main.simulation.UNIT_MELEE, 1)
			!= main.unit_renderer.get_unit_color(main.simulation.TEAM_ENEMY, main.simulation.UNIT_RANGED, 1),
			"ranged soldiers use a distinct color treatment"
		)

	var ranged_spawner_id: int = main.simulation.add_building(
		main.simulation.TEAM_ALLY,
		main.simulation.BUILDING_SPAWNER,
		Vector2i(6, 36),
		main.simulation.UNIT_RANGED
	)
	main._sync_building_views()
	var ranged_view = main.building_views.get(ranged_spawner_id)
	var ranged_view_properties := _property_names(ranged_view) if ranged_view != null else [] as Array[String]
	var displayed_kind := int(ranged_view.get("unit_kind")) if ranged_view != null and ranged_view_properties.has("unit_kind") else -1
	_expect(displayed_kind == main.simulation.UNIT_RANGED, "spawner view carries the produced unit kind for its visual marker")

	var fx_properties := _property_names(main.fx)
	var before_tracers: int = int(main.fx.get("ranged_shot_feedback_count")) if fx_properties.has("ranged_shot_feedback_count") else -1
	main._consume_events([{
		"type": "ranged_shot",
		"team": main.simulation.TEAM_ALLY,
		"origin": Vector2(4.5, 15.5),
		"position": Vector2(4.5, 11.5),
	}])
	var after_tracers: int = int(main.fx.get("ranged_shot_feedback_count")) if fx_properties.has("ranged_shot_feedback_count") else -1
	_expect(before_tracers >= 0 and after_tracers == before_tracers + 1, "ranged shot events route to a distinct tracer effect")
	_expect(main.unit_renderer.get_child_count() == 4, "mixed melee and ranged armies still create no per-unit nodes")
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
	var fx_properties := _property_names(victory.fx)
	_expect(fx_properties.has("hq_destroyed_feedback_count"), "HQ destruction exposes distinct major feedback counter")
	if fx_properties.has("hq_destroyed_feedback_count"):
		_expect(victory.fx.hq_destroyed_feedback_count == 1, "HQ destruction keeps its distinct visual feedback")
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


func _test_batched_lunge(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(5.5, 12.0))
	var simulation_properties := _property_names(main.simulation)
	if not simulation_properties.has("unit_lunge_timers"):
		_expect(false, "renderer lunge contract has packed timer data")
		main.queue_free()
		await tree.process_frame
		return
	main.simulation.unit_lunge_timers[0] = main.simulation.config.UNIT_LUNGE_DURATION * 0.5
	main.simulation.unit_lunge_directions[0] = Vector2.RIGHT
	_expect(main.unit_renderer.has_method("get_unit_render_position"), "renderer exposes its shared batched position calculation")
	if not main.unit_renderer.has_method("get_unit_render_position"):
		main.queue_free()
		await tree.process_frame
		return
	main.unit_renderer.sync()
	var rendered_origin: Vector2 = main.unit_renderer.get_unit_render_position(0)
	var expected_origin: Vector2 = main.grid.grid_to_screen(
		main.simulation.unit_positions[0] + Vector2.RIGHT * main.simulation.config.UNIT_LUNGE_DISTANCE
	) + Vector2(0, -11)
	_expect(rendered_origin.is_equal_approx(expected_origin), "batched transform applies target-facing lunge without a unit node")
	main.queue_free()
	await tree.process_frame


func _test_zero_screen_shake(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var base_position: Vector2 = main.world.position
	var fx_properties := _property_names(main.fx)
	_expect(not fx_properties.has("trauma"), "FX has no trauma state")
	for property_name in fx_properties:
		_expect("shake" not in property_name.to_lower(), "FX has no shake property: %s" % property_name)
	for hit_index in 20:
		main.fx.show_hq_hit(Vector2i(5, 21), main.simulation.TEAM_ALLY)
		main.fx._process(0.5)
		main._process(1.0 / 60.0)
		_expect(main.world.position.is_equal_approx(base_position), "repeated HQ hits never move the world")
	main.fx.show_hq_destroyed(Vector2i(5, 21), main.simulation.TEAM_ALLY)
	for sample in 30:
		main.fx._process(1.0 / 60.0)
		main._process(1.0 / 60.0)
		_expect(main.world.position.is_equal_approx(base_position), "HQ destruction never moves the world")
	if main.fx.has_method("get_screen_shake_offset"):
		_expect(main.fx.get_screen_shake_offset() == Vector2.ZERO, "compatibility shake offset is always zero")
	main.queue_free()
	await tree.process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _property_names(value: Object) -> Array[String]:
	var names: Array[String] = []
	for property in value.get_property_list():
		names.append(String(property.name))
	return names
