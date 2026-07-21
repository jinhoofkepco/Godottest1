# Hybrid Movement, Shield Balance, and Match Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make armies route around cliff protrusions, let multiple ranged units form a firing line, add shield/siege/dragon balance changes, and expose detailed per-match tuning with copyable JSON before play begins.

**Architecture:** Keep the fixed-step data-oriented C# simulation and bulk MultiMesh renderer. Add an instance-owned `BattleMatchSettings`, then layer shared ground-transition rules and bounded recovery under ranged annulus reservations and priority yielding. A new GDScript start modal edits one complete settings payload and applies it atomically through three bulk C# calls.

**Tech Stack:** Godot 4.5 stable .NET, C# simulation core, GDScript UI/render bridge, procedural CanvasItem shader overlay, headless Godot tests, GitHub Actions Android .NET export.

## Global Constraints

- Preserve the C# SoA unit core; no per-unit Node instances.
- Preserve fixed 30 Hz simulation and bulk GDScript/C# boundaries.
- BLUE and RED use the same edited unit settings; AI income level remains separate.
- Shield mode: MELEE enter at hostile RANGED range `2.5`, release at `3.0`, speed multiplier `0.20`, incoming RANGED damage multiplier `0.10`.
- SIEGE defaults: production interval `12.342857`, range `14.0`, blast radius `1.8`, damage `55.8`.
- DRAGON defaults: production interval `45.0`, production batch `2`, HP `520`, damage `36`.
- Team live-unit cap remains 300 and partial batches stop exactly at the cap.
- Settings copy format is sorted canonical JSON with `schema_version: 1`; import is not added.
- Godot runtime verification must use official Godot 4.5 .NET and fail on C# load/script errors.
- Keep portrait, touch/mouse input, external asset set unchanged, and Android debug APK delivery through GitHub Actions.

---

### Task 1: Instance-owned match settings and atomic bulk API

**Files:**
- Create: `scripts/BattleMatchSettings.cs`
- Create: `scripts/BattleSimulation.Settings.cs`
- Modify: `scripts/BattleConfig.cs`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Legions.cs`
- Modify: `scripts/BattleSimulation.Ai.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `scripts/game_config.gd`
- Test: `tests/test_rules.gd`

**Interfaces:**
- Consumes: compile-time defaults in `BattleConfig` and existing unit helper methods.
- Produces: `GetMatchSettingsSchema() -> Godot.Collections.Array`, `GetMatchSettings() -> Dictionary`, `ConfigureAndReset(Dictionary) -> Dictionary`, and instance methods `UnitMaxHp`, `UnitSpeed`, `UnitAttackDamage`, `UnitAttackRange`, `UnitAttackInterval`, `UnitDetectRange`, `UnitRadius`, `ProductionInterval`, `ProductionBatch`, and `BuildCost`.

- [ ] **Step 1: Write failing settings contract tests**

Add `_test_match_settings_profile()` to `tests/test_rules.gd` and call it from `run()`. The test must assert the new API exists, the shipped settings contain all four unit groups, a custom RANGED HP applies after `ConfigureAndReset`, two simulation instances remain isolated, and an invalid SIEGE payload is rejected without changing the previous active profile.

```gdscript
func _test_match_settings_profile() -> void:
	var first = _new_simulation()
	var second = _new_simulation()
	_expect(first.has_method("GetMatchSettingsSchema") and first.has_method("ConfigureAndReset"), "bulk match settings API exists")
	var defaults: Dictionary = first.call("GetMatchSettings")
	_expect(defaults.has("melee") and defaults.has("ranged") and defaults.has("siege") and defaults.has("dragon"), "settings expose four unit profiles")
	var changed := defaults.duplicate(true)
	changed.ranged.max_hp = 31.5
	var applied: Dictionary = first.call("ConfigureAndReset", changed)
	_expect(bool(applied.ok) and is_equal_approx(float(first.call("GetMatchSettings").ranged.max_hp), 31.5), "settings apply atomically before reset")
	_expect(not is_equal_approx(float(second.call("GetMatchSettings").ranged.max_hp), 31.5), "simulation settings are instance isolated")
	var invalid := changed.duplicate(true)
	invalid.siege.min_range = 20.0
	invalid.siege.attack_range = 10.0
	var rejected: Dictionary = first.call("ConfigureAndReset", invalid)
	_expect(not bool(rejected.ok) and is_equal_approx(float(first.call("GetMatchSettings").ranged.max_hp), 31.5), "invalid payload is rejected without partial mutation")
	first.free()
	second.free()
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
DOTNET_ROOT=/opt/homebrew/opt/dotnet@9/libexec PATH=/opt/homebrew/opt/dotnet@9/bin:$PATH \
/tmp/godot45mono.0090Jt/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_rules.gd
```

