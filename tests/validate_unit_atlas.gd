extends SceneTree

const GameConfig = preload("res://scripts/game_config.gd")
const METADATA_PATH := "res://assets/units/infantry_atlas.json"
const TEAM_PATHS := [
	"res://assets/units/infantry_blue.png",
	"res://assets/units/infantry_red.png",
]
const WORLD_METADATA_PATH := "res://assets/world/world_atlas.json"
const WORLD_ATLAS_PATH := "res://assets/world/world_atlas.png"
const DRAGON_PATHS := [
	"res://assets/world/dragon_blue.png",
	"res://assets/world/dragon_red.png",
]
const SIEGE_METADATA_PATH := "res://assets/units/siege_atlas.json"
const SIEGE_PATHS := [
	"res://assets/units/siege_blue.png",
	"res://assets/units/siege_red.png",
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
			var representative_index := model_index * GameConfig.INFANTRY_CLASS_FRAME_COUNT + 2
			var representative_origin := Vector2i((representative_index % GameConfig.INFANTRY_ATLAS_COLUMNS) * cell_size.x, (representative_index / GameConfig.INFANTRY_ATLAS_COLUMNS) * cell_size.y)
			var representative := image.get_region(Rect2i(representative_origin, cell_size))
			var luminance_range := _opaque_luminance_range(representative)
			if luminance_range.x > 0.35 or luminance_range.y - luminance_range.x < 0.55:
				_fail("infantry shading lacks readable dark-to-light form in %s model=%d range=%s" % [path, model_index, luminance_range])
				return
	if not _validate_world_atlas():
		return
	if not _validate_siege_atlas():
		return
	print("ATLAS VALIDATION PASS: shaded infantry, upright animated dragon, CC0 SIEGE and buildings")
	quit(0)


func _opaque_luminance_range(image: Image) -> Vector2:
	var minimum := 1.0
	var maximum := 0.0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.10:
				continue
			var luminance := pixel.get_luminance()
			minimum = minf(minimum, luminance)
			maximum = maxf(maximum, luminance)
	return Vector2(minimum, maximum)


func _validate_world_atlas() -> bool:
	var metadata_file := FileAccess.open(WORLD_METADATA_PATH, FileAccess.READ)
	if metadata_file == null:
		_fail("world atlas metadata is missing")
		return false
	var metadata = JSON.parse_string(metadata_file.get_as_text())
	if not metadata is Dictionary:
		_fail("world atlas metadata is not a JSON object")
		return false
	var required_sprites := ["blue_hq", "red_hq", "blue_melee_spawner", "red_melee_spawner", "blue_ranged_spawner", "red_ranged_spawner", "blue_tower", "red_tower", "blue_dragon_lair", "red_dragon_lair", "rock_a", "rock_b", "rock_c", "crate"]
	var sprites: Dictionary = metadata.get("sprites", {})
	for sprite_name in required_sprites:
		if not sprites.has(sprite_name):
			_fail("world atlas is missing sprite %s" % sprite_name)
			return false
	var world_image := Image.load_from_file(ProjectSettings.globalize_path(WORLD_ATLAS_PATH))
	if world_image == null or world_image.is_empty() or world_image.get_size() != Vector2i(512, 512):
		_fail("world atlas must be a 512x512 image")
		return false
	if int(metadata.get("dragon_directions", 0)) != 8 or int(metadata.get("dragon_frames_per_direction", 0)) != 16:
		_fail("dragon atlas contract must be 8 directions x 16 frames")
		return false
	for dragon_path in DRAGON_PATHS:
		var dragon_image := Image.load_from_file(ProjectSettings.globalize_path(dragon_path))
		if dragon_image == null or dragon_image.is_empty() or dragon_image.get_size() != Vector2i(1536, 768):
			_fail("dragon atlas must be 1536x768: %s" % dragon_path)
			return false
		var direction_hashes: Dictionary = {}
		for direction_index in 8:
			var linear_index := direction_index * 16 + 2
			var origin := Vector2i((linear_index % 16) * 96, (linear_index / 16) * 96)
			var frame := dragon_image.get_region(Rect2i(origin, Vector2i(96, 96)))
			direction_hashes[hash(frame.get_data())] = true
		if direction_hashes.size() < 7:
			_fail("dragon headings are not visually distinct: %s" % dragon_path)
			return false
	return true


func _validate_siege_atlas() -> bool:
	var metadata_file := FileAccess.open(SIEGE_METADATA_PATH, FileAccess.READ)
	if metadata_file == null:
		_fail("SIEGE atlas metadata is missing")
		return false
	var metadata = JSON.parse_string(metadata_file.get_as_text())
	if not metadata is Dictionary or int(metadata.get("directions", 0)) != 8 or int(metadata.get("frames_per_direction", 0)) != 16:
		_fail("SIEGE metadata must describe 8 directions x 16 frames")
		return false
	if Vector2i(int(metadata.atlas_size[0]), int(metadata.atlas_size[1])) != Vector2i(1536, 1536):
		_fail("SIEGE atlas must be a 1536 square texture-array layer")
		return false
	for path in SIEGE_PATHS:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty() or image.get_size() != Vector2i(1536, 1536):
			_fail("invalid SIEGE atlas: %s" % path)
			return false
		var direction_hashes: Dictionary = {}
		for direction_index in 8:
			var linear_index := direction_index * 16 + 2
			var origin := Vector2i((linear_index % 16) * 96, (linear_index / 16) * 96)
			var frame := image.get_region(Rect2i(origin, Vector2i(96, 96)))
			direction_hashes[hash(frame.get_data())] = true
		if direction_hashes.size() < 7:
			_fail("SIEGE headings are not visually distinct: %s" % path)
			return false
		var attack_a := image.get_region(Rect2i(Vector2i(8 * 96, 0), Vector2i(96, 96)))
		var attack_b := image.get_region(Rect2i(Vector2i(11 * 96, 0), Vector2i(96, 96)))
		if hash(attack_a.get_data()) == hash(attack_b.get_data()):
			_fail("SIEGE attack frames do not show recoil: %s" % path)
			return false
	return true


func _fail(message: String) -> void:
	push_error("ATLAS VALIDATION FAILED: %s" % message)
	quit(1)
