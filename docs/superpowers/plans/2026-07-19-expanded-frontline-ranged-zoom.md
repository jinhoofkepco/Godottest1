# Expanded Frontline, Ranged Units, and Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a 22×44 persistent-territory frontline with zero camera shake, edge-to-HQ routing, deterministic blocked terrain, selectable melee/ranged spawners, and mobile/desktop zoom-pan controls.

**Architecture:** Keep all combat and territory state in `BattleSimulation` structure-of-arrays data. Add a low-count `MapView` node for view transforms/gestures, four team×kind MultiMeshes for batched units, and HUD selection signals. Persistent ownership is changed only by active supply-line claims, never rebuilt from defaults.

**Tech Stack:** Godot 4.5 stable, GDScript, 2D procedural drawing, PackedArrays, MultiMeshInstance2D, GitHub Actions Android debug export.

## Global Constraints

- No external or generated assets.
- No per-unit Node, signal, or `_physics_process` instances.
- Simulation remains fixed at 30 Hz and uses logical `(col,row)` coordinates.
- Map is exactly 22×44; match limit remains 180 seconds.
- Zoom is view-only and must not leak screen coordinates into simulation.
- All screen shake offsets are exactly zero.

---

### Task 1: Persistent territory, expanded grid, obstacles, and HQ fallback

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/battle_simulation.gd`
- Modify: `scripts/grid.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Produces: `BattleSimulation.is_blocked(cell: Vector2i) -> bool`
- Produces: `BattleSimulation.get_blocked_cells() -> PackedByteArray`
- Produces: persistent `ownership` updates through `recalculate_territory(emit_changes := true)`
- Consumes: unchanged `GridBoard.grid_to_screen`, `screen_to_grid`, and `world_to_cell`

- [ ] **Step 1: Write failing map and obstacle tests**

Add assertions for 22×44, 968 ownership entries, 32 deterministic mirrored blockers, reserved clear HQ/spawner rows, and blocked build rejection:

```gdscript
_expect(config.GRID_COLUMNS == 22 and config.GRID_ROWS == 44, "expanded grid has four times the tiles")
var blocked := simulation.get_blocked_cells()
_expect(blocked.count(1) == 32, "central terrain has sixteen mirrored obstacle pairs")
for cell in [Vector2i(11, 0), Vector2i(11, 43), Vector2i(4, 36)]:
    _expect(not simulation.is_blocked(cell), "reserved deployment cells stay clear")
```

- [ ] **Step 2: Run rules and confirm RED**

Run: `godot --headless --path . -s tests/run_rules.gd`

Expected: failures for old 11×22 dimensions and missing blocker APIs.

- [ ] **Step 3: Implement deterministic expanded terrain**

Set grid constants to 22×44, add obstacle seed/pair/band/steering constants, create `blocked: PackedByteArray`, and generate mirrored pairs without exceeding four blockers per row. Make `try_build_spawner`, `GridBoard.can_build`, and movement reject blocked cells. Draw blockers as raised neutral diamonds in `GridBoard._draw()`.

- [ ] **Step 4: Write failing persistent-territory and edge-HQ tests**

Use a forward blue unit to claim column 4, move it to column 5, recalculate, and assert the old blue supply line persists. Then advance red through one captured cell and assert recapture. Place an ally at `(0.5, 0.5)`, tick, and assert its target is `-enemy_hq_id` and x increases.

- [ ] **Step 5: Run rules and confirm RED**

Expected: old column resets and edge unit retains target id 0.

- [ ] **Step 6: Implement persistent claims and HQ fallback**

Change territory updates to mutate prior ownership only where active red/blue supply ranges claim. Resolve overlapping active claims at their midpoint. After local detection returns no target, assign the opposing HQ in the terminal band. Add obstacle repulsion plus full/x/y slide movement so no final unit position occupies a blocker.

- [ ] **Step 7: Verify Task 1 and commit**

Run:

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
git diff --check
```

Commit: `feat: expand persistent obstacle frontline`

---

### Task 2: Data-oriented ranged spawners and combat

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/battle_simulation.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Produces: `UNIT_MELEE := 0`, `UNIT_RANGED := 1`
- Produces: aligned `unit_kinds: PackedInt32Array`
- Changes: `spawn_unit(team, position, unit_kind := UNIT_MELEE) -> int`
- Changes: `try_build_spawner(team, cell, unit_kind := UNIT_MELEE) -> bool`
- Building dictionaries gain `unit_kind`.

- [ ] **Step 1: Write failing ranged-data tests**

Assert ranged build costs 80, produced units retain `UNIT_RANGED`, packed arrays remain aligned after swap-removal, and a ranged unit hits at distance 2.0 while a melee unit cannot.

```gdscript
_expect(simulation.try_build_spawner(simulation.TEAM_ALLY, cell, simulation.UNIT_RANGED), "ranged spawner builds")
_expect(simulation.ally_gold == GameConfig.START_GOLD - GameConfig.RANGED_SPAWNER_COST, "ranged cost is charged")
_expect(simulation.unit_kinds[0] == simulation.UNIT_RANGED, "spawner produces selected kind")
```

- [ ] **Step 2: Run rules and confirm RED**

Expected: missing constants, method parameters, packed kind array, and ranged-distance attack.

- [ ] **Step 3: Implement kind-specific data and stats**

Append/swap/resize `unit_kinds`; use helper functions for max HP, speed, range, damage, and interval. Store spawner `unit_kind`, make production pass it to `spawn_unit`, and alternate AI kinds based on build cursor while checking the correct cost.

- [ ] **Step 4: Add ranged event contract**

For ranged attacks append:

```gdscript
{"type": "ranged_shot", "team": attacker_team, "origin": unit_positions[attacker_index], "position": target_position}
```

Keep the normal `hit` event so damage feedback remains shared.

- [ ] **Step 5: Verify Task 2 and commit**

Run rules and stress. Commit: `feat: add selectable ranged simulation units`

---

### Task 3: Four-way batched rendering, ranged FX, and zero shake

**Files:**
- Modify: `scripts/unit_renderer.gd`
- Modify: `scripts/battle_building.gd`
- Modify: `scripts/fx.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- `UnitRenderer.get_multimesh_count() -> int` returns 4.
- Produces: `DefenseFx.show_ranged_shot(origin: Vector2, target: Vector2, team: int)`.
- Keeps: `DefenseFx.get_screen_shake_offset() -> Vector2`, always zero for compatibility.

