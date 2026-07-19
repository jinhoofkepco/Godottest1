extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")

var failures: Array[String] = []


class CountingGridSimulation:
	extends RefCounted

	var buildings: Array[Dictionary] = []
	var ownership_reads := 0
	var ownership := PackedByteArray()
	var blocked_cell := Vector2i(3, 35)


	func _init() -> void:
		ownership.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
		ownership.fill(2)
		buildings.append({"cell": Vector2i(4, 35), "destroyed": false})


	func get_ownership() -> PackedByteArray:
		ownership_reads += 1
		return ownership.duplicate()


	func is_blocked(cell: Vector2i) -> bool:
		return cell == blocked_cell


func run(tree: SceneTree) -> Array[String]:
	var main_scene := load("res://scenes/main.tscn")
	_expect(main_scene != null, "main scene exists")
	if main_scene == null:
		return failures
	await _test_grid_draw_ownership_snapshot(tree)
	await _test_scene_contract(tree, main_scene)
	await _test_dynamic_building(tree, main_scene)
	await _test_production_and_feedback(tree, main_scene)
	await _test_ranged_presentation(tree, main_scene)
	await _test_damage_hp_bar_policy(tree, main_scene)
	await _test_map_view_transform_and_input(tree, main_scene)
	await _test_emulated_mouse_stream_filter(tree, main_scene)
	await _test_finished_map_interaction_gate(tree, main_scene)
	await _test_hud_spawner_selection(tree, main_scene)
	await _test_batched_lunge(tree, main_scene)
	await _test_zero_screen_shake(tree, main_scene)
	await _test_terminal_routes(tree, main_scene)
	return failures


func _test_damage_hp_bar_policy(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var unit_id: int = main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(8.5, 25.5), main.simulation.UNIT_MELEE)
	main.unit_renderer.sync()
	_expect(main.unit_renderer.has_method("get_hp_bar_alpha"), "renderer exposes damage-only HP-bar visibility")
	if not main.unit_renderer.has_method("get_hp_bar_alpha"):
		main.queue_free()
		await tree.process_frame
		return
	_expect(is_zero_approx(main.unit_renderer.get_hp_bar_alpha(unit_id)), "full-health unit hides its HP bar")
	var unit_index: int = main.simulation.unit_ids.find(unit_id)
	main.simulation.unit_hp[unit_index] -= 1.0
	main.unit_renderer.sync()
	_expect(is_equal_approx(main.unit_renderer.get_hp_bar_alpha(unit_id), 1.0), "taking damage shows the HP bar at full alpha")
	main.unit_renderer.advance_visuals(2.7)
	var fade_alpha: float = main.unit_renderer.get_hp_bar_alpha(unit_id)
	_expect(fade_alpha > 0.0 and fade_alpha < 1.0, "unit HP bar fades during the end of its three-second window")
	main.unit_renderer.advance_visuals(0.4)
	_expect(is_zero_approx(main.unit_renderer.get_hp_bar_alpha(unit_id)), "unit HP bar disappears after three seconds")
	main.queue_free()
	await tree.process_frame


func _test_grid_draw_ownership_snapshot(tree: SceneTree) -> void:
	var grid = load("res://scenes/grid.tscn").instantiate()
	var counting_simulation := CountingGridSimulation.new()
	tree.root.add_child(grid)
	await tree.process_frame
	grid.set_simulation(counting_simulation)
	await tree.process_frame
	counting_simulation.ownership_reads = 0
	grid.queue_redraw()
	await tree.process_frame
	_expect(counting_simulation.ownership_reads == 1, "one GridBoard redraw snapshots ownership exactly once (got %d)" % counting_simulation.ownership_reads)
	counting_simulation.ownership_reads = 0
	_expect(not grid.can_build(counting_simulation.blocked_cell), "public build check still rejects blockers")
	_expect(counting_simulation.ownership_reads == 0, "public blocked check does not need an ownership snapshot")
	_expect(not grid.can_build(Vector2i(4, 35)), "public build check still rejects existing buildings")
	_expect(counting_simulation.ownership_reads == 1, "public valid-cell build check snapshots ownership once")
	grid.queue_free()
	await tree.process_frame


