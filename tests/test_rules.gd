extends RefCounted

var failures: Array[String] = []


func run() -> Array[String]:
	_test_config_values()
	_test_wave_scaling()
	_test_grid_build_rules()
	_test_grid_projection()
	_test_entity_sort_scene()
	_test_enemy_logical_movement()
	_test_enemy_damage_and_defeat()
	_test_tower_logical_range()
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
	var config := load("res://scripts/game_config.gd")
	var grid_script := load("res://scripts/grid.gd")
	_expect(grid_script != null, "grid script exists")
	_expect(grid_script != null and grid_script.can_instantiate(), "grid script parses")
	if grid_script == null or not grid_script.can_instantiate():
		return
	var grid = grid_script.new()
	_expect(grid.can_build(Vector2i(4, 5)), "ally row is buildable")
	_expect(not grid.can_build(Vector2i(4, 2)), "enemy zone is not buildable")
	_expect(not grid.can_build(Vector2i(4, config.CORE_ROW)), "core row is not buildable")
	_expect(not grid.can_build(Vector2i(-1, 7)), "outside column is not buildable")
	grid.occupy(Vector2i(4, 5))
	_expect(not grid.can_build(Vector2i(4, 5)), "occupied cell is not buildable")
	grid.free()


func _test_grid_projection() -> void:
	var config := load("res://scripts/game_config.gd")
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
		Vector2(config.GRID_COLUMNS - 0.125, config.GRID_ROWS - 0.875),
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
	for column in config.GRID_COLUMNS:
		edge_cells.append(Vector2i(column, 0))
		edge_cells.append(Vector2i(column, config.GRID_ROWS - 1))
	for row in range(1, config.GRID_ROWS - 1):
		edge_cells.append(Vector2i(0, row))
		edge_cells.append(Vector2i(config.GRID_COLUMNS - 1, row))
	for cell in edge_cells:
		_expect(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "edge cell center picks its source cell: %s" % cell)

	var outside_cells: Array[Vector2i] = [
		Vector2i(-1, 5),
		Vector2i(config.GRID_COLUMNS, 5),
		Vector2i(4, -1),
		Vector2i(4, config.GRID_ROWS),
	]
	for cell in outside_cells:
		var picked_cell = grid.world_to_cell(grid.cell_to_world(cell))
		_expect(not grid.can_build(picked_cell), "projected out-of-board cell is rejected: %s" % cell)
	grid.free()


func _test_entity_sort_scene() -> void:
	var main_scene := load("res://scenes/main.tscn")
	_expect(main_scene != null, "main scene loads for depth configuration")
	if main_scene == null:
		return
	var main = main_scene.instantiate()
	var entity_sort = main.get_node_or_null("World/EntitySort")
	_expect(entity_sort != null, "world has one entity sort layer")
	_expect(entity_sort != null and entity_sort.y_sort_enabled, "entity sort layer enables y sorting")
	for container_name in ["Enemies", "Towers", "Projectiles"]:
		_expect(entity_sort != null and entity_sort.get_node_or_null(container_name) != null, "%s live under entity sort" % container_name)
	main.free()


func _test_enemy_logical_movement() -> void:
	var config := load("res://scripts/game_config.gd")
	var grid_script := load("res://scripts/grid.gd")
	var enemy_script := load("res://scripts/enemy.gd")
	if grid_script == null or not grid_script.can_instantiate() or enemy_script == null or not enemy_script.can_instantiate():
		return
	var grid = grid_script.new()
	var enemy = enemy_script.new()
	enemy.setup(grid, 2, 50.0, 20.0)
	_expect(enemy.grid_position.is_equal_approx(Vector2(2.5, 0.5)), "enemy starts at its logical column center")
	_expect(is_equal_approx(enemy.move_speed * config.CELL_SIZE, 50.0), "enemy pixel speed converts exactly to logical rows per second")
	enemy._physics_process(0.54)
	_expect(enemy.grid_position.is_equal_approx(Vector2(2.5, 1.0)), "enemy advances continuously in logical rows")
	_expect(enemy.position.is_equal_approx(grid.grid_to_screen(enemy.grid_position)), "enemy presentation follows projected logical position")
	var terminal_enemy = enemy_script.new()
	terminal_enemy.setup(grid, 2, config.CELL_SIZE, 20.0)
	var original_travel_seconds: float = (
		config.ENEMY_CORE_Y
		- (config.GRID_ORIGIN.y + config.CELL_SIZE * 0.5)
	) / config.CELL_SIZE
	terminal_enemy._physics_process(original_travel_seconds - 0.001)
	_expect(not terminal_enemy.is_dead, "enemy remains active until the original travel duration")
	terminal_enemy._physics_process(0.002)
	_expect(terminal_enemy.is_dead, "enemy reaches the core at the original travel duration")
	terminal_enemy.free()
	enemy.free()
	grid.free()


