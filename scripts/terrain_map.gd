class_name TerrainMap
extends RefCounted

const NEIGHBORS := [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

var width := 1
var height := 1
var elevation := PackedByteArray()


func _init(grid_width: int = 1, grid_height: int = 1) -> void:
	width = maxi(1, grid_width)
	height = maxi(1, grid_height)
	elevation.resize(width * height)
	elevation.fill(0)


func generate(
	seed: int,
	hill_pair_count: int,
	summit_pair_count: int,
	cliff_pair_count: int,
	minimum_row: int,
	maximum_row: int,
	deployment_depth: int,
	maximum_attempts: int
) -> PackedByteArray:
	for attempt in maxi(1, maximum_attempts):
		elevation.fill(0)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + attempt * 104729
		_stamp_hill_pairs(rng, hill_pair_count, summit_pair_count, minimum_row, maximum_row)
		_stamp_cliff_pairs(rng, cliff_pair_count, minimum_row, maximum_row)
		_clear_hq_zones()
		if all_required_paths_reachable(deployment_depth):
			return elevation.duplicate()
	elevation.fill(0)
	return elevation.duplicate()


func get_elevation(cell: Vector2i) -> int:
	return int(elevation[_index(cell)]) if _valid(cell) else 0


func can_step(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	return _valid(from_cell) and _valid(to_cell) and absi(get_elevation(from_cell) - get_elevation(to_cell)) <= 1


func all_required_paths_reachable(deployment_depth: int) -> bool:
	var enemy_hq := Vector2i(width / 2, 0)
	var ally_hq := Vector2i(width / 2, height - 1)
	var from_enemy := _reachable_from(enemy_hq)
	var from_ally := _reachable_from(ally_hq)
	var depth := clampi(deployment_depth, 1, maxi(1, height / 2 - 1))
	for row in range(1, depth + 1):
		for column in width:
			if from_ally[_index(Vector2i(column, row))] == 0:
				return false
	for row in range(height - depth - 1, height - 1):
		for column in width:
			if from_enemy[_index(Vector2i(column, row))] == 0:
				return false
	return from_enemy[_index(ally_hq)] != 0 and from_ally[_index(enemy_hq)] != 0


func _stamp_hill_pairs(rng: RandomNumberGenerator, pair_count: int, summit_count: int, minimum_row: int, maximum_row: int) -> void:
	var min_row := clampi(minimum_row, 2, maxi(2, height / 2 - 2))
	var max_row := clampi(maximum_row, min_row, maxi(min_row, height / 2 - 1))
	for pair_index in maxi(0, pair_count):
		var center := Vector2i(rng.randi_range(2, maxi(2, width - 3)), rng.randi_range(min_row, max_row))
		var radius_x := rng.randi_range(2, 4)
		var radius_y := rng.randi_range(2, 4)
		for y_offset in range(-radius_y, radius_y + 1):
			for x_offset in range(-radius_x, radius_x + 1):
				var normalized := pow(float(x_offset) / float(radius_x), 2.0) + pow(float(y_offset) / float(radius_y), 2.0)
				if normalized > 1.0:
					continue
				_set_mirrored(center + Vector2i(x_offset, y_offset), 1)
		if pair_index < summit_count:
			_set_mirrored(center, 2)
			if pair_index % 2 == 0:
				_set_mirrored(center + Vector2i(1 if center.x < width / 2 else -1, 0), 2)


func _stamp_cliff_pairs(rng: RandomNumberGenerator, pair_count: int, minimum_row: int, maximum_row: int) -> void:
	var min_row := clampi(minimum_row, 2, maxi(2, height / 2 - 2))
	var max_row := clampi(maximum_row, min_row, maxi(min_row, height / 2 - 1))
	var added := 0
	for ignored in 128:
		if added >= pair_count:
			break
		var cell := Vector2i(rng.randi_range(1, maxi(1, width - 2)), rng.randi_range(min_row, max_row))
		if get_elevation(cell) != 0 or not _neighbors_are_level(cell, 0):
			continue
		_set_mirrored(cell, 2)
		added += 1


func _neighbors_are_level(cell: Vector2i, level: int) -> bool:
	for offset: Vector2i in NEIGHBORS:
		var neighbor := cell + offset
		if _valid(neighbor) and get_elevation(neighbor) != level:
			return false
	return true


func _set_mirrored(cell: Vector2i, level: int) -> void:
	if not _valid(cell):
		return
	var mirrored := Vector2i(width - 1 - cell.x, height - 1 - cell.y)
	elevation[_index(cell)] = maxi(elevation[_index(cell)], clampi(level, 0, 2))
	elevation[_index(mirrored)] = elevation[_index(cell)]


func _clear_hq_zones() -> void:
	var enemy_hq := Vector2i(width / 2, 0)
	var ally_hq := Vector2i(width / 2, height - 1)
	for hq in [enemy_hq, ally_hq]:
		for row_offset in range(-2, 3):
			for column_offset in range(-2, 3):
				var cell: Vector2i = hq + Vector2i(column_offset, row_offset)
				if _valid(cell):
					elevation[_index(cell)] = 0


func _reachable_from(start: Vector2i) -> PackedByteArray:
	var visited := PackedByteArray()
	visited.resize(width * height)
	if not _valid(start):
		return visited
	var queue: Array[Vector2i] = [start]
	visited[_index(start)] = 1
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset: Vector2i in NEIGHBORS:
			var neighbor := current + offset
			if not _valid(neighbor) or visited[_index(neighbor)] != 0 or not can_step(current, neighbor):
				continue
			visited[_index(neighbor)] = 1
			queue.append(neighbor)
	return visited


func _valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x
