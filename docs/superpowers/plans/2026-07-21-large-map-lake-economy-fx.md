# Large Map, Lake, Economy, Construction, and Combat FX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a 44-by-88 battlefield with one central ground-blocking lake, slower timed construction and production, larger rallies, five-times-durable buildings, 300-unit team caps, population-scaled income, a five-level enemy-income control, proper procedural legion flags, and transparent readable combat FX.

**Architecture:** Keep all rules in the existing C# `BattleSimulation` partial class and expose only bulk snapshots/events plus a small difficulty setter. Extend immutable terrain with a water mask, keep the 3,872-tile board in one MultiMesh, retain data-only units/legions and debug stress bypass, and leave GDScript responsible only for input, HUD, buildings, board rendering, and transient FX.

**Tech Stack:** Godot 4.5 stable .NET, C# simulation, GDScript rendering/UI/tests, OpenGL Compatibility, `MultiMeshInstance2D`, canvas-item shaders, GitHub Actions Android .NET export.

## Global Constraints

- Map dimensions are exactly 44 columns by 88 rows.
- Water is one connected central symmetric lake, blocks ground units/buildings, allows dragons, and is excluded from occupancy.
- Rally ADVANCE launches 20; DEFEND holds 28 and launches overflow.
- RANGED HP is exactly 20.4; all production intervals are doubled.
- Construction duration is exactly building cost times 0.1 seconds; HQs start complete.
- Spawner, rally, tower, dragon lair, and HQ maximum HP are 1,200, 1,300, 1,600, 1,500, and 12,000.
- SIEGE against MELEE uses a 1.5 class multiplier.
- Each team is capped at 300 living gameplay units.
- Passive income and kill rewards lose 10 percentage points per complete 30 living units.
- Enemy difficulty levels 1-5 map to 1.0, 1.25, 1.5, 1.75, and 2.0; level 3 is the restart default.
- Screen shake remains zero.
- No per-unit, per-legion, per-water-cell, or per-effect gameplay nodes.
- Existing stress debug injection may bypass the gameplay unit cap; normal production and AI may not.
- GitHub Actions must still produce `build/godottest1.apk` as `godottest1-debug-apk`.

---

## File Structure

- `scripts/BattleConfig.cs`: authoritative C# rule constants for dimensions, lake, construction, unit cap, economy, balance, rally, and FX limits shared by partial simulation files.
- `scripts/game_config.gd`: matching render/UI constants and palette values.
- `scripts/TerrainMap.cs`: deterministic elevation plus connected symmetric water-mask generation and path validation.
- `scripts/FlowField.cs`: consumes immutable water/blocked cells through the existing blocked-cost input; no separate water policy.
- `scripts/BattleSimulation.cs`: stores water, construction fields, team counts, difficulty state, reset defaults, build allocation, and public boundary methods.
- `scripts/BattleSimulation.Step.cs`: construction, scaled income, production pause/resume, buckets, flow rebuilding, and active-building filtering.
- `scripts/BattleSimulation.Combat.cs`: water-aware movement/spawn checks, SIEGE-to-MELEE multiplier, and scaled kill rewards.
- `scripts/BattleSimulation.Legions.cs`: 20/28 rally thresholds and bounded large-formation slots.
- `scripts/BattleSimulation.Ai.cs`: completed-building counts and difficulty-aware economy behavior.
- `scripts/BattleSimulation.Snapshots.cs`: immutable water, construction, population, income, difficulty, and banner data in bulk snapshots.
- `scripts/BattleSimulation.Debug.cs`: deterministic fixtures for water, population, construction, income, and cap tests; stress-only cap bypass.
- `scripts/grid.gd`: 3,872-instance board, water custom data/shader, water-aware build preview, picking, and frontline exclusion.
- `scripts/static_terrain_layer.gd`: one-time shoreline drawing beside existing cliffs.
- `scripts/battle_building.gd`: incomplete-building opacity/progress and completion pulse without changing rules.
- `scripts/hud.gd`: population/income line and cycling AI level button.
- `scripts/main.gd`: one difficulty setter call, expanded HUD snapshot routing, and construction FX routing.
- `scripts/unit_renderer.gd`: composite procedural flag mesh/material while preserving one banner buffer upload.
- `scripts/fx.gd`: transparent tracers, hits, SIEGE, death, construction, building, and HQ feedback under the existing frame budget.
- `tests/test_rules.gd`: terrain, construction, balance, cap, income, difficulty, and rally rule assertions.
- `tests/test_flow_features.gd`: water detour and dragon-crossing movement assertions.
- `tests/test_dotnet_port.gd`: constants, snapshot, deterministic state, and boundary contracts.
- `tests/test_game_flow.gd`: board/HUD/building/flag/FX renderer contracts and input behavior.
- `tests/run_stress.gd`: gameplay-capped 300-versus-300 case while retaining debug 600/1,500/3,000 cases.
- `tests/smoke_capture.gd`: lake, construction, rally, flag, and transparent battle captures.
- `README.md`: final rules, controls, measurements, visual self-check, and APK path.

