class_name AgentBattleLab
extends Node2D

const MODE_BASELINE := 0
const MODE_AGENT := 1
const TEST_SEED := 230723
const ARENA_SIZE := Vector2i(28, 36)
const CELL_SIZE := 14.0
const MAP_ORIGIN := Vector2(74.0, 158.0)
const MAP_RECT := Rect2(MAP_ORIGIN, Vector2(ARENA_SIZE) * CELL_SIZE)
const MAX_HP := 80.0
const ATTACK_PULSE_SECONDS := 0.14

const BLUE := Color("#43a9ff")
const BLUE_DARK := Color("#164c78")
const RED := Color("#ff5e70")
const RED_DARK := Color("#70283a")
const INK := Color("#07101c")
const PANEL := Color("#111d2c")
const GRID := Color(0.19, 0.31, 0.40, 0.34)
const WALL := Color("#26384b")
const WALL_TOP := Color("#52677c")
const TEXT := Color("#d9ebf6")
const MUTED := Color("#7590a4")

const ACTION_NAMES := [
	"ADVANCE",
	"ENGAGE",
	"FILL GAP",
	"FLANK L",
	"FLANK R",
	"YIELD",
	"HOLD",
	"RETREAT",
]
const ACTION_COLORS := [
	Color("#34d4f3"),
	Color("#ff9a3d"),
	Color("#91e84a"),
	Color("#a979ff"),
	Color("#ff68d4"),
	Color("#f5d451"),
	Color("#e7f0f5"),
	Color("#ff3d55"),
]

@onready var _simulation: Node = $AgentBattleSimulation
@onready var _metrics_label: Label = $Interface/Header/Metrics
@onready var _mode_label: Label = $Interface/Header/Mode
@onready var _result_label: Label = $Interface/Result
@onready var _agent_button: Button = $Interface/Controls/Buttons/Agent
@onready var _baseline_button: Button = $Interface/Controls/Buttons/Baseline
@onready var _pause_button: Button = $Interface/Controls/Buttons/Pause
@onready var _speed_button: Button = $Interface/Controls/Buttons/Speed

var _mode := MODE_AGENT
var _paused := false
var _speed := 1.0
var _snapshot: Dictionary = {}
var _metrics: Dictionary = {}


func _ready() -> void:
	_agent_button.pressed.connect(set_mode.bind(MODE_AGENT))
	_baseline_button.pressed.connect(set_mode.bind(MODE_BASELINE))
	_pause_button.pressed.connect(_toggle_pause)
	_speed_button.pressed.connect(_toggle_speed)
	$Interface/Controls/Buttons/Reset.pressed.connect(reset_lab)
	reset_lab()


func _process(delta: float) -> void:
	if not _paused and String(_snapshot.get("result", "")).is_empty():
		_simulation.call("Step", delta * _speed)
	sync_view()


func set_mode(value: int) -> void:
	_mode = clampi(value, MODE_BASELINE, MODE_AGENT)
	reset_lab()


func reset_lab() -> void:
	_paused = false
	_simulation.call("ResetExperiment", _mode, TEST_SEED)
	sync_view()
	_update_controls()


func get_metrics_text() -> String:
	if _metrics.is_empty():
		return "WAITING FOR SIMULATION"
	var action_counts := PackedInt32Array(_metrics.get("action_counts", PackedInt32Array()))
	var engaged := _action_count(action_counts, 1) + _action_count(action_counts, 2)
	return (
		"BLUE %02d   RED %02d   ENGAGED %02d\n"
		+ "ATTACKED %02d   RELIEF %02d   ACTIVE %3d%%\n"
		+ "IDLE %5.1fs   MAX STUCK %4.1fs   TICK %.3fms"
	) % [
		int(_metrics.get("blue_count", 0)),
		int(_metrics.get("red_count", 0)),
		engaged,
		int(_metrics.get("units_ever_attacked", 0)),
		int(_metrics.get("frontline_replacements", 0)),
		roundi(float(_metrics.get("active_participation_ratio", 0.0)) * 100.0),
		float(_metrics.get("idle_agent_seconds", 0.0)),
		float(_metrics.get("maximum_stuck_seconds", 0.0)),
		float(_metrics.get("average_tick_ms", 0.0)),
	]


