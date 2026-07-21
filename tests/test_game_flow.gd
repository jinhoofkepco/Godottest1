extends RefCounted

const GameConfig = preload("res://scripts/game_config.gd")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const UNIT_SIEGE := 3
const BUILD_MELEE := 0
const BUILD_RANGED := 1
const BUILD_TOWER := 2
const BUILD_DRAGON := 3
const BUILD_SIEGE := 4
const BUILD_RALLY := 5
const FORMATION_LINE := 0
const FORMATION_LOOSE := 2
const RALLY_DEFEND := 1

var failures: Array[String] = []


func run(tree: SceneTree) -> Array[String]:
	var main_scene := load("res://scenes/main.tscn")
	_expect(main_scene != null, "main scene exists")
	if main_scene == null: return failures
	await _test_match_settings_panel(tree, main_scene)
	await _test_scene_and_bulk_render(tree, main_scene)
	await _test_incremental_board_render(tree, main_scene)
	await _test_build_selection_and_picking(tree, main_scene)
	await _test_zoom_grounding_and_zero_shake(tree, main_scene)
	await _test_event_feedback_and_terminal_routes(tree, main_scene)
	return failures


func _spawn_paused_main(tree: SceneTree, main_scene: PackedScene):
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	return main


func _spawn_main(tree: SceneTree, main_scene: PackedScene):
	var main = await _spawn_paused_main(tree, main_scene)
	var panel = main.get_node_or_null("MatchSettingsPanel")
	if panel != null and panel.has_method("press_start"):
		panel.press_start()
	await tree.process_frame
	return main