---

### Task 1: Lock Constants and Failing Rule Contracts

**Files:**
- Modify: `tests/test_dotnet_port.gd`
- Modify: `tests/test_rules.gd`
- Modify: `scripts/BattleConfig.cs`
- Modify: `scripts/game_config.gd`

**Interfaces:**
- Consumes: current `GameConfig` constants and `BattleSimulation.GetConfigSnapshot()`.
- Produces: exact constants used by every later task, including `GridColumns`, `GridRows`, `TeamUnitCap`, `IncomeUnitStep`, `IncomeStepPenalty`, `AiIncomeMultipliers`, `LakeRadiusX`, `LakeRadiusY`, and `ConstructionSecondsPerGold`.

- [ ] **Step 1: Add failing constant assertions**

Add assertions equivalent to:

```gdscript
_expect(GameConfig.GRID_COLUMNS == 44 and GameConfig.GRID_ROWS == 88, "battlefield is 44x88")
_expect(is_equal_approx(GameConfig.RANGED_UNIT_MAX_HP, 20.4), "RANGED HP is 60 percent")
_expect(is_equal_approx(GameConfig.SPAWNER_PRODUCTION_INTERVAL, 5.76), "normal production rate is halved")
_expect(is_equal_approx(GameConfig.SIEGE_PRODUCTION_INTERVAL, 17.28), "SIEGE production rate is halved")
_expect(is_equal_approx(GameConfig.DRAGON_PRODUCTION_INTERVAL, 45.0), "dragon production rate is halved")
_expect(GameConfig.RALLY_LAUNCH_SIZE == 20 and GameConfig.RALLY_DEFENSE_CAPACITY == 28, "rally capacity doubles")
_expect(GameConfig.TEAM_UNIT_CAP == 300, "each team is capped at 300 living units")
_expect(GameConfig.AI_DIFFICULTY_DEFAULT == 3, "AI difficulty defaults to level three")
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `godot --headless --path . -s tests/run_dotnet_port.gd`

Expected: FAIL on the first old 22-by-44 or old balance assertion, not a parser error.

- [ ] **Step 3: Add exact matching constants in C# and GDScript**

Use these values in both config hubs:

```csharp
public const int GridColumns = 44;
public const int GridRows = 88;
public const int TeamUnitCap = 300;
public const int IncomeUnitStep = 30;
public const float IncomeStepPenalty = 0.10f;
public const int AiDifficultyDefault = 3;
public static readonly float[] AiIncomeMultipliers = { 0f, 1f, 1.25f, 1.5f, 1.75f, 2f };
public const int LakeRadiusX = 10;
public const int LakeRadiusY = 9;
public const float ConstructionSecondsPerGold = 0.1f;
public const float RangedHp = 20.4f;
public const float SpawnerProductionInterval = 5.76f;
public const float SiegeProductionInterval = 17.28f;
public const float DragonProductionInterval = 45f;
public const int RallyLaunchSize = 20;
public const int RallyDefenseCapacity = 28;
public const float SiegeVsMelee = 1.5f;
```

Set HP to 1,200/1,300/1,600/1,500/12,000 and update terrain generation bands proportionally for the 88-row map.

- [ ] **Step 4: Expose constants from `GetConfigSnapshot()` and verify GREEN**

Run: `godot --headless --path . -s tests/run_dotnet_port.gd`

Expected: constant contract assertions PASS; behavior tests that depend on unimplemented water/construction may remain outside this task.

- [ ] **Step 5: Commit the constant contract**

```bash
git add scripts/BattleConfig.cs scripts/game_config.gd tests/test_dotnet_port.gd tests/test_rules.gd
git commit -m "test: lock expanded battlefield balance"
```

### Task 2: Generate and Simulate the Central Lake

**Files:**
- Modify: `scripts/TerrainMap.cs`
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Legions.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_flow_features.gd`

