# Board Rendering Performance Pass 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove full-board tessellation and per-cell territory FX work by rendering immutable tile geometry once and applying ownership changes as shader-animated per-cell deltas.

**Architecture:** C# exposes a cheap board version and deduplicated board delta channel. `GridBoard` initializes one 242-instance tile MultiMesh, delegates immutable cliffs and cached frontline lines to focused child layers, and updates only changed instance colors/custom data. `DefenseFx` no longer owns territory effects.

**Tech Stack:** Godot 4.5 .NET, C# `BattleSimulation`, GDScript view/HUD/FX, `MultiMeshInstance2D`, CanvasItem shader, headless and OpenGL smoke tests, GitHub Actions Android export.

## Global Constraints

- Simulation rules and balance must not change.
- Tile transforms and cliff geometry are initialized exactly once per match.
- Ownership changes update only changed tile instances; initial sync is the only full board snapshot.
- Territory flash duration is 0.62 seconds and advances entirely in the tile shader.
- A forced 30-cell flip must render in at most 2.0 ms on the local reference machine.
- All existing tests, deterministic checks, smoke captures, and Android export must remain valid.

---

### Task 1: Freeze board delta and rendering contracts

**Files:**
- Modify: `tests/test_dotnet_port.gd`
- Modify: `tests/test_game_flow.gd`
- Create: `tests/run_board_stress.gd`

**Interfaces:**
- Consumes: existing `BattleSimulation` scene and `GridBoard` scene.
- Produces: failing expectations for `GetBoardVersion`, `GetBoardDelta`, tile MultiMesh counters, static/frontline layers, and territory FX removal.

- [ ] Add tests that require `GetBoardVersion()` and packed ownership/blocked delta arrays after a forced ownership update.
- [ ] Add live-scene tests requiring exactly 242 tile instances, immutable transform count, 30 incremental color/custom writes, and no `territory_change` object in `DefenseFx`.
- [ ] Add `run_board_stress.gd` with an old-path fallback so the pre-change 30-cell flip frame can be measured.
- [ ] Run the focused suites and confirm failures are caused by the missing delta/MultiMesh APIs.
- [ ] Record the pre-change board frame measurement for the README table.

### Task 2: Implement the C# board delta boundary

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`

**Interfaces:**
- Consumes: `_ownership`, `_blocked`, `_buildings`, `_boardVersion`.
- Produces: `int GetBoardVersion()`, `Dictionary GetBoardDelta()`, deduplicated `QueueOwnershipDelta(int)` and `QueueBlockedDelta(int)`.

- [ ] Add fixed pending-cell arrays and deduplication flags reset during `Reset()`.
- [ ] Enqueue ownership deltas in territory recomputation and debug ownership updates instead of allocating territory event dictionaries.
- [ ] Enqueue blocked deltas on building construction/destruction.
- [ ] Implement the cheap version getter and packed delta snapshot with the latest owners/blocked values and building records.
- [ ] Run the focused C# boundary tests and confirm they pass.

### Task 3: Replace full board drawing with immutable and delta layers

**Files:**
- Create: `scripts/static_terrain_layer.gd`
- Create: `scripts/frontline_layer.gd`
- Modify: `scripts/grid.gd`
- Modify: `scripts/main.gd`

**Interfaces:**
- Consumes: initial `GetBoardSnapshot()` and subsequent `GetBoardDelta()` dictionaries.
- Produces: `GridBoard.sync_initial(snapshot)`, `GridBoard.apply_board_delta(delta)`, one tile MultiMesh, static cliff layer, cached frontline layer, and instrumentation counters.

- [ ] Build a six-vertex diamond `ArrayMesh` and one 242-instance `MultiMesh` with depth-ordered immutable transforms.
- [ ] Add the tile shader for grid edge, build marker, elevation-colored ownership, and `TIME`-based flash.
- [ ] Move cliff drawing into `StaticTerrainLayer` and frontline drawing into `FrontlineLayer`.
- [ ] Implement initial sync and changed-cell updates without `queue_redraw()` on the full grid.
- [ ] Change `main.gd` to probe `GetBoardVersion()` and request initial/full versus subsequent/delta data correctly.
- [ ] Run focused rendering and picking tests and confirm they pass.

### Task 4: Remove territory FX allocation and update visual QA

**Files:**
- Modify: `scripts/fx.gd`
- Modify: `tests/smoke_capture.gd`

**Interfaces:**
- Consumes: tile custom-data flash timestamps applied by `GridBoard`.
- Produces: no CPU territory effect path and a smoke frame with active territory shader flash.

- [ ] Delete territory duration/counter, `show_territory_change`, match dispatch, and draw function from `DefenseFx`.
- [ ] Update smoke setup to force a territory delta and capture during the shader flash interval.
- [ ] Run smoke capture and inspect tile color, elevation, cliffs, frontline, and flash visibility.

### Task 5: Measure, document, verify, and publish

**Files:**
- Modify: `tests/run_stress.gd`
- Modify: `.github/workflows/android.yml`
- Modify: `README.md`
- Modify: `export_presets.cfg`

**Interfaces:**
- Consumes: board stress output and the complete test suite.
- Produces: before/after 30-cell flip table, updated Android version, successful CI artifact, and release APK.

- [ ] Run the optimized 30-cell benchmark and enforce the 2.0 ms local target.
- [ ] Run `dotnet build`, clean import, deterministic, rules, game-flow, atlas, balance, 600/1500/3000 stress, board stress, smoke capture, and main-scene smoke.
- [ ] Record exact before/after numbers and explain any remaining bottleneck in README.
- [ ] Add board stress to CI and bump Android version metadata.
- [ ] Commit, push `main`, watch Actions to success, download and verify its APK, then publish the verified binary as a GitHub Release asset.

