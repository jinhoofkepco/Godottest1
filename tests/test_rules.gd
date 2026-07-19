extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_values()
	_test_wave_scaling()
	_test_grid_build_rules()
	_test_grid_projection()
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
	grid.free()


func _test_grid_projection() -> void:
	var grid_script := load("res://scripts/grid.gd")
	if grid_script == null or not grid_script.can_instantiate():
		return
	var grid = grid_script.new()
	_expect(grid.cell_to_world(Vector2i(0, 0)).is_equal_approx(Vector2(0, 16)), "origin cell center uses isometric projection")
	_expect(grid.cell_to_world(Vector2i(4, 7)).is_equal_approx(Vector2(-96, 192)), "interior cell center uses isometric projection")
	_expect(grid.has_method("grid_to_screen"), "grid exposes forward projection")
	_expect(grid.has_method("screen_to_grid"), "grid exposes inverse projection")
	_expect(grid.has_method("get_board_bounds"), "grid exposes projected board bounds")
	_expect(grid.has_method("get_core_anchor"), "grid exposes projected core anchor")
	if (
		not grid.has_method("grid_to_screen")
		or not grid.has_method("screen_to_grid")
		or not grid.has_method("get_board_bounds")
		or not grid.has_method("get_core_anchor")
	):
		grid.free()
		return
	_expect(grid.get_board_bounds().is_equal_approx(Rect2(-448, 0, 736, 368)), "projected board bounds include every diamond")
	_expect(grid.get_core_anchor().is_equal_approx(Vector2(-304, 296)), "core anchor is centered under the final board edge")

	var logical_points: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(0.25, 0.75),
		Vector2(4.5, 7.5),
		Vector2(8.875, 13.125),
	]
	for logical_point in logical_points:
		var round_trip = grid.screen_to_grid(grid.grid_to_screen(logical_point))
		_expect(round_trip.is_equal_approx(logical_point), "continuous grid point round trips through projection: %s" % logical_point)

	var interior_cell := Vector2i(4, 7)
	var interior_center: Vector2 = grid.cell_to_world(interior_cell)
	var interior_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(15, 0),
		Vector2(-15, 0),
		Vector2(0, 7),
		Vector2(0, -7),
		Vector2(8, 4),
		Vector2(-8, -4),
	]
	for offset in interior_offsets:
		_expect(grid.world_to_cell(interior_center + offset) == interior_cell, "diamond interior picks cell at offset %s" % offset)

	var edge_cells: Array[Vector2i] = []
	for column in 9:
		edge_cells.append(Vector2i(column, 0))
		edge_cells.append(Vector2i(column, 13))
	for row in range(1, 13):
		edge_cells.append(Vector2i(0, row))
		edge_cells.append(Vector2i(8, row))
	for cell in edge_cells:
		_expect(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "edge cell center picks its source cell: %s" % cell)

	var outside_cells: Array[Vector2i] = [
		Vector2i(-1, 5),
		Vector2i(9, 5),
		Vector2i(4, -1),
		Vector2i(4, 14),
	]
	for cell in outside_cells:
		var picked_cell = grid.world_to_cell(grid.cell_to_world(cell))
		_expect(not grid.can_build(picked_cell), "projected out-of-board cell is rejected: %s" % cell)
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
