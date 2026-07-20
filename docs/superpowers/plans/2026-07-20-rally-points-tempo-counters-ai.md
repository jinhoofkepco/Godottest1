# Rally Points, Tempo, Counters, and AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore continuous class spawners, assemble existing legion formations at configurable rally points, slow matches to five-to-seven minutes, strengthen class counters, and replace the opening-only enemy builder with a measurable team-agnostic AI state machine.

**Architecture:** C# remains the sole simulation owner. Units remain SoA data and cache a rally ID; rally buildings transfer arrived unit IDs into the existing Legion SoA. GDScript continues to receive only bulk snapshots/events and implements construction/edit controls plus overlay presentation.

**Tech Stack:** Godot 4.5 stable .NET, C# simulation, GDScript HUD/render/FX/tests, MultiMesh rendering, GitHub Actions Android .NET export.

## Global Constraints

- No per-unit Node2D, signals, getters, or GDScript simulation loops.
- Preserve flow fields, steering, elevation, territory, siege, rendering, and fixed 30 Hz simulation semantics.
- Match duration is 420 seconds, occupancy victory is 92%, and target terminal duration is 300-420 seconds.
- Rally launch size is 10 and defense capacity is 14.
- Damage counter multipliers compose multiplicatively with elevation and AoE falloff.
- All behavior changes are introduced with a failing automated test first.

---

### Task 1: Baseline AI Diagnosis and Constants

**Files:**
- Modify: `scripts/BattleConfig.cs`
- Modify: `scripts/game_config.gd`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `tests/test_dotnet_port.gd`
- Modify: `README.md`

**Interfaces:**
- Produces `GetConfigSnapshot()` keys for match duration, occupancy, income, production intervals, rally launch/cap, and all unit speeds.
- Produces debug AI counters consumed by the 50-match runner.

- [ ] Add assertions for 420 seconds, 0.92 occupancy, 2.25 income, 2400 HQ HP, speed factor 0.7, and production factor 1.8.
- [ ] Run `tests/run_dotnet_port.gd` and confirm it fails on the old constants.
- [ ] Replace barracks constants with restored spawner/rally constants and add `RallyLaunchSize = 10`, `RallyDefenseCapacity = 14`, and AI thresholds.
- [ ] Expose matching snake-case config keys and rerun the contract test to green.
- [ ] Record the confirmed `CountBarracks >= 3` early-return diagnosis in README.

### Task 2: Restored Spawners and Rally Construction

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- `TryBuild(int team, Vector2I cell, int buildKind) -> bool` accepts build kinds 0-5.
- `ConfigureRally(int buildingId, int mode, int formation) -> bool` and `DemolishRally(int buildingId) -> bool` edit only friendly live rally points through the caller's team-aware wrapper.

- [ ] Replace barracks construction tests with exact costs/kinds for four spawners, rally, and tower; assert individual production role and interval.
- [ ] Run `tests/run_rules.gd` and confirm failures reference missing rally/spawner behavior.
- [ ] Restore `BuildingSpawner` and `BuildingDragonLair`, add `BuildingRallyPoint`, and implement costs/HP/production periods without legion creation.
- [ ] Add rally mode/formation/waiting fields to building snapshots and structural events.
- [ ] Rerun rule and deterministic tests to green.

### Task 3: Rally Assignment and Legion Assembly

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Legions.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Unit SoA adds `_rallyPointIds` and preserves it through swap removal.
- `CreateLegionFromMembers(int team, int rallyId, int formation, Span<int> members, bool defending)` assigns role-derived slots.
- `UpdateRallyPoints(float delta)` maintains assignment, launch, garrison, overflow, and destruction fallback.

- [ ] Add independent failing tests for nearest rally, no-rally movement, launch at ten, defense cap fourteen, overflow launch, destroyed-rally ungrouping, and defend engage/reform.
- [ ] Confirm every new assertion fails for the missing behavior rather than setup errors.
- [ ] Add cached nearest-rally selection and rally steering for ungrouped units.
- [ ] Refactor slot generation to accept member-derived role counts, then transfer arrived members into MARCHING or defending GATHERING legions.
- [ ] Break the rally-linked garrison and clear all target IDs on destruction; verify rule tests green.