func _test_scene_contract(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	_expect(main.simulation != null and main.simulation is RefCounted, "main owns one data simulation")
	_expect(main.unit_renderer != null, "main owns batched unit renderer")
	_expect(main.unit_renderer.get_multimesh_count() == 3, "renderer uses one globally sorted infantry batch plus two dragon batches")
	_expect(main.simulation.unit_ids.is_empty(), "units begin as data, not child nodes")
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(4.5, 32.5))
	main.unit_renderer.sync()
	_expect(main.unit_renderer.get_child_count() == 4, "spawning data creates only three unit batches plus one shared shadow batch")
	_expect(main.unit_renderer.get_shadow_batch_count() == 1, "all units share one blob-shadow MultiMesh")
	_expect(main.buildings_layer.y_sort_enabled, "low-count building layer uses y sorting")
	_expect(main.fx.z_index > main.unit_renderer.z_index, "FX overlay stays above units and buildings")
	_expect(main.grid.world_to_cell(main.grid.cell_to_world(Vector2i(3, 35))) == Vector2i(3, 35), "isometric center picking remains exact")
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
	tap.position = main.map_view.to_global(main.grid.cell_to_world(build_cell))
	main.map_view._unhandled_input(tap)
	tap.pressed = false
	main.map_view._unhandled_input(tap)
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
	main.simulation.unit_hp[main.simulation.unit_ids.find(blue_id)] = 0.5
	main.step_simulation(1.0 / 30.0)
	_expect(red_id > 0 and main.fx.hit_feedback_count > 0, "melee strike routes hit spark")
	_expect(main.fx.unit_death_feedback_count > 0, "lethal strike routes death pop")
	main.queue_free()
	await tree.process_frame


func _test_ranged_presentation(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.simulation.spawn_unit(main.simulation.TEAM_ENEMY, Vector2(4.5, 10.5), main.simulation.UNIT_MELEE)
	main.simulation.spawn_unit(main.simulation.TEAM_ENEMY, Vector2(5.5, 10.5), main.simulation.UNIT_RANGED)
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(4.5, 32.5), main.simulation.UNIT_MELEE)
	main.simulation.spawn_unit(main.simulation.TEAM_ALLY, Vector2(5.5, 32.5), main.simulation.UNIT_RANGED)
	main.unit_renderer.sync()
	var infantry = main.unit_renderer.get_node_or_null("InfantryUnits")
	_expect(infantry is MultiMeshInstance2D, "all infantry share one MultiMesh batch")
	if infantry is MultiMeshInstance2D:
		_expect(infantry.multimesh.instance_count == 4, "global infantry batch receives both teams and classes")
		_expect(infantry.multimesh.use_custom_data and infantry.multimesh.use_colors, "atlas selection and team layer use per-instance data")
		_expect(infantry.material is ShaderMaterial, "infantry batch uses the texture-array atlas shader")
		var previous_y := -INF
		for instance_index in infantry.multimesh.instance_count:
			var instance_y: float = infantry.multimesh.get_instance_transform_2d(instance_index).origin.y
			_expect(instance_y >= previous_y, "global infantry painter order follows screen Y")
			previous_y = instance_y
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
		"origin": Vector2(4.5, 32.5),
		"position": Vector2(4.5, 30.5),
	}])
	var after_tracers: int = int(main.fx.get("ranged_shot_feedback_count")) if fx_properties.has("ranged_shot_feedback_count") else -1
	_expect(before_tracers >= 0 and after_tracers == before_tracers + 1, "ranged shot events route to a distinct tracer effect")
	_expect(main.unit_renderer.get_child_count() == 4, "mixed ground and dragon armies still create no per-unit nodes")
	main.queue_free()
	await tree.process_frame