**Interfaces:**
- Consumes: `BattleConfig.LakeRadiusX/Y`, existing elevation, blocked arrays, `FlowField.Rebuild`, and `MoveGround`/`MoveFlying`.
- Produces: `_water: byte[]`, `TerrainMap.Water`, `IsWater(Vector2I)`, initial snapshot key `water`, debug snapshot key `water`, and water-aware reachability/occupancy.

- [ ] **Step 1: Write failing lake rule tests**

Cover exact size, connectedness, point symmetry, center placement, ground rejection, dragon crossing, build rejection, occupancy exclusion, and a reachable left/right detour. Use the public/debug boundaries:

```gdscript
var debug: Dictionary = simulation.call("GetDebugSnapshot")
var water := PackedByteArray(debug.water)
_expect(water.size() == 44 * 88, "water mask matches expanded board")
_expect(int(simulation.call("WaterComponentCount")) == 1, "lake is one connected body")
_expect(simulation.call("IsWaterCell", Vector2i(22, 44)), "lake covers map center")
_expect(not simulation.call("CanGroundStep", Vector2i(22, 34), Vector2i(22, 35)), "ground step rejects water edge")
_expect(simulation.call("CanFlyingStep", Vector2i(22, 34), Vector2i(22, 35)), "dragon step crosses water")
_expect(simulation.call("TerrainPathsValid"), "both HQ regions route around the lake")
```

- [ ] **Step 2: Run the rules suite and verify RED**

Run: `godot --headless --path . -s tests/run_rules.gd`

Expected: FAIL because `water`, `IsWaterCell`, and `CanFlyingStep` do not exist.

- [ ] **Step 3: Add deterministic lake generation**

Add `Water` to `TerrainMap`; generate one centered oval with mirrored deterministic edge variation, force elevation zero inside it, flood-fill to verify one component, and regenerate if HQ corridors are not reachable. Use one index helper and a shared passability predicate so flow validation and gameplay agree.

- [ ] **Step 4: Integrate water into simulation movement and flow**

Use these policies:

```csharp
private bool IsWater(Vector2I cell) => Valid(cell) && _water[Index(cell)] != 0;
private bool CellBlocksGround(Vector2I cell) => IsWater(cell) || IsBlocked(cell) || BuildingAt(cell) >= 0;
private bool CanGroundStepInternal(Vector2I from, Vector2I to) =>
    Valid(from) && Valid(to) && !IsWater(to) && Math.Abs(_elevation[Index(from)] - _elevation[Index(to)]) <= 1;
public bool CanFlyingStep(Vector2I from, Vector2I to) => Valid(from) && Valid(to);
```

Copy water into `_flowBlocked` before buildings, reject water from ground spawn candidates and legion anchors, leave `MoveFlying` unchanged, and exclude water cells from territory ownership counts and transitions.

- [ ] **Step 5: Add immutable water to snapshots/debug boundaries**

Return `(byte[])_water.Clone()` only in the initial board and debug snapshots. Add deterministic test helpers without per-cell runtime getters beyond test-only methods.

- [ ] **Step 6: Run rule and flow tests and verify GREEN**

Run: `godot --headless --path . -s tests/run_rules.gd`

Expected: PASS including lake connectivity, movement, flow detour, and occupancy cases.

- [ ] **Step 7: Commit the lake simulation slice**

```bash
git add scripts/TerrainMap.cs scripts/BattleSimulation.cs scripts/BattleSimulation.Step.cs scripts/BattleSimulation.Combat.cs scripts/BattleSimulation.Legions.cs scripts/BattleSimulation.Snapshots.cs scripts/BattleSimulation.Debug.cs tests/test_rules.gd tests/test_flow_features.gd
git commit -m "feat: add central lake terrain rules"
```

### Task 3: Render the Expanded Water Board and Preserve Picking