### Task 4: Class Counter Damage and Strong-Hit FX

**Files:**
- Modify: `scripts/BattleConfig.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Events.cs`
- Modify: `scripts/fx.gd`
- Create: `tests/run_counter_matrix.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- `GetClassDamageMultiplier(int attackerKind, int targetKind) -> float` exposes the exact table for tests.
- Packed hit event flags use bit 0 for high ground and bit 1 for favorable class damage.

- [ ] Add exact table assertions and an attack test proving class, elevation, and AoE multipliers multiply.
- [ ] Run rule tests and confirm the table API is absent.
- [ ] Implement the table in all direct and siege unit-damage paths and pack the favorable flag.
- [ ] Render favorable hits with the warm strong-hit spark while retaining normal/high-ground variants.
- [ ] Add deterministic equal-gold matchup trials and tune each listed favorable multiplier within plus or minus 0.2 until every rate is at least 75%.

### Task 5: Team-Agnostic AI and 50-Match Health Runner

**Files:**
- Create: `scripts/BattleSimulation.Ai.cs`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Create: `tests/run_ai_health.gd`
- Modify: `.github/workflows/android.yml`

**Interfaces:**
- `SetAiEnabled(int team, bool enabled)` toggles either controller.
- Debug snapshot returns per-team decisions, builds, failed searches, forced spends, maximum gold, and last reason.

- [ ] Add a short failing health fixture proving an enabled AI builds a rally plus a class spawner and continues deciding after three buildings.
- [ ] Confirm the old early return fails that fixture and capture accumulated gold/build counters.
- [ ] Implement per-team economy, counter-pick, occupancy posture, and forced-spend state using shared methods.
- [ ] Run 50 passive matches and 50 AI-vs-AI matches; assert 50 passive defeats, 40-60% blue wins, 300-420 second average, and no gold/build stall.
- [ ] Add the health runner to CI only after its local runtime and deterministic output are recorded.

### Task 6: Mobile HUD and Rally Readability

**Files:**
- Modify: `scripts/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/grid.gd`
- Modify: `scripts/unit_renderer.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- HUD emits `build_kind_selected`, `rally_config_changed`, and `rally_demolish_requested`.
- Main uses building snapshot cache to open the editor only for an allied rally.
- Rally overlay consumes building mode, formation, waiting count, cell, and elevation.

- [ ] Replace barracks/template UI tests with six selectors and rally editor behavior; assert touch construction and enemy-rally rejection.
- [ ] Run game-flow tests and confirm the old five-control bar fails.
- [ ] Build a compact two-row selector, ADVANCE/DEFEND toggle, three formation buttons, and demolition action.
- [ ] Draw top-layer flag/arrow for ADVANCE, shield ring for DEFEND, and an occlusion-safe waiting-count badge.
- [ ] Rerun game-flow tests and inspect both modes at maximum zoom.

### Task 7: Balance, Captures, Documentation, and Android Delivery

**Files:**
- Modify: `tests/run_balance.gd`
- Modify: `tests/run_stress.gd`
- Modify: `tests/smoke_capture.gd`
- Modify: `README.md`
- Modify: `export_presets.cfg`
- Modify: `project.godot`
- Modify: `.github/workflows/android.yml`

**Interfaces:**
- Balance output includes passive and active result/duration, AI-vs-AI average, and final constants.
- Smoke output includes `smoke_rally_defend.png` and `smoke_rally_launch.png` at 540x960.

- [ ] Add failing balance expectations for 300-420 seconds and the two new smoke filenames.
- [ ] Run balance and capture scripts to observe the pre-tuning failures.
- [ ] Tune only production, income, HQ HP, and documented AI cadence within the approved slow direction until passive defeat and active victory both fall in range.
- [ ] Run import, C# warning-as-error build, all rule/contract/UI/atlas/counter/AI/balance/stress/board/smoke/runtime checks and inspect both rally captures.
- [ ] Update README constants, diagnosis, AI/counter results, capture checklist, and APK instructions; bump Android metadata to 1.3.0/code 12.
- [ ] Commit, push main, watch GitHub Actions, download and verify the CI APK, and publish the exact artifact as release v1.3.0.

