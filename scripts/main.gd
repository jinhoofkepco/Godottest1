class_name DefenseMain
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const BuildingViewScene = preload("res://scenes/battle_building.tscn")
const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const BUILDING_HQ := 0
const BUILDING_DEFENSE_TOWER := 2
const BUILDING_DRAGON_LAIR := 3
const BUILDING_RALLY_POINT := 4
const UNIT_MELEE := 0
const UNIT_RANGED := 1
const UNIT_DRAGON := 2
const UNIT_SIEGE := 3
const BUILD_MELEE := 0
const BUILD_RANGED := 1
const BUILD_DEFENSE_TOWER := 2
const BUILD_DRAGON := 3
const BUILD_SIEGE := 4
const BUILD_RALLY := 5

@onready var map_view: MapView = $MapView
@onready var world: Node2D = $MapView
@onready var grid: GridBoard = $MapView/Grid
@onready var buildings_layer: Node2D = $MapView/Buildings
@onready var unit_renderer: UnitRenderer = $MapView/UnitRenderer
@onready var fx: DefenseFx = $MapView/Fx
@onready var hud: DefenseHud = $Hud
@onready var simulation = $BattleSimulation

var building_views: Dictionary = {}
var building_records: Dictionary = {}
var game_result := ""
var selected_build_kind := BUILD_MELEE
var _last_board_version := -1
var _hud_snapshot: Dictionary = {}


func _ready() -> void:
	simulation.call("Reset")
	grid.set_simulation(simulation)
	unit_renderer.setup(grid, simulation)
	fx.setup(grid)
	map_view.setup(grid, Rect2(
		Vector2(GameConfig.WORLD_FRAME_MARGIN, GameConfig.WORLD_FRAME_TOP),
		Vector2(
			GameConfig.VIEW_SIZE.x - GameConfig.WORLD_FRAME_MARGIN * 2.0,
			GameConfig.VIEW_SIZE.y - GameConfig.WORLD_FRAME_TOP - GameConfig.WORLD_FRAME_BOTTOM
		)
	))
	_sync_board_and_buildings(true)
	_update_hud()
	map_view.tile_tapped.connect(try_build_spawner)
	hud.restart_pressed.connect(_restart)
	hud.build_kind_selected.connect(_on_build_kind_selected)
	hud.rally_config_changed.connect(_on_rally_config_changed)
	hud.demolish_requested.connect(_on_demolish_requested)
	hud.show_message("FRONTLINE ACTIVE", GameConfig.COLOR_TEXT)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GameConfig.VIEW_SIZE)), GameConfig.COLOR_BACKGROUND)
	draw_rect(Rect2(Vector2(0, 142), Vector2(GameConfig.VIEW_SIZE.x, 3)), GameConfig.COLOR_TEAL.darkened(0.55))


func _process(delta: float) -> void:
	if simulation != null and game_result == "":
		step_simulation(delta)


func try_build_spawner(cell: Vector2i) -> bool:
	if game_result != "":
		return false
	var existing_id := _building_at_cell(cell)
	if existing_id >= 0:
		var config: Dictionary = simulation.call("GetRallyConfig", existing_id)
		if not config.is_empty() and int(config.get("team", 0)) == TEAM_ALLY:
			hud.open_rally_panel(config)
			hud.show_message("RALLY ORDERS", GameConfig.COLOR_TEAL)
			return true
		return false
	var valid := bool(simulation.call("TryBuild", TEAM_ALLY, cell, selected_build_kind))
	fx.show_placement(cell, valid)
	if valid:
		_sync_board_and_buildings()
		_update_hud()
		hud.show_message("BLUE %s DEPLOYED" % _build_kind_name(selected_build_kind), GameConfig.COLOR_ALLY)
	else:
		hud.show_message("%s BUILD BLOCKED" % _build_kind_name(selected_build_kind), GameConfig.COLOR_ENEMY.lightened(0.25))
	return valid


func step_simulation(delta: float) -> void:
	if simulation == null:
		return
	fx.begin_frame()
	if game_result == "":
		simulation.call("Step", delta)
	_sync_board_and_buildings()
	unit_renderer.advance_visuals(delta)
	unit_renderer.sync()
	_consume_event_channels(simulation.call("DrainEvents"))
	_update_hud()
	var result := String(_hud_snapshot.get("result", ""))
	if game_result == "" and result != "":
		_finish_match(result)