**Files:**
- Modify: `scripts/grid.gd`
- Modify: `scripts/static_terrain_layer.gd`
- Modify: `scripts/frontline_layer.gd`
- Modify: `scripts/map_view.gd`
- Modify: `tests/test_game_flow.gd`
- Modify: `tests/smoke_capture.gd`

**Interfaces:**
- Consumes: initial board `water`, existing tile color/custom-data buffer, immutable static terrain, and `MapView` fit/zoom/pan.
- Produces: `_water: PackedByteArray`, water-aware tile shader and build preview, one-time shoreline, water-filtered frontlines, and `smoke_lake_overview.png`.

- [ ] **Step 1: Write failing renderer and picking tests**

Assert 3,872 tile instances, water custom data, no build marker on water, one static terrain rebuild, no frontline segment through water, and exact screen-to-cell results for representative lake and shoreline cells.

- [ ] **Step 2: Run game-flow tests and verify RED**

Run: `godot --headless --path . -s tests/run_game_flow.gd`

Expected: FAIL at the 3,872 tile or missing water assertion.

- [ ] **Step 3: Add water instance data and shader color**

Store the snapshot water mask and write it into `INSTANCE_CUSTOM.a`. For water, suppress the build marker and use the water palette instead of ownership color. Add a low-amplitude `TIME` shimmer in the existing canvas-item shader without per-frame GDScript work.

- [ ] **Step 4: Draw the shoreline once and filter frontlines**

Extend `StaticTerrainLayer.setup()` to cache shore edges between water and land. Change `get_frontline_segments()` to skip an edge if either cell is water. Keep build counts test-visible.

- [ ] **Step 5: Keep large-board interaction accurate**

Retain fit-scale calculation, pinch/wheel zoom, and panning. Limit elevation-aware polygon testing to a small neighborhood around the inverse-isometric candidate rather than scanning all 3,872 cells per tap, then assert high land and water cells pick exactly.

- [ ] **Step 6: Add and inspect the full-map lake capture**

Add a deterministic capture showing the centered lake, both land corridors, hills, HQs, muted ownership, and shoreline. Run:

`godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd`

Expected: `build/smoke_lake_overview.png` exists and the lake is immediately distinguishable from cliffs/territory.

- [ ] **Step 7: Commit the board renderer slice**

```bash
git add scripts/grid.gd scripts/static_terrain_layer.gd scripts/frontline_layer.gd scripts/map_view.gd tests/test_game_flow.gd tests/smoke_capture.gd
git commit -m "feat: render expanded lake battlefield"
```

### Task 4: Add Timed Construction and Five-Times Building HP

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Ai.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `scripts/battle_building.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/fx.gd`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- Consumes: `BuildCost(int)`, building structs/snapshots, production/static-defense/rally/AI loops.
- Produces: `ConstructionDuration`, `ConstructionRemaining`, `Complete`, `ConstructionProgress`, `building_completed` event, inactive-building filters, and procedural completion feedback.

- [ ] **Step 1: Write failing construction lifecycle tests**

For each build kind, assert duration equals cost times 0.1, initial HP equals 20 percent of final max HP, blocked cell immediately, targetability during work, no production/attack/rally before completion, exactly one completion event, full functional activation after completion, destruction during work, and all five-times HP values.

- [ ] **Step 2: Run rules and game-flow tests and verify RED**

Run: `godot --headless --path . -s tests/run_rules.gd`

Expected: FAIL because construction fields and `building_completed` do not exist.

- [ ] **Step 3: Extend `Building` and initialization**

Add:

```csharp
public float ConstructionDuration;
public float ConstructionRemaining;
public float ConstructionHpPerSecond;
public bool Complete;
```

Starting HQs use `Complete = true`. Player and AI builds use duration `BuildCost(buildKind) * 0.1f`, start at `MaxHp * 0.2f`, reserve their cell immediately, and start production timers only at completion.

- [ ] **Step 4: Update construction before active-building systems**

Add `UpdateConstruction(delta)` before AI facility evaluation and spawner/defense/rally work. Grow HP by the fixed scheduled rate, keep damage deficit, emit one `building_completed`, mark the board version, and initialize the full production interval on completion.

- [ ] **Step 5: Filter every active-building consumer**

