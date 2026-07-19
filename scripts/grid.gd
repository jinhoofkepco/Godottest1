class_name GridBoard
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var simulation


func _ready() -> void:
	queue_redraw()


func set_simulation(value) -> void:
	simulation = value
	queue_redraw()


func can_build(cell: Vector2i, team: int = 2) -> bool:
	if not _cell_is_valid(cell) or simulation == null:
		return false
	var cell_blocked: bool = simulation.is_blocked(cell)
	if cell_blocked:
		return false
	var current_ownership: PackedByteArray = simulation.get_ownership()
	return _can_build_with_ownership(cell, team, current_ownership, cell_blocked)


func _can_build_with_ownership(cell: Vector2i, team: int, current_ownership: PackedByteArray, cell_blocked: bool) -> bool:
	if not _cell_is_valid(cell) or simulation == null or cell_blocked:
		return false
	if current_ownership[cell.y * GameConfig.GRID_COLUMNS + cell.x] != team:
		return false
	for building in simulation.buildings:
		if not bool(building.destroyed) and Vector2i(building.cell) == cell:
			return false
	return true


func occupy(cell: Vector2i) -> void:
	# Kept as a no-op compatibility hook; occupancy now belongs to the simulation.
	queue_redraw()


func grid_to_screen(grid_position: Vector2) -> Vector2:
	return Vector2(
		(grid_position.x - grid_position.y) * GameConfig.ISO_TILE_WIDTH * 0.5,
		(grid_position.x + grid_position.y) * GameConfig.ISO_TILE_HEIGHT * 0.5
	)


func screen_to_grid(screen_position: Vector2) -> Vector2:
	return Vector2(
		screen_position.x / GameConfig.ISO_TILE_WIDTH + screen_position.y / GameConfig.ISO_TILE_HEIGHT,
		screen_position.y / GameConfig.ISO_TILE_HEIGHT - screen_position.x / GameConfig.ISO_TILE_WIDTH
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return grid_to_screen(Vector2(cell) + Vector2(0.5, 0.5))


func world_to_cell(world_position: Vector2) -> Vector2i:
	var grid_position := screen_to_grid(world_position)
	return Vector2i(floori(grid_position.x), floori(grid_position.y))


func get_board_bounds() -> Rect2:
	var corners: Array[Vector2] = [
		grid_to_screen(Vector2.ZERO),
		grid_to_screen(Vector2(GameConfig.GRID_COLUMNS, 0)),
		grid_to_screen(Vector2(0, GameConfig.GRID_ROWS)),
		grid_to_screen(Vector2(GameConfig.GRID_COLUMNS, GameConfig.GRID_ROWS)),
	]
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum = Vector2(minf(minimum.x, corner.x), minf(minimum.y, corner.y))
		maximum = Vector2(maxf(maximum.x, corner.x), maxf(maximum.y, corner.y))
	return Rect2(minimum, maximum - minimum)


func get_core_anchor() -> Vector2:
	var bounds := get_board_bounds()
	return Vector2(bounds.get_center().x, bounds.end.y + GameConfig.CORE_ANCHOR_GAP)


func _draw() -> void:
	var current_ownership := PackedByteArray()
	if simulation != null:
		current_ownership = simulation.get_ownership()
	for depth in GameConfig.GRID_COLUMNS + GameConfig.GRID_ROWS - 1:
		var first_row := maxi(0, depth - GameConfig.GRID_COLUMNS + 1)
		var last_row := mini(GameConfig.GRID_ROWS - 1, depth)
		for row in range(first_row, last_row + 1):
			var column := depth - row
			var cell := Vector2i(column, row)
			var color := _cell_color(cell, current_ownership)
			var cell_blocked: bool = simulation != null and simulation.is_blocked(cell)
			var diamond := PackedVector2Array([
				grid_to_screen(Vector2(column, row)),
				grid_to_screen(Vector2(column + 1, row)),
				grid_to_screen(Vector2(column + 1, row + 1)),
				grid_to_screen(Vector2(column, row + 1)),
			])
			draw_colored_polygon(diamond, color)
			diamond.append(diamond[0])
			draw_polyline(diamond, GameConfig.COLOR_GRID_LINE, 1.4, true)
			if cell_blocked:
				_draw_blocker(diamond)
			if _can_build_with_ownership(cell, 2, current_ownership, cell_blocked):
				draw_circle(cell_to_world(cell), 1.8, Color(GameConfig.COLOR_TEAL, 0.38))


func _draw_blocker(base_diamond: PackedVector2Array) -> void:
	var top := base_diamond.slice(0, 4)
	for index in top.size():
		top[index] += Vector2(0.0, -6.0)
	var lower_side := PackedVector2Array([base_diamond[1], base_diamond[2], top[2], top[1]])
	var left_side := PackedVector2Array([base_diamond[2], base_diamond[3], top[3], top[2]])
	draw_colored_polygon(lower_side, GameConfig.COLOR_OBSTACLE_SIDE)
	draw_colored_polygon(left_side, GameConfig.COLOR_NEUTRAL)
	draw_colored_polygon(top, GameConfig.COLOR_OBSTACLE)
	top.append(top[0])
	draw_polyline(top, GameConfig.COLOR_OBSTACLE_EDGE, 1.6, true)


func _cell_color(cell: Vector2i, current_ownership: PackedByteArray) -> Color:
	var owner := 1 if cell.y < GameConfig.GRID_ROWS / 2 else 2
	if not current_ownership.is_empty():
		owner = current_ownership[cell.y * GameConfig.GRID_COLUMNS + cell.x]
	var alternate := (cell.x + cell.y) % 2 == 0
	if owner == 2:
		return GameConfig.COLOR_ALLY if alternate else GameConfig.COLOR_ALLY_DARK
	return GameConfig.COLOR_ENEMY if alternate else GameConfig.COLOR_ENEMY_DARK


func _cell_is_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GameConfig.GRID_COLUMNS and cell.y >= 0 and cell.y < GameConfig.GRID_ROWS