func _consume_event_channels(channels: Dictionary) -> void:
	_consume_events(Array(channels.get("events", [])))
	var hit_unit_ids: PackedInt32Array = channels.get("hit_unit_ids", PackedInt32Array())
	var hit_positions: PackedVector2Array = channels.get("hit_positions", PackedVector2Array())
	var hit_high_ground: PackedByteArray = channels.get("hit_high_ground", PackedByteArray())
	for index in hit_positions.size():
		unit_renderer.note_damage(hit_unit_ids[index])
		var flags := int(hit_high_ground[index])
		fx.show_hit(hit_positions[index], (flags & 1) != 0, (flags & 2) != 0)
	var shot_origins: PackedVector2Array = channels.get("shot_origins", PackedVector2Array())
	var shot_targets: PackedVector2Array = channels.get("shot_targets", PackedVector2Array())
	var shot_teams: PackedInt32Array = channels.get("shot_teams", PackedInt32Array())
	for index in shot_origins.size():
		fx.show_ranged_shot(shot_origins[index], shot_targets[index], shot_teams[index])
	var death_positions: PackedVector2Array = channels.get("death_positions", PackedVector2Array())
	var death_teams: PackedInt32Array = channels.get("death_teams", PackedInt32Array())
	var death_kinds: PackedInt32Array = channels.get("death_kinds", PackedInt32Array())
	var death_directions: PackedVector2Array = channels.get("death_directions", PackedVector2Array())
	for index in death_positions.size():
		unit_renderer.queue_death(death_positions[index], death_teams[index], death_kinds[index], death_directions[index])
		fx.show_unit_death(death_positions[index], death_teams[index])


func _consume_events(events: Array) -> void:
	for event in events:
		var event_type := String(event.get("type", ""))
		match event_type:
			"hit":
				fx.show_hit(Vector2(event.position), bool(event.get("high_ground", false)))
			"ranged_shot":
				fx.show_ranged_shot(Vector2(event.origin), Vector2(event.position), int(event.team))
			"tower_shot":
				fx.show_ranged_shot(Vector2(event.origin), Vector2(event.position), int(event.team))
			"hq_shot":
				fx.show_ranged_shot(Vector2(event.origin), Vector2(event.position), int(event.team))
			"siege_projectile":
				fx.show_siege_projectile(Vector2(event.origin), Vector2(event.position), int(event.team), float(event.get("duration", GameConfig.SIEGE_FLIGHT_SECONDS)))
			"siege_impact":
				fx.show_siege_impact(Vector2(event.position), int(event.team), float(event.get("radius", GameConfig.SIEGE_BLAST_RADIUS)))
			"unit_death":
				unit_renderer.queue_death(Vector2(event.position), int(event.team), int(event.get("unit_kind", UNIT_MELEE)), Vector2(event.get("direction", Vector2.ZERO)))
				fx.show_unit_death(Vector2(event.position), int(event.team))
			"unit_produced":
				fx.show_production(Vector2i(event.cell), int(event.team))
			"rally_hit", "building_hit":
				fx.show_spawner_hit(Vector2i(event.cell), int(event.team))
				_flash_building(int(event.building_id))
			"rally_mode_changed":
				var advancing := int(event.get("mode", 0)) == 0
				hud.show_message("RALLY: ADVANCE" if advancing else "RALLY: DEFEND", GameConfig.COLOR_TEAL)
			"legion_launched":
				fx.show_production(Vector2i(event.cell), int(event.team))
			"hq_hit":
				fx.show_hq_hit(Vector2i(event.cell), int(event.team))
				_flash_building(int(event.building_id))
			"building_destroyed":
				if int(event.kind) == BUILDING_HQ:
					fx.show_hq_destroyed(Vector2i(event.cell), int(event.team))
				else:
					fx.show_spawner_destroyed(Vector2i(event.cell), int(event.team))
				_start_building_destroy(int(event.building_id))
			"building_built":
				var team := int(event.team)
				hud.show_message(
					"%s %s ONLINE" % ["BLUE" if team == TEAM_ALLY else "RED", _building_kind_name(int(event.kind), int(event.unit_kind))],
					GameConfig.COLOR_ALLY if team == TEAM_ALLY else GameConfig.COLOR_ENEMY
				)


