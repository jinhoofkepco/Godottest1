# Visual Hierarchy and Unit Roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebalance melee, ranged, and dragon roles while restoring shaded sprites and a clear actor-over-board visual hierarchy.

**Architecture:** Derive combat constants from one base contract, keep targeting data-oriented, and add renderer-only timers for damaged HP bars. Bake all new 3D sources to transparent 2D atlases; simulation data and low-count building nodes remain unchanged.

**Tech Stack:** Godot 4.5 stable, GDScript, MultiMeshInstance2D, CanvasItem shaders, SubViewport 3D baking, GitHub Actions Android export.

## Global Constraints

- Preserve packed-array units and fixed 30 Hz simulation.
- Preserve CC0-only external assets and commit license files.
- Preserve portrait touch/mouse play and existing zoom/pan behavior.
- Source 3D assets must not ship in the APK.
- Run all behavior changes through a failing test before production edits.

---

### Task 1: Combat role contract

**Files:**
- Modify: `tests/test_rules.gd`
- Modify: `scripts/game_config.gd`
- Modify: `scripts/battle_simulation.gd`

**Interfaces:**
- Produces: `get_unit_detect_range(unit_kind: int) -> float`

- [ ] Add assertions for melee HP x2/damage x0.5, ranged HP x0.5/damage x1.5/range x2, and dragon range/detection x1.5.
- [ ] Run `godot --headless --path . -s tests/run_rules.gd` and confirm ratio failures.
- [ ] Add derived constants and per-kind bucket radius/detection filtering.
- [ ] Re-run rules and confirm all targeting and balance paths pass.

### Task 2: Damage-only HP bars and visual contracts

**Files:**
- Modify: `tests/test_game_flow.gd`
- Modify: `scripts/unit_renderer.gd`
- Modify: `scripts/game_config.gd`

**Interfaces:**
- Produces: `get_hp_bar_alpha(unit_id: int) -> float`

- [ ] Add tests that full-health units return zero alpha, damage resets visibility to one, and 3.0 seconds causes fade to zero.
- [ ] Run `godot --headless --path . -s tests/run_game_flow.gd` and confirm missing API failure.
- [ ] Implement renderer-only previous-HP and timer dictionaries, thin near-head bars, foot anchors, and soft 0.35-alpha shadows.
- [ ] Re-run game-flow tests.

### Task 3: Shaded infantry rebake

**Files:**
- Modify: `tools/sprite_baker/bake_sprites.gd`
- Modify: `tests/validate_unit_atlas.gd`
- Regenerate: `assets/units/infantry_blue.png`
- Regenerate: `assets/units/infantry_red.png`
- Modify: `assets/units/infantry_atlas.json`

**Interfaces:**
- Produces: two 1536x1536 shaded team atlases.

- [ ] Extend atlas validation with opaque-pixel luminance-range assertions and confirm current flat atlases fail.
- [ ] Preserve original albedo textures and tint only team-color regions/materials; keep fixed key/fill/ambient lighting.
- [ ] Re-run the baker and validator under Godot 4.5.

### Task 4: Dragon, building, and obstacle assets

**Files:**
- Create: `assets/source/quaternius_monsters/*`
- Create: `assets/source/kaykit_medieval/*`
- Create: `tools/sprite_baker/bake_world_sprites.gd`
- Create: `assets/world/world_atlas.png`
- Create: `assets/world/world_atlas.json`
- Modify: `scripts/unit_renderer.gd`
- Modify: `scripts/battle_building.gd`
- Modify: `scripts/grid.gd`
- Modify: `tests/validate_unit_atlas.gd`

**Interfaces:**
- Produces: a versioned world atlas and metadata mapping for dragon states/directions, four building kinds per team, and obstacle variants.

- [ ] Commit exact source subsets and CC0 provenance.
- [ ] Add world-atlas validation and confirm it fails before the atlas exists.
- [ ] Implement the reusable bake script and generate the atlas.
- [ ] Replace procedural dragon/building/blocker bodies with atlas regions while retaining overlays and effects.
- [ ] Validate both atlases and renderer batch invariants.

### Task 5: Muted board and frontier line

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/grid.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Consumes: packed ownership snapshot from `GridBoard._draw()`.

- [ ] Add palette contrast assertions and a frontier-segment helper test; confirm failures.
- [ ] Apply muted territory/checker/grid colors and draw thin bright ownership boundaries.
- [ ] Re-run rules and game-flow tests.

### Task 6: Visual QA, performance, docs, and APK

**Files:**
- Modify: `tests/smoke_capture.gd`
- Modify: `.github/workflows/android.yml`
- Modify: `README.md`
- Modify: `export_presets.cfg`
- Replace: `apk/godottest1.apk`

**Interfaces:**
- Produces: Godot 4.5 debug APK and `godottest1-debug-apk` Actions artifact.

- [ ] Add a visual-hierarchy capture and CI file check.
- [ ] Run Godot 4.5 import, rules, game flow, both atlas validators, 300+ stress, runtime smoke, and all captures.
- [ ] Inspect captures for shading, damaged-only bars, obstacle separation, muted board, grounding, dragon, and buildings.
- [ ] Update README metrics, visual checklist, sources, and version.
- [ ] Export and verify the signed APK, commit, push main, wait for Actions success, and publish the exact CI APK at the stable raw link.