Expected: exit 1 with `bulk match settings API exists` because the methods do not exist.

- [ ] **Step 3: Implement the settings model and migrate dynamic reads**

Use an instance-owned model, not mutable static fields:

```csharp
internal sealed class BattleMatchSettings
{
    internal sealed class UnitTuning
    {
        public float MaxHp, Damage, AttackInterval, AttackRange, DetectRange, Speed, Radius, ProductionInterval;
        public int ProductionBatch, SpawnerCost;
        public readonly float[] DamageVs = new float[4];
        public UnitTuning Clone();
    }

    public readonly UnitTuning[] Units = new UnitTuning[4];
    public float ShieldEnterRange, ShieldReleaseRange, ShieldSpeedMultiplier, ShieldRangedDamageTakenMultiplier;
    public float RangedStandoffDistance, RangedHighGroundBonus, PreferredFiringRangeRatio;
    public float SiegeMinRange, SiegeBlastRadius, SiegeEdgeDamageMultiplier, SiegeFlightSeconds;
    public static BattleMatchSettings CreateDefault();
    public BattleMatchSettings Clone();
}
```

`ConfigureAndReset` builds a clone, validates every supplied field with `float.IsFinite`, applies it only after all checks pass, calls `Reset()`, and returns the normalized dictionary. Replace all runtime unit, counter, production, batch, radius, cost, and render-size reads with `_settings`; keep map/performance constants in `BattleConfig`.

- [ ] **Step 4: Run rules, game-flow, and C# compile tests and verify GREEN**

Run:

```bash
/opt/homebrew/opt/dotnet@9/bin/dotnet build
DOTNET_ROOT=/opt/homebrew/opt/dotnet@9/libexec PATH=/opt/homebrew/opt/dotnet@9/bin:$PATH /tmp/godot45mono.0090Jt/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_rules.gd
DOTNET_ROOT=/opt/homebrew/opt/dotnet@9/libexec PATH=/opt/homebrew/opt/dotnet@9/bin:$PATH /tmp/godot45mono.0090Jt/Godot_mono.app/Contents/MacOS/Godot --headless --path . -s tests/run_game_flow.gd
```

Expected: build with 0 warnings/0 errors and both runners print PASS with no `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts tests/test_rules.gd
git commit -m "feat: add per-match unit tuning profile"
```

---

### Task 2: Shield mode and requested production balance

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Ai.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/unit_renderer.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Consumes: `_settings` and dynamic helpers from Task 1.
- Produces: SoA `_shieldModes`, debug `unit_shield_modes`, infantry-buffer shield flag in `COLOR.b`, shield-aware damage/AI scoring, and batch production respecting the 300-unit cap.

- [ ] **Step 1: Write failing shield and production tests**

Add tests that exact-spawn a MELEE and hostile RANGED at 2.4 cells, assert shield activation and speed multiplier, compare one RANGED hit against `8 * 1.7 * 0.1`, verify a MELEE hit is unreduced, and move the RANGED beyond 3.0 cells to assert release. Add completed SIEGE/DRAGON spawners with forced zero spawn timers and assert the shipped defaults plus two dragons per cycle and a one-dragon partial batch at 299 population.

```gdscript
_expect(is_equal_approx(float(config.siege_production_interval), 12.342857, 0.0001), "SIEGE production throughput is forty percent faster")
_expect(is_equal_approx(float(config.siege_range), 14.0) and is_equal_approx(float(config.siege_blast_radius), 1.8), "SIEGE range and blast radius are doubled")
_expect(is_equal_approx(float(config.dragon_hp), 520.0) and is_equal_approx(float(config.dragon_damage), 36.0) and int(config.dragon_production_batch) == 2, "DRAGON batch HP and damage are doubled")
```

