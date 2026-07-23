# Mini Battle Multi-Scenario Lab and Dedicated APK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing 30-vs-30 individual-agent prototype into a four-case interactive mobile lab and deliver a separately installable, branch-built Android APK.

**Architecture:** Keep the current single C# simulation Node and fixed SoA unit arrays. Add reset-time scenario construction and fixed route/region metadata in a focused partial class, expose bulk scenario metrics to the existing procedural GDScript renderer, then add a two-row mobile selector. A dedicated branch workflow exports an independently named Android package and uploads an unmistakable artifact.

**Tech Stack:** Godot 4.5 stable .NET, C#, GDScript, fixed 30 Hz simulation, procedural CanvasItem drawing, GitHub Actions, `dulvui/godot-android-export@v4.2.0`.

## Global Constraints

- Work only on `codex/mini-battle-agent-ai`; do not merge into `main`.
- Preserve the fixed 28×36 arena, 30 blue and 30 red shield infantry, fixed 30 Hz tick, and existing combat stats in all cases.
- Use seeds `230723`, `230724`, and `230725` for the comparison matrix.
- Units remain fixed-array data; do not create per-unit Nodes, LINQ hot loops, or per-tick terrain allocations.
- Scenario IDs are exactly `0 BOTTLENECK`, `1 CORNER_TRAP`, `2 ROUTE_CHOICE`, and `3 OPEN_CONTROL`.
- The app identity is exactly `Mini Battle AI Lab`, package `com.jinhoofkepco.godottest1.agentlab`, version `0.2.0-lab` code `1`.
- The exported file is `build/mini-battle-ai-lab.apk`; the Actions artifact is `mini-battle-ai-lab-debug-apk`.
- The production `.github/workflows/android.yml` remains unchanged.
- Tests are written and observed failing before production changes.
- No physical-device or managed-GC claim is allowed without direct measurement.

---

### Task 1: Deterministic Scenario Builder and Generic Terrain Queries

**Files:**
- Create: `scripts/agent_lab/AgentBattleSimulation.Scenarios.cs`
- Create: `scripts/agent_lab/AgentBattleSimulation.Scenarios.cs.uid`
- Modify: `scripts/agent_lab/AgentBattleConfig.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.Decision.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.Movement.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.Combat.cs`
- Modify: `tests/test_agent_battle_lab.gd`

**Interfaces:**
- Consumes: existing `ResetExperiment(mode, seed)`, `_blockedMask`, movement candidates, spatial buckets, and snapshots.
- Produces: `ResetExperiment(int mode, int seed, int scenario = 0)`, scenario constants, scenario snapshot fields, active blocked-cell prefix, mirrored route waypoints, and generic segment-clear terrain checks.

- [ ] **Step 1: Add failing scenario contract tests**

Add a scenario test loop to `tests/test_agent_battle_lab.gd` that calls:

```gdscript
const SCENARIO_NAMES := ["BOTTLENECK", "CORNER_TRAP", "ROUTE_CHOICE", "OPEN_CONTROL"]

for scenario in SCENARIO_NAMES.size():
    simulation.call("ResetExperiment", 1, TEST_SEED, scenario)
    var snapshot: Dictionary = simulation.call("GetSnapshot")
    _expect(int(snapshot.scenario_id) == scenario, "scenario id round-trips")
    _expect(String(snapshot.scenario_name) == SCENARIO_NAMES[scenario], "scenario name round-trips")
    _expect(_blocked_geometry_matches(scenario, snapshot.blocked_cells), "scenario blocked geometry matches")
    _expect(_blocked_geometry_is_vertically_symmetric(snapshot.blocked_cells), "scenario terrain is mirrored")
    _expect(_both_teams_have_a_reachable_passage(snapshot), "scenario keeps mirrored passages reachable")

simulation.call("ResetExperiment", 1, TEST_SEED, 99)
_expect(int(simulation.call("GetSnapshot").scenario_id) == 0, "invalid scenario falls back to bottleneck")
```

