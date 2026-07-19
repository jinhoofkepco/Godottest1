class_name DefenseWaveManager
extends Node

signal spawn_enemy(wave: int, column: int, speed: float, health: float)
signal wave_started(wave: int)
signal wave_cleared(wave: int)

const GameConfig = preload("res://scripts/game_config.gd")

@export var spawn_interval := GameConfig.SPAWN_INTERVAL

var current_wave := 0
var wave_active := false
var _remaining_to_spawn := 0
var _living_enemies := 0
var _spawn_timer := 0.0
var _spawn_index := 0


func start_next_wave() -> bool:
	if wave_active or current_wave >= GameConfig.TOTAL_WAVES:
		return false
	current_wave += 1
	wave_active = true
	_remaining_to_spawn = GameConfig.wave_enemy_count(current_wave)
	_living_enemies = 0
	_spawn_timer = 0.0
	_spawn_index = 0
	wave_started.emit(current_wave)
	return true


func _process(delta: float) -> void:
	if not wave_active or _remaining_to_spawn <= 0:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	var column := (_spawn_index * 2 + current_wave * 3) % GameConfig.GRID_COLUMNS
	_spawn_index += 1
	_remaining_to_spawn -= 1
	_living_enemies += 1
	_spawn_timer = spawn_interval
	spawn_enemy.emit(
		current_wave,
		column,
		GameConfig.wave_enemy_speed(current_wave),
		GameConfig.wave_enemy_health(current_wave)
	)


func notify_enemy_removed() -> void:
	_living_enemies = maxi(0, _living_enemies - 1)
	if wave_active and _remaining_to_spawn == 0 and _living_enemies == 0:
		wave_active = false
		wave_cleared.emit(current_wave)


func stop() -> void:
	wave_active = false
	_remaining_to_spawn = 0
	_living_enemies = 0

