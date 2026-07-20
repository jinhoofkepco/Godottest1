# Siege and Army Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add radius-scaled armies and delayed bucket-based SIEGE AoE combat, fix upside-down dragons, and publish a verified Godot 4.5 APK.

**Architecture:** Keep every unit and siege impact as simulation data. Extend the existing team buckets for target density and AoE, then project events into the existing batched renderer and overlay FX layer.

**Tech Stack:** Godot 4.5 stable, GDScript, MultiMeshInstance2D, shader atlas selection, headless tests, GitHub Actions Android export.

## Global Constraints

- No per-unit Node instances.
- SIEGE AoE must query spatial buckets rather than scan all units.
- Unit radius is the render and collision-spacing source of truth.
- Match duration remains 180 seconds and both outcomes stay reachable.
- Assets remain CC0 and keep their license files.

---

### Task 1: Lock radius and dragon orientation contracts

**Files:** `tests/test_rules.gd`, `tests/test_game_flow.gd`, `scripts/game_config.gd`, `scripts/unit_renderer.gd`

- [ ] Add failing tests for four radii, pair separation distance, radius-inclusive attack contact, radius-derived rendering, and a negative dragon transform Y basis.
- [ ] Run rules/game-flow tests and confirm failures identify missing radius/SIEGE constants and the positive dragon Y basis.
- [ ] Add the balance constants and minimally flip dragon transforms vertically.
- [ ] Re-run both tests and commit the isolated dragon fix with the radius contract.

### Task 2: Add packed SIEGE production and delayed combat

**Files:** `tests/test_rules.gd`, `tests/test_flow_features.gd`, `scripts/battle_simulation.gd`, `scripts/game_config.gd`

- [ ] Add failing tests for SIEGE build cost/kind, minimum range, densest-bucket target, delayed impact, falloff, target-radius inclusion, five-target splash, friendly-fire exclusion, building damage, and enemy AI cycling SIEGE.
- [ ] Add `UNIT_SIEGE`, `BUILD_SIEGE_SPAWNER`, pending-impact data, and public deterministic test helpers.
- [ ] Select targets from hostile bucket density, schedule impacts, and resolve unit damage using only intersecting buckets.
- [ ] Apply elevation damage at launch, resolve hostile building damage, emit projectile/impact events, and verify RED becomes GREEN.

### Task 3: Derive movement spacing and view scale from radius

**Files:** `scripts/battle_simulation.gd`, `scripts/unit_renderer.gd`, `scripts/game_config.gd`, `tests/test_rules.gd`, `tests/test_game_flow.gd`

- [ ] Replace fixed separation radius with pair-radius spacing and include target radius in normal attack/static defense checks.
- [ ] Expose render size, shadow size, foot anchor, HP-bar width, and death scale from `get_unit_radius`.
- [ ] Keep all ground kinds in one Y-sorted batch and dragons in two team batches.
- [ ] Run rule and game-flow regressions.

### Task 4: Bake and integrate the SIEGE atlas

**Files:** `tools/sprite_baker/bake_siege_sprites.gd`, `tools/sprite_baker/README.md`, `assets/units/siege_blue.png`, `assets/units/siege_red.png`, `assets/units/siege_atlas.json`, `tests/validate_unit_atlas.gd`, `scripts/unit_renderer.gd`

- [ ] Add atlas metadata validation that fails before generated files exist.
- [ ] Bake the vendored KayKit blue/red catapult sources at eight headings with idle/walk/attack frame contracts and transparent cells.
- [ ] Load both textures into the ground texture array and map SIEGE direction/state/frame custom data.
- [ ] Validate dimensions, transparency, non-empty cells, direction differences, and runtime batch selection.

### Task 5: Add readable artillery FX and five-way HUD

**Files:** `scripts/fx.gd`, `scripts/main.gd`, `scripts/hud.gd`, `tests/test_game_flow.gd`

- [ ] Add failing feedback counters/state tests for launch telegraph and impact explosion.
- [ ] Draw a duration-persistent landing ring, arcing projectile, linear ground shadow, impact flash, and earth fragments.
- [ ] Route simulation events through main and add a SIEGE 140 selector button/instruction.
- [ ] Verify all five controls fit portrait width and remain touchable.

### Task 6: Balance, capture, and stress

**Files:** `tests/test_rules.gd`, `tests/run_stress.gd`, `tests/smoke_capture.gd`, `README.md`, `.github/workflows/android.yml`, `export_presets.cfg`

- [ ] Encode and run equal-cost clustered/spread melee vs SIEGE, close-melee vs SIEGE, dragon vs SIEGE, and enemy mixed-build scenarios.
- [ ] Tune only listed combat/production/income/cost constants within 20 percent while preserving the 180-second result routes.
- [ ] Raise stress to 600 mixed units, exercise impacts, record average/p95/max/candidates, and keep bucket bounds explicit.
- [ ] Add large-army and SIEGE-impact 540x960 captures and verify the telegraph visually.
- [ ] Update README, version code/name, and CI capture checks.

### Task 7: Verify and publish

**Files:** `apk/godottest1.apk`

- [ ] Run Godot 4.5 import, rules, game-flow, atlas, 600-unit stress, runtime scene, and all smoke captures.
- [ ] Review the complete diff and run `git diff --check`.
- [ ] Push `main`, wait for the exact commit's Android workflow, and inspect every job step.
- [ ] Download the Actions artifact, verify ZIP digest plus APK signature/package/version, replace the direct-download APK, push it, and confirm the remote hash from a fresh clone.