The geometry helper must assert the exact cell ranges in the design, including zero blocked cells for `OPEN_CONTROL`.

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_agent_battle_lab.gd
```

Expected: FAIL because `ResetExperiment` has no scenario parameter and the snapshot has no scenario fields.

- [ ] **Step 3: Add reset-time scenario storage**

In `AgentBattleConfig.cs`, add:

```csharp
public const int ScenarioBottleneck = 0;
public const int ScenarioCornerTrap = 1;
public const int ScenarioRouteChoice = 2;
public const int ScenarioOpenControl = 3;
public const int ScenarioCount = 4;
public const int ArenaCellCount = ArenaWidth * ArenaHeight;
```

Replace the 40-cell blocked buffer with `int[ArenaCellCount]` plus
`_blockedCellCount`. Add `_scenario`, `_routeCrossingFlags`,
`_scenarioRegionFlags`, fixed team/route waypoint arrays, and per-unit waypoint
cursors. `ResetExperiment` validates `scenario` before clearing and building.

- [ ] **Step 4: Implement exact reset-time geometry**

In `AgentBattleSimulation.Scenarios.cs`, implement:

```csharp
private void BuildScenario(int scenario)
{
    _blockedCellCount = 0;
    Array.Clear(_blockedMask);
    Array.Clear(_scenarioRegionFlags);
    switch (scenario)
    {
        case AgentBattleConfig.ScenarioCornerTrap:
            BuildCornerTrap();
            break;
        case AgentBattleConfig.ScenarioRouteChoice:
            BuildRouteChoice();
            break;
        case AgentBattleConfig.ScenarioOpenControl:
            break;
        default:
            BuildBottleneck();
            break;
    }
    BuildMirroredRouteWaypoints();
}

private void BlockCell(int x, int y)
{
    int cell = y * AgentBattleConfig.ArenaWidth + x;
    if (_blockedMask[cell])
        return;
    _blockedMask[cell] = true;
    _blockedCells[_blockedCellCount++] = cell;
}
```

Use the exact geometry in the design spec. Snapshot only
`_blockedCells.AsSpan(0, _blockedCellCount).ToArray()` and add
`scenario_id`/`scenario_name`.

- [ ] **Step 5: Remove original-wall assumptions from decisions and movement**

Replace fixed `17.5`, fortification bounds, gate bounds, and asymmetric
`BypassLaneX` logic with scenario metadata:

```csharp
private bool IsApproachingScenarioBarrier(int index) =>
    _scenario != AgentBattleConfig.ScenarioOpenControl
    && !HasPassedScenarioBarrier(index)
    && MathF.Abs(_positions[index].Y - _barrierCenterY) < 8.5f;

private Vector2 RouteObjective(int index) =>
    _routeWaypoints[RouteWaypointOffset(index, _routeIntents[index], _routeWaypointCursor[index])];
```

Waypoints for red must equal the exact vertical reflection of blue:
`new Vector2(blue.X, ArenaHeight - blue.Y)`. Once a waypoint is reached, advance
the cursor; after the barrier, return to direct opponent-side movement.

- [ ] **Step 6: Make combat passage checks terrain-generic**

Replace `HasCombatPassage`'s one-wall intersection math with a fixed-step DDA
over `_blockedMask`:

```csharp
private bool HasCombatPassage(Vector2 from, Vector2 to)
{
    float distance = from.DistanceTo(to);
    int steps = Math.Max(1, Mathf.CeilToInt(distance / 0.2f));
    for (int step = 1; step < steps; step++)
    {
        Vector2 sample = from.Lerp(to, step / (float)steps);
        if (IsBlockedPoint(sample, AgentBattleConfig.UnitRadius * 0.8f))
            return false;
    }
    return true;
}
```

Keep the loop allocation-free and reuse existing blocked-point/radius checks.

- [ ] **Step 7: Verify GREEN and existing behavior**

Run the build, scenario contract, and existing production rules:

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 /private/tmp/godottest1-dotnet9/dotnet build --nologo
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_agent_battle_lab.gd
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_rules.gd
```

