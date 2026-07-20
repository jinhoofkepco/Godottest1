# .NET Simulation Core and SIEGE Rebalance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the GDScript simulation with a fast C# core, remove per-unit GDScript render work, rebalance and visually correct SIEGE, and ship a Godot 4.5 .NET Android APK.

**Architecture:** A single C# `BattleSimulation` facade owns fixed-step rules, terrain, flow fields, spatial buckets, events, snapshots, and profiling. GDScript keeps view/HUD/FX/input and consumes only bulk snapshots.

**Tech Stack:** Godot 4.5 .NET, C#/.NET 9, GDScript view layer, PackedArrays, MultiMesh buffers, headless tests, GitHub Actions Android export.

---

### Task 1: Freeze GDScript behavior and add failing SIEGE contracts

**Files:**
- Add: `tests/fixtures/gdscript_determinism.json`
- Add/modify: `tests/test_dotnet_port.gd`
- Modify: `tests/test_rules.gd`
- Modify: `tests/validate_unit_atlas.gd`
- Modify: `scripts/game_config.gd`

- [ ] Generate fixed-seed GDScript checkpoints before altering the simulation.
- [ ] Add red tests for SIEGE upright UV flag, 3x production interval, 7.0 range, and 55.8 damage.
- [ ] Run the focused tests and record the expected failures.
- [ ] Apply only the balance constants and shader flip flag, then make focused tests green.

### Task 2: Establish the Godot .NET project and C# public facade

**Files:**
- Add: `godottest1.csproj`
- Add: `global.json`
- Add: `scripts/BattleSimulation.cs`
- Add: `scripts/BattleConfig.cs`
- Add: `scripts/BattleTypes.cs`
- Modify: `project.godot`
- Modify: `scripts/main.gd`

- [ ] Add a red smoke test that requires `[GlobalClass] BattleSimulation` and the bulk API.
- [ ] Create the .NET project targeting `net9.0` and compile with official Godot 4.5 .NET.
- [ ] Implement constants, reset state, fixed-step facade, build/query snapshots, and debug commands.
- [ ] Instantiate the C# global class from `main.gd`; keep old core available only for deterministic comparison.

### Task 3: Port terrain, flow field, and battle rules

**Files:**
- Add: `scripts/TerrainMap.cs`
- Add: `scripts/FlowField.cs`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_flow_features.gd`
- Modify: `tests/test_game_flow.gd`

- [ ] Port symmetric elevation generation, reachability, Dijkstra integration, direction caching, congestion, and building blocking.
- [ ] Port unit pools, spawning, movement, target acquisition, separation, WAIT, combat, SIEGE impacts, buildings, income, territory, AI, and terminal outcomes.
- [ ] Port spatial buckets, three-way decisions, territory interval, event channels, and profiling counters.
- [ ] Rewrite rules/flow/game-flow fixtures to use debug commands and bulk snapshots and make each slice green.

### Task 4: Determinism gate and old-core removal

**Files:**
- Modify: `tests/test_dotnet_port.gd`
- Delete: `scripts/battle_simulation.gd`
- Delete: `scripts/flow_field.gd`
- Delete: `scripts/terrain_map.gd`

- [ ] Replay the golden GDScript seed/input sequence against C# and compare checkpoints within tolerance.
- [ ] Run all rule and game-flow tests against C#.
- [ ] Delete the three GDScript simulation-core files only after determinism is green.
- [ ] Verify no live or test preload references a deleted core file.

### Task 5: Bulk render, HUD, board, and events

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/unit_renderer.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/grid.gd`
- Modify: `scripts/battle_building.gd`
- Modify: `scripts/hud.gd`
- Modify: `scripts/fx.gd`
- Modify: `tests/test_game_flow.gd`

- [ ] Add red tests that the renderer uploads C# buffers directly and contains no full-unit loop.
- [ ] Assemble sorted infantry/dragon/shadow MultiMesh buffers and compact HP bars in C#.
- [ ] Make the shared atlas shader flip SIEGE frames only; inspect a close capture upright.
- [ ] Consume HUD, board/building, and event packed snapshots with a few calls per frame.
- [ ] Remove all GDScript reads of per-unit simulation arrays.

### Task 6: Three-scale performance and visual verification

**Files:**
- Modify: `tests/run_stress.gd`
- Modify: `tests/smoke_capture.gd`
- Modify: `README.md`

- [ ] Measure 600, 1500, and 3000 units with fixed-tick average/p95/worst, snapshot assembly, subsystem totals, and GC deltas.
- [ ] Optimize the measured dominant C# path while preserving squared-distance comparisons, cached targets, pooled events, and fixed rules.
- [ ] Verify the SIEGE production/range/damage behavior for both teams and all existing balance scenarios.
- [ ] Capture and inspect upright SIEGE, large army, elevation, and impact scenes.
- [ ] Record GDScript-before/C#-after data and any remaining bottleneck in README.

### Task 7: .NET Android CI and publication

**Files:**
- Modify: `.github/workflows/android.yml`
- Modify: `export_presets.cfg` if required by .NET export
- Modify: `README.md`
- Modify: `apk/godottest1.apk`

- [ ] Install official Godot 4.5 .NET editor/templates and .NET 9 locally; run import, build, tests, stress, smoke, and debug Android export.
- [ ] Update CI to retain Android SDK/JDK setup and explicitly install the matching .NET editor/templates/toolchain.
- [ ] Commit and push source, wait for Actions, inspect failure logs if any, and rerun until green.
- [ ] Download the Actions artifact, verify APK integrity/signature, publish it at `apk/godottest1.apk`, and push the stable link.
