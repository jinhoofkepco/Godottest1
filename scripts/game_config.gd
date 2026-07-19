class_name GameConfig
extends RefCounted

const VIEW_SIZE := Vector2i(540, 960)
const GRID_COLUMNS := 9
const GRID_ROWS := 14
const CELL_SIZE := 54.0
const GRID_ORIGIN := Vector2(27, 108)
const ISO_TILE_WIDTH := 64.0
const ISO_TILE_HEIGHT := 32.0
const WORLD_FRAME_MARGIN := 14.0
const WORLD_FRAME_TOP := 112.0
const WORLD_FRAME_BOTTOM := 24.0
const CORE_ANCHOR_GAP := 28.0
const ENEMY_ZONE_ROWS := 3
const ALLY_BUILD_START_ROW := 5
const CORE_ROW := 13

const START_GOLD := 150
const TOWER_COST := 50
const KILL_REWARD := 10
const WAVE_REWARD := 25
const CORE_MAX_HP := 20
const TOTAL_WAVES := 5

const TOWER_RANGE := 132.0
const TOWER_FIRE_INTERVAL := 0.62
const TOWER_DAMAGE := 18.0
const PROJECTILE_SPEED := 440.0
const ENEMY_CORE_Y := 890.0
const SPAWN_INTERVAL := 0.58

const COLOR_BACKGROUND := Color("101521")
const COLOR_PANEL := Color("171e2d")
const COLOR_GRID_LINE := Color("263044")
const COLOR_ALLY := Color("315f4b")
const COLOR_ALLY_DARK := Color("24483d")
const COLOR_ENEMY := Color("65417d")
const COLOR_ENEMY_DARK := Color("422b56")
const COLOR_NEUTRAL := Color("202a3a")
const COLOR_TEAL := Color("31d6c8")
const COLOR_ORANGE := Color("ff9e4a")
const COLOR_TEXT := Color("edf7f4")


static func wave_enemy_count(wave: int) -> int:
	return 6 + (clampi(wave, 1, TOTAL_WAVES) - 1) * 2


static func wave_enemy_speed(wave: int) -> float:
	return 46.0 + float(clampi(wave, 1, TOTAL_WAVES) - 1) * 6.0


static func wave_enemy_health(wave: int) -> float:
	return 28.0 + float(clampi(wave, 1, TOTAL_WAVES) - 1) * 9.0