Expected: build has zero errors; both runners print PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/agent_lab tests/test_agent_battle_lab.gd
git commit -m "feat: add deterministic battle lab scenarios"
```

### Task 2: Scenario Metrics, Comparison Matrix, and Controlled AI Tuning

**Files:**
- Create: `tests/test_agent_scenario_matrix.gd`
- Create: `tests/run_agent_scenario_matrix.gd`
- Create: corresponding `.uid` files
- Modify: `scripts/agent_lab/AgentBattleSimulation.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.Combat.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.Movement.cs`
- Modify: `scripts/agent_lab/AgentBattleConfig.cs`
- Modify: `tests/test_agent_battle_lab.gd`

**Interfaces:**
- Consumes: Task 1 scenario reset, route regions, trap region, current metrics, and fixed seeds.
- Produces: per-team participation/HP metrics, route counters, trap timing metrics, and one runner for the 24-run matrix.

- [ ] **Step 1: Write failing metric and matrix tests**

Require these keys from `GetMetrics()`:

```gdscript
for key in [
    "blue_units_ever_attacked", "red_units_ever_attacked",
    "blue_remaining_hp", "red_remaining_hp",
    "route_crossings", "trap_entries_blue", "trap_entries_red",
    "trap_escapes_within_12s", "trap_escape_ratio",
    "maximum_trap_dwell_seconds"
]:
    _expect(metrics.has(key), "metrics expose %s" % key)
```

`test_agent_scenario_matrix.gd` must run all `4×3×2` combinations, repeat each
Agent run once, and assert equal result/alive/position/action/route arrays.
Encode each design-spec acceptance threshold as a named assertion.

- [ ] **Step 2: Run the new runner and verify RED**

Run:

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_agent_scenario_matrix.gd
```

Expected: FAIL because the new metrics and runner contract are absent.

- [ ] **Step 3: Add fixed-array route and trap instrumentation**

Add fixed per-unit arrays for route crossed, trap entry tick, trap entered, and
trap escaped. Update them after movement using scenario region flags:

```csharp
if (!_trapEntered[index] && IsTrapRegion(_positions[index]))
{
    _trapEntered[index] = true;
    _trapEntryTicks[index] = _tickCount;
}
if (_trapEntered[index] && !_trapEscaped[index] && HasPassedScenarioBarrier(index))
{
    float dwell = (_tickCount - _trapEntryTicks[index]) * AgentBattleConfig.FixedDelta;
    _trapEscaped[index] = true;
    if (dwell <= 12f)
        _trapEscapesWithin12Seconds++;
    _maximumTrapDwellSeconds = MathF.Max(_maximumTrapDwellSeconds, dwell);
}
```

Track route crossings once per unit, split actual attackers by team, and sum
remaining HP only when `GetMetrics()` is called.

- [ ] **Step 4: Add the 24-run comparison output**

Print one stable TSV-style line per run:

```text
CASE=%s SEED=%d MODE=%s attacked=%d idle=%.1f stuck=%.1f routes=%d/%d/%d trap=%d/%d alive=%d/%d hp=%.1f/%.1f result=%s
```

Finish with `AGENT SCENARIO MATRIX PASS` or a nonzero Godot exit.

- [ ] **Step 5: Run initial matrix and tune one variable at a time**

Run the matrix with unchanged constants and save its output outside tracked
source at `.superpowers/sdd/scenario-matrix-initial.txt`. For every failing
criterion:

1. name the single candidate from the design tuning table;
2. change exactly that constant;
3. rerun all 24 combinations;
4. keep it only if the failed case improves without breaking passed cases;
5. append old value, new value, and before/after metrics to
   `.superpowers/sdd/tuning-log.md`;
