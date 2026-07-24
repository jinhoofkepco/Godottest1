extends RefCounted

const PROJECT_PATH := "res://project.godot"
const EXPORT_PRESET_PATH := "res://export_presets.cfg"
const LAB_WORKFLOW_PATH := "res://.github/workflows/android-agent-lab.yml"
const PRODUCTION_WORKFLOW_PATH := "res://.github/workflows/android.yml"
const SCENARIO_MATRIX_RUNNER_PATH := "res://tests/run_agent_scenario_matrix.gd"
const PRODUCTION_WORKFLOW_SHA256 := "c8093cbc4ae707cc33f236969c2544b9dfd7a31703d6ac402be8540ffcb8298e"
const CHECKOUT_SHA := "11d5960a326750d5838078e36cf38b85af677262"
const GODOT_ANDROID_EXPORT_SHA := "9344383c3c917d807d155aa5695292a13ff5b2a2"
const SETUP_DOTNET_SHA := "67a3573c9a986a3f9c594539f4ab511d57bb3ce9"
const UPLOAD_ARTIFACT_SHA := "ea165f8d65b6e75b540449e92b4886f43607fa02"

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
	_expect(_contains_line(workflow, "  push:"), "lab workflow has a push trigger")
	_expect(
		_contains_line(workflow, "    branches: [codex/mini-battle-agent-ai]"),
		"branch push trigger is exact"
	)
	_expect(not workflow.contains("workflow_dispatch:"), "branch-only workflow has no inert manual trigger")
	_expect(not workflow.contains("pull_request:"), "lab workflow does not run for other refs")
	_expect(
		workflow.contains("\npermissions:\n  contents: read\n\njobs:\n"),
		"workflow has only top-level read-only contents permission"
	)
	_expect(workflow.count("permissions:") == 1, "workflow has no job-level permission override")
	_expect(not workflow.contains("write-all"), "workflow does not grant write-all")
	_expect(not workflow.contains(": write"), "workflow grants no write permissions")
	_expect(
		_contains_line(workflow, "        uses: actions/checkout@%s" % CHECKOUT_SHA),
		"checkout action is pinned"
	)
	_expect(
		_contains_line(
			workflow,
			"        uses: dulvui/godot-android-export@%s" % GODOT_ANDROID_EXPORT_SHA
		),
		"Godot Android action is pinned"
	)
	_expect(
		_contains_line(workflow, "        uses: actions/setup-dotnet@%s" % SETUP_DOTNET_SHA),
		"setup-dotnet action is pinned"
	)
	_expect(
		_contains_line(workflow, "        uses: actions/upload-artifact@%s" % UPLOAD_ARTIFACT_SHA),
		"upload-artifact action is pinned"
	)
	_expect(
		_contains_line(workflow, "          godot --headless --path . -s tests/run_agent_battle_lab.gd"),
		"workflow runs lab rules"
	)
	_expect(FileAccess.file_exists(SCENARIO_MATRIX_RUNNER_PATH), "scenario matrix runner exists")
	_expect(
		_contains_line(
			workflow,
			"          godot --headless --path . -s tests/run_agent_scenario_matrix.gd"
		),
		"workflow runs scenario matrix"
	)
	_expect(
		_contains_line(workflow, "          godot --headless --path . -s tests/run_agent_apk_contract.gd"),
		"workflow runs APK contract"
	)
	_expect(
		_contains_line(workflow, "          godot --headless --path . -s tests/run_rules.gd"),
		"workflow runs production rules"
	)
	_expect(
		_contains_line(
			workflow,
			"          godot --headless --path . --scene res://scenes/agent_battle_lab.tscn --quit-after 180"
		),
		"workflow smokes the lab scene"
	)
	_expect(
		_contains_line(
			workflow,
			"          godot --headless --path . --export-debug Android build/mini-battle-ai-lab.apk"
		),
		"workflow performs an exact debug export"
	)
	_expect(
		_contains_line(workflow, "          test -s build/mini-battle-ai-lab.apk"),
		"workflow rejects a missing or empty APK"
	)
	_expect(
		_contains_line(workflow, "          name: mini-battle-ai-lab-debug-apk"),
		"artifact name is exact"
	)
	_expect(
		_contains_line(workflow, "          path: build/mini-battle-ai-lab.apk"),
		"artifact path is exact"
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
