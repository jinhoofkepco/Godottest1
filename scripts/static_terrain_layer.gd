class_name StaticTerrainLayer
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var build_count := 0
var redraw_count := 0
var _grid: GridBoard


func setup(board: GridBoard) -> void:
	_grid = board
	build_count += 1
	queue_redraw()


func _draw() -> void:
	redraw_count += 1
	if not is_instance_valid(_grid):
		return
	for depth in GameConfig.GRID_COLUMNS + GameConfig.GRID_ROWS - 1:
		var first_row := maxi(0, depth - GameConfig.GRID_COLUMNS + 1)
		var last_row := mini(GameConfig.GRID_ROWS - 1, depth)
		for row in range(first_row, last_row + 1):
			var cell := Vector2i(depth - row, row)
			if _grid.is_water(cell):
				_draw_shore(cell, _grid.get_cell_diamond(cell))
				continue
			_draw_cliff_sides(cell, _grid.get_cell_diamond(cell), _grid.get_elevation_at(cell))


func _draw_shore(cell: Vector2i, diamond: PackedVector2Array) -> void:
	var shore := Color(GameConfig.COLOR_SHORE, 0.72)
	if not _grid.is_water(cell + Vector2i.UP): draw_line(diamond[0], diamond[1], shore, 1.4, true)
	if not _grid.is_water(cell + Vector2i.RIGHT): draw_line(diamond[1], diamond[2], shore, 1.4, true)
	if not _grid.is_water(cell + Vector2i.DOWN): draw_line(diamond[2], diamond[3], shore, 1.4, true)
	if not _grid.is_water(cell + Vector2i.LEFT): draw_line(diamond[3], diamond[0], shore, 1.4, true)


func _draw_cliff_sides(cell: Vector2i, diamond: PackedVector2Array, elevation_level: int) -> void:
	if elevation_level <= 0:
		return
	var right_difference := elevation_level - _grid.get_elevation_at(Vector2i(cell.x + 1, cell.y))
	if right_difference > 0:
		var drop := Vector2(0.0, float(right_difference) * GameConfig.ELEVATION_PIXEL_STEP)
		var wall := PackedVector2Array([diamond[1], diamond[2], diamond[2] + drop, diamond[1] + drop])
		draw_colored_polygon(wall, GameConfig.COLOR_CLIFF_SIDE.lightened(0.05))
		draw_line(diamond[1], diamond[2], Color(GameConfig.COLOR_CLIFF_EDGE, 0.58), 0.8, true)
	var front_difference := elevation_level - _grid.get_elevation_at(Vector2i(cell.x, cell.y + 1))
	if front_difference > 0:
		var drop := Vector2(0.0, float(front_difference) * GameConfig.ELEVATION_PIXEL_STEP)
		var wall := PackedVector2Array([diamond[2], diamond[3], diamond[3] + drop, diamond[2] + drop])
		draw_colored_polygon(wall, GameConfig.COLOR_CLIFF_SIDE.darkened(0.08))
		draw_line(diamond[2], diamond[3], Color(GameConfig.COLOR_CLIFF_EDGE, 0.52), 0.8, true)