6. revert rejected changes before trying the next candidate.

Do not change combat stats. If all cases pass without AI constant changes,
record `No decision-weight change accepted`; route symmetry and generic terrain
handling are still reported as structural changes.

- [ ] **Step 6: Verify matrix, determinism, performance, and rules**

Run:

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 /private/tmp/godottest1-dotnet9/dotnet build --nologo
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_agent_scenario_matrix.gd
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_agent_battle_lab.gd
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_rules.gd
```

Expected: all runners PASS and each Agent case average tick is below 1 ms on
the development machine. Do not assert GC count.

- [ ] **Step 7: Commit**

```bash
git add scripts/agent_lab tests
git commit -m "test: compare agent AI across four battle cases"
```

### Task 3: Mobile Scenario Selector and Five Visual Captures

**Files:**
- Modify: `scripts/agent_battle_lab.gd`
- Modify: `scenes/agent_battle_lab.tscn`
- Modify: `tests/test_agent_battle_lab.gd`
- Modify: `tests/smoke_agent_battle_lab.gd`

**Interfaces:**
- Consumes: `ResetExperiment(mode, seed, scenario)`, scenario snapshot fields, and metrics from Tasks 1–2.
- Produces: `set_scenario(int)`, four large case buttons, mode controls, scenario-aware drawing, and five smoke PNGs.

- [ ] **Step 1: Write failing UI contract tests**

Require:

```gdscript
for method in ["set_scenario", "set_mode", "reset_lab", "get_metrics_text"]:
    _expect(lab.has_method(method), "lab exposes %s" % method)
for path in [
    "Interface/ScenarioControls/Gate",
    "Interface/ScenarioControls/Corner",
    "Interface/ScenarioControls/Routes",
    "Interface/ScenarioControls/Open"
]:
    var button := lab.get_node_or_null(path)
    _expect(button is Button and button.custom_minimum_size.y >= 44.0, "%s is touch-sized" % path)
```

Select each button, then assert snapshot scenario ID and title text change.

- [ ] **Step 2: Run the UI contract and verify RED**

Run `tests/run_agent_battle_lab.gd`.

Expected: FAIL because scenario controls and `set_scenario` do not exist.

- [ ] **Step 3: Add the scenario selector and unmistakable lab identity**

Add a four-button row labeled exactly `1 GATE`, `2 CORNER`, `3 ROUTES`,
`4 OPEN`. Set the header title to `MINI BATTLE AI LAB // 30 vs 30 SHIELDS`.
Wire:

```gdscript
func set_scenario(value: int) -> void:
    _scenario = clampi(value, 0, 3)
    reset_lab()

func reset_lab() -> void:
    _paused = false
    _simulation.call("ResetExperiment", _mode, TEST_SEED, _scenario)
    sync_view()
    _update_controls()
```

Disable/highlight the selected scenario and mode. Keep both button rows at
least 44 px high and within 540×960.

- [ ] **Step 4: Make arena annotations scenario-aware**

Draw blocked cells only from the snapshot. Remove fixed central-gate posts and
instead label open route mouths from snapshot route metadata or scenario ID.
Header shows case name, mode, and time. Metrics retain alive, attacked,
replacement, idle, stuck, and tick time.

- [ ] **Step 5: Extend smoke capture to five deterministic images**

Produce:

```text
build/smoke_agent_case_1_gate.png
build/smoke_agent_case_2_corner.png
build/smoke_agent_case_3_routes.png
build/smoke_agent_case_4_open.png
build/smoke_baseline_case_1_gate.png
```

For each capture set scenario/mode, reset, run to the deterministic contact
condition, wait two rendered frames, capture 540×960, and assert non-empty
RGBA output.

- [ ] **Step 6: Verify GREEN and visually inspect all captures**

Run:

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_agent_battle_lab.gd
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy \
  --path . -s tests/smoke_agent_battle_lab.gd
