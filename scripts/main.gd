class_name DefenseMain
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")
const TowerScene = preload("res://scenes/tower.tscn")
const EnemyScene = preload("res://scenes/enemy.tscn")

@export var shake_duration := 0.22
@export var shake_strength := 7.0

@onready var world: Node2D = $World
@onready var grid = $World/Grid
@onready var core = $World/Core
@onready var enemies: Node2D = $World/Enemies
@onready var towers: Node2D = $World/Towers
@onready var projectiles: Node2D = $World/Projectiles
@onready var fx = $World/Fx
@onready var wave_manager = $WaveManager
@onready var hud = $Hud

var gold := GameConfig.START_GOLD
var core_hp := GameConfig.CORE_MAX_HP
var game_result := ""
var _shake_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 41025
	wave_manager.spawn_enemy.connect(_on_spawn_enemy)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.wave_cleared.connect(_on_wave_cleared)
	hud.next_wave_pressed.connect(start_next_wave)
	hud.restart_pressed.connect(_restart)
	hud.update_stats(gold, core_hp, wave_manager.current_wave)
	hud.set_wave_button(true, wave_manager.current_wave)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GameConfig.VIEW_SIZE)), GameConfig.COLOR_BACKGROUND)
	draw_rect(Rect2(Vector2(0, 100), Vector2(540, 5)), GameConfig.COLOR_TEAL.darkened(0.65))


func _process(delta: float) -> void:
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var falloff := _shake_left / shake_duration
		world.position = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * shake_strength * falloff
	else:
		world.position = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if game_result != "":
		return
	var tap_position := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		tap_position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tap_position = event.position
	if tap_position.x >= 0.0:
		try_place_tower(grid.world_to_cell(tap_position))


func try_place_tower(cell: Vector2i) -> bool:
	if game_result != "" or gold < GameConfig.TOWER_COST or not grid.can_build(cell):
		return false
	var tower = TowerScene.instantiate()
	towers.add_child(tower)
	tower.position = grid.cell_to_world(cell)
	tower.setup(enemies, projectiles)
	grid.occupy(cell)
	gold -= GameConfig.TOWER_COST
	hud.update_stats(gold, core_hp, wave_manager.current_wave)
	return true


func start_next_wave() -> void:
	if game_result != "":
		return
	if wave_manager.start_next_wave():
		hud.set_wave_button(false, wave_manager.current_wave)


func damage_core(amount: int) -> void:
	if game_result != "":
		return
	core_hp = maxi(0, core_hp - amount)
	core.set_hp(core_hp)
	_shake_left = shake_duration
	hud.update_stats(gold, core_hp, wave_manager.current_wave)
	if core_hp <= 0:
		_finish_match("DEFEAT")


func _on_spawn_enemy(_wave: int, column: int, speed: float, health: float) -> void:
	if game_result != "":
		return
	var enemy = EnemyScene.instantiate()
	enemies.add_child(enemy)
	enemy.setup(column, speed, health)
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.reached_core.connect(_on_enemy_reached_core)


func _on_enemy_defeated(at: Vector2) -> void:
	if game_result != "":
		return
	gold += GameConfig.KILL_REWARD
	wave_manager.notify_enemy_removed()
	fx.spawn_burst(at)
	hud.update_stats(gold, core_hp, wave_manager.current_wave)


func _on_enemy_reached_core(_at: Vector2) -> void:
	if game_result != "":
		return
	wave_manager.notify_enemy_removed()
	damage_core(1)


func _on_wave_started(wave: int) -> void:
	hud.update_stats(gold, core_hp, wave)


func _on_wave_cleared(wave: int) -> void:
	if game_result != "":
		return
	gold += GameConfig.WAVE_REWARD
	hud.update_stats(gold, core_hp, wave)
	if wave >= GameConfig.TOTAL_WAVES:
		_finish_match("VICTORY")
	else:
		hud.set_wave_button(true, wave)


func _finish_match(result: String) -> void:
	game_result = result
	wave_manager.stop()
	hud.set_wave_button(false, wave_manager.current_wave)
	hud.show_result(result)
	if result == "DEFEAT":
		world.process_mode = Node.PROCESS_MODE_DISABLED


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

