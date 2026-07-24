extends RefCounted

const PROJECT_PATH := "res://project.godot"
const EXPORT_PRESET_PATH := "res://export_presets.cfg"
const LAB_WORKFLOW_PATH := "res://.github/workflows/android-agent-lab.yml"
const PRODUCTION_WORKFLOW_PATH := "res://.github/workflows/android.yml"
const PRODUCTION_WORKFLOW_SHA256 := "c8093cbc4ae707cc33f236969c2544b9dfd7a31703d6ac402be8540ffcb8298e"

var failures: Array[String] = []


func run() -> Array[String]:
	var project := _read(PROJECT_PATH)
	var preset := _read(EXPORT_PRESET_PATH)
	var workflow := _read(LAB_WORKFLOW_PATH)

	_expect(_contains_line(project, 'config/name="Mini Battle AI Lab"'), "project has lab name")
	_expect(
		_contains_line(project, 'run/main_scene="res://scenes/agent_battle_lab.tscn"'),
		"lab is main scene"
	)
	_expect(_contains_line(preset, 'name="Android"'), "Android preset name stays stable")
	_expect(
		_contains_line(preset, 'package/unique_name="com.jinhoofkepco.godottest1.agentlab"'),
		"package is separate"
	)
	_expect(_contains_line(preset, 'package/name="Mini Battle AI Lab"'), "launcher label is separate")
	_expect(
		_contains_line(preset, 'export_path="build/mini-battle-ai-lab.apk"'),
		"export path is separate"
	)
	_expect(_contains_line(preset, 'version/code=1'), "lab version code is 1")
	_expect(_contains_line(preset, 'version/name="0.2.0-lab"'), "lab version name is separate")

	_expect(FileAccess.file_exists(LAB_WORKFLOW_PATH), "dedicated lab workflow exists")
	_expect(workflow.contains("codex/mini-battle-agent-ai"), "branch push triggers lab workflow")
	_expect(workflow.contains("workflow_dispatch:"), "lab workflow supports manual dispatch")
	_expect(workflow.contains("tests/run_agent_battle_lab.gd"), "workflow runs lab rules")
	_expect(workflow.contains("tests/run_agent_scenario_matrix.gd"), "workflow runs scenario matrix")
	_expect(workflow.contains("tests/run_agent_apk_contract.gd"), "workflow runs APK contract")
	_expect(workflow.contains("tests/run_rules.gd"), "workflow runs production rules")
	_expect(
		workflow.contains("--scene res://scenes/agent_battle_lab.tscn"),
		"workflow smokes the lab scene"
	)
	_expect(
		workflow.contains("build/mini-battle-ai-lab.apk"),
		"workflow exports the separate APK"
	)
	_expect(
		workflow.contains("mini-battle-ai-lab-debug-apk"),
		"artifact name is separate"
	)
	_expect(
		workflow.contains("com.jinhoofkepco.godottest1.agentlab"),
		"workflow verifies the separate package"
	)
	_expect(
		workflow.contains("application-label:'Mini Battle AI Lab'"),
		"workflow verifies the launcher label"
	)
	_expect(
		workflow.contains("assets/.godot/mono/publish/arm64/godottest1.dll"),
		"workflow verifies the arm64 C# assembly"
	)
	_expect(workflow.contains("apksigner"), "workflow verifies the APK signature")
	_expect(workflow.contains("retention-days: 14"), "artifact retention is 14 days")

	_expect(
		FileAccess.get_sha256(PRODUCTION_WORKFLOW_PATH) == PRODUCTION_WORKFLOW_SHA256,
		"production Android workflow remains byte-identical"
	)
	return failures


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _contains_line(text: String, expected: String) -> bool:
	return Array(text.split("\n", false)).has(expected)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