func _test_enemy_damage_and_defeat() -> void:
	var grid_script := load("res://scripts/grid.gd")
	var enemy_script := load("res://scripts/enemy.gd")
	_expect(enemy_script != null and enemy_script.can_instantiate(), "enemy script parses")
	if enemy_script == null or not enemy_script.can_instantiate():
		return
	var grid = grid_script.new()
	var enemy = enemy_script.new()
	var defeated := [false]
	var damaged_at := [Vector2.ZERO]
	var damaged_amount := [0.0]
	enemy.defeated.connect(func(_at: Vector2) -> void: defeated[0] = true)
	enemy.damaged.connect(func(at_grid: Vector2, amount: float) -> void:
		damaged_at[0] = at_grid
		damaged_amount[0] = amount
	)
	enemy.setup(grid, 2, 50.0, 20.0)
	enemy.take_damage(5.0)
	_expect(is_equal_approx(enemy.health, 15.0), "enemy loses exact damage")
	_expect(damaged_at[0].is_equal_approx(enemy.grid_position), "enemy damage reports its logical hit position")
	_expect(is_equal_approx(damaged_amount[0], 5.0), "enemy damage reports the applied amount")
	enemy.take_damage(15.0)
	_expect(enemy.is_dead, "lethal damage marks enemy dead")
	_expect(defeated[0], "lethal damage emits defeated")
	enemy.free()
	grid.free()


func _test_tower_logical_range() -> void:
	var config := load("res://scripts/game_config.gd")
	var grid_script := load("res://scripts/grid.gd")
	var enemy_script := load("res://scripts/enemy.gd")
	var tower_script := load("res://scripts/tower.gd")
	if (
		grid_script == null
		or not grid_script.can_instantiate()
		or enemy_script == null
		or not enemy_script.can_instantiate()
		or tower_script == null
		or not tower_script.can_instantiate()
	):
		return
	var grid = grid_script.new()
	var enemies := Node.new()
	var projectiles := Node.new()
	var tower = tower_script.new()
	tower.grid_position = Vector2(4.5, 8.5)
	tower.setup(grid, enemies, projectiles)
	var enemy = enemy_script.new()
	enemies.add_child(enemy)
	enemy.setup(grid, 4, 0.0, 20.0)
	enemy.grid_position = tower.grid_position + Vector2(0.0, config.TOWER_RANGE / config.CELL_SIZE - 0.01)
	enemy.position = Vector2(10000, 10000)
	_expect(is_equal_approx(tower.attack_range * config.CELL_SIZE, config.TOWER_RANGE), "tower range preserves its pixel-tuned distance in grid units")
	_expect(is_equal_approx(tower.projectile_speed * config.CELL_SIZE, config.PROJECTILE_SPEED), "tower projectile speed preserves its pixel-tuned value in grid units")
	_expect(tower._nearest_target() == enemy, "tower target selection uses logical distance")
	enemies.free()
	projectiles.free()
	tower.free()
	grid.free()


func _test_projectile_delivery() -> void:
	var config := load("res://scripts/game_config.gd")
	var grid_script := load("res://scripts/grid.gd")
	var enemy_script := load("res://scripts/enemy.gd")
	var projectile_script := load("res://scripts/projectile.gd")
	_expect(projectile_script != null and projectile_script.can_instantiate(), "projectile script parses")
	if enemy_script == null or not enemy_script.can_instantiate() or projectile_script == null or not projectile_script.can_instantiate():
		return
	var grid = grid_script.new()
	var enemy = enemy_script.new()
	enemy.setup(grid, 0, 0.0, 20.0)
	enemy.grid_position = Vector2(0.1, 0.0)
	enemy.position = Vector2(10000, 10000)
	var projectile = projectile_script.new()
	projectile.grid_position = Vector2.ZERO
	projectile.setup(grid, enemy, 7.0, 100.0 / config.CELL_SIZE)
	projectile._physics_process(0.01)
	_expect(is_equal_approx(enemy.health, 13.0), "projectile applies damage on logical arrival")

	var moving_enemy = enemy_script.new()
	moving_enemy.setup(grid, 2, 0.0, 20.0)
	moving_enemy.grid_position = Vector2(2.0, 0.0)
	var moving_projectile = projectile_script.new()
	moving_projectile.grid_position = Vector2.ZERO
	moving_projectile.setup(grid, moving_enemy, 7.0, 1.0)
	moving_projectile._physics_process(0.25)
	_expect(moving_projectile.grid_position.is_equal_approx(Vector2(0.25, 0.0)), "projectile advances through logical distance")
	_expect(moving_projectile.position.is_equal_approx(grid.grid_to_screen(moving_projectile.grid_position)), "projectile presentation follows projected logical position")
	projectile.free()
	moving_projectile.free()
	moving_enemy.free()
	enemy.free()
	grid.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
