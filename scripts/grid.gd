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


func cell_to_world(cell: Vector2i) -> Vector2:
	return GameConfig.GRID_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * GameConfig.CELL_SIZE


func world_to_cell(world_position: Vector2) -> Vector2i:
	var local := (world_position - GameConfig.GRID_ORIGIN) / GameConfig.CELL_SIZE
	return Vector2i(floori(local.x), floori(local.y))


func _draw() -> void:
	var board_size := Vector2(GameConfig.GRID_COLUMNS, GameConfig.GRID_ROWS) * GameConfig.CELL_SIZE
	draw_rect(Rect2(GameConfig.GRID_ORIGIN, board_size), GameConfig.COLOR_GRID_LINE)
	for row in GameConfig.GRID_ROWS:
		for column in GameConfig.GRID_COLUMNS:
			var cell := Vector2i(column, row)
			var top_left := GameConfig.GRID_ORIGIN + Vector2(cell) * GameConfig.CELL_SIZE + Vector2(2, 2)
			var rect := Rect2(top_left, Vector2.ONE * (GameConfig.CELL_SIZE - 4.0))
			var color := _cell_color(row)
			if occupied.has(cell):
				color = color.darkened(0.22)
			draw_rect(rect, color)
			if can_build(cell):
				draw_circle(rect.get_center(), 2.2, Color(GameConfig.COLOR_TEAL, 0.32))


func _cell_color(row: int) -> Color:
	if row < GameConfig.ENEMY_ZONE_ROWS:
		return GameConfig.COLOR_ENEMY if row % 2 == 0 else GameConfig.COLOR_ENEMY_DARK
	if row >= GameConfig.ALLY_BUILD_START_ROW:
		return GameConfig.COLOR_ALLY if row % 2 == 0 else GameConfig.COLOR_ALLY_DARK
	return GameConfig.COLOR_NEUTRAL
