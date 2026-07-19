# Frontline Battle Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the tower-defense loop with a 300+ unit, fixed-tick, two-army frontline simulation and publish the verified Godot 4.5 Android APK.

**Architecture:** `BattleSimulation` owns data-only unit arrays, buildings, territory, economy, AI, and results. `GridBoard` remains the sole isometric conversion boundary; `UnitRenderer` batches units into two MultiMeshes, while low-count building nodes, HUD, and FX render model snapshots/events.

**Tech Stack:** Godot 4.5 stable, GDScript, `Packed*Array`, `MultiMeshInstance2D`, procedural `ArrayMesh`, GitHub Actions, Xvfb, Android debug export.

## Global Constraints

- Use an 11 x 22 logical grid and keep `GridBoard` projection/inverse formulas unchanged.
- Units are pure data and must never be `Node`, `Node2D`, scene instances, or individual signal/process owners.
- Use a 30 Hz fixed simulation step and grid buckets for local target search; no O(n²) all-pairs target scan.
- Render units with exactly one blue and one red `MultiMeshInstance2D`.
- Keep Godot 4.5, GDScript, 540 x 960 portrait, touch/mouse input, and zero external assets.
- Match duration is 180 seconds; HQ destruction, 90% territory, or timeout comparison ends the match.
- All tuning values live in `GameConfig` or exported view-only timing variables.
- Preserve workflow artifact `godottest1-debug-apk`, export output `build/godottest1.apk`, and direct repository APK path `apk/godottest1.apk`.

---

### Task 1: Data-Only Simulation Core

**Files:**
- Modify: `scripts/game_config.gd`
- Create: `scripts/battle_simulation.gd`
- Rewrite: `tests/test_rules.gd`
- Keep: `tests/run_rules.gd`

**Interfaces:**
- Produces: `BattleSimulation.reset()`, `tick(delta)`, `spawn_unit(team, position)`, `add_building(team, kind, cell)`, `try_build_spawner(team, cell)`, `get_ownership()`, `get_occupancy(team)`, `drain_events()`.
- Produces public packed arrays: `unit_ids`, `unit_teams`, `unit_positions`, `unit_hp`, `unit_states`, `unit_target_ids`, `unit_cooldowns`.

- [ ] Replace old rule assertions with failing tests for exact 11 x 22 constants, initial 50% split, fixed tick, packed-array unit insertion, 60-gold build cost, passive income, kill reward, HQ/90%/timeout terminal results, and adjacent-bucket target acquisition.
- [ ] Run `godot --headless --path . -s tests/run_rules.gd`; require RED because `BattleSimulation` does not exist.
- [ ] Add the constants from the design verbatim to `GameConfig`, removing tower/wave-only constants and keeping colors/projection constants.
- [ ] Implement `BattleSimulation` with structure-of-arrays storage, swap-removal, ID-index rebuilding, per-cell unit buckets, melee movement/attack, building/HQ records, passive economy, deterministic red AI, event queue, and terminal evaluation.
- [ ] Add an explicit diagnostic counter `target_candidate_checks` reset each tick; test a 360-unit separated formation stays far below `n * n` candidate checks.
- [ ] Re-run the rules suite and require `RULE TESTS PASS`; commit simulation and tests.

### Task 2: Territory-Aware Grid and Batched Unit Rendering

**Files:**
- Modify: `scripts/grid.gd`
- Create: `scripts/unit_renderer.gd`
- Create: `scenes/unit_renderer.tscn`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Consumes: `BattleSimulation.unit_teams`, `unit_positions`, `unit_hp`, `get_ownership()`.
- Produces: `GridBoard.set_territory(PackedByteArray)`, `set_occupied_cells(Array[Vector2i])`, `can_build(Vector2i, int)`, `pulse_territory_cells(PackedInt32Array)`.
- Produces: `UnitRenderer.setup(GridBoard, BattleSimulation)`, `sync_instances()` and exactly two MultiMesh children.

- [ ] Add failing tests proving projection round trips are unchanged for 11 x 22, blue/red build validation follows current ownership, occupied/HQ cells reject builds, and the renderer scene has exactly two `MultiMeshInstance2D` nodes with no per-unit children.
- [ ] Change only GridBoard dimensions/color ownership/build validation and retain the existing projection/inverse function bodies byte-for-byte.
- [ ] Build one procedural `ArrayMesh` raised soldier silhouette and assign it to two color-enabled MultiMeshes; resize and write instance transforms after approximate projected-Y sort per team.
- [ ] Verify renderer synchronization for 360 packed units without creating child nodes, run rules, and commit.

