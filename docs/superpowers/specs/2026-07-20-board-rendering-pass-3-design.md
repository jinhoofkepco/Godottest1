# Board Rendering Performance Pass 3 Design

## Scope

This pass changes only board presentation and its C#/GDScript transfer path. Simulation rules, territory ownership results, combat, economy, balance, input semantics, and all unit/building rendering remain unchanged.

## Chosen approach

Use one `MultiMeshInstance2D` with `GRID_COLUMNS × GRID_ROWS` instances (the retained 22×44 map is 968 tiles) for all diamond tile tops. The diagnostic's older 242-cell count predates the locked four-times map expansion, so this pass must not shrink the gameplay map. Each transform is written once at initial board sync, in isometric depth order. A fixed cell-index-to-instance-index table lets later ownership deltas update only the affected instance color and custom data. The tile shader draws the subdued grid edge, optional build marker, elevation-preserving ownership color, and a 0.62-second `TIME`-based territory flash.

Rejected alternatives:

- Rebuilding and assigning a complete 968-instance buffer on every ownership change still performs full-board work and violates the delta-only requirement.
- One node or polygon per tile removes tessellation but adds hundreds of CanvasItems and draw calls.

## Layer responsibilities

- `GridBoard`: owns immutable board arrays, the tile MultiMesh, cell-to-instance mapping, picking, and delta application. It does not draw the full board in `_draw`.
- `StaticTerrainLayer`: receives elevation once, draws cliff side polygons once, and is never queued for redraw during play.
- `FrontlineLayer`: owns a cached array of line segments. It redraws only after an ownership delta changes the segment set.
- `DefenseFx`: retains transient combat/building effects but has no territory-change object, update, or draw path.

The tile custom data layout is `(flash_start_seconds, can_build, elevation_normalized, reserved)`. Ownership and elevation brightness are baked into per-instance color. A negative flash time means inactive.

## C# boundary

`BattleSimulation.GetBoardVersion()` is the cheap frame-level probe. `GetBoardSnapshot()` remains only for initial population. `GetBoardDelta()` returns the current version, changed ownership cell indices and owners, changed blocked indices and values, plus the small building list required by existing building views. Changed-cell queues deduplicate cells until drained, so multiple simulation ticks between rendered frames do not lose the latest state.

Territory recomputation enqueues ownership deltas instead of allocating one `Dictionary` event per flipped cell. Construction and destruction enqueue blocked-cell deltas. `main.gd` calls `GetBoardSnapshot()` once, then calls `GetBoardDelta()` only when `GetBoardVersion()` changes.

## Performance measurement

`tests/run_board_stress.gd` forces a 30-cell ownership push, measures the old full redraw/FX frame before the change, then measures the new version-probe, delta marshal, delta application, and rendered frame after the change. It reports total flip-frame, board boundary, and tile update times. The acceptance gate is at most 2.0 ms for the 30-cell optimized render update on the local reference machine; CI uses a documented relaxed shared-runner ceiling while still verifying exactly 30 delta updates and no full tile rebuild.

## Verification

- Contract tests prove one 968-instance tile MultiMesh, one-time transforms/static terrain, delta-only instance updates, cached frontline redraw, and the absence of territory FX objects.
- C# tests prove initial full snapshot, cheap version probing, deduplicated ownership/blocked deltas, and no board snapshot request on an unchanged version.
- Existing rule, flow, balance, deterministic-port, atlas, and game-flow suites remain green.
- Smoke capture retains tile colors, elevation brightness, cliffs, frontline, and captures an active shader-driven territory flash.
- A new Android debug APK is built by the Godot 4.5 .NET workflow, verified, and uploaded as both an Actions artifact and a GitHub Release asset.
