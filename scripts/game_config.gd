class_name GameConfig
extends RefCounted

const VIEW_SIZE := Vector2i(540, 960)
const GRID_COLUMNS := 11
const GRID_ROWS := 22
const ISO_TILE_WIDTH := 64.0
const ISO_TILE_HEIGHT := 32.0
const WORLD_FRAME_MARGIN := 14.0
const WORLD_FRAME_TOP := 112.0
const WORLD_FRAME_BOTTOM := 24.0
const CORE_ANCHOR_GAP := 28.0
const SIM_TICK_RATE := 30
const MAX_CATCH_UP_TICKS := 8
const MATCH_DURATION := 180.0
const OCCUPANCY_WIN_RATIO := 0.9

const START_GOLD := 180
const ENEMY_START_GOLD := 120
const SPAWNER_COST := 60
const PASSIVE_INCOME_PER_SECOND := 3.0
const KILL_REWARD := 6
const ENEMY_BUILD_INTERVAL := 14.0
const ENEMY_MAX_SPAWNERS := 4

const UNIT_MAX_HP := 48.0
const UNIT_SPEED := 1.45
const UNIT_ATTACK_RANGE := 0.72
const UNIT_ATTACK_DAMAGE := 10.0
const UNIT_ATTACK_INTERVAL := 0.65
const SPAWNER_MAX_HP := 240.0
const SPAWNER_PRODUCTION_INTERVAL := 2.6
const HQ_MAX_HP := 1200.0

const COLOR_BACKGROUND := Color("101521")
const COLOR_PANEL := Color("171e2d")
const COLOR_GRID_LINE := Color("263044")
const COLOR_ALLY := Color("287eea")
const COLOR_ALLY_DARK := Color("174982")
const COLOR_ENEMY := Color("e24a57")
const COLOR_ENEMY_DARK := Color("7c2935")
const COLOR_NEUTRAL := Color("202a3a")
const COLOR_TEAL := Color("31d6c8")
const COLOR_ORANGE := Color("ff9e4a")
const COLOR_TEXT := Color("edf7f4")
