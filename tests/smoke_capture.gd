extends SceneTree

const GameConfig = preload("res://scripts/game_config.gd")
const MAIN_SCENE = preload("res://scenes/main.tscn")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const UNIT_SIEGE := 3

var main


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	root.size = Vector2i(GameConfig.VIEW_SIZE)
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	await process_frame
	await _capture_opening()
	await _capture_army("smoke_advantage.png", TEAM_ALLY, 60, false)
	await _capture_army("smoke_disadvantage.png", TEAM_ENEMY, 60, false)
	await _capture_cluster("smoke_cluster.png", 110)
	await _capture_army("smoke_persistent_flank.png", TEAM_ALLY, 36, true)
	await _capture_flow_split()
	await _capture_closeup("smoke_infantry_closeup.png", false)
	await _capture_visual_hierarchy()
	await _capture_elevation_overview()
	await _capture_territory_flash()
	await _capture_high_ground()
	await _capture_cluster("smoke_large_army.png", 360)
	await _capture_siege_impact()
	await _capture_closeup("smoke_siege_closeup.png", true)
	await _capture_legion_gathering()
	await _capture_rally_mode("smoke_rally_defend.png", 1)
	await _capture_rally_mode("smoke_rally_advance.png", 0)
	await _capture_legion_formation("smoke_legion_line.png", 0)
	await _capture_legion_formation("smoke_legion_wedge.png", 1)
	await _capture_legion_engaged()
	await _capture_legion_formation("smoke_legion_loose.png", 2)
	print("SMOKE CAPTURE PASS: 21 frames")
	quit(0)


func _reset() -> void:
	main.simulation.call("Reset")
	main.fx.clear_all()
	for view in main.building_views.values():
		if is_instance_valid(view): view.free()
	main.building_views.clear()
	main.building_records.clear()
	main._last_board_version = -1
	main.game_result = ""
	main.map_view.set_interaction_enabled(true)
	main.map_view.setup(main.grid, main.map_view.frame_rect)
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	main.fx.begin_frame()


func _spawn(team: int, kind: int, position: Vector2) -> void:
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_unit", "team": team, "kind": kind, "position": position, "exact": true})


func _add_building(team: int, kind: int, cell: Vector2i, unit_kind := UNIT_MELEE) -> void:
	main.simulation.call("ApplyDebugCommand", {"op": "add_building", "team": team, "kind": kind, "cell": cell, "unit_kind": unit_kind})


func _capture_opening() -> void:
	_reset()
	_add_building(TEAM_ENEMY, 1, Vector2i(7, 7), UNIT_MELEE)
	_add_building(TEAM_ALLY, 1, Vector2i(14, 36), UNIT_RANGED)
	main._sync_board_and_buildings(true)
	await _save("smoke_opening.png")


func _capture_army(file_name: String, dominant_team: int, count: int, flank: bool) -> void:
	_reset()
	for index in count:
		var team := dominant_team if index < int(count * 0.72) else (TEAM_ENEMY if dominant_team == TEAM_ALLY else TEAM_ALLY)
		var kind: int = [UNIT_MELEE, UNIT_RANGED, UNIT_MELEE, UNIT_SIEGE][index % 4]
		var col := (index * 3) % GameConfig.GRID_COLUMNS
		var row_base := 18 if team == TEAM_ENEMY else 26
		var row := row_base + (index / GameConfig.GRID_COLUMNS) * (1 if team == TEAM_ENEMY else -1)
		if flank: col = 2 + index % 5
		_spawn(team, kind, Vector2(float(col) + 0.5, float(row) + 0.5))
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	await _save(file_name)


func _capture_cluster(file_name: String, count: int) -> void:
	_reset()
	for index in count:
		var team := TEAM_ENEMY if index % 2 == 0 else TEAM_ALLY
		var kind: int = [UNIT_MELEE, UNIT_RANGED, UNIT_SIEGE][index % 3]
		var col := 3 + (index * 5) % 16
		var rank := (index / 16) % 9
		var y := 21.0 + (float(rank) - 4.0) * 0.28 + (-0.35 if team == TEAM_ENEMY else 0.35)
		_spawn(team, kind, Vector2(float(col) + 0.35 + float(index % 3) * 0.16, y))
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	await _save(file_name)


