class_name GridBoard
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

var simulation
var _board_version := -1
var _ownership := PackedByteArray()
var _blocked := PackedByteArray()
var _elevation := PackedByteArray()
var _buildings: Array = []


func _ready() -> void:
	queue_redraw()


func set_simulation(value) -> void:
	simulation = value
	if simulation != null:
		sync_board(simulation.call("GetBoardSnapshot"))
	queue_redraw()


func sync_board(snapshot: Dictionary) -> void:
	var version := int(snapshot.get("version", -1))
	if version == _board_version:
		return
	_board_version = version
	_ownership = snapshot.get("ownership", PackedByteArray())
	_blocked = snapshot.get("blocked", PackedByteArray())
	_elevation = snapshot.get("elevation", PackedByteArray())
	_buildings = snapshot.get("buildings", [])
	queue_redraw()


func can_build(cell: Vector2i, team: int = 2) -> bool:
	if not _cell_is_valid(cell) or simulation == null:
		return false
	var cell_blocked: bool = not _blocked.is_empty() and _blocked[cell.y * GameConfig.GRID_COLUMNS + cell.x] != 0
	if cell_blocked:
		return false
	return _can_build_with_ownership(cell, team, _ownership, cell_blocked)


func _can_build_with_ownership(cell: Vector2i, team: int, current_ownership: PackedByteArray, cell_blocked: bool) -> bool:
	if not _cell_is_valid(cell) or simulation == null or cell_blocked:
		return false
	if current_ownership[cell.y * GameConfig.GRID_COLUMNS + cell.x] != team:
		return false
	for building in _buildings:
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


func grid_to_screen_elevated(grid_position: Vector2, elevation_level: int) -> Vector2:
	return grid_to_screen(grid_position) - Vector2(0.0, float(elevation_level) * GameConfig.ELEVATION_PIXEL_STEP)


func position_to_world(grid_position: Vector2) -> Vector2:
	var cell := Vector2i(clampi(floori(grid_position.x), 0, GameConfig.GRID_COLUMNS - 1), clampi(floori(grid_position.y), 0, GameConfig.GRID_ROWS - 1))
	return grid_to_screen_elevated(grid_position, _elevation_at(cell))