func _test_map_view_transform_and_input(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var map_view = main.get_node_or_null("MapView")
	_expect(map_view != null, "main owns the MapView transform controller")
	if map_view == null:
		main.queue_free()
		await tree.process_frame
		return
	_expect(map_view.get_child_count() == 4, "MapView contains grid, buildings, four-batch units, and FX only")
	_expect(map_view.has_method("set_zoom_at") and map_view.has_method("pan_by") and map_view.has_method("screen_to_cell"), "MapView exposes the narrow view and picking API")
	if not map_view.has_method("set_zoom_at") or not map_view.has_method("pan_by") or not map_view.has_method("screen_to_cell"):
		main.queue_free()
		await tree.process_frame
		return

	var map_properties := _property_names(map_view)
	_expect(map_properties.has("zoom_level"), "MapView exposes its relative zoom for controls and tests")
	if not map_properties.has("zoom_level"):
		main.queue_free()
		await tree.process_frame
		return
	_expect(is_equal_approx(float(map_view.zoom_level), 1.35), "map starts at 1.35x zoom")
	var frame_rect: Rect2 = map_view.frame_rect
	var focus_cell := Vector2i(11, 30)
	var focus_screen: Vector2 = map_view.to_global(main.grid.cell_to_world(focus_cell))
	var focus_local: Vector2 = map_view.to_local(focus_screen)
	map_view.set_zoom_at(2.0, focus_screen)
	_expect(map_view.to_global(focus_local).distance_to(focus_screen) <= 0.25, "zoom preserves the exact transformed focus point within a quarter pixel")
	_expect(map_view.screen_to_cell(focus_screen) == focus_cell, "zooming around a tile keeps exact transformed picking under the focus")
	map_view.set_zoom_at(99.0, focus_screen)
	_expect(is_equal_approx(float(map_view.zoom_level), GameConfig.MAP_ZOOM_MAX), "zoom clamps to configured deep maximum")
	map_view.set_zoom_at(0.01, focus_screen)
	_expect(is_equal_approx(float(map_view.zoom_level), 1.0), "zoom clamps to 1.0x minimum")
	map_view.set_zoom_at(1.35, frame_rect.get_center())
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = frame_rect.get_center()
	map_view._unhandled_input(wheel_up)
	_expect(float(map_view.zoom_level) > 1.35, "mouse wheel zooms around the cursor")

	map_view.set_zoom_at(2.5, focus_screen)
	var before_pan: Vector2 = map_view.position
	map_view.pan_by(Vector2(80, 0))
	_expect(not map_view.position.is_equal_approx(before_pan), "pan moves a zoomed map")
	map_view.pan_by(Vector2(100000, 100000))
	var board_bounds: Rect2 = main.grid.get_board_bounds()
	var first_corner: Vector2 = map_view.to_global(board_bounds.position)
	var last_corner: Vector2 = map_view.to_global(board_bounds.end)
	var transformed_bounds := Rect2(
		Vector2(minf(first_corner.x, last_corner.x), minf(first_corner.y, last_corner.y)),
		Vector2(absf(last_corner.x - first_corner.x), absf(last_corner.y - first_corner.y))
	)
	_expect(frame_rect.intersects(transformed_bounds, true), "pan clamp keeps the board intersecting the play frame")
	var right_limit: Vector2 = map_view.position
	map_view.pan_by(Vector2(-200000, -200000))
	_expect(not map_view.position.is_equal_approx(right_limit), "opposite map edge remains reachable through clamped panning")
	map_view.pan_by(Vector2(-280, 0))
	var picked_cell := Vector2i(16, 32)
	var picked_screen: Vector2 = map_view.to_global(main.grid.cell_to_world(picked_cell))
	_expect(map_view.screen_to_cell(picked_screen) == picked_cell, "picking stays exact after non-default zoom and pan")

	var tapped_cells: Array[Vector2i] = []
	map_view.tile_tapped.connect(func(cell: Vector2i) -> void: tapped_cells.append(cell))
	var drag_origin := Vector2(250, 470)
	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	mouse_press.position = drag_origin
	map_view._unhandled_input(mouse_press)
	var mouse_drag := InputEventMouseMotion.new()
	mouse_drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse_drag.position = drag_origin + Vector2(32, 0)
	mouse_drag.relative = Vector2(32, 0)
	map_view._unhandled_input(mouse_drag)
	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.pressed = false
	mouse_release.position = mouse_drag.position
	map_view._unhandled_input(mouse_release)
	_expect(tapped_cells.is_empty(), "mouse drag suppresses the build click")

	map_view.set_zoom_at(1.35, frame_rect.get_center())
	var touch_a := InputEventScreenTouch.new()
	touch_a.index = 0
	touch_a.pressed = true
	touch_a.position = Vector2(210, 470)
	map_view._unhandled_input(touch_a)
	var touch_b := InputEventScreenTouch.new()
	touch_b.index = 1
	touch_b.pressed = true
	touch_b.position = Vector2(310, 470)
	map_view._unhandled_input(touch_b)
	var zoom_before_pinch: float = map_view.zoom_level
	var pinch_drag := InputEventScreenDrag.new()
	pinch_drag.index = 1
	pinch_drag.position = Vector2(350, 470)
	pinch_drag.relative = Vector2(40, 0)
	map_view._unhandled_input(pinch_drag)
	touch_b.pressed = false
	touch_b.position = pinch_drag.position
	map_view._unhandled_input(touch_b)
	touch_a.pressed = false
	map_view._unhandled_input(touch_a)
	_expect(float(map_view.zoom_level) > zoom_before_pinch, "two-finger pinch zooms around the gesture midpoint")
	_expect(tapped_cells.is_empty(), "pinch suppresses tap building")

	var touch_drag_start: Vector2 = frame_rect.get_center()
	touch_a.pressed = true
	touch_a.position = touch_drag_start
	map_view._unhandled_input(touch_a)
	var one_finger_drag := InputEventScreenDrag.new()
	one_finger_drag.index = 0
	one_finger_drag.position = touch_drag_start + Vector2(30, 0)
	one_finger_drag.relative = Vector2(30, 0)
	var before_touch_pan: Vector2 = map_view.position
	map_view._unhandled_input(one_finger_drag)
	touch_a.pressed = false
	touch_a.position = one_finger_drag.position
	map_view._unhandled_input(touch_a)
	_expect(not map_view.position.is_equal_approx(before_touch_pan), "one-finger drag pans the map")
	_expect(tapped_cells.is_empty(), "one-finger drag suppresses tap building")

	map_view.setup(main.grid, frame_rect)
	var touch_tap_cell := Vector2i(5, 36)
	var touch_tap_screen: Vector2 = map_view.to_global(main.grid.cell_to_world(touch_tap_cell))
	touch_a.pressed = true
	touch_a.position = touch_tap_screen
	map_view._unhandled_input(touch_a)
	touch_a.pressed = false
	map_view._unhandled_input(touch_a)
	_expect(tapped_cells == [touch_tap_cell], "stationary single touch emits the exact tapped tile")

	var tap_cell := Vector2i(4, 36)
	var tap_screen: Vector2 = map_view.to_global(main.grid.cell_to_world(tap_cell))
	mouse_press.position = tap_screen
	map_view._unhandled_input(mouse_press)
	mouse_release.position = tap_screen
	map_view._unhandled_input(mouse_release)
	_expect(tapped_cells == [touch_tap_cell, tap_cell], "stationary mouse click emits the exact tapped tile")
	main.queue_free()
	await tree.process_frame


func _test_emulated_mouse_stream_filter(tree: SceneTree, main_scene: PackedScene) -> void:
	_expect(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)), "touch-to-mouse emulation remains enabled for HUD buttons")
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var map_view = main.map_view
	var frame_rect: Rect2 = map_view.frame_rect
	var tapped_cells: Array[Vector2i] = []
	map_view.tile_tapped.connect(func(cell: Vector2i) -> void: tapped_cells.append(cell))

	var tap_cell := Vector2i(5, 36)
	var tap_screen: Vector2 = map_view.to_global(main.grid.cell_to_world(tap_cell))
	_send_touch_tap(map_view, tap_screen)
	_send_mouse_tap(map_view, tap_screen, InputEvent.DEVICE_ID_EMULATION)
	_expect(tapped_cells == [tap_cell], "native touch plus its emulated mouse stream emits exactly one tile tap")

	map_view.setup(main.grid, frame_rect)
	tapped_cells.clear()
	var drag_start := frame_rect.get_center()
	var drag_end := drag_start + Vector2(30, 0)
	_send_touch_drag(map_view, drag_start, drag_end)
	var touch_pan_position: Vector2 = map_view.position
	_send_mouse_drag(map_view, drag_start, drag_end, InputEvent.DEVICE_ID_EMULATION)
	_expect(map_view.position.is_equal_approx(touch_pan_position), "emulated mouse drag never applies a second pan after native touch drag")
	_expect(tapped_cells.is_empty(), "native and emulated drag streams do not leak a tap")

	map_view.setup(main.grid, frame_rect)
	tapped_cells.clear()
	var first_touch := Vector2(210, 470)
	var second_touch := Vector2(310, 470)
	var touch_a := InputEventScreenTouch.new()
	touch_a.index = 0
	touch_a.pressed = true
	touch_a.position = first_touch
	map_view._unhandled_input(touch_a)
	var touch_b := InputEventScreenTouch.new()
	touch_b.index = 1
	touch_b.pressed = true
	touch_b.position = second_touch
	map_view._unhandled_input(touch_b)
	var pinch_drag := InputEventScreenDrag.new()
	pinch_drag.index = 1
	pinch_drag.position = second_touch + Vector2(40, 0)
	pinch_drag.relative = Vector2(40, 0)
	map_view._unhandled_input(pinch_drag)
	touch_b.pressed = false
	touch_b.position = pinch_drag.position
	map_view._unhandled_input(touch_b)
	touch_a.pressed = false
	map_view._unhandled_input(touch_a)
	_send_mouse_tap(map_view, (first_touch + second_touch) * 0.5, InputEvent.DEVICE_ID_EMULATION)
	_expect(tapped_cells.is_empty(), "pinch plus its emulated mouse stream emits zero tile taps")
	main.queue_free()
	await tree.process_frame


