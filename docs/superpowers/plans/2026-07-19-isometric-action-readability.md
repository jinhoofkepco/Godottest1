# Isometric Action Readability Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Replace the top-down presentation with a readable 2:1 isometric view while preserving every game rule, then publish a verified Godot 4.5 debug APK through Actions and a stable repository link.

**Architecture:** `GridBoard` is the only logical-grid/view projection boundary. Entities simulate with continuous logical grid coordinates and update projected node positions for drawing. A Y-sorted entity layer handles body occlusion while a separate high-z FX layer handles semantic overlays.

**Tech Stack:** Godot 4.5 stable, GDScript 2D, procedural drawing, GitHub Actions, `dulvui/godot-android-export@v4.1.0`.

## Global Constraints

- Preserve all existing economy, wave, combat, core, and terminal-state values exactly.
- Keep a 9 x 14 logical grid and straight per-column enemy movement; projection math must not enter game rules.
- Use 64 x 32 2:1 diamond projection and exact inverse picking through the transformed World local space.
- Keep a 540 x 960 portrait canvas with `canvas_items` stretch and `keep` aspect.
- Use only procedural shapes and built-in controls; external assets remain zero.
- Put raised entity bodies under a Y-sorted parent and HP/range/damage/placement feedback on a higher-z overlay.
- Visually distinguish aim, fire, hit, kill, leak, placement, and wave start using the design's color and motion language.
- Preserve Android preset `Android`, output `build/godottest1.apk`, and artifact `godottest1-debug-apk`.
- Do not commit `.godot/`, `build/`, Android export caches, or temporary review files.

---

### Task 1: Isometric Projection and Picking

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/grid.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- `GridBoard.grid_to_screen(Vector2) -> Vector2`
- `GridBoard.screen_to_grid(Vector2) -> Vector2`
- `GridBoard.cell_to_world(Vector2i) -> Vector2`
- `GridBoard.world_to_cell(Vector2) -> Vector2i`
- `GridBoard.get_board_bounds() -> Rect2`
- `GridBoard.get_core_anchor() -> Vector2`

- [ ] Add projection tests for cell centers `(0,0) -> (0,16)` and `(4,7) -> (-96,192)`, continuous point round trips, diamond interior picks, all edge cell centers, and out-of-board rejection through `can_build`.
- [ ] Run `godot --headless --path . --script tests/run_rules.gd` and confirm the new projection assertions fail against the top-down implementation.
- [ ] Add projection and framing constants without modifying locked balance values.
- [ ] Replace rectangular drawing with back-to-front diamond polygons and implement the exact inverse.
- [ ] Frame and scale `World` under the HUD; convert input with `world.to_local` before inverse projection; retain a stable base world position during shake.
- [ ] Re-run the rules suite and confirm projection and picking assertions pass.

### Task 2: Logical Entities and Depth Sorting

**Files:**
- Modify: `scripts/enemy.gd`
- Modify: `scripts/tower.gd`
- Modify: `scripts/projectile.gd`
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Entities expose `grid_position: Vector2`.
- Setup methods receive `GridBoard` for projection while movement/range/delivery use grid-unit derived constants.
- `DefenseEnemy.damaged(at_grid: Vector2, amount: float)` reports semantic hits.

- [ ] Add failing tests proving enemy logical row movement, projectile logical delivery, unchanged travel/range conversions, and `EntitySort.y_sort_enabled` scene configuration.
- [ ] Convert enemy travel to logical rows while preserving pixels-per-second timing through `CELL_SIZE` conversion.
- [ ] Convert nearest-target range and projectile movement to logical distances, keeping existing damage/fire/range/speed values equivalent.
- [ ] Restructure the scene under `EntitySort`, position entity nodes at projected ground points, and draw raised silhouettes.
- [ ] Move HP rendering out of enemies so body occlusion and overlays can be tested independently.
- [ ] Re-run rule and game-flow tests and confirm gameplay rules still pass.

### Task 3: Semantic Action Feedback

**Files:**
- Modify: `scripts/tower.gd`
- Modify: `scripts/enemy.gd`
- Modify: `scripts/projectile.gd`
- Modify: `scripts/core.gd`
- Modify: `scripts/fx.gd`
- Modify: `scripts/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- `DefenseFx.show_placement(cell, is_valid, range_cells)`
- `DefenseFx.show_damage(grid_position, amount)`
- `DefenseFx.spawn_kill_burst(grid_position)`
- `DefenseFx.show_leak(from_grid, core_anchor)`
- `DefenseHud.show_wave_banner(wave)`
- `DefenseCore.flash_damage()`

- [ ] Add failing state-level assertions for placement validity feedback, wave banner state, and distinct kill/leak counters or modes.
- [ ] Implement rotating aim, idle/active color separation, synchronized recoil/muzzle flash/projectile tracer, enemy white flash/view-only knockback, and lethal shrink.
- [ ] Implement high-z projected range, selection diamond, invalid X, damage numbers, HP bars, orange kill fragments, and red leak slash.
- [ ] Add core red flash and wave-start screen-space banner; route events from Main without altering accounting order.
- [ ] Keep the approximately 60 ms kill hit-stop and existing decaying leak shake.
- [ ] Re-run both headless suites and a timed main-scene smoke run with runtime errors treated as failures.

### Task 4: Documentation, CI Guardrails, and Visual QA

**Files:**
- Modify: `README.md`
- Modify: `.github/workflows/android.yml`
- Modify: `export_presets.cfg`
- Create: `tests/smoke_capture.gd`

**Interfaces:**
- README contains one explicit line for each of fire, hit, kill, leak, placement, and wave-start feedback.
- Workflow ignores `apk/**`-only pushes.
- Android export excludes `apk/*`.

- [ ] Document controls, unchanged rules, projection boundary, the six required feedback events, Actions artifact steps, and the stable APK link.
- [ ] Add APK-only push filtering and export exclusion without changing the working Godot 4.5 debug export path.
- [ ] Add a deterministic smoke capture that places towers, starts a wave, and writes a portrait PNG after enough frames for entities to be visible.
- [ ] Run capture headlessly, inspect the PNG for full-board framing and distinct silhouettes, and fix only readability defects.
- [ ] Run `actionlint`, config inspections, `git diff --check`, and confirm no external asset file types were introduced.

### Task 5: Godot 4.5 Verification and APK Publication

**Files:**
- Create after CI: `apk/godottest1.apk`
- Modify only defects revealed by verification.

**Interfaces:**
- Source branch and final `main` pass local checks.
- Actions run succeeds and uploads `godottest1-debug-apk`.
- Stable direct URL resolves `apk/godottest1.apk` from `main`.

- [ ] Run clean `godot --headless --import`, both test suites, deterministic smoke capture, and timed main-scene smoke; require no parser/import/runtime errors.
- [ ] Commit the implementation, review the whole branch, integrate to `main`, and push source.
- [ ] Watch the new GitHub Actions run to success and download its artifact.
- [ ] Verify APK file type, package metadata, and Android v2/v3 debug signature.
- [ ] Commit the exact verified artifact to `apk/godottest1.apk`, push without triggering a redundant APK-only build, and verify the raw download URL returns the APK.
