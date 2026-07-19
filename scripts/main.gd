class_name DefenseMain
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const BattleSimulationScript = preload("res://scripts/battle_simulation.gd")
const BuildingViewScene = preload("res://scenes/battle_building.tscn")

@onready var map_view: MapView = $MapView
@onready var world: Node2D = $MapView
@onready var grid: GridBoard = $MapView/Grid
@onready var buildings_layer: Node2D = $MapView/Buildings
@onready var unit_renderer: UnitRenderer = $MapView/UnitRenderer
@onready var fx: DefenseFx = $MapView/Fx
@onready var hud: DefenseHud = $Hud

var simulation: BattleSimulation
var building_views: Dictionary = {}
var game_result := ""
var selected_build_kind := BattleSimulationScript.BUILD_MELEE_SPAWNER


func _ready() -> void:
	simulation = BattleSimulationScript.new()
	simulation.reset()
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
	_sync_building_views()
	_update_hud()
	map_view.tile_tapped.connect(try_build_spawner)
	hud.restart_pressed.connect(_restart)
	hud.build_kind_selected.connect(_on_build_kind_selected)
	hud.show_message("FRONTLINE ACTIVE", GameConfig.COLOR_TEXT)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GameConfig.VIEW_SIZE)), GameConfig.COLOR_BACKGROUND)
	draw_rect(Rect2(Vector2(0, 142), Vector2(GameConfig.VIEW_SIZE.x, 3)), GameConfig.COLOR_TEAL.darkened(0.55))


func _process(delta: float) -> void:
	if simulation != null and game_result == "":
		step_simulation(delta)


func try_build_spawner(cell: Vector2i) -> bool:
	var valid := game_result == "" and simulation.try_build(simulation.TEAM_ALLY, cell, selected_build_kind)
	fx.show_placement(cell, valid)
	if valid:
		_sync_building_views()
		grid.queue_redraw()
		_update_hud()
		hud.show_message("BLUE %s DEPLOYED" % _build_kind_name(selected_build_kind), GameConfig.COLOR_ALLY)
	else:
		hud.show_message("%s BUILD BLOCKED" % _build_kind_name(selected_build_kind), GameConfig.COLOR_ENEMY.lightened(0.25))
	return valid


func step_simulation(delta: float) -> void:
	if simulation == null:
		return
	if game_result == "":
		simulation.tick(delta)
	_sync_building_views()
	unit_renderer.advance_visuals(delta)
	unit_renderer.sync()
	_consume_events(simulation.drain_events())
	_update_hud()
	if game_result == "" and simulation.result != "":
		_finish_match(simulation.result)


func _consume_events(events: Array) -> void:
	for event in events:
		var event_type := String(event.get("type", ""))
		match event_type:
			"hit":
				fx.show_hit(Vector2(event.position))
			"ranged_shot":
				fx.show_ranged_shot(Vector2(event.origin), Vector2(event.position), int(event.team))
			"tower_shot":
				fx.show_ranged_shot(Vector2(event.origin), Vector2(event.position), int(event.team))
			"hq_shot":
				fx.show_ranged_shot(Vector2(event.origin), Vector2(event.position), int(event.team))
			"unit_death":
				unit_renderer.queue_death(Vector2(event.position), int(event.team), int(event.get("unit_kind", simulation.UNIT_MELEE)), Vector2(event.get("direction", Vector2.ZERO)))
				fx.show_unit_death(Vector2(event.position), int(event.team))
			"unit_produced":
				fx.show_production(Vector2i(event.cell), int(event.team))
			"spawner_hit":
				fx.show_spawner_hit(Vector2i(event.cell), int(event.team))
				_flash_building(int(event.building_id))
			"hq_hit":
				fx.show_hq_hit(Vector2i(event.cell), int(event.team))
				_flash_building(int(event.building_id))
			"building_destroyed":
				if int(event.kind) == simulation.BUILDING_HQ:
					fx.show_hq_destroyed(Vector2i(event.cell), int(event.team))
				else:
					fx.show_spawner_destroyed(Vector2i(event.cell), int(event.team))
				_start_building_destroy(int(event.building_id))
			"territory_changed":
				fx.show_territory_change(Vector2i(event.cell), int(event.team))
				grid.queue_redraw()
			"building_built":
				var team := int(event.team)
				hud.show_message(
					"%s %s ONLINE" % ["BLUE" if team == simulation.TEAM_ALLY else "RED", _building_kind_name(int(event.kind), int(event.unit_kind))],
					GameConfig.COLOR_ALLY if team == simulation.TEAM_ALLY else GameConfig.COLOR_ENEMY
				)


func _sync_building_views() -> void:
	if simulation == null:
		return
	for record in simulation.buildings:
		var building_id := int(record.id)
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
	hud.update_stats(
		simulation.ally_gold,
		_building_hp(simulation.ally_hq_id),
		_building_hp(simulation.enemy_hq_id),
		simulation.time_remaining,
		simulation.get_occupancy(simulation.TEAM_ALLY)
	)


func _building_hp(building_id: int) -> float:
	for building in simulation.buildings:
		if int(building.id) == building_id:
			return float(building.hp)
	return 0.0


func _finish_match(value: String) -> void:
	game_result = value
	map_view.set_interaction_enabled(false)
	hud.show_result(value)


func _unit_kind_name(unit_kind: int) -> String:
	if unit_kind == simulation.UNIT_DRAGON:
		return "DRAGON"
	return "RANGED" if unit_kind == simulation.UNIT_RANGED else "MELEE"


func _build_kind_name(build_kind: int) -> String:
	match build_kind:
		simulation.BUILD_RANGED_SPAWNER:
			return "RANGED SPAWNER"
		simulation.BUILD_DEFENSE_TOWER:
			return "DEFENSE TOWER"
		simulation.BUILD_DRAGON_LAIR:
			return "DRAGON LAIR"
		_:
			return "MELEE SPAWNER"


func _building_kind_name(kind: int, unit_kind: int) -> String:
	if kind == simulation.BUILDING_DEFENSE_TOWER:
		return "DEFENSE TOWER"
	if kind == simulation.BUILDING_DRAGON_LAIR:
		return "DRAGON LAIR"
	return "%s SPAWNER" % _unit_kind_name(unit_kind)


func _on_build_kind_selected(build_kind: int) -> void:
	selected_build_kind = build_kind


func _restart() -> void:
	get_tree().reload_current_scene()