func sync_view() -> void:
	_snapshot = _simulation.call("GetSnapshot")
	_metrics = _simulation.call("GetMetrics")
	if is_instance_valid(_metrics_label):
		_metrics_label.text = get_metrics_text()
		_mode_label.text = (
			"INDIVIDUAL AGENT AI" if _mode == MODE_AGENT
			else "BASELINE / FORWARD ONLY"
		)
		var elapsed := float(_snapshot.get("time", 0.0))
		_mode_label.text += "   %05.1fs / 120s" % elapsed
		var result := String(_snapshot.get("result", ""))
		_result_label.visible = not result.is_empty()
		_result_label.text = result if not result.is_empty() else ""
	queue_redraw()


func _toggle_pause() -> void:
	_paused = not _paused
	_update_controls()


func _toggle_speed() -> void:
	_speed = 2.0 if is_equal_approx(_speed, 1.0) else 1.0
	_update_controls()


func _update_controls() -> void:
	if not is_instance_valid(_agent_button):
		return
	_agent_button.disabled = _mode == MODE_AGENT
	_baseline_button.disabled = _mode == MODE_BASELINE
	_pause_button.text = "RESUME" if _paused else "PAUSE"
	_speed_button.text = "2X" if is_equal_approx(_speed, 2.0) else "1X"


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(540.0, 960.0)), INK)
	_draw_arena()
	if not _snapshot.is_empty():
		_draw_attack_pulses()
		_draw_units()
	_draw_legend()


func _draw_arena() -> void:
	draw_rect(MAP_RECT.grow(5.0), Color("#0b1725"), true)
	draw_rect(MAP_RECT, Color("#102536"), true)
	draw_rect(Rect2(MAP_ORIGIN, Vector2(MAP_RECT.size.x, MAP_RECT.size.y * 0.5)), Color(0.32, 0.10, 0.14, 0.16), true)
	draw_rect(Rect2(MAP_ORIGIN + Vector2(0.0, MAP_RECT.size.y * 0.5), Vector2(MAP_RECT.size.x, MAP_RECT.size.y * 0.5)), Color(0.06, 0.28, 0.44, 0.18), true)
	for x in ARENA_SIZE.x + 1:
		var px := MAP_ORIGIN.x + float(x) * CELL_SIZE
		draw_line(Vector2(px, MAP_RECT.position.y), Vector2(px, MAP_RECT.end.y), GRID, 1.0)
	for y in ARENA_SIZE.y + 1:
		var py := MAP_ORIGIN.y + float(y) * CELL_SIZE
		draw_line(Vector2(MAP_RECT.position.x, py), Vector2(MAP_RECT.end.x, py), GRID, 1.0)
	var middle_y := _world_to_screen(Vector2(0.0, 18.0)).y
	draw_line(
		Vector2(MAP_RECT.position.x, middle_y),
		Vector2(MAP_RECT.end.x, middle_y),
		Color(0.42, 0.90, 0.91, 0.45),
		1.5
	)

	var blocked := PackedInt32Array(_snapshot.get("blocked_cells", PackedInt32Array()))
	for cell in blocked:
		var cell_x := cell % ARENA_SIZE.x
		var cell_y := cell / ARENA_SIZE.x
		var rect := Rect2(
			MAP_ORIGIN + Vector2(float(cell_x), float(cell_y)) * CELL_SIZE + Vector2(1.0, 1.0),
			Vector2(CELL_SIZE - 2.0, CELL_SIZE - 2.0)
		)
		draw_rect(rect, WALL, true)
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), WALL_TOP, 2.0)

	var gate_center := _world_to_screen(Vector2(14.0, 18.0))
	draw_line(
		gate_center + Vector2(-14.0, -16.0),
		gate_center + Vector2(-14.0, 16.0),
		Color("#7f94a8"),
		2.0
	)
	draw_line(
		gate_center + Vector2(14.0, -16.0),
		gate_center + Vector2(14.0, 16.0),
		Color("#7f94a8"),
		2.0
	)


func _draw_attack_pulses() -> void:
	var positions := PackedVector2Array(_snapshot.get("positions", PackedVector2Array()))
	var hp := PackedFloat32Array(_snapshot.get("hp", PackedFloat32Array()))
	var targets := PackedInt32Array(_snapshot.get("targets", PackedInt32Array()))
	var pulses := PackedFloat32Array(_snapshot.get("attack_pulses", PackedFloat32Array()))
	var teams := PackedInt32Array(_snapshot.get("teams", PackedInt32Array()))
	if pulses.size() != positions.size() or targets.size() != positions.size():
		return
	for index in positions.size():
		if hp[index] <= 0.0 or pulses[index] <= 0.0:
			continue
		var target := targets[index]
		if target < 0 or target >= positions.size() or hp[target] <= 0.0:
			continue
		var strength := clampf(pulses[index] / ATTACK_PULSE_SECONDS, 0.0, 1.0)
		var from := _world_to_screen(positions[index])
		var to := _world_to_screen(positions[target])
		var color := BLUE if teams[index] == 0 else RED
		color.a = 0.22 + strength * 0.58
		draw_line(from, to, color, 1.0 + strength * 2.2, true)
		draw_arc(to, 4.0 + (1.0 - strength) * 7.0, 0.0, TAU, 18, color, 1.5, true)


