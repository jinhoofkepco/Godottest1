# Elevation Terrain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic mirrored 0/1/2 elevation with slope-aware flow movement, high-ground combat, elevated rendering, and accurate picking.

**Architecture:** A new data-only `TerrainMap` owns generation, elevation queries, step legality, and reachability. `BattleSimulation` consumes it for fixed-tick movement and combat; `FlowField` consumes packed elevation for integration costs; all view classes use `GridBoard` elevated projection helpers.

**Tech Stack:** Godot 4.5 stable, GDScript, PackedByteArray, fixed-tick data simulation, CanvasItem drawing, existing MultiMesh sprite renderer.

## Global Constraints

- Elevation values are integers 0/1/2 and center-mirrored.
- Ground transitions allow absolute delta at most one; uphill speed is 0.7.
- Damage multipliers are 1.25 high-to-low, 0.75 low-to-high, and 1.0 equal.
- Ranged infantry at elevation at least one gains 0.5 cells of range.
- Building permission ignores elevation; dragons ignore terrain movement.
- No separate prop blockers remain in runtime play.
- Existing territory, economy, match length, unit data orientation, portrait input, and CI delivery stay unchanged.

---

### Task 1: Terrain data and generation

**Files:**
- Create: `scripts/terrain_map.gd`
- Modify: `scripts/game_config.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Produces: `TerrainMap.generate()`, `get_elevation(cell)`, `can_step(from, to)`, `all_required_paths_reachable()` and packed `elevation`.

- [ ] Add failing assertions for constants, packed 0/1/2 values, deterministic mirror symmetry, clear HQ cells, and required reachability.
- [ ] Run `godot --headless --path . -s tests/run_rules.gd` and confirm failures name the missing elevation contract.
- [ ] Implement seeded mirrored hill stamping with retry-on-unreachable validation.
- [ ] Re-run rules and keep the new terrain assertions green.
- [ ] Commit terrain data and generation.

### Task 2: Flow, movement, and combat rules

**Files:**
- Modify: `scripts/flow_field.gd`
- Modify: `scripts/battle_simulation.gd`
- Modify: `tests/test_flow_features.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Consumes: packed elevation and `TerrainMap.can_step`.
- Produces: elevation-aware `FlowField.rebuild`, `_unit_attack_range(kind, position)`, `_elevation_damage_multiplier`, and high-ground event metadata.

- [ ] Add failing fixtures for cliff blocking, slope passage, uphill cost, uphill slowdown, three damage multipliers, and ranged high-ground range.
- [ ] Run rule/flow tests and confirm behavior-specific failures.
- [ ] Extend Dijkstra transitions with cliff exclusion and uphill cost.
- [ ] Replace prop blocking with elevation-aware movement and apply uphill velocity scaling.
- [ ] Apply elevation-aware range and damage to units and static defenses.
- [ ] Run rule/flow tests and commit the green simulation slice.

### Task 3: Elevated board and picking

**Files:**
- Modify: `scripts/grid.gd`
- Modify: `scripts/map_view.gd`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- Produces: `grid_to_screen_elevated`, `position_to_world`, elevation-aware `cell_to_world`, and top-surface `world_to_cell`.

- [ ] Add failing round-trip tests for every elevation and overlapping visible tile candidates.
- [ ] Confirm the flat inverse picks the wrong cell before implementation.
- [ ] Draw elevated top diamonds, side walls, elevation lighting, and raised front-line edges.
- [ ] Implement local candidate polygon picking and elevated board bounds.
- [ ] Run rule/game-flow tests and commit the green board slice.

### Task 4: Elevate actors, buildings, and FX

**Files:**
- Modify: `scripts/unit_renderer.gd`
- Modify: `scripts/battle_building.gd`
- Modify: `scripts/fx.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- Consumes: `GridBoard.position_to_world` and simulation elevation queries.
- Produces: elevation-aligned actors, shadows, bars, buildings, shots, and enhanced high-ground hit spark.

- [ ] Add failing position and high-ground feedback assertions.
- [ ] Route every world-space view through the shared elevated projection.
- [ ] Include high-ground metadata in event dispatch and enlarge/brighten only those sparks.
- [ ] Run game-flow/rule tests and commit the visual integration slice.

### Task 5: Visual QA, performance, and delivery

**Files:**
- Modify: `tests/smoke_capture.gd`
- Modify: `.github/workflows/android.yml`
- Modify: `README.md`
- Modify: `export_presets.cfg`
- Modify: `apk/godottest1.apk`

**Interfaces:**
- Produces: elevation overview/high-ground captures, current stress numbers, versioned debug APK, and Actions artifact.

- [ ] Add two 540x960 smoke scenarios and CI file checks.
- [ ] Run Godot 4.5 import, rule, game-flow, atlas, 400-unit stress, runtime smoke, and all captures.
- [ ] Record measured stress and elevation visual/rule checklist in README; increment Android version.
- [ ] Export and verify a signed debug APK locally where templates are available.
- [ ] Push `main`, verify the Godot 4.5 Actions run, download and verify its APK, publish the identical file at `apk/godottest1.apk`, and re-check the remote commit.