func _capture_flow_split() -> void:
	_reset()
	var elevation := PackedByteArray()
	elevation.resize(GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS)
	elevation.fill(0)
	var row := GameConfig.GRID_ROWS / 2
	for col in range(GameConfig.GRID_COLUMNS):
		if col != 4 and col != 17: elevation[row * GameConfig.GRID_COLUMNS + col] = 2
	main.simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	for index in 90:
		_spawn(TEAM_ALLY, UNIT_MELEE, Vector2(8.0 + float(index % 6), 27.0 + float(index / 18) * 0.25))
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	await _save("smoke_flow_split.png")


func _capture_closeup(file_name: String, siege: bool) -> void:
	_reset()
	var center := Vector2(10.5, 22.5)
	if siege:
		_add_building(TEAM_ALLY, 1, Vector2i(9, 24), UNIT_SIEGE)
		_add_building(TEAM_ENEMY, 2, Vector2i(12, 21))
	for index in 8:
		var kind := UNIT_SIEGE if siege else (UNIT_MELEE if index % 2 == 0 else UNIT_RANGED)
		_spawn(TEAM_ALLY if index < 4 else TEAM_ENEMY, kind, center + Vector2(float(index % 4) - 1.5, float(index / 4) - 0.5) * 0.75)
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	var focus: Vector2 = main.map_view.to_global(main.grid.position_to_world(center))
	main.map_view.set_zoom_at(10.0 if siege else 12.0, focus)
	await _save(file_name)


func _capture_visual_hierarchy() -> void:
	_reset()
	_add_building(TEAM_ALLY, 1, Vector2i(7, 27), UNIT_RANGED)
	_add_building(TEAM_ENEMY, 2, Vector2i(14, 17))
	_spawn(TEAM_ALLY, UNIT_DRAGON, Vector2(11.5, 24.0))
	for index in 24: _spawn(TEAM_ALLY if index % 2 else TEAM_ENEMY, UNIT_MELEE if index % 3 else UNIT_RANGED, Vector2(4.5 + float(index % 14), 20.5 + float(index % 4)))
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	await _save("smoke_visual_hierarchy.png")


func _capture_elevation_overview() -> void:
	_reset()
	for index in 50: _spawn(TEAM_ALLY if index % 2 else TEAM_ENEMY, UNIT_MELEE, Vector2(2.5 + float(index % 18), 16.5 + float(index % 12)))
	main.unit_renderer.sync()
	await _save("smoke_elevation_overview.png")


func _capture_territory_flash() -> void:
	_reset()
	var indices := PackedInt32Array()
	var owners := PackedInt32Array()
	for offset in 30:
		var column := offset % GameConfig.GRID_COLUMNS
		var row := 5 + floori(float(offset) / GameConfig.GRID_COLUMNS)
		indices.append(row * GameConfig.GRID_COLUMNS + column)
		owners.append(TEAM_ALLY)
	main.simulation.call("ApplyDebugCommand", {"op": "force_ownership_delta", "indices": indices, "owners": owners})
	main._sync_board_and_buildings()
	await _save("smoke_territory_flash.png")


func _capture_high_ground() -> void:
	_reset()
	var board: Dictionary = main.simulation.call("GetBoardSnapshot")
	var elevation: PackedByteArray = board.elevation
	for row in range(18, 22):
		for col in range(7, 14): elevation[row * GameConfig.GRID_COLUMNS + col] = 1
	for row in range(19, 21):
		for col in range(9, 12): elevation[row * GameConfig.GRID_COLUMNS + col] = 2
	main.simulation.call("ApplyDebugCommand", {"op": "set_elevation", "values": elevation})
	for index in 12:
		_spawn(TEAM_ALLY, UNIT_RANGED, Vector2(8.5 + float(index % 4), 20.0 + float(index / 4) * 0.2))
		_spawn(TEAM_ENEMY, UNIT_MELEE, Vector2(8.5 + float(index % 4), 23.0 + float(index / 4) * 0.2))
	main.fx.show_hit(Vector2(10.5, 22.0), true)
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	await _save("smoke_high_ground_combat.png")