func _test_match_settings_panel(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_paused_main(tree, main_scene)
	var panel = main.get_node_or_null("MatchSettingsPanel")
	_expect(panel != null, "portrait match settings panel is part of the main scene")
	var initial_time := float(main.simulation.call("GetHudSnapshot").get("time_remaining", -1.0))
	for frame in 30:
		main._process(1.0 / 30.0)
	main.step_simulation(1.0)
	var paused_time := float(main.simulation.call("GetHudSnapshot").get("time_remaining", -2.0))
	_expect(main.get("match_started") != true, "match starts in a paused pre-match state")
	_expect(is_equal_approx(initial_time, paused_time), "simulation and manual stepping stay frozen for 30 pre-match frames")
	_expect(not main.map_view.interaction_enabled and not main.try_build_spawner(Vector2i(4, 70)), "map input and build commands are blocked before START")
	_expect(not main.hud.visible, "game HUD and its controls stay hidden behind pre-match settings")
	if panel == null:
		main.queue_free()
		await tree.process_frame
		return
	_expect(panel.has_method("get_field_paths") and panel.has_method("set_field_value") and panel.has_method("press_start"), "settings panel exposes stable test controls")
	_expect(panel.has_method("get_scroll_container") and panel.get_scroll_container() is ScrollContainer, "one portrait ScrollContainer owns the detailed field list")
	var backdrop = panel.get_node_or_null("OpaqueBackdrop")
	_expect(backdrop != null and backdrop.size == Vector2(GameConfig.VIEW_SIZE) and is_equal_approx(backdrop.color.a, 1.0), "settings modal has an opaque full-portrait backdrop")
	_expect(panel.get_tab_order() == PackedStringArray(["melee", "ranged", "siege", "dragon"]), "unit tabs keep the fixed MELEE, RANGED, SIEGE, DRAGON order")
	var paths: PackedStringArray = panel.get_field_paths()
	var schema: Array = main.simulation.call("GetMatchSettingsSchema")
	_expect(paths.size() == schema.size(), "every C# schema field, including nested damage multipliers, is editable")
	_expect(paths.has("melee.damage_vs.ranged") and paths.has("siege.damage_vs.melee"), "dotted nested damage keys round-trip through the panel")
	var integer_metadata: Dictionary = panel.get_field_metadata("dragon.production_batch")
	_expect(bool(integer_metadata.get("integer", false)) and is_equal_approx(float(integer_metadata.get("step", 0.0)), 1.0), "integer schema metadata is preserved by the numeric editor")
	panel.select_group("ranged")
	_expect(panel.get_field_display_text("ranged.max_hp") == "20.4", "numeric editor displays an off-step runtime value without rounding it")
	panel.set_field_value("dragon.production_batch", 2.7)
	_expect(typeof(panel.get_field_value("dragon.production_batch")) == TYPE_INT and int(panel.get_field_value("dragon.production_batch")) == 3, "integer fields stay integer when edited")
	panel.set_field_value("ranged.max_hp", 31.0)
	panel.set_field_value("ranged.spawner_cost", 95)
	panel.set_field_value("ranged.standoff_distance", 3.0)
	panel.press_start()
	_expect(panel.visible and main.get("match_started") != true, "invalid relational settings keep the modal open")
	_expect(is_equal_approx(float(panel.get_field_value("ranged.standoff_distance")), 3.0), "validation feedback preserves pending edits")
	_expect(not String(panel.get_feedback_text()).is_empty(), "validation failure is explained inside the panel")
	panel.set_field_value("ranged.standoff_distance", 1.5)
	var serialized: String = panel.serialize_settings(panel.get_pending_values())
	var parsed = JSON.parse_string(serialized)
	_expect(parsed is Dictionary and int(parsed.get("schema_version", 0)) == 1, "copied settings JSON carries schema_version 1")
	_expect(is_equal_approx(float(parsed.settings.ranged.max_hp), 31.0) and int(parsed.settings.dragon.production_batch) == 3, "copied canonical JSON preserves edited float and integer values")
	panel.press_copy()
	_expect(panel.get_feedback_text().contains("SETTINGS COPIED"), "COPY SETTINGS confirms the clipboard action")
	panel.press_defaults()
	_expect(is_equal_approx(float(panel.get_field_value("ranged.max_hp")), 20.4) and int(panel.get_field_value("dragon.production_batch")) == 2, "DEFAULTS restores the shipped profile from schema defaults")
	panel.set_field_value("ranged.max_hp", 31.0)
	panel.set_field_value("ranged.spawner_cost", 95)
	panel.set_field_value("ranged.standoff_distance", 1.5)
	panel.set_field_value("dragon.production_batch", 3)
	var panel_source := FileAccess.get_file_as_string("res://scripts/match_settings_panel.gd")
	_expect(panel_source.contains("DisplayServer.clipboard_set") and panel_source.contains("sort_keys"), "COPY SETTINGS uses the OS clipboard and canonical sorted keys")
	panel.press_start()
	await tree.process_frame
	_expect(main.get("match_started") == true and not panel.visible and main.map_view.interaction_enabled and main.hud.visible, "valid START atomically enables the match, map, and HUD")
	_expect(is_equal_approx(float(main.simulation.call("GetMatchSettings").ranged.max_hp), 31.0), "normalized C# settings become the active match profile")
	main.hud.select_build_kind(BUILD_RANGED)
	_expect(main.hud.build_buttons[BUILD_RANGED].text.contains("95") and main.hud.instruction_label.text.contains("95"), "HUD button and current instruction read the active runtime spawner cost")
	main.simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(4, 70), BUILD_RANGED), "restart fixture creates a disposable building")
	main._sync_board_and_buildings(true)
	_expect(not main.building_views.is_empty(), "restart fixture has live building presentation")
	main.hud.open_rally_panel({"id": 99, "mode": 0, "formation": 0})
	main._restart()
	_expect(panel.visible and main.get("match_started") != true and not main.map_view.interaction_enabled, "RESTART returns to paused settings without scene reload")
	_expect(not main.hud.visible, "restart settings hide the old HUD and block its controls")
	_expect(not main.hud.result_overlay.visible and not main.hud.edit_panel.visible, "restart hides result and rally state")
	var preserved_view = main.building_views.values()[0]
	var preserved_count: int = main.building_views.size()
	panel.set_field_value("ranged.standoff_distance", 3.0)
	panel.press_start()
	_expect(panel.visible and main.building_views.size() == preserved_count and is_instance_valid(preserved_view), "invalid restart settings preserve the existing battlefield presentation")
	panel.set_field_value("ranged.standoff_distance", 1.5)
	panel.press_start()
	_expect(main.building_views.size() == 2 and main.building_records.size() == 2, "START clears stale presentation before reset IDs are reused")
	main.queue_free()
	await tree.process_frame