func _test_finished_map_interaction_gate(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var map_view = main.map_view
	var map_properties := _property_names(map_view)
	_expect(map_view.has_method("set_interaction_enabled") and map_properties.has("interaction_enabled"), "MapView exposes a narrow interaction-enabled contract")
	if not map_view.has_method("set_interaction_enabled") or not map_properties.has("interaction_enabled"):
		main.queue_free()
		await tree.process_frame
		return
	_expect(bool(map_view.interaction_enabled), "MapView interaction starts enabled")
	var frame_rect: Rect2 = map_view.frame_rect
	var tapped_cells: Array[Vector2i] = []
	map_view.tile_tapped.connect(func(cell: Vector2i) -> void: tapped_cells.append(cell))
	main._finish_match("VICTORY")
	_expect(not bool(map_view.interaction_enabled), "finishing a match disables map interaction before the result overlay")
	var terminal_position: Vector2 = map_view.position
	var terminal_zoom: float = map_view.zoom_level
	var focus := frame_rect.get_center()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = focus
	map_view._unhandled_input(wheel)
	_send_mouse_drag(map_view, focus, focus + Vector2(30, 0))
	_send_touch_tap(map_view, focus)
	_expect(is_equal_approx(float(map_view.zoom_level), terminal_zoom), "wheel input cannot zoom after the match finishes")
	_expect(map_view.position.is_equal_approx(terminal_position), "mouse drag cannot pan after the match finishes")
	_expect(tapped_cells.is_empty(), "touch tap cannot emit placement after the match finishes")
	map_view.setup(main.grid, frame_rect)
	_expect(bool(map_view.interaction_enabled), "setup resets MapView interaction for a fresh match")
	main.queue_free()
	await tree.process_frame


func _test_hud_spawner_selection(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var hud_properties := _property_names(main.hud)
	_expect(hud_properties.has("melee_button") and hud_properties.has("ranged_button") and hud_properties.has("tower_button") and hud_properties.has("dragon_button"), "HUD exposes all four build selectors")
	if not hud_properties.has("melee_button") or not hud_properties.has("ranged_button") or not hud_properties.has("tower_button") or not hud_properties.has("dragon_button"):
		main.queue_free()
		await tree.process_frame
		return
	_expect(main.hud.melee_button.text == "MELEE 60" and main.hud.ranged_button.text == "RANGED 80", "HUD selectors show both ground spawner costs")
	_expect(main.hud.tower_button.text == "TOWER 120" and main.hud.dragon_button.text == "DRAGON 220", "HUD selectors show tower and dragon costs")
	_expect(main.selected_build_kind == main.simulation.BUILD_MELEE_SPAWNER, "melee is selected by default")
	main.hud.ranged_button.pressed.emit()
	_expect(main.selected_build_kind == main.simulation.BUILD_RANGED_SPAWNER, "ranged HUD selection updates only the requested build kind")
	var ranged_cell := Vector2i(6, 36)
	var tap_screen: Vector2 = main.map_view.to_global(main.grid.cell_to_world(ranged_cell))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = tap_screen
	main.map_view._unhandled_input(press)
	press.pressed = false
	main.map_view._unhandled_input(press)
	var placed = main.simulation.buildings.back()
	_expect(Vector2i(placed.cell) == ranged_cell and int(placed.unit_kind) == main.simulation.UNIT_RANGED, "selected ranged kind routes through the next exact tile tap")
	_expect(main.simulation.ally_gold == GameConfig.START_GOLD - GameConfig.RANGED_SPAWNER_COST, "ranged placement spends 80 gold")
	_expect("RANGED" in main.hud.message_label.text, "placement feedback names the selected spawner type")
	main.hud.tower_button.pressed.emit()
	_expect(main.selected_build_kind == main.simulation.BUILD_DEFENSE_TOWER, "tower HUD selection routes to the defense build kind")
	main.hud.dragon_button.pressed.emit()
	_expect(main.selected_build_kind == main.simulation.BUILD_DRAGON_LAIR, "dragon HUD selection routes to the lair build kind")
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
	) + Vector2(0, main.simulation.config.INFANTRY_FOOT_ANCHOR_Y)
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
		main.fx.show_hq_hit(Vector2i(11, 43), main.simulation.TEAM_ALLY)
		main.fx._process(0.5)
		main._process(1.0 / 60.0)
		_expect(main.world.position.is_equal_approx(base_position), "repeated HQ hits never move the world")
	main.fx.show_hq_destroyed(Vector2i(11, 43), main.simulation.TEAM_ALLY)
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


func _send_mouse_tap(map_view, at: Vector2, device_id: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.device = device_id
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	map_view._unhandled_input(event)
	event.pressed = false
	map_view._unhandled_input(event)


func _send_mouse_drag(map_view, start: Vector2, finish: Vector2, device_id: int = 0) -> void:
	var press := InputEventMouseButton.new()
	press.device = device_id
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	map_view._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.device = device_id
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = finish
	drag.relative = finish - start
	map_view._unhandled_input(drag)
	press.pressed = false
	press.position = finish
	map_view._unhandled_input(press)


func _send_touch_tap(map_view, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = true
	event.position = at
	map_view._unhandled_input(event)
	event.pressed = false
	map_view._unhandled_input(event)


func _send_touch_drag(map_view, start: Vector2, finish: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = start
	map_view._unhandled_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = finish
	drag.relative = finish - start
	map_view._unhandled_input(drag)
	touch.pressed = false
	touch.position = finish
	map_view._unhandled_input(touch)