- [ ] **Step 2: Run rules and verify RED**

Expected failures: missing `unit_shield_modes`, old SIEGE defaults, old DRAGON HP/damage, and one dragon produced.

- [ ] **Step 3: Implement shield state, effective damage, batch production, and shader feedback**

Add `_shieldModes` and copy/clear it in spawn, reset, and swap-remove. On each staggered decision, use the hostile spatial buckets to apply enter/release hysteresis. On a RANGED attack against MELEE, activate shield before damage and multiply only that attack by `ShieldRangedDamageTakenMultiplier`. Multiply MELEE movement speed by `ShieldSpeedMultiplier` while active. Feed the flag to the infantry instance color blue channel.

In the atlas shader, composite a translucent cyan rim only when `instance_data.b > 0.5`:

```glsl
vec4 base_color = vec4(sample_color.rgb * instance_data.g, sample_color.a * instance_data.a);
float shield = step(0.5, instance_data.b);
vec2 p = UV - vec2(0.5, 0.58);
float rim = smoothstep(0.035, 0.0, abs(length(p / vec2(0.34, 0.27)) - 1.0));
vec4 shield_color = vec4(0.32, 0.86, 1.0, rim * 0.42 * shield);
COLOR = mix(base_color, vec4(mix(base_color.rgb, shield_color.rgb, shield_color.a), max(base_color.a, shield_color.a)), shield);
```

Loop `ProductionBatch(kind)` times in a spawner cycle, call `SpawnUnit` for each member, and emit one event per successful unit. Stop the loop on the first cap/placement failure.

- [ ] **Step 4: Run focused and regression tests and verify GREEN**

Run `dotnet build`, `run_rules.gd`, `run_counter_matrix.gd`, and `run_game_flow.gd`. Expected: all PASS, with the counter expectations updated to shield-aware effective damage rather than old unshielded RANGED superiority.

- [ ] **Step 5: Commit**

```bash
git add scripts tests
git commit -m "feat: add shield stance and heavy unit buffs"
```

---

### Task 3: Clearance-aware ground transitions and stuck recovery

**Files:**
- Create: `scripts/GroundNavigation.cs`
- Modify: `scripts/FlowField.cs`
- Modify: `scripts/TerrainMap.cs`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Legions.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `tests/test_flow_features.gd`

**Interfaces:**
- Consumes: current water/building/elevation arrays and dynamic unit radii.
- Produces: shared `GroundNavigation.CanTransition`, infantry/heavy team flow fields, `FlowField.NextCellAt`, SoA progress/recovery arrays, and passability-projected legion slots.

- [ ] **Step 1: Write failing physical detour tests**

Replace the query-only cliff test with an exact-spawn movement test. Use a single elevation-2 protrusion at `(22,27)`, an ally MELEE at `(22.5,30.5)`, and 210 fixed ticks. Assert it never enters the cliff cell, moves laterally by at least 0.55 cells, reaches `y < 26.5`, and never remains without 0.05 forward progress for more than 60 ticks. Add a six-member LINE legion variant and assert at least five members cross.

- [ ] **Step 2: Run flow tests and verify RED**

Expected: the unit or legion stalls at the protrusion and the physical crossing assertion fails.

- [ ] **Step 3: Implement one transition predicate, portal steering, and bounded recovery**

`GroundNavigation.CanTransition` must reject out-of-bounds cells, blocked endpoints, elevation deltas above one, and diagonal moves whose orthogonal transitions are not both executable for the selected clearance class. Build infantry and heavy masks once per flow rebuild. Store the chosen next cell in `FlowField` and steer from the current sub-cell position toward that transition's safe center.

Track actual displacement:

```csharp
if (desiredSpeed > 0.01f && movedDistance < BattleConfig.NavigationProgressEpsilon)
    _stuckTimers[index] += delta;
else
    _stuckTimers[index] = 0f;

if (_stuckTimers[index] >= _settings.StuckSeconds)
    desired = RecoveryDirection(index, SelectFlow(index));
```

