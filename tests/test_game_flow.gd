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

var failures: Array[String] = []


func run(tree: SceneTree) -> Array[String]:
	var main_scene := load("res://scenes/main.tscn")
	_expect(main_scene != null, "main scene exists")
	if main_scene == null: return failures
	await _test_scene_and_bulk_render(tree, main_scene)
	await _test_incremental_board_render(tree, main_scene)
	await _test_build_selection_and_picking(tree, main_scene)
	await _test_zoom_grounding_and_zero_shake(tree, main_scene)
	await _test_event_feedback_and_terminal_routes(tree, main_scene)
	return failures


func _spawn_main(tree: SceneTree, main_scene: PackedScene):
	var main = main_scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	return main


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
	main.queue_free()
	await tree.process_frame


func _test_scene_and_bulk_render(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	_expect(main.simulation.get_script().resource_path.ends_with("BattleSimulation.cs"), "live match uses the C# simulation core")
	_expect(main.simulation.get_child_count() == 0, "simulation owns no per-unit Nodes")
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_MELEE, "position": Vector2(8.5, 27.5), "exact": true})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_RANGED, "position": Vector2(9.5, 17.5), "exact": true})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ALLY, "kind": UNIT_SIEGE, "position": Vector2(10.5, 28.5), "exact": true})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": TEAM_ENEMY, "kind": UNIT_DRAGON, "position": Vector2(11.5, 16.5), "exact": true})
	main.unit_renderer.reset_bulk_upload_count()
	main.unit_renderer.sync()
	_expect(main.unit_renderer.bulk_upload_count == 4, "renderer updates four MultiMesh batches with four bulk uploads")
	var render: Dictionary = main.simulation.call("GetRenderSnapshot")
	_expect(int(render.infantry_count) == 3 and int(render.enemy_dragon_count) == 1, "bulk snapshot separates infantry/SIEGE and dragon batches")
	_expect(PackedFloat32Array(render.infantry_buffer).size() == int(render.infantry_count) * 16, "MultiMesh interleaved buffer has exactly 16 floats per instance")
	var siege_flip_found := false
	for index in range(int(render.infantry_count)):
		siege_flip_found = siege_flip_found or PackedFloat32Array(render.infantry_buffer)[index * 16 + 15] > 0.5
	_expect(siege_flip_found, "SIEGE tank atlas is vertically corrected in the live render snapshot")
	main.queue_free()
	await tree.process_frame


func _test_build_selection_and_picking(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	var elevated_cell := Vector2i(4, 35)
	var world: Vector2 = main.grid.cell_to_world(elevated_cell)
	var picked: Vector2i = main.grid.world_to_cell(world)
	_expect(picked == elevated_cell, "elevation-aware isometric picking returns the exact displayed tile")
	main._on_build_kind_selected(BUILD_RANGED)
	_expect(main.selected_build_kind == BUILD_RANGED, "ranged production can be selected")
	_expect(main.try_build_spawner(elevated_cell), "selected ranged spawner is built on the tapped owned tile")
	main._on_build_kind_selected(BUILD_SIEGE)
	_expect(main.selected_build_kind == BUILD_SIEGE, "SIEGE production can be selected")
	main._on_build_kind_selected(BUILD_TOWER)
	_expect(main.selected_build_kind == BUILD_TOWER, "defense tower can be selected independently")
	main._on_build_kind_selected(BUILD_DRAGON)
	_expect(main.selected_build_kind == BUILD_DRAGON, "dragon lair can be selected independently")
	main.queue_free()
	await tree.process_frame


func _test_zoom_grounding_and_zero_shake(tree: SceneTree, main_scene: PackedScene) -> void:
	var main = await _spawn_main(tree, main_scene)
	main.map_view.set_zoom_at(999.0, main.map_view.frame_rect.get_center())
	_expect(is_equal_approx(main.map_view.zoom_level, GameConfig.MAP_ZOOM_MAX) and GameConfig.MAP_ZOOM_MAX >= 16.0, "pinch/wheel zoom reaches the maximum practical 16x close-up")
	main.simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000})
	_expect(main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(9, 41), BUILD_TOWER), "grounding fixture builds a tower")
	main._sync_board_and_buildings(true)
	var tower_view = null
	for view in main.building_views.values():
		if int(view.kind) == 2:
			tower_view = view
			break
	_expect(tower_view != null and absf(tower_view.get_sprite_opaque_bottom_y() - tower_view.get_ground_contact_y()) <= 0.01, "building sprite opaque base is anchored exactly to its ground contact")
	var fx_source := FileAccess.get_file_as_string("res://scripts/fx.gd")
	_expect(not fx_source.contains("shake") and not fx_source.contains("trauma"), "all camera shake and trauma code is removed")
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
