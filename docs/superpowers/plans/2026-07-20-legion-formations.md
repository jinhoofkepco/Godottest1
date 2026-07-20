# Legion Formations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace class spawners with configurable barracks that repeatedly assemble and deploy twelve-unit-or-smaller legions in LINE, WEDGE, or LOOSE formations.

**Architecture:** Add a fixed-capacity Legion SoA beside the existing unit SoA and reuse current buckets, flow fields, steering, combat, and packed snapshots. Barracks store templates and produce one active gathering legion; GDScript remains a low-frequency UI and bulk-render consumer.

**Tech Stack:** Godot 4.5 Mono, C# net9.0 simulation, GDScript UI/rendering, MultiMeshInstance2D, headless Godot tests.

## Global Constraints

- Units and legions are pure data; neither may create a Node.
- Template total is at most 12, SIEGE at most 2, and DRAGON at most 1.
- Formations change geometry only and never apply stat modifiers.
- Existing flow, congestion, separation, wait, elevation, combat, territory, tower, and win rules remain authoritative.
- Barracks cost 100 and produces one unit every 1.2 seconds; gathering deployment is bounded to 15 seconds.
- Touch and mouse remain supported in a 540 x 960 portrait viewport.

---

### Task 1: Legion contracts and geometry

**Files:**
- Modify: `tests/test_rules.gd`
- Create: `scripts/BattleSimulation.Legions.cs`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleConfig.cs`
- Modify: `scripts/game_config.gd`

**Interfaces:**
- Produces: `ValidateTemplate(Dictionary)`, `GetFormationSlots(Dictionary, int, Vector2)`, legion and formation constants.
- Consumes: existing unit kind constants and fixed unit pool.

- [ ] Add failing tests that request the new constants, validate every cap, assert LINE melee projection is ahead of ranged projection, assert a 90-degree heading rotates every slot, and compare LINE versus LOOSE blast intersections.
- [ ] Run `godot --headless --path . -s tests/run_rules.gd` and confirm failures name the missing legion methods.
- [ ] Add fixed legion/unit arrays, compact template values, deterministic slot generation, and public packed debug geometry helpers.
- [ ] Run rule tests and confirm all new geometry assertions pass without modifying unit combat statistics.
- [ ] Commit the isolated geometry/data slice.

### Task 2: Barracks production and legion state machine

**Files:**
- Modify: `tests/test_rules.gd`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Legions.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`

**Interfaces:**
- Consumes: formation slot helpers from Task 1.
- Produces: `TryBuildBarracks`, `ConfigureBarracks`, `SetBarracksWaypoint`, `DemolishBuilding`, `GetBarracksConfig`, legion state updates.

- [ ] Add failing tests for barracks cost, exact 1.2-second role-ordered production, gathering deployment no later than 15 seconds, second legion production, engagement/reformation, and survivor release below 30 percent.
- [ ] Run rule tests and verify they fail on the missing barracks/state behavior.
- [ ] Replace spawner-specific building data with a barracks template, formation, active legion ID, and waypoint while retaining tower/HQ behavior.
- [ ] Implement group anchors and legion transitions before each unit update; layer slot-follow steering into the existing refresh branch and preserve ungrouped steering when `legion_id == -1`.
- [ ] Preserve new parallel unit arrays during swap-removal and update legion membership on death.
- [ ] Run all rule and .NET contract tests; fix only state-machine regressions.
- [ ] Commit the working simulation slice.

### Task 3: Enemy legion AI and match balance

**Files:**
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `tests/run_balance.gd`
- Modify: `tests/run_stress.gd`

**Interfaces:**
- Consumes: barracks APIs and four deterministic templates.
- Produces: enemy weighted template selection, waypoint assignment, 20-legion stress fixture.

- [ ] Add failing checks that enemy construction records contain valid templates/formations and that a 20-legion fixture contains 240 units with legion membership.
- [ ] Implement enemy barracks selection using the existing build timer, maximum-building difficulty constant, and deterministic RNG.
- [ ] Run passive and active matches; adjust only production/gathering timing within the allowed range until both terminate in 120-240 seconds.
- [ ] Record tick and render snapshot timing for 20 full legions.
- [ ] Commit AI and balance changes.

### Task 4: Barracks and formation mobile UI

**Files:**
- Modify: `tests/test_game_flow.gd`
- Modify: `scripts/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/map_view.gd`
- Modify: `scripts/battle_building.gd`

**Interfaces:**
- Consumes: `TryBuildBarracks`, config/edit/waypoint APIs, building snapshot metadata.
- Produces: build/template signals, edit panel signals, existing-building tap resolution, waypoint mode.

- [ ] Add failing scene tests for two build buttons, three template cards, barracks placement with the selected template, plus/minus cap enforcement, formation switching, waypoint tap consumption, and demolition.
- [ ] Replace the five class-spawner controls with compact barracks/tower and template controls.
- [ ] Add a barracks panel that opens from a tapped allied building and calls one bulk configuration API per user action.
- [ ] Route the next map tap to waypoint mode and suppress build/pan side effects.
- [ ] Run game-flow tests and a 180-frame scene smoke.
- [ ] Commit the UI slice.

### Task 5: Legion banners and gathering ghosts

**Files:**
- Modify: `tests/test_game_flow.gd`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/unit_renderer.gd`

**Interfaces:**
- Consumes: legion anchors, states, teams, rotated slots.
- Produces: packed `legion_banner_buffer`, `legion_banner_count`, `legion_ghost_buffer`, `legion_ghost_count` and renderer batches.

- [ ] Add failing bulk-buffer tests asserting one upload per banner/ghost batch and no per-legion getter loop.
- [ ] Assemble banner and ghost records inside C# using the existing 16-float MultiMesh format.
- [ ] Add procedural flag and translucent diamond/circle ghost meshes with team/state coloring.
- [ ] Run game-flow and bulk-render tests.
- [ ] Commit the render slice.

### Task 6: Visual QA, documentation, APK and publish

**Files:**
- Modify: `tests/smoke_capture.gd`
- Modify: `.github/workflows/android.yml`
- Modify: `README.md`
- Modify: `export_presets.cfg`

**Interfaces:**
- Consumes: debug legion fixtures and all final snapshots.
- Produces: four 540 x 960 captures, stress table, Android debug artifact and release APK.

- [ ] Add gathering, LINE march, engaged, and LOOSE smoke fixtures and verify every PNG is exactly 540 x 960.
- [ ] Run .NET build, import, contracts, rules, flow, atlas, balance, stress, 180-frame runtime, and visual capture using Godot 4.5 Mono.
- [ ] Inspect the four new captures for distinct geometry, correct role order, banners, and ghost slots.
- [ ] Update README with controls, legion behavior, test evidence, timing, and the six requested visual checks.
- [ ] Export and verify the signed debug APK, update version metadata, push `main`, wait for Actions success, verify the downloaded artifact, and attach the exact CI APK to a GitHub release.

## Plan self-review

- Every locked requirement maps to a task and a named test or API.
- No placeholder steps or deferred behavior remain.
- The plan preserves C# bulk boundaries and does not introduce unit/legion Nodes.
- UI, simulation, rendering, AI, balance, stress, smoke capture, CI, and APK delivery are all covered.