file build/smoke_agent_case_*.png build/smoke_baseline_case_1_gate.png
```

Inspect each PNG and confirm complete arena, title, selected case, legend, and
both button rows are visible with no overlap.

- [ ] **Step 7: Commit**

```bash
git add scripts/agent_battle_lab.gd scenes/agent_battle_lab.tscn tests
git commit -m "feat: add mobile multi-case AI lab controls"
```

### Task 4: Separate Android Identity and Branch-Only APK Workflow

**Files:**
- Create: `.github/workflows/android-agent-lab.yml`
- Create: `tests/test_agent_apk_contract.gd`
- Create: `tests/run_agent_apk_contract.gd`
- Create: corresponding `.uid` files
- Modify: `project.godot`
- Modify: `export_presets.cfg`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 3 main lab scene and test runners.
- Produces: separate Android application/package, branch workflow, signed APK, and unambiguous artifact documentation.

- [ ] **Step 1: Write a failing branch APK contract**

Parse `project.godot`, `export_presets.cfg`, and the dedicated workflow as
plain text and assert:

```gdscript
_expect(project.contains('config/name="Mini Battle AI Lab"'), "project has lab name")
_expect(project.contains('run/main_scene="res://scenes/agent_battle_lab.tscn"'), "lab is main scene")
_expect(preset.contains('package/unique_name="com.jinhoofkepco.godottest1.agentlab"'), "package is separate")
_expect(preset.contains('package/name="Mini Battle AI Lab"'), "launcher label is separate")
_expect(preset.contains('export_path="build/mini-battle-ai-lab.apk"'), "export path is separate")
_expect(workflow.contains("codex/mini-battle-agent-ai"), "branch push triggers lab workflow")
_expect(workflow.contains("mini-battle-ai-lab-debug-apk"), "artifact name is separate")
```

Also assert `.github/workflows/android.yml` remains byte-identical to its
pre-task SHA-256 recorded in the test fixture.

- [ ] **Step 2: Run the APK contract and verify RED**

Run:

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 PATH=/private/tmp/godottest1-dotnet9:$PATH \
  /private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_agent_apk_contract.gd
```

Expected: FAIL because lab identity/workflow do not yet exist.

- [ ] **Step 3: Apply the separate app identity**

Set:

```ini
config/name="Mini Battle AI Lab"
run/main_scene="res://scenes/agent_battle_lab.tscn"
```

and:

```ini
export_path="build/mini-battle-ai-lab.apk"
version/code=1
version/name="0.2.0-lab"
package/unique_name="com.jinhoofkepco.godottest1.agentlab"
package/name="Mini Battle AI Lab"
```

Do not change the Android preset name `Android`.

- [ ] **Step 4: Add the dedicated workflow**

Copy the proven Godot 4.5 .NET/JDK/Android setup into
`android-agent-lab.yml`, with:

```yaml
name: Mini Battle AI Lab APK
on:
  push:
    branches: [codex/mini-battle-agent-ai]
  workflow_dispatch:
permissions:
  contents: read
```

Its verification step runs build, import, `run_agent_battle_lab.gd`,
`run_agent_scenario_matrix.gd`, `run_agent_apk_contract.gd`, `run_rules.gd`,
and a headless lab scene smoke. Export with:

```bash
godot --headless --path . --export-debug Android build/mini-battle-ai-lab.apk
test -s build/mini-battle-ai-lab.apk
unzip -l build/mini-battle-ai-lab.apk | grep -Fq 'assets/.godot/mono/publish/arm64/godottest1.dll'
aapt dump badging build/mini-battle-ai-lab.apk | grep -Fq "package: name='com.jinhoofkepco.godottest1.agentlab'"
aapt dump badging build/mini-battle-ai-lab.apk | grep -Fq "application-label:'Mini Battle AI Lab'"
```

Verify with the newest installed `apksigner`, then upload artifact
`mini-battle-ai-lab-debug-apk` with 14-day retention.

