class_name GridBoard
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var occupied: Dictionary = {}


func _ready() -> void:
	queue_redraw()


func can_build(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < GameConfig.GRID_COLUMNS
		and cell.y >= GameConfig.ALLY_BUILD_START_ROW
		and cell.y < GameConfig.CORE_ROW
		and not occupied.has(cell)
	)


func occupy(cell: Vector2i) -> void:
	occupied[cell] = true
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
	return grid_to_screen(Vector2(float(GameConfig.GRID_COLUMNS) * 0.5, GameConfig.GRID_ROWS))


func _draw() -> void:
	for depth in GameConfig.GRID_COLUMNS + GameConfig.GRID_ROWS - 1:
		var first_row := maxi(0, depth - GameConfig.GRID_COLUMNS + 1)
		var last_row := mini(GameConfig.GRID_ROWS - 1, depth)
		for row in range(first_row, last_row + 1):
			var column := depth - row
			var cell := Vector2i(column, row)
			var color := _cell_color(row)
			if occupied.has(cell):
				color = color.darkened(0.22)
			var diamond := PackedVector2Array([
				grid_to_screen(Vector2(column, row)),
				grid_to_screen(Vector2(column + 1, row)),
				grid_to_screen(Vector2(column + 1, row + 1)),
				grid_to_screen(Vector2(column, row + 1)),
			])
			draw_colored_polygon(diamond, color)
			diamond.append(diamond[0])
			draw_polyline(diamond, GameConfig.COLOR_GRID_LINE, 1.4, true)
			if can_build(cell):
				draw_circle(cell_to_world(cell), 2.2, Color(GameConfig.COLOR_TEAL, 0.32))


func _cell_color(row: int) -> Color:
	if row < GameConfig.ENEMY_ZONE_ROWS:
		return GameConfig.COLOR_ENEMY if row % 2 == 0 else GameConfig.COLOR_ENEMY_DARK
	if row >= GameConfig.ALLY_BUILD_START_ROW:
		return GameConfig.COLOR_ALLY if row % 2 == 0 else GameConfig.COLOR_ALLY_DARK
	return GameConfig.COLOR_NEUTRAL