func _capture_siege_impact() -> void:
	_reset()
	for index in 3: _spawn(TEAM_ALLY, UNIT_SIEGE, Vector2(8.5 + float(index), 25.0))
	for index in 18: _spawn(TEAM_ENEMY, UNIT_MELEE, Vector2(8.0 + float(index % 6) * 0.6, 20.0 + float(index / 6) * 0.4))
	main.fx.show_siege_projectile(Vector2(9.5, 25.0), Vector2(10.0, 20.5), TEAM_ALLY, 0.9)
	main.fx.show_siege_impact(Vector2(10.0, 20.5), TEAM_ALLY, GameConfig.SIEGE_BLAST_RADIUS)
	main.unit_renderer.sync()
	await _save("smoke_siege_impact.png")


func _capture_legion_gathering() -> void:
	_reset()
	main.simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 0})
	main.simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(10, 35), 5)
	main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(7, 37), 0)
	main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(10, 37), 0)
	main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(13, 37), 1)
	for tick in 360: main.simulation.call("Step", 1.0 / 30.0)
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	var focus: Vector2 = main.map_view.to_global(main.grid.position_to_world(Vector2(10.5, 33.8)))
	main.map_view.set_zoom_at(8.0, focus)
	await _save("smoke_legion_gathering.png")


func _capture_rally_mode(file_name: String, mode: int) -> void:
	_reset()
	main.simulation.call("ApplyDebugCommand", {"op": "set_gold", "ally": 1000, "enemy": 0})
	main.simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	main.simulation.call("TryBuild", TEAM_ALLY, Vector2i(10, 35), 5)
	var board: Dictionary = main.simulation.call("GetBoardSnapshot")
	var rally_id := -1
	for building in Array(board.buildings):
		if int(building.kind) == 4 and int(building.team) == TEAM_ALLY: rally_id = int(building.id)
	main.simulation.call("ConfigureRally", rally_id, mode, 0 if mode == 1 else 1)
	var count := 14 if mode == 1 else 10
	for index in count:
		_spawn(TEAM_ALLY, UNIT_MELEE if index < 7 else UNIT_RANGED, Vector2(8.6 + float(index % 5) * 0.65, 33.0 + float(index / 5) * 0.35))
	for tick in 45: main.simulation.call("Step", 1.0 / 30.0)
	main._sync_board_and_buildings(true)
	main.unit_renderer.sync()
	var focus: Vector2 = main.map_view.to_global(main.grid.position_to_world(Vector2(10.5, 33.8)))
	main.map_view.set_zoom_at(7.0, focus)
	await _save(file_name)


func _capture_legion_formation(file_name: String, formation: int) -> void:
	_reset()
	main.simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": TEAM_ALLY, "formation": formation, "template": {"melee": 6, "ranged": 3, "siege": 2, "dragon": 1}, "anchor": Vector2(10.5, 28.0)})
	main.unit_renderer.sync()
	var focus: Vector2 = main.map_view.to_global(main.grid.position_to_world(Vector2(10.5, 28.0)))
	main.map_view.set_zoom_at(5.0, focus)
	await _save(file_name)


func _capture_legion_engaged() -> void:
	_reset()
	main.simulation.call("ApplyDebugCommand", {"op": "set_enemy_ai", "enabled": false})
	var template := {"melee": 6, "ranged": 3, "siege": 1, "dragon": 0}
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": TEAM_ALLY, "formation": 1, "template": template, "anchor": Vector2(10.5, 24.2)})
	main.simulation.call("ApplyDebugCommand", {"op": "spawn_legion", "team": TEAM_ENEMY, "formation": 0, "template": template, "anchor": Vector2(10.5, 20.8)})
	for tick in 30: main.simulation.call("Step", 1.0 / 30.0)
	main.unit_renderer.sync()
	main.fx.show_hit(Vector2(10.5, 22.5), false)
	var focus: Vector2 = main.map_view.to_global(main.grid.position_to_world(Vector2(10.5, 22.5)))
	main.map_view.set_zoom_at(5.0, focus)
	await _save("smoke_legion_engaged.png")


func _save(file_name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	if image.get_size() != Vector2i(GameConfig.VIEW_SIZE):
		image.resize(int(GameConfig.VIEW_SIZE.x), int(GameConfig.VIEW_SIZE.y), Image.INTERPOLATE_LANCZOS)
	var error := image.save_png("res://build/%s" % file_name)
	if error != OK:
		push_error("capture failed: %s" % file_name)
		quit(1)