func _sync_board_and_buildings(force := false) -> void:
	if simulation == null:
		return
	var version := int(simulation.call("GetBoardVersion"))
	if not force and version == _last_board_version:
		return
	var board_data: Dictionary
	if _last_board_version < 0 or force:
		board_data = simulation.call("GetBoardSnapshot")
		grid.sync_initial(board_data)
	else:
		board_data = simulation.call("GetBoardDelta")
		grid.apply_board_delta(board_data)
	_last_board_version = int(board_data.get("version", version))
	for record in board_data.get("buildings", []):
		var building_id := int(record.id)
		building_records[building_id] = record
		if bool(record.destroyed):
			continue
		if not building_views.has(building_id):
			var view := BuildingViewScene.instantiate()
			view.name = "Building_%d" % building_id
			buildings_layer.add_child(view)
			view.setup(grid, record)
			view.collapse_finished.connect(_on_building_view_collapsed)
			building_views[building_id] = view
		var current_view = building_views[building_id]
		if is_instance_valid(current_view):
			current_view.update_from_data(record)


func _flash_building(building_id: int) -> void:
	if building_views.has(building_id) and is_instance_valid(building_views[building_id]):
		building_views[building_id].flash_hit()


func _start_building_destroy(building_id: int) -> void:
	if building_views.has(building_id) and is_instance_valid(building_views[building_id]):
		building_views[building_id].start_destroy()


func _on_building_view_collapsed(building_id: int) -> void:
	building_views.erase(building_id)


func _update_hud() -> void:
	if simulation == null or not is_instance_valid(hud):
		return
	_hud_snapshot = simulation.call("GetHudSnapshot")
	hud.update_stats(
		int(_hud_snapshot.get("ally_gold", 0)),
		float(_hud_snapshot.get("ally_hq_hp", 0.0)),
		float(_hud_snapshot.get("enemy_hq_hp", 0.0)),
		float(_hud_snapshot.get("time_remaining", 0.0)),
		float(_hud_snapshot.get("occupancy", 0.5))
	)


func _finish_match(value: String) -> void:
	game_result = value
	map_view.set_interaction_enabled(false)
	hud.show_result(value)


func _unit_kind_name(unit_kind: int) -> String:
	if unit_kind == UNIT_DRAGON:
		return "DRAGON"
	if unit_kind == UNIT_SIEGE:
		return "SIEGE"
	return "RANGED" if unit_kind == UNIT_RANGED else "MELEE"


func _build_kind_name(build_kind: int) -> String:
	match build_kind:
		BUILD_RANGED: return "RANGED SPAWNER"
		BUILD_SIEGE: return "SIEGE SPAWNER"
		BUILD_DRAGON: return "DRAGON LAIR"
		BUILD_RALLY: return "RALLY POINT"
		BUILD_DEFENSE_TOWER: return "DEFENSE TOWER"
		_: return "MELEE SPAWNER"


func _building_kind_name(kind: int, unit_kind: int) -> String:
	if kind == BUILDING_DEFENSE_TOWER:
		return "DEFENSE TOWER"
	if kind == BUILDING_DRAGON_LAIR:
		return "DRAGON LAIR"
	if kind == BUILDING_RALLY_POINT:
		return "RALLY POINT"
	return "%s SPAWNER" % _unit_kind_name(unit_kind)


func _on_build_kind_selected(build_kind: int) -> void:
	selected_build_kind = build_kind


func _on_rally_config_changed(building_id: int, mode: int, formation: int) -> void:
	if simulation.call("ConfigureRally", building_id, mode, formation):
		_sync_board_and_buildings()
		hud.show_message("RALLY ORDERS UPDATED", GameConfig.COLOR_TEAL)


func _on_demolish_requested(building_id: int) -> void:
	if simulation.call("DemolishRally", building_id):
		_sync_board_and_buildings()
		hud.show_message("RALLY POINT DEMOLISHED", GameConfig.COLOR_ORANGE)


func _building_at_cell(cell: Vector2i) -> int:
	for building_id in building_records:
		var record: Dictionary = building_records[building_id]
		if not bool(record.get("destroyed", false)) and Vector2i(record.get("cell", Vector2i(-1, -1))) == cell:
			return int(building_id)
	return -1


func _restart() -> void:
	get_tree().reload_current_scene()