- [ ] **Step 5: Replace misleading branch README APK directions**

At the top experiment section, state that production APK artifacts are not the
lab. Link the dedicated workflow and show exact artifact name. Preserve the
production game's general documentation but visibly scope it as production
background.

- [ ] **Step 6: Verify GREEN and workflow syntax**

Run the APK contract, build, scenario matrix, rules, and:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/android-agent-lab.yml", aliases: true); puts "YAML PASS"'
git diff --exit-code 8a22c1a -- .github/workflows/android.yml
```

Expected: contract/rules/matrix PASS, YAML PASS, production workflow unchanged.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/android-agent-lab.yml project.godot export_presets.cfg README.md tests
git commit -m "ci: build separate mini battle AI lab APK"
```

### Task 5: Results Report, Full Verification, GitHub Build, and APK Audit

**Files:**
- Create: `docs/agent-battle-multi-case-results.md`
- Modify: `README.md`
- Modify: `.superpowers/sdd/progress.md` (ignored ledger only)

**Interfaces:**
- Consumes: all tests, matrix output, tuning log, smoke captures, export identity, and dedicated workflow.
- Produces: evidence-backed results report, pushed branch, successful run URL, downloaded and inspected artifact, and final user handoff.

- [ ] **Step 1: Write the measured report**

Document each case and each seed, Agent versus Baseline, acceptance verdict,
average/worst tick, route/trap metrics, and remaining bias. Add a tuning table:

```markdown
| Case/criterion | Factor | Old | New | Before | After | Accepted? |
```

Include rejected attempts. State explicitly that phone frame time and GC are
unmeasured unless measured during this task.

- [ ] **Step 2: Run fresh full local verification**

Run build, import, all three lab runners, production rules, display smoke, file
dimension checks, `git diff --check`, and inspect all five images. Do not claim
success from prior outputs.

- [ ] **Step 3: Request whole-branch code review and fix findings**

Generate a review package from merge base `5562c27` to `HEAD`, dispatch the
final reviewer, fix every Critical/Important finding with covering tests, and
repeat review until both spec compliance and code quality are approved.

- [ ] **Step 4: Push the exact verified state**

```bash
git push origin codex/mini-battle-agent-ai
```

Confirm the remote branch SHA equals local `HEAD`.

- [ ] **Step 5: Wait for the dedicated Actions run**

Locate the push run for workflow `android-agent-lab.yml`, inspect status at
intervals shorter than 60 seconds, and if it fails use logs to fix the root
cause, rerun local covering tests, commit, and push again. Stop only for a
credential requirement.

- [ ] **Step 6: Download and audit the exact artifact**

Download the successful run artifact to a new temporary directory:

```bash
run_id="$(gh run list --repo jinhoofkepco/Godottest1 \
  --workflow android-agent-lab.yml --branch codex/mini-battle-agent-ai \
  --status success --limit 1 --json databaseId --jq '.[0].databaseId')"
artifact_dir="$(mktemp -d /tmp/mini-ai-lab-apk.XXXXXX)"
gh run download "$run_id" --repo jinhoofkepco/Godottest1 \
  --name mini-battle-ai-lab-debug-apk --dir "$artifact_dir"
```

Verify SHA-256, nonzero size, ZIP integrity, `apksigner verify`, package ID,
launcher label, version, and presence of the arm64 C# assembly. Confirm the run
head SHA equals the pushed branch SHA.

- [ ] **Step 7: Update report with final links and commit/push**

Add the successful run URL, artifact name, commit SHA, APK SHA-256 and size to
the report, rerun documentation checks, commit, push, and confirm the final
documentation-only run if triggered does not replace the already audited APK
link without noting its SHA.

- [ ] **Step 8: Final handoff**

Report only:

- branch URL;
- exact Actions run URL and artifact name;
- four-case headline findings;
- accepted/rejected tuning changes;
- APK identity and SHA-256;
- five things to check on the phone.