`RecoveryDirection` first selects the legal lower-cost neighbor using unit-ID parity for ties, then performs a bounded queue search over a 9x9 local window only when no lower-cost adjacent transition exists. Project blocked formation slots to the nearest legal local point before calculating slot steering.

- [ ] **Step 4: Run flow, rules, and stress tests and verify GREEN**

Expected: detour and legion crossing assertions pass; existing elevation/lake tests remain green; 600-unit stress completes without allocations or NaN positions.

- [ ] **Step 5: Commit**

```bash
git add scripts tests/test_flow_features.gd
git commit -m "fix: recover ground units around cliff corners"
```

---

### Task 4: Ranged firing annulus and asymmetric friendly yielding

**Files:**
- Create: `scripts/BattleSimulation.FiringPositions.cs`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `tests/test_flow_features.gd`

**Interfaces:**
- Consumes: shared passability and flow selection from Task 3.
- Produces: SoA firing target/position/slot arrays, `shot_source_ids` in drained events, in-range lateral steering, and pairwise yield priority using existing spatial buckets.

- [ ] **Step 1: Write the failing ranged-throughput test**

Exact-spawn three durable enemy MELEE units in a line and eight ally RANGED units in a column. Over 150 ticks, drain shot events and collect `shot_source_ids`. Assert at least four distinct RANGED units fire, at least four live RANGED units simultaneously reach attack state, and their lateral x-span reaches 0.9 cells while y-span stays below 1.6 cells. Add a true single-width corridor fixture and assert WAIT remains stable without overlap or oscillation.

- [ ] **Step 2: Run flow tests and verify RED**

Expected: only the front shooter fires and lateral spread remains below 0.9.

- [ ] **Step 3: Implement deterministic firing positions and yield weights**

Sample 16 points around the target at `attackRange * PreferredFiringRangeRatio`. Reject blocked/unreachable/out-of-range candidates. Score remaining candidates by travel distance, local bucket density, angle separation from nearby same-target reservations, and flow cost. Store the winning position and slot index in SoA arrays; refresh only on the existing decision group.

In-range RANGED attackers continue to attack but also apply low-strength separation and lateral correction toward their reserved slot. When pair separation finds a stationary friendly attacker blocking a unit with an active firing reservation, give the moving unit 20% of the correction and the blocker 80%, validating both corrected positions through ground transition rules. WAIT is allowed only if no valid side slot exists.

Add source IDs alongside existing shot channels:

```csharp
_shotSourceIds[eventIndex] = sourceUnitId;
result["shot_source_ids"] = Copy(_shotSourceIds, _shotCount);
```

- [ ] **Step 4: Run movement, rules, counter, and 600-unit stress tests and verify GREEN**

Expected: at least four unique shooters form the line, corridor WAIT remains stable, all rule tests pass, and stress output contains no regression beyond the recorded target budget.

- [ ] **Step 5: Commit**

```bash
git add scripts tests/test_flow_features.gd
git commit -m "feat: form ranged firing lines in crowded combat"
```

---

### Task 5: Portrait start settings panel and copy JSON

**Files:**
- Create: `scripts/match_settings_panel.gd`
- Create: `scenes/match_settings_panel.tscn`
- Modify: `scripts/main.gd`
- Modify: `scripts/hud.gd`
- Modify: `tests/test_game_flow.gd`
- Modify: `tests/smoke_capture.gd`

**Interfaces:**
- Consumes: Task 1 bulk settings schema/get/configure API.
- Produces: `MatchSettingsPanel.open(schema, values)`, `serialize_settings(values) -> String`, signal `start_requested(values)`, and main state `match_started`.

- [ ] **Step 1: Write failing UI and serialization tests**

Add tests that instantiate main, assert the settings modal is visible, confirm simulation time does not decrease for 30 frames, verify map interaction is disabled, change a numeric field, and press START to observe the normalized C# setting. Unit-test `serialize_settings` by parsing its JSON and asserting `schema_version == 1` plus value round-trip. Check the source invokes `DisplayServer.clipboard_set` because OS clipboard reads are unreliable headlessly.

