extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_values()
	_test_wave_scaling()
	_test_grid_build_rules()
	_test_enemy_damage_and_defeat()
	_test_projectile_delivery()
	return failures


func _test_config_values() -> void:
	var config := load("res://scripts/game_config.gd")
	_expect(config != null, "game config script exists")
	_expect(config != null and config.can_instantiate(), "game config parses")
	if config == null or not config.can_instantiate():
		return
	_expect(config.START_GOLD == 150, "start gold is 150")
	_expect(config.TOWER_COST == 50, "tower cost is 50")
	_expect(config.KILL_REWARD == 10, "kill reward is 10")
	_expect(config.WAVE_REWARD == 25, "wave reward is 25")
	_expect(config.CORE_MAX_HP == 20, "core HP is 20")
	_expect(config.TOTAL_WAVES == 5, "there are five waves")


func _test_wave_scaling() -> void:
	var config := load("res://scripts/game_config.gd")
	if config == null:
		return
	_expect(config.wave_enemy_count(1) == 6, "wave one has six enemies")
	_expect(config.wave_enemy_count(5) == 14, "wave five has fourteen enemies")
	_expect(config.wave_enemy_speed(5) > config.wave_enemy_speed(1), "enemy speed increases")
	_expect(config.wave_enemy_health(5) > config.wave_enemy_health(1), "enemy health increases")


func _test_grid_build_rules() -> void:
	var grid_script := load("res://scripts/grid.gd")
	_expect(grid_script != null, "grid script exists")
	_expect(grid_script != null and grid_script.can_instantiate(), "grid script parses")
	if grid_script == null or not grid_script.can_instantiate():
		return
	var grid = grid_script.new()
	_expect(grid.can_build(Vector2i(4, 5)), "ally row is buildable")
	_expect(not grid.can_build(Vector2i(4, 2)), "enemy zone is not buildable")
	_expect(not grid.can_build(Vector2i(4, 13)), "core row is not buildable")
	_expect(not grid.can_build(Vector2i(-1, 7)), "outside column is not buildable")
	grid.occupy(Vector2i(4, 5))
	_expect(not grid.can_build(Vector2i(4, 5)), "occupied cell is not buildable")
	_expect(grid.cell_to_world(Vector2i(0, 0)).is_equal_approx(Vector2(54, 135)), "cell center conversion is stable")
	grid.free()


func _test_enemy_damage_and_defeat() -> void:
	var enemy_script := load("res://scripts/enemy.gd")
	_expect(enemy_script != null and enemy_script.can_instantiate(), "enemy script parses")
	if enemy_script == null or not enemy_script.can_instantiate():
		return
	var enemy = enemy_script.new()
	var defeated := [false]
	enemy.defeated.connect(func(_at: Vector2) -> void: defeated[0] = true)
	enemy.setup(2, 50.0, 20.0)
	enemy.take_damage(5.0)
	_expect(is_equal_approx(enemy.health, 15.0), "enemy loses exact damage")
	enemy.take_damage(15.0)
	_expect(enemy.is_dead, "lethal damage marks enemy dead")
	_expect(defeated[0], "lethal damage emits defeated")
	enemy.free()


func _test_projectile_delivery() -> void:
	var enemy_script := load("res://scripts/enemy.gd")
	var projectile_script := load("res://scripts/projectile.gd")
	_expect(projectile_script != null and projectile_script.can_instantiate(), "projectile script parses")
	if enemy_script == null or not enemy_script.can_instantiate() or projectile_script == null or not projectile_script.can_instantiate():
		return
	var enemy = enemy_script.new()
	enemy.setup(0, 0.0, 20.0)
	enemy.position = Vector2(2, 0)
	var projectile = projectile_script.new()
	projectile.position = Vector2.ZERO
	projectile.setup(enemy, 7.0, 100.0)
	projectile._physics_process(0.1)
	_expect(is_equal_approx(enemy.health, 13.0), "projectile applies damage on arrival")
	projectile.free()
	enemy.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
