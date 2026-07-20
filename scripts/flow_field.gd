class_name FlowField
extends RefCounted

const CARDINAL_COST := 1.0
const DIAGONAL_COST := 1.41421356
const DIRECTIONS := [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

var costs := PackedFloat32Array()
var directions := PackedVector2Array()
var width := 0
var height := 0


func _init(grid_width: int = 1, grid_height: int = 1) -> void:
	width = maxi(1, grid_width)
	height = maxi(1, grid_height)
	costs.resize(width * height)
	directions.resize(width * height)


func rebuild(
	goal: Vector2i,
	blocked: PackedByteArray,
	density: PackedInt32Array,
	congestion_weight: float,
	elevation: PackedByteArray = PackedByteArray(),
	uphill_cost: float = 0.0
) -> void:
	var cell_count := width * height
	costs.resize(cell_count)
	directions.resize(cell_count)
	costs.fill(INF)
	directions.fill(Vector2.ZERO)
	if not _valid(goal):
		return
	var goal_index := _index(goal)
	costs[goal_index] = 0.0
	var heap_indices: Array[int] = [goal_index]
	var heap_costs: Array[float] = [0.0]
	while not heap_indices.is_empty():
		var current_index := heap_indices[0]
		var queued_cost := heap_costs[0]
		_heap_pop(heap_indices, heap_costs)
		if queued_cost > costs[current_index] + 0.0001:
			continue
		var current := Vector2i(current_index % width, current_index / width)
		for offset: Vector2i in DIRECTIONS:
			var neighbor := current + offset
			if not _valid(neighbor):
				continue
			var neighbor_index := _index(neighbor)
			if neighbor_index != goal_index and neighbor_index < blocked.size() and blocked[neighbor_index] != 0:
				continue
			if offset.x != 0 and offset.y != 0 and _diagonal_is_pinched(current, offset, blocked, goal_index):
				continue
			if not _elevation_transition_allowed(neighbor, current, elevation):
				continue
			var step_cost := DIAGONAL_COST if offset.x != 0 and offset.y != 0 else CARDINAL_COST
			step_cost += _uphill_transition_cost(neighbor, current, elevation, uphill_cost)
			if neighbor_index < density.size():
				step_cost += float(density[neighbor_index]) * maxf(0.0, congestion_weight)
			var candidate := queued_cost + step_cost
			if candidate + 0.0001 >= costs[neighbor_index]:
				continue
			costs[neighbor_index] = candidate
			_heap_push(heap_indices, heap_costs, neighbor_index, candidate)
	_build_directions(blocked, goal_index, elevation, uphill_cost)


func cost_at(cell: Vector2i) -> float:
	return costs[_index(cell)] if _valid(cell) else INF


func direction_at(cell: Vector2i) -> Vector2:
	return directions[_index(cell)] if _valid(cell) else Vector2.ZERO


func _build_directions(blocked: PackedByteArray, goal_index: int, elevation: PackedByteArray, uphill_cost: float) -> void:
	for row in height:
		for column in width:
			var cell := Vector2i(column, row)
			var cell_index := _index(cell)
			if cell_index == goal_index:
				continue
			if cell_index != goal_index and cell_index < blocked.size() and blocked[cell_index] != 0:
				continue
			var best_cost := INF
			var best_offset := Vector2i.ZERO
			for offset: Vector2i in DIRECTIONS:
				var neighbor := cell + offset
				if not _valid(neighbor):
					continue
				var neighbor_index := _index(neighbor)
				if neighbor_index != goal_index and neighbor_index < blocked.size() and blocked[neighbor_index] != 0:
					continue
				if offset.x != 0 and offset.y != 0 and _diagonal_is_pinched(cell, offset, blocked, goal_index):
					continue
				if not _elevation_transition_allowed(cell, neighbor, elevation):
					continue
				var transition_cost := DIAGONAL_COST if offset.x != 0 and offset.y != 0 else CARDINAL_COST
				transition_cost += _uphill_transition_cost(cell, neighbor, elevation, uphill_cost)
				var candidate_cost := costs[neighbor_index] + transition_cost
				if candidate_cost + 0.0001 < best_cost:
					best_cost = candidate_cost
					best_offset = offset
			directions[cell_index] = Vector2(best_offset).normalized()


func _elevation_transition_allowed(from_cell: Vector2i, to_cell: Vector2i, elevation: PackedByteArray) -> bool:
	if elevation.size() != width * height:
		return true
	return absi(int(elevation[_index(from_cell)]) - int(elevation[_index(to_cell)])) <= 1


func _uphill_transition_cost(from_cell: Vector2i, to_cell: Vector2i, elevation: PackedByteArray, uphill_cost: float) -> float:
	if elevation.size() != width * height:
		return 0.0
	return maxf(0.0, uphill_cost) if elevation[_index(to_cell)] > elevation[_index(from_cell)] else 0.0


func _diagonal_is_pinched(cell: Vector2i, offset: Vector2i, blocked: PackedByteArray, goal_index: int) -> bool:
	var side_a := Vector2i(cell.x + offset.x, cell.y)
	var side_b := Vector2i(cell.x, cell.y + offset.y)
	return _blocked_at(side_a, blocked, goal_index) and _blocked_at(side_b, blocked, goal_index)


func _blocked_at(cell: Vector2i, blocked: PackedByteArray, goal_index: int) -> bool:
	if not _valid(cell):
		return true
	var cell_index := _index(cell)
	return cell_index != goal_index and cell_index < blocked.size() and blocked[cell_index] != 0


func _heap_push(indices: Array[int], values: Array[float], cell_index: int, value: float) -> void:
	indices.append(cell_index)
	values.append(value)
	var child := indices.size() - 1
	while child > 0:
		var parent := (child - 1) / 2
		if values[parent] <= value:
			break
		indices[child] = indices[parent]
		values[child] = values[parent]
		child = parent
	indices[child] = cell_index
	values[child] = value


func _heap_pop(indices: Array[int], values: Array[float]) -> void:
	var last_index: int = indices.pop_back()
	var last_value: float = values.pop_back()
	if indices.is_empty():
		return
	var parent := 0
	while true:
		var left := parent * 2 + 1
		if left >= indices.size():
			break
		var right := left + 1
		var child := right if right < indices.size() and values[right] < values[left] else left
		if values[child] >= last_value:
			break
		indices[parent] = indices[child]
		values[parent] = values[child]
		parent = child
	indices[parent] = last_index
	values[parent] = last_value


func _valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x