Require `building.Complete` in spawner production, static defense, rally assignment/operation, active AI counts, and functional snapshot markers. Continue allowing combat targeting and destruction regardless of completion.

- [ ] **Step 6: Render construction progress**

Add `complete` and `construction_progress` to building snapshots. In `battle_building.gd`, darken incomplete art, lower alpha to 0.65-0.85 as progress rises, and draw a small ground-attached progress bar. Route `building_completed` to a brief transparent teal/team pulse in `fx.gd`.

- [ ] **Step 7: Verify GREEN and commit**

Run:

```bash
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
```

Expected: PASS with construction lifecycle and view assertions.

```bash
git add scripts/BattleSimulation.cs scripts/BattleSimulation.Step.cs scripts/BattleSimulation.Ai.cs scripts/BattleSimulation.Snapshots.cs scripts/BattleSimulation.Debug.cs scripts/battle_building.gd scripts/main.gd scripts/fx.gd tests/test_rules.gd tests/test_game_flow.gd
git commit -m "feat: add timed building construction"
```

### Task 5: Enforce Unit Balance, Production Slowdown, and Team Caps

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_dotnet_port.gd`
- Modify: `tests/run_stress.gd`

**Interfaces:**
- Consumes: unit SoA, bucket rebuild, `SpawnUnit`, `UpdateSpawners`, class multiplier table.
- Produces: `_livingTeamCounts`, `CanSpawnForTeam(int)`, cap-aware `SpawnUnit(..., bool bypassTeamCap = false)`, SIEGE-to-MELEE multiplier, and cap-aware stress fixtures.

- [ ] **Step 1: Write failing balance and cap tests**

Assert RANGED spawns at 20.4 HP, production does not occur before the doubled interval, SIEGE AoE applies 1.5 against MELEE and 1.0 against an otherwise equal RANGED fixture, each side reaches but never exceeds 300 through normal production, and a death permits exactly one later replacement without a burst.

- [ ] **Step 2: Run the focused rules test and verify RED**

Run: `godot --headless --path . -s tests/run_rules.gd`

Expected: FAIL at SIEGE-vs-MELEE or 300-unit cap behavior.

- [ ] **Step 3: Cache living team counts and gate spawning**

Update counts during bucket rebuild and after removals. Change normal spawn allocation to:

```csharp
private int SpawnUnit(int team, Vector2 position, int unitKind, int legionId = -1,
    Vector2 slotOffset = default, bool bypassTeamCap = false)
{
    if (!bypassTeamCap && _livingTeamCounts[team] >= BattleConfig.TeamUnitCap) return 0;
    // existing fixed-pool allocation
}
```

At cap, set the building retry timer to a small bounded delay such as 0.5 seconds and never subtract multiple intervals.

- [ ] **Step 4: Add the class multiplier and debug-only bypass**

Add `(UnitSiege, UnitMelee) => BattleConfig.SiegeVsMelee` to `GetClassDamageMultiplier`. Only the `spawn_stress`/bulk profile debug operation passes `bypassTeamCap: true`; ordinary debug gameplay commands do not.

- [ ] **Step 5: Retain stress ranges and add a capped battle**

Keep 600/1,500/3,000 injections valid. Add a normal 300-versus-300 measurement that asserts gameplay counts and records tick/snapshot timing on the larger board.

- [ ] **Step 6: Verify GREEN and commit**

Run:

```bash
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_stress.gd
```

Expected: all cap/balance tests pass; old high-count stress cases still report their requested counts.

```bash
git add scripts/BattleSimulation.cs scripts/BattleSimulation.Step.cs scripts/BattleSimulation.Combat.cs scripts/BattleSimulation.Debug.cs tests/test_rules.gd tests/test_dotnet_port.gd tests/run_stress.gd
git commit -m "feat: cap armies and rebalance production"
```

### Task 6: Scale Income and Add Five-Level Enemy Difficulty

**Files:**
- Modify: `scripts/BattleSimulation.cs`
- Modify: `scripts/BattleSimulation.Step.cs`
- Modify: `scripts/BattleSimulation.Combat.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/BattleSimulation.Debug.cs`
- Modify: `scripts/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- Consumes: cached living team counts, passive income remainder, `AwardKill`, HUD snapshot/update.
- Produces: `SetAiDifficulty(int) -> bool`, `IncomeUnitFactor(int) -> float`, `TeamIncomeMultiplier(int) -> float`, HUD keys `ally_unit_count`, `enemy_unit_count`, `ally_income_percent`, `ai_difficulty`, `ai_income_multiplier`, and HUD signal `ai_difficulty_requested(level)`.

