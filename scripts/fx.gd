class_name DefenseFx
extends Node2D

const GameConfig = preload("res://scripts/game_config.gd")

const TEAM_ENEMY := 1
const TEAM_ALLY := 2
const ALLY_BLUE := Color("43a8ff")
const ENEMY_RED := Color("ff4f63")
const HIT_WHITE := Color("fff8db")
const DARK_DEBRIS := Color("182033")

@export var placement_duration := 0.42
@export var hit_duration := 0.18
@export var ranged_shot_duration := 0.12
@export var death_duration := 0.42
@export var production_duration := 0.58
@export var building_hit_duration := 0.28
@export var building_destroy_duration := 0.72
@export var territory_duration := 0.62
@export var hq_hit_duration := 0.48
@export var fragment_count := 7

var placement_feedback_count := 0
var hit_feedback_count := 0
var ranged_shot_feedback_count := 0
var unit_death_feedback_count := 0
var production_feedback_count := 0
var spawner_hit_feedback_count := 0
var spawner_destroyed_feedback_count := 0
var territory_change_feedback_count := 0
var hq_hit_feedback_count := 0
var hq_destroyed_feedback_count := 0
var last_feedback_mode := ""
var last_placement_cell := Vector2i(-1, -1)
var last_placement_valid := false
var last_hit_high_ground := false

var _grid: GridBoard
var _effects: Array[Dictionary] = []
var _fragments: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_as_relative = false
	z_index = 1000
	_rng.seed = 90714


func setup(board: GridBoard) -> void:
	_grid = board
	queue_redraw()


func show_placement(cell: Vector2i, is_valid: bool) -> void:
	last_placement_cell = cell
	last_placement_valid = is_valid
	_add_effect("placement", cell, TEAM_ALLY, placement_duration, {"valid": is_valid})
	placement_feedback_count += 1
	last_feedback_mode = "placement_valid" if is_valid else "placement_invalid"


func show_hit(grid_position: Vector2, high_ground: bool = false) -> void:
	last_hit_high_ground = high_ground
	_add_effect("hit", grid_position, 0, hit_duration, {"high_ground": high_ground})
	hit_feedback_count += 1
	last_feedback_mode = "hit"


func show_ranged_shot(origin: Vector2, grid_position: Vector2, team: int) -> void:
	_add_effect("ranged_shot", grid_position, team, ranged_shot_duration, {"origin": origin})
	ranged_shot_feedback_count += 1
	last_feedback_mode = "ranged_shot"


func show_unit_death(grid_position: Vector2, team: int) -> void:
	_add_effect("unit_death", grid_position, team, death_duration)
	_spawn_fragments(grid_position, team, fragment_count, 70.0, 125.0, 2.0, 4.0)
	unit_death_feedback_count += 1
	last_feedback_mode = "unit_death"


func show_production(cell: Vector2i, team: int) -> void:
	_add_effect("production", cell, team, production_duration)
	production_feedback_count += 1
	last_feedback_mode = "production"


func show_spawner_hit(cell: Vector2i, team: int) -> void:
	_add_effect("spawner_hit", cell, team, building_hit_duration)
	spawner_hit_feedback_count += 1
	last_feedback_mode = "spawner_hit"


func show_spawner_destroyed(cell: Vector2i, team: int) -> void:
	_add_effect("spawner_destroyed", cell, team, building_destroy_duration)
	_spawn_fragments(Vector2(cell) + Vector2(0.5, 0.5), team, fragment_count + 6, 70.0, 155.0, 3.0, 7.0)
	spawner_destroyed_feedback_count += 1
	last_feedback_mode = "spawner_destroyed"


func show_territory_change(cell: Vector2i, team: int) -> void:
	_add_effect("territory_change", cell, team, territory_duration)
	territory_change_feedback_count += 1
	last_feedback_mode = "territory_change"


func show_hq_hit(cell: Vector2i, team: int) -> void:
	_add_effect("hq_hit", cell, team, hq_hit_duration)
	hq_hit_feedback_count += 1
	last_feedback_mode = "hq_hit"


func show_hq_destroyed(cell: Vector2i, team: int) -> void:
	_add_effect("hq_hit", cell, team, hq_hit_duration)
	hq_destroyed_feedback_count += 1
	last_feedback_mode = "hq_destroyed"


func _add_effect(kind: String, grid_position: Variant, team: int, duration: float, extras: Dictionary = {}) -> void:
	var effect := {
		"kind": kind,
		"grid_position": Vector2(grid_position),
		"team": team,
		"life": duration,
		"duration": duration,
	}
	effect.merge(extras, true)
	_effects.append(effect)
	queue_redraw()


