extends SceneTree

const GameConfig = preload("res://scripts/game_config.gd")
const METADATA_PATH := "res://assets/units/infantry_atlas.json"
const TEAM_PATHS := [
	"res://assets/units/infantry_blue.png",
	"res://assets/units/infantry_red.png",
]


func _initialize() -> void:
	var metadata_file := FileAccess.open(METADATA_PATH, FileAccess.READ)
	if metadata_file == null:
		_fail("metadata is missing")
		return
	var metadata = JSON.parse_string(metadata_file.get_as_text())
	if not metadata is Dictionary:
		_fail("metadata is not a JSON object")
		return
	if int(metadata.get("directions", 0)) != GameConfig.INFANTRY_ATLAS_DIRECTIONS or int(metadata.get("frames_per_direction", 0)) != GameConfig.INFANTRY_FRAMES_PER_DIRECTION:
		_fail("metadata does not describe 8 directions x 16 frames")
		return
	var state_counts: Dictionary = metadata.get("state_counts", {})
	var state_offsets: Dictionary = metadata.get("state_offsets", {})
	if int(state_counts.get("idle", 0)) != 2 or int(state_counts.get("walk", 0)) != 6 or int(state_counts.get("attack", 0)) != 4 or int(state_counts.get("death", 0)) != 4:
		_fail("animation frame counts do not match the runtime contract")
		return
	if int(state_offsets.get("idle", -1)) != 0 or int(state_offsets.get("walk", -1)) != 2 or int(state_offsets.get("attack", -1)) != 8 or int(state_offsets.get("death", -1)) != 12:
		_fail("animation offsets do not match the runtime contract")
		return
	if metadata.get("models", []).size() != 2 or metadata.get("teams", []).size() != 2 or metadata.get("direction_degrees", []).size() != 8:
		_fail("metadata must describe two classes, two teams, and eight headings")
		return
	var cell_size := Vector2i(int(metadata.cell_size[0]), int(metadata.cell_size[1]))
	var atlas_size := Vector2i(int(metadata.atlas_size[0]), int(metadata.atlas_size[1]))
	if int(metadata.get("columns", 0)) != GameConfig.INFANTRY_ATLAS_COLUMNS or int(metadata.get("rows", 0)) != GameConfig.INFANTRY_ATLAS_ROWS:
		_fail("atlas grid dimensions do not match the runtime contract")
		return
	if cell_size != Vector2i.ONE * GameConfig.INFANTRY_ATLAS_CELL_SIZE or atlas_size != Vector2i(GameConfig.INFANTRY_ATLAS_COLUMNS, GameConfig.INFANTRY_ATLAS_ROWS) * GameConfig.INFANTRY_ATLAS_CELL_SIZE:
		_fail("atlas dimensions are not 96px cells in a 1536px sheet")
		return
	for path in TEAM_PATHS:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty() or image.get_size() != atlas_size:
			_fail("invalid atlas image: %s" % path)
			return
		for corner in [Vector2i(0, 0), Vector2i(atlas_size.x - 1, 0), Vector2i(0, atlas_size.y - 1), atlas_size - Vector2i.ONE]:
			if image.get_pixelv(corner).a > 0.01:
				_fail("atlas corner is not transparent: %s at %s" % [path, corner])
				return
		for linear_index in GameConfig.INFANTRY_ATLAS_COLUMNS * GameConfig.INFANTRY_ATLAS_ROWS:
			var origin := Vector2i((linear_index % GameConfig.INFANTRY_ATLAS_COLUMNS) * cell_size.x, (linear_index / GameConfig.INFANTRY_ATLAS_COLUMNS) * cell_size.y)
			var frame := image.get_region(Rect2i(origin, cell_size))
			var alpha_pixels := 0
			for y in range(0, cell_size.y, 4):
				for x in range(0, cell_size.x, 4):
					if frame.get_pixel(x, y).a > 0.05:
						alpha_pixels += 1
			if alpha_pixels < 12:
				_fail("empty atlas cell in %s at linear index %d" % [path, linear_index])
				return
		for model_index in 2:
			var direction_hashes: Dictionary = {}
			for direction_index in GameConfig.INFANTRY_ATLAS_DIRECTIONS:
				var linear_index := model_index * GameConfig.INFANTRY_CLASS_FRAME_COUNT + direction_index * GameConfig.INFANTRY_FRAMES_PER_DIRECTION + 2
				var origin := Vector2i((linear_index % GameConfig.INFANTRY_ATLAS_COLUMNS) * cell_size.x, (linear_index / GameConfig.INFANTRY_ATLAS_COLUMNS) * cell_size.y)
				var frame := image.get_region(Rect2i(origin, cell_size))
				direction_hashes[hash(frame.get_data())] = true
			if direction_hashes.size() < 7:
				_fail("directions are not visually distinct in %s model=%d" % [path, model_index])
				return
	print("ATLAS VALIDATION PASS: all 512 cells, 2 teams x 2 classes x 8 distinct directions, transparent 1536x1536 RGBA")
	quit(0)


func _fail(message: String) -> void:
	push_error("ATLAS VALIDATION FAILED: %s" % message)
	quit(1)
