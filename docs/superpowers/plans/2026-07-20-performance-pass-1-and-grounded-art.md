# Performance Pass 1 and Grounded Art Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reach the 600-unit GDScript performance budgets while preserving rules and correcting the SIEGE and building grounding visuals.

**Architecture:** Keep fixed-tick packed simulation data, cache expensive decisions across three round-robin groups, cache territory/occupancy, move high-frequency feedback through packed channels, and upload MultiMeshes with one interleaved buffer assignment. Re-bake only the SIEGE cart and world atlas metadata; gameplay values remain unchanged.

**Tech Stack:** Godot 4.5 stable, GDScript, PackedArrays, MultiMeshInstance2D, CC0 KayKit source models, headless rule/stress runners, GitHub Actions Android export.

## Global Constraints

- Combat rules, balance constants, deterministic seed, and win/loss results remain unchanged.
- Fixed simulation tick remains 30 Hz; movement, cooldowns, attack validation, and damage run every tick.
- `TERRITORY_UPDATE_INTERVAL` is 0.2 seconds, `DECISION_GROUP_COUNT` is 3, and `FX_MAX_PER_FRAME` is 40.
- No per-unit Nodes may be introduced.
- Android remains portrait and uses the `gl_compatibility` renderer.

---

### Task 1: Profiling and regression contracts

**Files:**
- Modify: `tests/run_stress.gd`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_game_flow.gd`
- Modify: `scripts/battle_simulation.gd`

**Interfaces:**
- Produces: `profile_target_usec`, `profile_separation_usec`, `profile_territory_usec`, `profile_event_usec`, `profile_tick_usec`, `profile_tick_count`, and `reset_profile_counters()`.

- [ ] Add tests asserting the profiling fields and reset method exist; run `godot --headless --path . -s tests/run_rules.gd` and confirm the missing-field failure.
- [ ] Add `Time.get_ticks_usec()` boundaries around the existing work without changing its order or frequency.
- [ ] Extend `run_stress.gd` to instantiate the main scene, measure `unit_renderer.sync()`, and print average/worst totals plus subsystem averages.
- [ ] Run the exact 600-unit fixture and save its output as the pre-optimization row.

### Task 2: Territory and occupancy cache

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/battle_simulation.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Produces: `request_territory_update(force := false)`, cached `_ally_occupancy`, and `_territory_update_timer`.

- [ ] Add failing tests proving ownership is unchanged before 0.2 seconds, refreshed at the interval, and immediately refreshed after building creation/destruction.
- [ ] Add `TERRITORY_UPDATE_INTERVAL := 0.2` and update front rows from non-empty bucket indices plus building records.
- [ ] Count ownership once per territory pass and make `get_occupancy(team)` return the cached ratio.
- [ ] Run the rules suite and confirm territory and terminal-state scenarios remain green.

### Task 3: Three-way decision staggering

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/battle_simulation.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Produces packed `unit_cached_target_positions`, `unit_cached_target_radii`, `unit_cached_steering`, and `unit_cached_waiting`; consumes unit id modulo `DECISION_GROUP_COUNT`.

- [ ] Add failing tests that observe exactly one rotating decision group while cooldown, movement, and valid cached attacks still update every tick.
- [ ] Append, swap-remove, and resize every new packed field with existing unit lifecycle arrays.
- [ ] Split decision refresh from per-tick target validation/integration; retain the exact attack range/radius and SIEGE minimum-range rules.
- [ ] Re-run cross-column combat, separation, WAIT, terrain, SIEGE, and balance tests.

### Task 4: Packed event transfer and FX budgets

**Files:**
- Modify: `scripts/battle_simulation.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/fx.gd`
- Modify: `scripts/unit_renderer.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- Produces: `drain_event_channels() -> Dictionary`, `UnitRenderer.note_damage(unit_id)`, `DefenseFx.begin_frame()`, and `minor_effects_dropped_this_frame`.

- [ ] Add failing tests for swap-drained structural arrays, packed hit/shot/death arrays, damage-triggered HP timers, 40-minor-effect cap, and SIEGE/HQ exemption.
- [ ] Replace dictionary creation at every hit/shot/death site with parallel PackedArray appends; keep low-frequency dictionaries shallow and swap them on drain.
- [ ] Consume the channel bundle in `DefenseMain`, calling `note_damage` only for hit unit ids.
- [ ] Reset the FX frame counter once per `step_simulation` and reject only minor effects beyond `FX_MAX_PER_FRAME`.

### Task 5: MultiMesh bulk buffers

**Files:**
- Modify: `scripts/unit_renderer.gd`
- Modify: `tests/test_game_flow.gd`
- Modify: `tests/run_stress.gd`

**Interfaces:**
- Produces: `_upload_multimesh(multimesh, transforms, colors, custom_data)` and `last_sync_usec`.

- [ ] Add a failing test that compares one uploaded transform/color/custom record with the prior expected values and asserts one buffer assignment path is exposed.
- [ ] Build 2D MultiMesh records in order `[x.x, x.y, 0, origin.x, y.x, y.y, 0, origin.y, color rgba, custom rgba]`, omitting disabled blocks according to flags.
- [ ] Bulk upload infantry, both dragon teams, and shadows while retaining Y ordering and animation selection.
- [ ] Measure renderer average/worst milliseconds in the 600-unit stress run.

### Task 6: Mobile SIEGE and grounded buildings

**Files:**
- Modify: `tools/sprite_baker/bake_siege_sprites.gd`
- Modify: `tools/sprite_baker/bake_world_sprites.gd`
- Modify: `assets/units/siege_blue.png`
- Modify: `assets/units/siege_red.png`
- Modify: `assets/units/siege_atlas.json`
- Modify: `assets/world/world_atlas.json`
- Modify: `scripts/battle_building.gd`
- Modify: `tests/validate_unit_atlas.gd`
- Modify: `tests/smoke_capture.gd`

**Interfaces:**
- Produces SIEGE metadata `silhouette: mobile_wheeled_catapult` and per-world-sprite `opaque_bounds`; `BattleBuildingView.get_ground_contact_y()` exposes the resolved contact line for tests.

- [ ] Add failing atlas validation for a mobile-catapult marker, nonempty directional silhouettes, and opaque bounds for all ten building frames.
- [ ] Strip the CC0 tower base mesh, lower its catapult turret onto a procedural cart, add four wheels, and bake all states/directions.
- [ ] Calculate and write static-frame opaque bounds during world baking.
- [ ] Place each building's opaque bottom on the contact line and draw a contact shadow/plinth below it.
- [ ] Capture close SIEGE and building-grounding smoke images and inspect them at original resolution.

### Task 7: Full regression, report, and APK

**Files:**
- Modify: `README.md`
- Modify: `.github/workflows/android.yml` only if the new smoke file list requires it
- Modify: `apk/godottest1.apk`

**Interfaces:**
- Consumes all prior verification output; produces the GitHub Actions `godottest1-debug-apk` artifact and repository APK.

- [ ] Run import, rules, game flow, atlas validation, 600-unit stress, main-scene smoke, and screenshot capture with no errors.
- [ ] Record the same-machine before/after table, budget status, remaining bottleneck if any, and `gl_compatibility` confirmation in README.
- [ ] Commit and push source changes, wait for the Godot 4.5 Android workflow, download and integrity-check its APK, then replace and push `apk/godottest1.apk`.