func screen_to_grid(screen_position: Vector2) -> Vector2:
	return Vector2(
		screen_position.x / GameConfig.ISO_TILE_WIDTH + screen_position.y / GameConfig.ISO_TILE_HEIGHT,
		screen_position.y / GameConfig.ISO_TILE_HEIGHT - screen_position.x / GameConfig.ISO_TILE_WIDTH
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return grid_to_screen_elevated(Vector2(cell) + Vector2(0.5, 0.5), _elevation_at(cell))


func world_to_cell(world_position: Vector2) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_depth := -1
	for depth in GameConfig.GRID_COLUMNS + GameConfig.GRID_ROWS - 1:
		var first_row := maxi(0, depth - GameConfig.GRID_COLUMNS + 1)
		var last_row := mini(GameConfig.GRID_ROWS - 1, depth)
		for row in range(first_row, last_row + 1):
			var cell := Vector2i(depth - row, row)
			if Geometry2D.is_point_in_polygon(world_position, _cell_diamond(cell)) and depth >= best_depth:
				best_cell = cell
				best_depth = depth
	if best_cell.x >= 0:
		return best_cell
	var flat_position := screen_to_grid(world_position)
	return Vector2i(floori(flat_position.x), floori(flat_position.y))


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
	minimum.y -= float(GameConfig.ELEVATION_LEVELS - 1) * GameConfig.ELEVATION_PIXEL_STEP
	return Rect2(minimum, maximum - minimum)


func get_core_anchor() -> Vector2:
	var bounds := get_board_bounds()
	return Vector2(bounds.get_center().x, bounds.end.y + GameConfig.CORE_ANCHOR_GAP)


func _draw() -> void:
	var current_ownership := _ownership
	for depth in GameConfig.GRID_COLUMNS + GameConfig.GRID_ROWS - 1:
		var first_row := maxi(0, depth - GameConfig.GRID_COLUMNS + 1)
		var last_row := mini(GameConfig.GRID_ROWS - 1, depth)
		for row in range(first_row, last_row + 1):
			var column := depth - row
			var cell := Vector2i(column, row)
			var elevation_level := _elevation_at(cell)
			var color := _cell_color(cell, current_ownership).lightened(float(elevation_level) * GameConfig.ELEVATION_BRIGHTNESS_STEP)
			var cell_blocked: bool = not _blocked.is_empty() and _blocked[cell.y * GameConfig.GRID_COLUMNS + cell.x] != 0
			var diamond := _cell_diamond(cell)
			_draw_cliff_sides(cell, diamond, elevation_level)
			draw_colored_polygon(diamond, color)
			diamond.append(diamond[0])
			draw_polyline(diamond, Color(GameConfig.COLOR_GRID_LINE, 0.48), 0.75, true)
			if _can_build_with_ownership(cell, 2, current_ownership, cell_blocked):
				draw_circle(cell_to_world(cell), 1.8, Color(GameConfig.COLOR_TEAL, 0.38))
	for segment in get_frontline_segments(current_ownership):
		draw_line(segment[0], segment[1], Color(GameConfig.COLOR_FRONTLINE, 0.82), 1.35, true)


func _draw_cliff_sides(cell: Vector2i, diamond: PackedVector2Array, elevation_level: int) -> void:
	if elevation_level <= 0:
		return
	var right_neighbor := Vector2i(cell.x + 1, cell.y)
	var front_neighbor := Vector2i(cell.x, cell.y + 1)
	var right_difference := elevation_level - _elevation_at(right_neighbor)
	if right_difference > 0:
		var drop := Vector2(0.0, float(right_difference) * GameConfig.ELEVATION_PIXEL_STEP)
		var wall := PackedVector2Array([diamond[1], diamond[2], diamond[2] + drop, diamond[1] + drop])
		draw_colored_polygon(wall, GameConfig.COLOR_CLIFF_SIDE.lightened(0.05))
		draw_line(diamond[1], diamond[2], Color(GameConfig.COLOR_CLIFF_EDGE, 0.58), 0.8, true)
	var front_difference := elevation_level - _elevation_at(front_neighbor)
	if front_difference > 0:
		var drop := Vector2(0.0, float(front_difference) * GameConfig.ELEVATION_PIXEL_STEP)
		var wall := PackedVector2Array([diamond[2], diamond[3], diamond[3] + drop, diamond[2] + drop])
		draw_colored_polygon(wall, GameConfig.COLOR_CLIFF_SIDE.darkened(0.08))
		draw_line(diamond[2], diamond[3], Color(GameConfig.COLOR_CLIFF_EDGE, 0.52), 0.8, true)


func has_elevation_side_walls() -> bool:
	return true


func get_cell_diamond(cell: Vector2i) -> PackedVector2Array:
	return _cell_diamond(cell)


func get_frontline_segments(current_ownership: PackedByteArray) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	if current_ownership.size() != GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS:
		return segments
	for row in GameConfig.GRID_ROWS:
		for column in GameConfig.GRID_COLUMNS:
			var owner: int = current_ownership[row * GameConfig.GRID_COLUMNS + column]
			if column + 1 < GameConfig.GRID_COLUMNS and current_ownership[row * GameConfig.GRID_COLUMNS + column + 1] != owner:
				var edge_elevation := maxi(_elevation_at(Vector2i(column, row)), _elevation_at(Vector2i(column + 1, row)))
				segments.append(PackedVector2Array([
					grid_to_screen_elevated(Vector2(column + 1, row), edge_elevation),
					grid_to_screen_elevated(Vector2(column + 1, row + 1), edge_elevation),
				]))
			if row + 1 < GameConfig.GRID_ROWS and current_ownership[(row + 1) * GameConfig.GRID_COLUMNS + column] != owner:
				var edge_elevation := maxi(_elevation_at(Vector2i(column, row)), _elevation_at(Vector2i(column, row + 1)))
				segments.append(PackedVector2Array([
					grid_to_screen_elevated(Vector2(column + 1, row + 1), edge_elevation),
					grid_to_screen_elevated(Vector2(column, row + 1), edge_elevation),
				]))
	return segments


func _cell_color(cell: Vector2i, current_ownership: PackedByteArray) -> Color:
	var owner := 1 if cell.y < GameConfig.GRID_ROWS / 2 else 2
	if not current_ownership.is_empty():
		owner = current_ownership[cell.y * GameConfig.GRID_COLUMNS + cell.x]
	var alternate := (cell.x + cell.y) % 2 == 0
	if owner == 2:
		return GameConfig.COLOR_TERRITORY_ALLY if alternate else GameConfig.COLOR_TERRITORY_ALLY_ALT
	return GameConfig.COLOR_TERRITORY_ENEMY if alternate else GameConfig.COLOR_TERRITORY_ENEMY_ALT


func _cell_is_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GameConfig.GRID_COLUMNS and cell.y >= 0 and cell.y < GameConfig.GRID_ROWS


func _elevation_at(cell: Vector2i) -> int:
	if not _cell_is_valid(cell) or _elevation.size() != GameConfig.GRID_COLUMNS * GameConfig.GRID_ROWS:
		return 0
	return int(_elevation[cell.y * GameConfig.GRID_COLUMNS + cell.x])


func _cell_diamond(cell: Vector2i) -> PackedVector2Array:
	var elevation_level := _elevation_at(cell)
	return PackedVector2Array([
		grid_to_screen_elevated(Vector2(cell.x, cell.y), elevation_level),
		grid_to_screen_elevated(Vector2(cell.x + 1, cell.y), elevation_level),
		grid_to_screen_elevated(Vector2(cell.x + 1, cell.y + 1), elevation_level),
		grid_to_screen_elevated(Vector2(cell.x, cell.y + 1), elevation_level),
	])