func _spawn_fragments(
	grid_position: Vector2,
	team: int,
	count: int,
	min_speed: float,
	max_speed: float,
	min_size: float,
	max_size: float
) -> void:
	var at := _screen_position(grid_position)
	for index in count:
		var angle := TAU * float(index) / float(count) + _rng.randf_range(-0.18, 0.18)
		var speed := _rng.randf_range(min_speed, max_speed)
		_fragments.append({
			"position": at,
			"velocity": Vector2.from_angle(angle) * speed,
			"team": team,
			"life": death_duration,
			"duration": death_duration,
			"size": _rng.randf_range(min_size, max_size),
		})


func _process(delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		effect["life"] = float(effect.life) - delta
		if float(effect.life) <= 0.0:
			_effects.remove_at(index)
		else:
			_effects[index] = effect
	for index in range(_fragments.size() - 1, -1, -1):
		var fragment := _fragments[index]
		fragment["life"] = float(fragment.life) - delta
		if float(fragment.life) <= 0.0:
			_fragments.remove_at(index)
			continue
		fragment["position"] = Vector2(fragment.position) + Vector2(fragment.velocity) * delta
		fragment["velocity"] = Vector2(fragment.velocity) * pow(0.055, delta)
		_fragments[index] = fragment
	queue_redraw()


func _draw() -> void:
	for effect in _effects:
		var kind := String(effect.kind)
		match kind:
			"placement":
				_draw_placement(effect)
			"hit":
				_draw_hit(effect)
			"ranged_shot":
				_draw_ranged_shot(effect)
			"unit_death":
				_draw_unit_death(effect)
			"production":
				_draw_production(effect)
			"spawner_hit":
				_draw_spawner_hit(effect)
			"spawner_destroyed":
				_draw_spawner_destroyed(effect)
			"territory_change":
				_draw_territory_change(effect)
			"hq_hit":
				_draw_hq_hit(effect)
	for fragment in _fragments:
		var ratio := _life_ratio(fragment)
		var size_value := float(fragment.size) * (0.35 + ratio * 0.65)
		var color := Color(_team_color(int(fragment.team)), ratio)
		draw_rect(Rect2(Vector2(fragment.position) - Vector2.ONE * size_value * 0.5, Vector2.ONE * size_value), color)


func _draw_placement(effect: Dictionary) -> void:
	if not is_instance_valid(_grid):
		return
	var cell := Vector2i(effect.grid_position)
	var fade := _life_ratio(effect)
	var valid := bool(effect.valid)
	var color := Color(ALLY_BLUE if valid else ENEMY_RED, fade)
	_draw_cell_outline(cell, color, 4.0)
	if not valid:
		var center := _grid.cell_to_world(cell)
		draw_line(center + Vector2(-14, -8), center + Vector2(14, 8), color, 5.0, true)
		draw_line(center + Vector2(-14, 8), center + Vector2(14, -8), color, 5.0, true)


func _draw_hit(effect: Dictionary) -> void:
	var at := _screen_position(Vector2(effect.grid_position)) + Vector2(0, -17)
	var ratio := _life_ratio(effect)
	var high_ground := bool(effect.get("high_ground", false))
	var scale_multiplier := 1.32 if high_ground else 1.0
	var spark_color := Color.WHITE if high_ground else HIT_WHITE
	for index in 6:
		var direction := Vector2.from_angle(TAU * float(index) / 6.0)
		var inner := at + direction * (4.0 + 6.0 * (1.0 - ratio)) * scale_multiplier
		var outer := at + direction * (10.0 + 13.0 * (1.0 - ratio)) * scale_multiplier
		draw_line(inner, outer, Color(spark_color, ratio), 3.6 if high_ground else 3.0, true)
	draw_circle(at, 5.0 * ratio * scale_multiplier, Color(GameConfig.COLOR_ORANGE.lightened(0.18 if high_ground else 0.0), ratio))


func _draw_ranged_shot(effect: Dictionary) -> void:
	var origin := _screen_position(Vector2(effect.origin)) + Vector2(0, -17)
	var target := _screen_position(Vector2(effect.grid_position)) + Vector2(0, -17)
	var ratio := _life_ratio(effect)
	var color := _team_color(int(effect.team)).lightened(0.45)
	draw_line(origin, target, Color(color, ratio * 0.7), 5.0, true)
	draw_line(origin, target, Color(HIT_WHITE, ratio), 2.0, true)
	draw_circle(target, 2.5, Color(HIT_WHITE, ratio))


func _draw_unit_death(effect: Dictionary) -> void:
	var at := _screen_position(Vector2(effect.grid_position)) + Vector2(0, -13)
	var ratio := _life_ratio(effect)
	var radius := 4.0 + 10.0 * (1.0 - ratio)
	draw_arc(at, radius, 0.0, TAU, 24, Color(_team_color(int(effect.team)), ratio), 3.0, true)
	# The contracting center makes death read as a pop rather than another hit.
	draw_circle(at, 5.0 * ratio, Color(HIT_WHITE, ratio * 0.85))


func _draw_production(effect: Dictionary) -> void:
	var at := _cell_center(Vector2i(effect.grid_position))
	var ratio := _life_ratio(effect)
	var progress := 1.0 - ratio
	var color := _team_color(int(effect.team))
	draw_arc(at, 9.0 + 24.0 * progress, 0.0, TAU, 32, Color(color, ratio), 3.0, true)
	draw_line(at + Vector2(0, 7), at + Vector2(0, -22.0 - 10.0 * progress), Color(color.lightened(0.35), ratio), 4.0, true)


func _draw_spawner_hit(effect: Dictionary) -> void:
	var at := _cell_center(Vector2i(effect.grid_position)) + Vector2(0, -18)
	var ratio := _life_ratio(effect)
	var flash := Color(HIT_WHITE if ratio > 0.55 else ENEMY_RED, ratio)
	draw_rect(Rect2(at - Vector2(19, 19), Vector2(38, 38)), flash, false, 5.0)
	draw_line(at + Vector2(-18, -18), at + Vector2(18, 18), Color(ENEMY_RED, ratio), 4.0, true)


func _draw_spawner_destroyed(effect: Dictionary) -> void:
	var at := _cell_center(Vector2i(effect.grid_position))
	var ratio := _life_ratio(effect)
	var progress := 1.0 - ratio
	var color := _team_color(int(effect.team))
	# Three blocks sink at different rates, producing a readable collapse silhouette.
	for index in 3:
		var width := 31.0 - float(index) * 7.0
		var height := 8.0
		var y := -32.0 + float(index) * 10.0 + progress * (16.0 + float(index) * 7.0)
		draw_rect(Rect2(at + Vector2(-width * 0.5, y), Vector2(width, height)), Color(color.darkened(progress * 0.65), ratio))
	draw_circle(at + Vector2(0, 3), 14.0 + 20.0 * progress, Color(ENEMY_RED, ratio * 0.28))


func _draw_territory_change(effect: Dictionary) -> void:
	if not is_instance_valid(_grid):
		return
	var cell := Vector2i(effect.grid_position)
	var ratio := _life_ratio(effect)
	var progress := 1.0 - ratio
	var color := _team_color(int(effect.team))
	var diamond := _cell_diamond(cell)
	draw_colored_polygon(diamond, Color(color, 0.16 + 0.36 * ratio))
	_draw_cell_outline(cell, Color(color.lightened(0.25), ratio), 2.0 + 3.0 * (1.0 - progress))
	var center := _grid.cell_to_world(cell)
	draw_line(center + Vector2(-18 + 36 * progress, -7), center + Vector2(-18 + 36 * progress, 7), Color(HIT_WHITE, ratio), 3.0, true)


func _draw_hq_hit(effect: Dictionary) -> void:
	var at := _cell_center(Vector2i(effect.grid_position)) + Vector2(0, -24)
	var ratio := _life_ratio(effect)
	var progress := 1.0 - ratio
	var color := _team_color(int(effect.team))
	# The concentric flash is intentionally much larger than unit/building feedback.
	draw_circle(at, 30.0 * ratio, Color(HIT_WHITE, ratio * 0.64))
	draw_arc(at, 32.0 + progress * 38.0, 0.0, TAU, 40, Color(ENEMY_RED, ratio), 7.0, true)
	draw_arc(at, 19.0 + progress * 22.0, 0.0, TAU, 32, Color(color, ratio), 4.0, true)
	for index in 4:
		var direction := Vector2.from_angle(PI * 0.25 + PI * 0.5 * index)
		draw_line(at + direction * 24.0, at + direction * (62.0 + progress * 12.0), Color(HIT_WHITE, ratio), 5.0, true)


func _screen_position(grid_position: Vector2) -> Vector2:
	return _grid.position_to_world(grid_position) if is_instance_valid(_grid) else grid_position


func _cell_center(cell: Vector2i) -> Vector2:
	return _grid.cell_to_world(cell) if is_instance_valid(_grid) else Vector2(cell)


func _cell_diamond(cell: Vector2i) -> PackedVector2Array:
	return _grid.get_cell_diamond(cell)


func _draw_cell_outline(cell: Vector2i, color: Color, width: float) -> void:
	var diamond := _cell_diamond(cell)
	diamond.append(diamond[0])
	draw_polyline(diamond, color, width, true)


func _life_ratio(item: Dictionary) -> float:
	return clampf(float(item.life) / maxf(float(item.duration), 0.001), 0.0, 1.0)


func _team_color(team: int) -> Color:
	return ALLY_BLUE if team == TEAM_ALLY else ENEMY_RED