- [ ] **Step 1: Write failing economy boundary tests**

Assert exact factors at 0, 29, 30, 59, 60, 269, 270, 299, and 300 units; passive and kill rewards use the same factor; levels clamp/reject outside 1-5; default level 3 is 1.5; changing difficulty leaves current gold untouched; restart returns level 3.

- [ ] **Step 2: Run rules tests and verify RED**

Run: `godot --headless --path . -s tests/run_rules.gd`

Expected: FAIL because population-scaled income and `SetAiDifficulty` do not exist.

- [ ] **Step 3: Centralize income arithmetic**

Implement:

```csharp
private float IncomeUnitFactor(int team) => Mathf.Max(0f,
    1f - (_livingTeamCounts[team] / BattleConfig.IncomeUnitStep) * BattleConfig.IncomeStepPenalty);
private float TeamIncomeMultiplier(int team) => IncomeUnitFactor(team) *
    (team == TeamEnemy ? BattleConfig.AiIncomeMultipliers[_aiDifficulty] : 1f);
public bool SetAiDifficulty(int level)
{
    if (level < 1 || level > 5) return false;
    _aiDifficulty = level;
    return true;
}
```

Use the result in passive and kill income. Preserve fractional rewards through per-team income remainders rather than truncating each kill.

- [ ] **Step 4: Extend the bulk HUD snapshot and UI**

Add a compact status line `UNITS 123/300 // INCOME 60%`. Add one `AI 3 x1.50` button that cycles to 4, 5, 1, 2, 3 and emits one requested level. `main.gd` calls `SetAiDifficulty`, refreshes HUD, and shows a short confirmation message.

- [ ] **Step 5: Verify UI and economy GREEN**

Run:

```bash
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
```

Expected: exact boundary and button-cycle assertions PASS.

- [ ] **Step 6: Commit the economy slice**

```bash
git add scripts/BattleSimulation.cs scripts/BattleSimulation.Step.cs scripts/BattleSimulation.Combat.cs scripts/BattleSimulation.Snapshots.cs scripts/BattleSimulation.Debug.cs scripts/hud.gd scripts/main.gd tests/test_rules.gd tests/test_game_flow.gd
git commit -m "feat: scale income by army and AI level"
```

### Task 7: Scale Rallies and Large Formations Without Queue Deadlock

**Files:**
- Modify: `scripts/BattleSimulation.Legions.cs`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `scripts/hud.gd`
- Modify: `scripts/battle_building.gd`
- Modify: `tests/test_rules.gd`
- Modify: `tests/test_game_flow.gd`
- Modify: `tests/smoke_capture.gd`

**Interfaces:**
- Consumes: rally member lists, `CreateLegionFromMembers`, `BuildLocalSlots`, rally snapshot badges.
- Produces: bounded 20-member marching formations, 28-member defensive formations, overflow chunking, updated HUD copy, and rally smoke captures.

- [ ] **Step 1: Write failing rally-size and geometry tests**

Assert a 19-member ADVANCE rally does not launch, the 20th launches one legion of 20, DEFEND holds 28, member 29 launches overflow, 40 overflow members become two 20-member legions, all three formations keep MELEE ahead of RANGED/SIEGE, and no slot layout exceeds the configured formation width.

- [ ] **Step 2: Reproduce the old crowd case at the new threshold**

Spawn 20 units on a narrow rally approach and step until the threshold timeout. Expected RED before implementation: old constants launch at 10 or large layout assertions fail; the final test must prove the waiting badge reaches 20 rather than freezing below it.

- [ ] **Step 3: Wrap large slot layouts into bounded ranks**

Replace single unlimited rows with helpers such as `RankedRoleSlots(count, columns, spacing, startDepth)` using at most 10 front columns for LINE and 7 for rear/support ranks. Preserve heading rotation and the existing role ordering; add no stat bonuses.

- [ ] **Step 4: Update overflow, badges, and copy**