func _test_incremental_board_render(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	_expect(main.grid.has_method("get_tile_instance_count"), "board exposes its tile MultiMesh instance count")
	_expect(main.grid.has_method("apply_board_delta"), "board accepts packed incremental deltas")
	if not main.grid.has_method("get_tile_instance_count") or not main.grid.has_method("apply_board_delta"):
		main.queue_free()
		await tree.process_frame
		return
	var expected_tiles := GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS
	_expect(main.grid.get_tile_instance_count() == expected_tiles, "one tile MultiMesh owns every fixed map tile instance")
	_expect(main.grid.tile_transform_write_count == expected_tiles, "tile transforms are initialized exactly once")
	var initial_full_syncs: int = main.grid.full_sync_count
	var initial_transforms: int = main.grid.tile_transform_write_count
	var initial_updates: int = main.grid.tile_incremental_update_count
	var indices := PackedInt32Array()
	var owners := PackedInt32Array()
	for offset in 30:
		indices.append(5 * GameConfig.GRID_COLUMNS + offset % GameConfig.GRID_COLUMNS + floori(float(offset) / GameConfig.GRID_COLUMNS) * GameConfig.GRID_COLUMNS)
		owners.append(TEAM_ALLY)
	_expect(main.simulation.call("ApplyDebugCommand", {"op": "force_ownership_delta", "indices": indices, "owners": owners}), "live board accepts a 30-cell territory push")
	main._sync_board_and_buildings()
	_expect(main.grid.full_sync_count == initial_full_syncs, "territory push does not rebuild the full board")
	_expect(main.grid.tile_transform_write_count == initial_transforms, "territory push never rewrites immutable tile transforms")
	_expect(main.grid.tile_incremental_update_count - initial_updates == 30, "territory push updates exactly 30 tile instances")
	_expect(main.grid.last_flash_update_count == 30, "all 30 changed tiles receive shader flash timestamps")
	_expect(main.grid.get_static_terrain_redraw_count() == 1, "immutable cliff geometry draws once")
	var fx_source := FileAccess.get_file_as_string("res://scripts/fx.gd")
	var grid_source := FileAccess.get_file_as_string("res://scripts/grid.gd")
	_expect(not fx_source.contains("territory_change"), "DefenseFx has no per-cell territory effect path")
	_expect(not grid_source.contains("func _draw()"), "GridBoard no longer tessellates all tile geometry in _draw")
	_expect(grid_source.contains("set_instance_color") and grid_source.contains("set_instance_custom_data"), "ownership deltas update only tile instance attributes")
	_expect(grid_source.contains("_water") and grid_source.contains("tile_data.a"), "water is rendered through immutable tile instance data")
	main.queue_free()
	await tree.process_frame


func _test_scene_and_bulk_render(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	_expect(main.simulation.get_script().resource_path.ends_with("BattleSimulation.cs"), "live match uses the C# simulation core")
	_expect(main.simulation.get_child_count() == 0, "simulation owns no per-unit Nodes")
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": TEAM_ALLY, "formation": FORMATION_LINE, "template": {"melee": 2, "ranged": 1, "siege": 1, "dragon": 0}, "anchor": Vector2(8.5, 27.5)})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_RANGED, "position": Vector2(9.5, 17.5), "exact": true})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_SIEGE, "position": Vector2(10.5, 28.5), "exact": true})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_DRAGON, "position": Vector2(11.5, 16.5), "exact": true})
	main.unit_renderer.reset_bulk_upload_count()
	main.unit_renderer.sync()
	_expect(main.unit_renderer.bulk_upload_count == 6, "renderer updates unit, shadow, banner, and gathering-ghost batches with six bulk uploads")
	var render: Dictionary = main.simulation.call("GetRenderSnapshot")
	_expect(int(render.infantry_count) == 6 and int(render.enemy_dragon_count) == 1, "bulk snapshot separates legion infantry/SIEGE and dragon batches")
	_expect(PackedFloat32Array(render.infantry_buffer).size() == int(render.infantry_count) * 16, "MultiMesh interleaved buffer has exactly 16 floats per instance")
	_expect(int(render.legion_banner_count) == 1 and PackedFloat32Array(render.legion_banner_buffer).size() == 16, "one marching legion crosses the C# boundary as one packed banner record")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	_expect(renderer_source.contains("ArrayMesh.new()") and renderer_source.contains("_make_flag_material") and not renderer_source.contains("mesh.size = Vector2(18, 24)"), "legion banner uses a procedural pole and waving cloth instead of a cyan QuadMesh")
	var siege_flip_found := false
	for index in range(int(render.infantry_count)):
		siege_flip_found = siege_flip_found or PackedFloat32Array(render.infantry_buffer)[index * 16 + 15] > 0.5
	_expect(siege_flip_found, "SIEGE tank atlas is vertically corrected in the live render snapshot")
	main.queue_free()
	await tree.process_frame


func _test_build_selection_and_picking(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	main.simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	var elevated_cell := Vector2i(4, 70)
	var world: Vector2 = main.grid.cell_to_world(elevated_cell)
	var picked: Vector2i = main.grid.world_to_cell(world)
	_expect(picked == elevated_cell, "elevation-aware isometric picking returns the exact displayed tile")
	var lake_cell := Vector2i(GameConfig.GRID_COLUMNS / 2, GameConfig.GRID_ROWS / 2)
	_expect(main.grid.world_to_cell(main.grid.cell_to_world(lake_cell)) == lake_cell, "large-board picking returns the exact displayed lake tile")
	_expect(not main.grid.can_build(lake_cell, TEAM_ALLY), "lake tile never exposes a build marker")
	_expect(main.hud.build_buttons.size() == 6, "mobile bar exposes four class spawners, RALLY, and TOWER")
	_expect(main.hud.ai_income_button != null and main.hud.population_label != null, "HUD exposes population income and enemy economy controls")
	main.hud.ai_income_button.pressed.emit()
	_expect(int(main.simulation.call("GetAiIncomeLevel")) == 4, "enemy economy button cycles the live C# difficulty level")
	for build_kind in [BUILD_MELEE, BUILD_RANGED, BUILD_SIEGE, BUILD_DRAGON, BUILD_RALLY, BUILD_TOWER]:
		_expect(main.hud.select_build_kind(build_kind), "each build kind can be selected from the mobile bar")
	main.hud.select_build_kind(BUILD_RALLY)
	_expect(main.selected_build_kind == BUILD_RALLY, "RALLY selection reaches the main controller")
	_expect(main.try_build_spawner(elevated_cell), "RALLY builds on allied territory")
	main._sync_board_and_buildings(true)
	var rally_id: int = main._building_at_cell(elevated_cell)
	_expect(not bool(main.building_records[rally_id].complete) and is_equal_approx(float(main.building_records[rally_id].construction_duration), 8.0), "RALLY view begins an eight-second construction phase")
	for tick in range(241): main.simulation.call("Step", 1.0 / 30.0)
	main._sync_board_and_buildings()
	var config: Dictionary = main.simulation.call("GetRallyConfig", rally_id)
	_expect(int(config.mode) == 0 and int(config.formation) == FORMATION_LINE, "new RALLY defaults to ADVANCE and LINE")
	var rally_view = main.building_views.get(rally_id)
	_expect(rally_view != null and int(rally_view.z_index) > int(main.unit_renderer.z_index), "RALLY marker and waiting count stay above battlefield occlusion")
	_expect(main.try_build_spawner(elevated_cell) and main.hud.edit_panel.visible, "tapping an allied RALLY opens its compact editor")
	main.hud.select_rally_mode(RALLY_DEFEND)
	main.hud.select_edit_formation(FORMATION_LOOSE)
	config = main.simulation.call("GetRallyConfig", rally_id)
	_expect(int(config.mode) == RALLY_DEFEND and int(config.formation) == FORMATION_LOOSE, "RALLY mode and formation edits reach C# in one config call")
	main._on_build_kind_selected(BUILD_TOWER)
	_expect(main.selected_build_kind == BUILD_TOWER, "defense tower can be selected independently")
	main.hud.open_rally_panel(config)
	main.hud.request_edit_demolish()
	main._sync_board_and_buildings()
	_expect(bool(main.building_records[rally_id].destroyed), "RALLY editor demolition removes the selected building")
	main.queue_free()
	await tree.process_frame


func _test_zoom_grounding_and_zero_shake(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	main.map_view.set_zoom_at(999.0, main.map_view.frame_rect.get_center())
	_expect(is_equal_approx(main.map_view.zoom_level, GameConfig.MAP_ZOOM_MAX) and GameConfig.MAP_ZOOM_MAX >= 16.0, "pinch/wheel zoom reaches the maximum practical 16x close-up")
	main.simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(22, 86), BUILD_TOWER), "grounding fixture builds a tower")
	main._sync_board_and_buildings(true)
	var tower_view = null
	for view in main.building_views.values():
		if int(view.kind) == 2:
			tower_view = view
			break
	_expect(tower_view != null and absf(tower_view.get_sprite_opaque_bottom_y() - tower_view.get_ground_contact_y()) <= 0.01, "building sprite opaque base is anchored exactly to its ground contact")
	var fx_source := FileAccess.get_file_as_string("res://scripts/fx.gd")
	_expect(not fx_source.contains("shake") and not fx_source.contains("trauma"), "all camera shake and trauma code is removed")
	_expect(fx_source.contains("ratio * 0.28") and not fx_source.contains("draw_rect(Rect2(Vector2(fragment.position)"), "combat tracers and debris use transparent tactical shapes")
	main.queue_free()
	await tree.process_frame


func _test_event_feedback_and_terminal_routes(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	main.fx.begin_frame()
	for index in GameConfig.FX_MAX_PER_FRAME + 5: main.fx.show_hit(Vector2(8.5, 22.5))
	_expect(main.fx.hit_feedback_count == GameConfig.FX_MAX_PER_FRAME, "minor combat FX are capped per frame")
	_expect(main.fx.minor_effects_dropped_this_frame == 5, "overflow minor FX are dropped without affecting simulation")
	main.fx.show_siege_impact(Vector2(8.5, 22.5), TEAM_ALLY, GameConfig.SIEGE_BLAST_RADIUS)
	_expect(main.fx.siege_impact_feedback_count == 1, "major SIEGE impact FX bypasses the minor cap")
	var debug: Dictionary = main.simulation.call("GetDebugSnapshot")
	main.simulation.call("ApplyDebugCommand", {"op": "damage_building", "id": int(debug.enemy_hq_id), "damage": 99999.0, "team": TEAM_ALLY})
	main.step_simulation(0.0)
	_expect(main.game_result == "VICTORY" and not main.map_view.interaction_enabled, "enemy HQ destruction reaches victory and locks map input")
	main.queue_free()
	await tree.process_frame
	var defeat = await _spawn_main(tree, main_scene)
	debug = defeat.simulation.call("GetDebugSnapshot")
	defeat.simulation.call("ApplyDebugCommand", {"op": "damage_building", "id": int(debug.ally_hq_id), "damage": 99999.0, "team": TEAM_ENEMY})
	defeat.step_simulation(0.0)
	_expect(defeat.game_result == "DEFEAT", "allied HQ destruction reaches defeat")
	defeat.queue_free()
	await tree.process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
