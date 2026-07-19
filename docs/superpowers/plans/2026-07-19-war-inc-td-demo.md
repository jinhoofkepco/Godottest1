# War Inc Style Tower Defense Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, verify, publish, and CI-export a one-match Godot 4.5 portrait tower-defense demo.

**Architecture:** A small `Main` scene composes focused grid, combat entity, wave, HUD, core, and FX scenes. Pure configuration and geometry APIs are exercised by headless tests, while an accelerated scene-flow test proves both terminal states.

**Tech Stack:** Godot 4.5 stable, GDScript 2D, GitHub Actions, `dulvui/godot-android-export@v4`.

## Global Constraints

- Use Godot 4.5 stable and GDScript only.
- Use a 540 x 960 portrait canvas with `canvas_items` stretch and `keep` aspect.
- Use only procedural shapes and built-in controls; external assets remain zero.
- Keep the locked 9 x 14 grid, economy, 20 HP core, five waves, and one tower type.
- Export preset name is `Android`; output path is `build/godottest1.apk`.
- Do not commit `.godot/`, `build/`, or export caches.

---

### Task 1: Project Rules and Grid

**Files:**
- Create: `project.godot`, `scripts/game_config.gd`, `scripts/grid.gd`, `scenes/grid.tscn`
- Test: `tests/test_rules.gd`, `tests/run_rules.gd`

**Interfaces:**
- Produces: `GameConfig.wave_enemy_count(int) -> int`, `wave_enemy_speed(int) -> float`, and `Grid.can_build(Vector2i) -> bool`, `occupy(Vector2i) -> void`, `cell_to_world(Vector2i) -> Vector2`.

- [ ] Write `tests/test_rules.gd` assertions for exact economy values, wave growth, buildable rows, occupancy, and coordinate conversion.
- [ ] Run `godot --headless --path . -s tests/run_rules.gd` and confirm failure because scripts/scenes do not exist.
- [ ] Implement the minimal project configuration, config values, and grid API/drawing.
- [ ] Re-run the rules test and confirm all assertions pass.

### Task 2: Combat Entities

**Files:**
- Create: `scripts/enemy.gd`, `scripts/tower.gd`, `scripts/projectile.gd`, `scripts/core.gd`
- Create: `scenes/enemy.tscn`, `scenes/tower.tscn`, `scenes/projectile.tscn`, `scenes/core.tscn`
- Test: extend `tests/test_rules.gd`

**Interfaces:**
- Produces: `Enemy.setup(int, float, float)`, `take_damage(float)`, `Tower.setup(Node, Node)`, `Projectile.setup(Node2D, float, float)`, and signals for defeat/core arrival.

- [ ] Add failing tests for enemy damage/removal and projectile damage delivery.
- [ ] Run the rules test and confirm missing combat APIs cause the expected failure.
- [ ] Implement procedural combat entities with nearest-target acquisition and timed shooting.
- [ ] Re-run the rules test and confirm combat assertions pass.

### Task 3: Waves, Match State, HUD, and FX

**Files:**
- Create: `scripts/wave_manager.gd`, `scripts/hud.gd`, `scripts/fx.gd`, `scripts/main.gd`
- Create: `scenes/wave_manager.tscn`, `scenes/hud.tscn`, `scenes/fx.tscn`, `scenes/main.tscn`
- Test: `tests/test_game_flow.gd`, `tests/run_game_flow.gd`

**Interfaces:**
- Produces: `WaveManager.start_next_wave()`, `notify_enemy_removed()`, `Main.try_place_tower(Vector2i) -> bool`, `start_next_wave()`, plus HUD signals `next_wave_pressed` and `restart_pressed`.

- [ ] Write an accelerated scene test that places three towers, kills spawned enemies through all five waves, and asserts victory; create a second main instance and apply 20 core hits to assert defeat.
- [ ] Run the flow test and confirm failure because the main flow is missing.
- [ ] Implement wave spawning, economy, terminal states, procedural HUD, fragments, hit-stop, flash, and screen shake.
- [ ] Re-run rules and flow tests and confirm both pass.

### Task 4: Android Export and Documentation

**Files:**
- Create: `export_presets.cfg`, `.github/workflows/android.yml`, `.gitignore`, `README.md`

**Interfaces:**
- Produces: Android preset `Android`, output `build/godottest1.apk`, artifact `godottest1-debug-apk`.

- [ ] Add the Android preset with portrait/package/architecture settings.
- [ ] Add a workflow that generates a temporary debug keystore, invokes `dulvui/godot-android-export@v4` with `godot-version: 4.5` and `godot-channel: stable`, then uploads the APK.
- [ ] Document local controls, verification points, and Actions artifact download steps.
- [ ] Run a YAML/config inspection and `git diff --check`.

### Task 5: Final Verification and Publish

**Files:**
- Verify all project files; modify only defects revealed by verification.

**Interfaces:**
- Produces: private repository `github.com/jinhoofkepco/godottest1` on `main` with a successful Android workflow run.

- [ ] Run `godot --headless --path . --import` and require exit 0 with no script/import errors.
- [ ] Run both headless test suites and a timed main-scene smoke run; require exit 0 and no runtime errors.
- [ ] Initialize Git on `main`, commit intentional project files, create the private remote if absent, and push.
- [ ] Watch the Android workflow to completion, confirm `build/godottest1.apk` was uploaded as an artifact, and report the run URL.