Use ADVANCE chunks of exactly 20 and DEFEND capacity 28. Update the rally hint to `ADVANCE 20 // DEFEND 28 + AUTO-LAUNCH OVERFLOW` and keep badge counts readable at two digits.

- [ ] **Step 5: Verify and capture**

Run rules/game-flow suites and add `smoke_rally_advance_20.png` plus `smoke_rally_defend_28.png`.

Expected: formations remain visible and rally ingress does not stall.

- [ ] **Step 6: Commit the rally slice**

```bash
git add scripts/BattleSimulation.Legions.cs scripts/BattleSimulation.Snapshots.cs scripts/hud.gd scripts/battle_building.gd tests/test_rules.gd tests/test_game_flow.gd tests/smoke_capture.gd
git commit -m "feat: double rally army capacity"
```

### Task 8: Replace Rectangles with Procedural Legion Flags

**Files:**
- Modify: `scripts/unit_renderer.gd`
- Modify: `scripts/BattleSimulation.Snapshots.cs`
- Modify: `tests/test_game_flow.gd`
- Modify: `tests/smoke_capture.gd`

**Interfaces:**
- Consumes: existing `legion_banner_buffer` 16-float records and custom state/formation data.
- Produces: `_make_flag_mesh() -> ArrayMesh`, `_make_flag_material() -> ShaderMaterial`, bounded banner alpha, one MultiMesh upload, and `smoke_legion_flag_closeup.png`.

- [ ] **Step 1: Write failing flag renderer contracts**

Assert `_make_flag_mesh` no longer constructs `QuadMesh`, the generated mesh has pole and notched-cloth geometry, `_legion_banners` has a material, banner snapshot alpha is at most 0.78, and there is still exactly one banner MultiMesh and no per-legion Node loop.

- [ ] **Step 2: Run game-flow tests and verify RED**

Run: `godot --headless --path . -s tests/run_game_flow.gd`

Expected: FAIL on current `QuadMesh` or 0.95 banner alpha.

- [ ] **Step 3: Build the composite mesh and material**

Create one `ArrayMesh` combining a narrow dark pole, finial, and notched cloth with vertex colors/UVs that let the shader keep the pole neutral and tint cloth by instance color. Add subtle vertex waving based on `TIME`, local UV, and state/custom data; keep Compatibility renderer syntax.

- [ ] **Step 4: Tune snapshot placement and alpha**

Use alpha around 0.72 MARCHING, 0.58 GATHERING, and 0.78 ENGAGED. Raise the small flag enough to clear heads but keep its cloth shorter than the old 24-pixel rectangle.

- [ ] **Step 5: Verify and capture**

Run game-flow and smoke capture. Inspect close-up for a recognizable flag, neutral pole, team cloth, no large solid rectangles, and visible soldiers underneath.

- [ ] **Step 6: Commit the flag slice**

```bash
git add scripts/unit_renderer.gd scripts/BattleSimulation.Snapshots.cs tests/test_game_flow.gd tests/smoke_capture.gd
git commit -m "fix: render readable legion flags"
```