func _draw_units() -> void:
	var positions := PackedVector2Array(_snapshot.get("positions", PackedVector2Array()))
	var velocities := PackedVector2Array(_snapshot.get("velocities", PackedVector2Array()))
	var teams := PackedInt32Array(_snapshot.get("teams", PackedInt32Array()))
	var hp := PackedFloat32Array(_snapshot.get("hp", PackedFloat32Array()))
	var actions := PackedInt32Array(_snapshot.get("actions", PackedInt32Array()))
	if positions.size() != teams.size() or positions.size() != hp.size():
		return
	for index in positions.size():
		if hp[index] <= 0.0:
			continue
		var center := _world_to_screen(positions[index])
		var direction := velocities[index].normalized() if velocities[index].length_squared() > 0.01 else Vector2(0.0, -1.0 if teams[index] == 0 else 1.0)
		var action := clampi(actions[index], 0, ACTION_COLORS.size() - 1)
		_draw_unit(center, direction, teams[index], hp[index], ACTION_COLORS[action])


func _draw_unit(center: Vector2, direction: Vector2, team: int, health: float, action_color: Color) -> void:
	var angle := Vector2.UP.angle_to(direction)
	var shield_local := PackedVector2Array([
		Vector2(0.0, -7.5),
		Vector2(5.7, -3.5),
		Vector2(5.0, 4.0),
		Vector2(0.0, 8.0),
		Vector2(-5.0, 4.0),
		Vector2(-5.7, -3.5),
	])
	var shield := PackedVector2Array()
	for point in shield_local:
		shield.append(center + point.rotated(angle))
	var team_color := BLUE if team == 0 else RED
	var edge_color := BLUE_DARK if team == 0 else RED_DARK
	draw_circle(center + Vector2(1.3, 2.2), 6.3, Color(0.0, 0.0, 0.0, 0.32))
	draw_arc(center, 9.0, 0.0, TAU, 18, Color(action_color, 0.92), 2.2, true)
	draw_colored_polygon(shield, edge_color)
	var inset := PackedVector2Array()
	for point in shield_local:
		inset.append(center + (point * 0.72).rotated(angle))
	draw_colored_polygon(inset, team_color)
	draw_line(center, center + direction * 11.0, Color(0.94, 0.98, 1.0, 0.92), 1.4, true)
	if health < MAX_HP:
		var width := 14.0
		var bar := Rect2(center + Vector2(-width * 0.5, -13.0), Vector2(width, 2.0))
		draw_rect(bar, Color(0.03, 0.04, 0.06, 0.85), true)
		draw_rect(Rect2(bar.position, Vector2(width * health / MAX_HP, 2.0)), team_color, true)


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(32.0, 704.0), "ACTION STATE // RIM COLOR", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)
	for index in ACTION_NAMES.size():
		var column := index % 4
		var row := index / 4
		var origin := Vector2(43.0 + float(column) * 125.0, 730.0 + float(row) * 32.0)
		draw_arc(origin, 7.0, 0.0, TAU, 16, ACTION_COLORS[index], 2.0, true)
		draw_string(font, origin + Vector2(13.0, 5.0), ACTION_NAMES[index], HORIZONTAL_ALIGNMENT_LEFT, 94.0, 12, TEXT)
	draw_string(
		font,
		Vector2(32.0, 800.0),
		"RIM = CHOSEN ACTION   /   WHITE NOSE = FORWARD   /   FLASH = REAL HIT",
		HORIZONTAL_ALIGNMENT_LEFT,
		476.0,
		11,
		MUTED
	)


func _world_to_screen(world_position: Vector2) -> Vector2:
	return MAP_ORIGIN + world_position * CELL_SIZE


func _action_count(values: PackedInt32Array, index: int) -> int:
	return values[index] if index >= 0 and index < values.size() else 0