- [ ] **Step 1: Write failing renderer/FX/no-shake tests**

Assert four MultiMeshes, no per-unit children after spawning both kinds, ranged feedback counter increments, and hit/destruction offsets remain exactly zero before and after `_process` samples.

- [ ] **Step 2: Run game flow and confirm RED**

Expected: renderer count 2, missing ranged feedback, and nonzero HQ shake.

- [ ] **Step 3: Implement procedural ranged presentation**

Create melee/ranged ArrayMeshes once, create red/blue instance batches for each, and sync by team and kind. Draw ranged HP bars using ranged max HP. Add building production marks and a cyan-white hitscan tracer plus endpoint spark.

- [ ] **Step 4: Remove shake producer and consumer**

Remove trauma/cooldown/phase state and shake exports from `fx.gd`; keep HQ flash effects. Make `get_screen_shake_offset()` return `Vector2.ZERO`. Stop adding any FX offset to World in `main.gd`.

- [ ] **Step 5: Verify Task 3 and commit**

Run game flow and rules. Commit: `feat: render ranged squads without camera shake`

---

### Task 4: Selectable HUD and zoomable/pannable map view

**Files:**
- Create: `scripts/map_view.gd`
- Modify: `scenes/main.tscn`
- Modify: `scripts/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- `MapView` signals `tile_tapped(cell: Vector2i)`.
- `MapView.setup(board: GridBoard, frame_rect: Rect2) -> void`
- `MapView.set_zoom_at(value: float, screen_focus: Vector2) -> void`
- `MapView.pan_by(delta: Vector2) -> void`
- `MapView.screen_to_cell(screen_position: Vector2) -> Vector2i`
- `DefenseHud` signal `spawner_kind_selected(unit_kind: int)`.

- [ ] **Step 1: Write failing view-transform tests**

Instantiate Main, assert default zoom 1.35, set zoom at a known tile center and verify that focus maps back to the same cell, pan by a large delta and assert clamped board intersection, then call `screen_to_cell` after zoom/pan and assert exact picking.

- [ ] **Step 2: Write failing HUD selection test**

Select ranged through HUD, tap an owned cell, and assert the new building has `unit_kind == UNIT_RANGED` and gold decreased by 80.

- [ ] **Step 3: Run game flow and confirm RED**

Expected: missing `MapView`, selection signal/buttons, and typed build path.

- [ ] **Step 4: Implement MapView**

Move fit/center math from Main into `MapView`. Add wheel zoom, mouse drag, stationary-click emission, touch tracking, pinch zoom/midpoint pan, 10 px drag suppression, and frame-bound clamping. Keep all picking through World inverse transform plus `GridBoard.world_to_cell`.

- [ ] **Step 5: Implement HUD selector and Main wiring**

Create MELEE 60/RANGED 80 buttons, selection styling, and signal. Main stores selected kind, connects `MapView.tile_tapped`, and passes the kind to simulation.

- [ ] **Step 6: Verify Task 4 and commit**

Run game flow and the main scene smoke. Commit: `feat: add spawner selection and map zoom controls`

---

### Task 5: Balance, visual QA, documentation, and Android delivery

**Files:**
- Modify: `tests/test_rules.gd`
- Modify: `tests/run_stress.gd`
- Modify: `tests/smoke_capture.gd`
- Modify: `.github/workflows/android.yml` only if capture names change
- Modify: `README.md`
- Modify: `export_presets.cfg`
- Replace after CI: `apk/godottest1.apk`

**Interfaces:**
- Smoke outputs: `smoke_overview.png`, `smoke_zoomed_mixed.png`, `smoke_persistent_flank.png`, `smoke_obstacle_cluster.png`.

- [ ] **Step 1: Update deterministic balance fixtures**

Use config-relative cells on the 22×44 map. Verify no-spawner defeat and a mixed melee/ranged player build victory both end in 120–180 seconds. Tune only the values allowed by the design.

- [ ] **Step 2: Re-run 400-unit stress and update its gate/result**

Distribute 400 units using `GameConfig.GRID_COLUMNS` and central-row-relative ranks. Record average, p95, maximum, and candidate count in README without hiding outliers.

- [ ] **Step 3: Replace smoke scenarios and inspect images**

Generate the four required 540×960 captures, verify file dimensions, and visually inspect overview, zoomed ranged tracers, persistent flank, and obstacle navigation cluster.

- [ ] **Step 4: Update docs and APK version**

Document controls, unit table, persistent territory, obstacle behavior, zero shake, test commands, balance paths, and stress evidence. Bump Android version to `0.4.0`, code 3.

- [ ] **Step 5: Run full verification**

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --headless --path . -s tests/run_stress.gd
godot --headless --path . --scene res://scenes/main.tscn --quit-after 180
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
git diff --check
```

- [ ] **Step 6: Review, merge, push, and publish APK**

Request independent code review, fix Critical/Important findings, merge to main, repeat verification, push, monitor Godot 4.5 Actions, download and verify package/version/signature, replace `apk/godottest1.apk`, and push the APK-only commit.