### Task 9: Rework Combat FX for Transparent Tactical Readability

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/fx.gd`
- Modify: `tests/test_game_flow.gd`
- Modify: `tests/smoke_capture.gd`

**Interfaces:**
- Consumes: current hit/shot/death/SIEGE/building/HQ events, grid projection, and 40-minor-effect cap.
- Produces: thin alpha-bounded tracers, directional hits, segmented telegraph, layered SIEGE impact, non-rectangular death debris, construction completion pulse, and transparent battle captures.

- [ ] **Step 1: Write failing FX contracts**

Add source/state tests for maximum minor alpha 0.72, tracer outer width at most 2.5 pixels and bright core at most 1.1, no opaque filled SIEGE blast disk, no `draw_rect` for unit fragments, strong-hit warm color, full-flight telegraph, unchanged frame cap, large-event exemption, and zero shake.

- [ ] **Step 2: Run game-flow tests and verify RED**

Run: `godot --headless --path . -s tests/run_game_flow.gd`

Expected: FAIL on the current 5-pixel tracer, filled impact circle, or rectangular fragments.

- [ ] **Step 3: Centralize FX tuning and replace primitive profiles**

Add named constants for alpha, widths, dust count, and durations. Draw team trail at low alpha with a short bright core; hits as four-to-six rays; SIEGE ring with segmented arcs; projectile with bright head/fading trail/shadow; impact with a short center flash, expanding outline, and soft polygon shards; death with a compact pop and fading tapered shards.

- [ ] **Step 4: Keep semantic differences**

Strong counter hit stays warm orange; high ground stays bright white; ordinary hit stays cream; production is a vertical team pulse; construction completion is a wider teal/team ring; building hit is local red/white outline; HQ hit remains the largest local effect without moving the world.

- [ ] **Step 5: Verify FX budget and smoke visuals**

Run game-flow and capture a dense battle plus SIEGE impact. Confirm individual units remain visible through overlapping effects, the telegraph is readable, and no effect becomes a solid cyan/red rectangle.

- [ ] **Step 6: Commit the FX slice**

```bash
git add scripts/game_config.gd scripts/fx.gd tests/test_game_flow.gd tests/smoke_capture.gd
git commit -m "feat: polish transparent combat effects"
```

### Task 10: Full Regression, Documentation, Android APK, and Publish

**Files:**
- Modify: `README.md`
- Modify only if required: `.github/workflows/android.yml`
- Modify only if required: `export_presets.cfg`

**Interfaces:**
- Consumes: all completed slices and existing Android workflow.
- Produces: verified test/capture/performance evidence, pushed `main`, successful GitHub Actions artifact, and updated direct release APK.

- [ ] **Step 1: Run import, rule, integration, AI, balance, atlas, and scene smoke checks**

Run:

```bash
godot --headless --path . --import
godot --headless --path . -s tests/run_rules.gd
godot --headless --path . -s tests/run_game_flow.gd
godot --headless --path . -s tests/run_dotnet_port.gd
godot --headless --path . -s tests/run_counter_matrix.gd
godot --headless --path . -s tests/run_ai_health.gd
godot --headless --path . -s tests/run_balance.gd
godot --headless --path . -s tests/validate_unit_atlas.gd
godot --headless --path . --scene res://scenes/main.tscn --quit-after 180
```

Expected: every command exits 0 with no parser/runtime errors.

- [ ] **Step 2: Run stress, board, and smoke rendering checks**

Run:

```bash
godot --headless --path . -s tests/run_stress.gd
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/run_board_stress.gd
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tests/smoke_capture.gd
file build/smoke_*.png
```

Expected: capped 300-versus-300 and debug 600/1,500/3,000 measurements print; board delta gate passes; all new captures are 540-by-960 PNGs.

- [ ] **Step 3: Inspect required captures**

Inspect lake overview, ground detour/dragon crossing, construction progress/completion, 20/28 rallies, flag close-up, dense transparent battle, and SIEGE telegraph/impact. Fix visual regressions before documenting results.

- [ ] **Step 4: Update README with exact verified behavior and numbers**

Document 44-by-88 map, lake rules, construction times, HP values, production intervals, 300 cap, income table, AI levels, rally thresholds, SIEGE-vs-MELEE multiplier, flag/FX self-check, stress results, controls, and APK retrieval path. Do not write measured timing or match duration until the commands report it.

- [ ] **Step 5: Run final diff and repository hygiene checks**

Run:

```bash
git diff --check
git status --short
git ls-files .godot build
```

Expected: no whitespace errors; only intended source/docs/tests are pending; `.godot/` and generated `build/` outputs are untracked/ignored.

- [ ] **Step 6: Commit final evidence and push main**

```bash
git add README.md tests/smoke_capture.gd tests/run_stress.gd
git commit -m "docs: record expanded battlefield verification"
git push origin main
```

- [ ] **Step 7: Verify GitHub Actions and publish the direct APK**

Use `gh run list --workflow android.yml`, wait for the pushed run, inspect failures if any, download `godottest1-debug-apk`, verify the APK exists and is signed, then create a new release tag and upload the same verified APK as `godottest1.apk`. Do not alter CI inputs unless the existing Godot 4.5 .NET workflow fails for a reproducible configuration reason.

- [ ] **Step 8: Final report**

Report only the repository URL, successful Actions run/artifact path, direct APK URL, and five device test points: lake pathing/dragon crossing, construction timing, rally 20/28, population-income/AI level control, and flags/transparent combat FX.
