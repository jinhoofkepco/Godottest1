extends RefCounted

var failures: Array[String] = []


func run_siege_contracts() -> Array[String]:
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_RANGE, 7.0), "SIEGE maximum range is doubled to 7.0 cells")
	_expect(is_equal_approx(GameConfig.SIEGE_UNIT_ATTACK_DAMAGE, 55.8), "SIEGE base damage is multiplied by 1.8")
	_expect(is_equal_approx(GameConfig.SIEGE_PRODUCTION_INTERVAL, GameConfig.SPAWNER_PRODUCTION_INTERVAL * 3.0), "SIEGE production rate is one third of normal")
	var renderer_source := FileAccess.get_file_as_string("res://scripts/unit_renderer.gd")
	_expect(renderer_source.contains("atlas_data.a") and renderer_source.contains("1.0 - UV.y"), "shared atlas shader supports a per-instance vertical flip")
	_expect(renderer_source.contains("unit_kind == UNIT_SIEGE") and renderer_source.contains("atlas_flip"), "SIEGE records explicitly opt into the vertical flip")
	return failures


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


const GameConfig = preload("res://scripts/game_config.gd")
