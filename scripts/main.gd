class_name DefenseMain
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const BattleSimulationScript = preload("res://scripts/battle_simulation.gd")
const BuildingViewScript = preload("res://scripts/battle_building.gd")

@onready var world: Node2D = $World
@onready var grid: GridBoard = $World/Grid
@onready var buildings_layer: Node2D = $World/Buildings
@onready var unit_renderer: UnitRenderer = $World/UnitRenderer
@onready var fx: DefenseFx = $World/Fx
@onready var hud: DefenseHud = $Hud

var simulation: BattleSimulation
var building_views: Dictionary = {}
var game_result := ""
var _world_base_position := Vector2.ZERO


func _ready() -> void:
	simulation = BattleSimulationScript.new()
	simulation.reset()
	grid.set_simulation(simulation)
	unit_renderer.setup(grid, simulation)
	fx.setup(grid)
	_frame_world()
	_sync_building_views()
	_update_hud()
	hud.restart_pressed.connect(_restart)
	hud.show_message("FRONTLINE ACTIVE", GameConfig.COLOR_TEXT)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GameConfig.VIEW_SIZE)), GameConfig.COLOR_BACKGROUND)
	draw_rect(Rect2(Vector2(0, 142), Vector2(GameConfig.VIEW_SIZE.x, 3)), GameConfig.COLOR_TEAL.darkened(0.55))


func _process(delta: float) -> void:
	if simulation != null and game_result == "":
		step_simulation(delta)
	if is_instance_valid(fx):
		world.position = _world_base_position + fx.get_screen_shake_offset()


func _unhandled_input(event: InputEvent) -> void:
	if game_result != "":
		return
	var tap_position := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		tap_position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tap_position = event.position
	if tap_position.x >= 0.0:
		try_build_spawner(grid.world_to_cell(world.to_local(tap_position)))


func try_build_spawner(cell: Vector2i) -> bool:
	var valid := game_result == "" and simulation.try_build_spawner(simulation.TEAM_ALLY, cell)
	fx.show_placement(cell, valid)
	if valid:
		_sync_building_views()
		grid.queue_redraw()
		_update_hud()
	else:
		hud.show_message("BUILD BLOCKED", GameConfig.COLOR_ENEMY.lightened(0.25))
	return valid


func step_simulation(delta: float) -> void:
	if simulation == null:
		return
	if game_result == "":
		simulation.tick(delta)
	_sync_building_views()
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
			"unit_death":
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
				if int(event.kind) != simulation.BUILDING_HQ:
					fx.show_spawner_destroyed(Vector2i(event.cell), int(event.team))
				_start_building_destroy(int(event.building_id))
			"territory_changed":
				fx.show_territory_change(Vector2i(event.cell), int(event.team))
				grid.queue_redraw()
			"spawner_built":
				hud.show_message("BLUE SPAWNER ONLINE" if int(event.team) == simulation.TEAM_ALLY else "RED SPAWNER ONLINE", GameConfig.COLOR_ALLY if int(event.team) == simulation.TEAM_ALLY else GameConfig.COLOR_ENEMY)


func _sync_building_views() -> void:
	if simulation == null:
		return
	for record in simulation.buildings:
		var building_id := int(record.id)
		if not building_views.has(building_id):
			var view := BuildingViewScript.new()
			view.name = "Building_%d" % building_id
			buildings_layer.add_child(view)
			view.setup(grid, record)
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
	hud.show_result(value)


func _frame_world() -> void:
	var board_bounds := grid.get_board_bounds()
	var frame_top := 154.0
	var frame_bottom := 78.0
	var frame_size := Vector2(
		GameConfig.VIEW_SIZE.x - GameConfig.WORLD_FRAME_MARGIN * 2.0,
		GameConfig.VIEW_SIZE.y - frame_top - frame_bottom
	)
	var frame_scale := minf(frame_size.x / board_bounds.size.x, frame_size.y / board_bounds.size.y)
	world.scale = Vector2.ONE * frame_scale
	_world_base_position = Vector2(
		(float(GameConfig.VIEW_SIZE.x) - board_bounds.size.x * frame_scale) * 0.5 - board_bounds.position.x * frame_scale,
		frame_top + (frame_size.y - board_bounds.size.y * frame_scale) * 0.5 - board_bounds.position.y * frame_scale
	)
	world.position = _world_base_position


func _restart() -> void:
	get_tree().reload_current_scene()