### Task 3: Buildings, Match Integration, HUD, and Six FX Categories

**Files:**
- Create: `scripts/battle_building.gd`, `scenes/battle_building.tscn`
- Rewrite: `scripts/main.gd`, `scripts/hud.gd`, `scripts/fx.gd`
- Rewrite: `scenes/main.tscn`, `scenes/hud.tscn`, `scenes/fx.tscn`
- Delete: `scripts/enemy.gd`, `tower.gd`, `projectile.gd`, `wave_manager.gd`, `core.gd` and their `.uid` files
- Delete: `scenes/enemy.tscn`, `tower.tscn`, `projectile.tscn`, `wave_manager.tscn`, `core.tscn`
- Rewrite: `tests/test_game_flow.gd`

**Interfaces:**
- `BattleBuilding.bind_model(simulation, building_id, grid)` renders snapshot state only.
- `BattleFx.consume_events(events, grid)` maps hit, death, spawn, building hit/destroy, territory, and HQ hit events to distinct overlays.
- `BattleHud.update_state(gold, ally_hq, enemy_hq, time_left, ally_share)` and result/restart APIs.
- `BattleMain.try_build_spawner(cell) -> bool` is the touch/mouse entry point.

- [ ] Add failing flow tests showing no blue spawner reaches defeat, active blue reinforcement reaches victory, occupancy HUD equals model occupancy, invalid/red/occupied tile taps do not spend gold, and restart/result state works.
- [ ] Replace the main scene with Grid, UnitRenderer, Buildings, high-z FX, and HUD; accumulate render delta into 30 Hz ticks with an eight-tick catch-up cap.
- [ ] Synchronize low-count building nodes by building ID and remove them after the collapse display completes; keep building combat authority in the model.
- [ ] Implement the HUD gold/HQ/time/occupancy bar and immediate result overlay.
- [ ] Implement all six feedback categories and route HQ hit events to strong flash plus base-position-preserving shake.
- [ ] Remove all old combat/wave scripts/scenes and verify `rg` finds no preload, scene reference, per-unit node, or old wave API.
- [ ] Run rules, flow, and 180-frame main smoke; commit.

### Task 4: Stress Benchmark, Three Visual Captures, and Documentation

**Files:**
- Create: `tests/test_stress.gd`, `tests/run_stress.gd`
- Rewrite: `tests/smoke_capture.gd`
- Modify: `.github/workflows/android.yml`
- Rewrite: `README.md`

**Interfaces:**
- Stress output: `STRESS PASS units=<count> avg_ms=<value> max_ms=<value> checks=<count>` for at least 360 living units.
- Capture outputs: `build/smoke_opening.png`, `build/smoke_advantage.png`, `build/smoke_disadvantage.png`, each exactly 540 x 960.

- [ ] Write a benchmark that creates 360+ opposing units, runs warm-up ticks plus 300 measured ticks with `Time.get_ticks_usec()`, asserts average below 16.67 ms, and reports average/max/candidate checks.
- [ ] Rewrite capture setup to save opening, forced blue-advantage, and forced blue-disadvantage states without external assets or interactive input.
- [ ] Extend CI headless verification with `run_stress.gd`; extend Xvfb QA to assert all three PNG dimensions.
- [ ] Rewrite README with controls/rules/architecture, measured stress result and environment, APK paths, and one self-verification line for each of the six event categories.
- [ ] Run actionlint, rules, flow, stress, headless smoke, local three-shot capture, asset scan, and diff checks; inspect all three PNGs; commit.

### Task 5: Godot 4.5 CI and APK Publication

**Files:**
- Replace after CI: `apk/godottest1.apk`
- Modify only defects revealed by verification.

**Interfaces:**
- Successful Actions run on the source commit with artifact `godottest1-debug-apk`.
- Stable raw URL: `https://raw.githubusercontent.com/jinhoofkepco/Godottest1/main/apk/godottest1.apk`.

- [ ] Run clean local import, rules, flow, stress, headless smoke, three render captures, actionlint, diff checks, and final whole-branch review.
- [ ] Fast-forward the reviewed feature branch into `main`, repeat merged verification, and push source.
- [ ] Watch the Godot 4.5 Actions run through stress, three Xvfb captures, debug export, and artifact upload.
- [ ] Download the artifact; verify package ID, v2/v3 debug signature, file type, and SHA-256.
- [ ] Replace `apk/godottest1.apk` with the exact verified artifact, push the APK-only commit, and authenticated-download the raw URL to confirm byte equality.