- [ ] **Step 2: Run game-flow tests and verify RED**

Expected: no settings panel exists and the timer immediately advances.

- [ ] **Step 3: Build the modal and integrate match lifecycle**

Create a full-screen dark `Control` with four tabs and one `ScrollContainer`. Build rows from the C# schema; each row contains a label, minus button, numeric editor, and plus button. Use runtime schema bounds/step/decimals. Keep `DEFAULTS`, `COPY JSON`, and `START` fixed at the bottom.

Serialization must be deterministic:

```gdscript
func serialize_settings(values: Dictionary) -> String:
	return JSON.stringify({"schema_version": 1, "settings": values}, "  ", true, true)

func _copy_settings() -> void:
	DisplayServer.clipboard_set(serialize_settings(_pending_values))
	_set_feedback("SETTINGS COPIED", GameConfig.COLOR_TEAL)
```

In `main.gd`, set `match_started = false`, disable map interaction, and skip `Step` until a successful START response. On success, clear building views/records, apply `ConfigureAndReset`, force board/render/HUD sync, enable interaction, and start. RESTART reopens the panel with the current settings instead of reloading the scene. HUD build labels and instructions use active runtime costs.

- [ ] **Step 4: Run game-flow, rules, and smoke capture and verify GREEN**

Expected: UI tests pass, existing main tests explicitly press default START, smoke capture includes `smoke_match_settings.png`, and gameplay captures are not hidden by the modal.

- [ ] **Step 5: Commit**

```bash
git add scripts scenes tests
git commit -m "feat: add copyable pre-match unit settings"
```

---

### Task 6: Regression, performance, documentation, Android artifact, and publish

**Files:**
- Modify: `tests/run_stress.gd`
- Modify: `tests/run_rules.gd`
- Modify: `README.md`
- Modify only if required: `.github/workflows/android.yml`

**Interfaces:**
- Consumes: all completed behavior and current CI export preset.
- Produces: hard-failing .NET test runners, updated stress table, visual captures, Android debug APK artifact, and pushed `main`.

- [ ] **Step 1: Harden runner preflight before claiming regression coverage**

Each runner that instantiates the simulation must explicitly fail when `Reset`, `Step`, or `GetDebugSnapshot` is missing:

```gdscript
var probe = preload("res://scenes/battle_simulation.tscn").instantiate()
if not probe.has_method("Reset") or not probe.has_method("Step") or not probe.has_method("GetDebugSnapshot"):
	push_error("BattleSimulation C# class failed to load")
	quit(1)
	return
probe.free()
```

- [ ] **Step 2: Run the complete fresh verification suite**

Run official Godot 4.5 .NET import, `dotnet build`, dotnet-port, rules, game-flow, counter matrix, AI health, balance, atlas validation, 600-unit stress, and a 180-frame main-scene smoke. Capture logs and fail if output contains `SCRIPT ERROR`, `Parse Error`, or unhandled `ERROR:`.

- [ ] **Step 3: Measure and document**

Record 600-unit average/worst tick, target/separation/event time, render snapshot time, and candidate counts before/after the new movement logic. Update README with requested balance defaults, shield behavior, settings-copy instructions, movement self-checks, exact verification commands, and any remaining measured bottleneck.

- [ ] **Step 4: Review captures**

Render and inspect the settings modal, cliff detour, ranged firing line, and shield-mode battle captures. Confirm no clipping, cyan shield readability, distinct shooters, and correct grounding.

- [ ] **Step 5: Commit test, measurement, and documentation changes**

```bash
git add tests README.md .github/workflows/android.yml
git commit -m "docs: verify movement tuning and Android build"
```

- [ ] **Step 6: Final code review and fixes**

Generate a review package from the branch merge base through HEAD, dispatch a final whole-branch reviewer, fix every Critical/Important finding, and rerun the covering tests.

- [ ] **Step 7: Build and publish Android debug APK**

Push the reviewed commits to `main`, run/monitor `.github/workflows/android.yml`, verify the successful Actions run and APK artifact, and attach the verified APK to a new GitHub release so the user has a direct `.apk` URL as well as the Actions artifact path.
