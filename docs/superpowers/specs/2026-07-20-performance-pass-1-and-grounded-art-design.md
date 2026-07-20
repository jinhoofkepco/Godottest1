# Performance Pass 1 and Grounded Art Design

## Scope

Optimize the existing GDScript simulation without changing combat rules, balance constants, deterministic seeds, or terminal outcomes. Replace the misleading SIEGE tower silhouette with a clearly mobile catapult and ground every building sprite on its occupied elevated tile.

## Measured baseline

The committed 600-unit stress fixture on the local compatibility renderer reports 9.098 ms average, 18.697 ms p95, and 28.204 ms maximum simulation time. The profiling pass must first expose target search, separation/avoidance, territory, event, and render-update timings so the optimized run can be compared against the same fixture.

## Considered approaches

1. **Recommended: cached decisions plus packed transfer channels.** Retain the fixed 30 Hz simulation and packed unit arrays, but update one of three decision groups per tick, cache steering/target state, throttle territory to 0.2 seconds, transfer high-frequency events through typed packed channels, and upload each MultiMesh through one interleaved buffer assignment. This preserves rules while removing repeated work and call overhead.
2. **Lower-risk partial pass.** Only throttle territory and bulk-upload rendering. This touches less code but leaves the dominant all-unit target/separation searches every tick and is unlikely to reach the 8 ms target.
3. **Native extension rewrite.** Move simulation work to C++ or GDExtension. This could be faster but violates the locked GDScript requirement and is out of scope.

## Simulation architecture

`BattleSimulation` keeps movement integration, cooldown decrement, attack-range validation, hit resolution, death removal, and terminal checks on every fixed tick. Each unit gains cached steering and cached target position/radius data. Unit id modulo three selects the decision group; only the active group reruns target acquisition, separation, waiting, and obstacle response. Every tick validates cached targets by id and team, drops dead or invalid targets, and still evaluates whether the cached target is inside attack range.

Territory has a 0.2-second accumulator and dirty flag. A normal tick updates it only when the interval elapses; building creation/destruction sets the dirty flag and forces an update. Front rows come from the already rebuilt team buckets rather than a second full unit scan. Allied and enemy occupancy ratios are updated with ownership in the same pass and returned in O(1).

Profiling counters store microseconds for target decisions, separation/avoidance, territory, and event work. They are diagnostic only and never alter simulation state.

## Events and FX

Low-frequency structural events remain dictionaries. Hit, shot, and unit-death traffic uses typed packed channels containing parallel arrays for positions, teams, flags, ids, kinds, and directions. `drain_events` swaps ownership of all channel buffers and replaces internal buffers with empty arrays; it never deep-copies.

`DefenseMain` consumes the channel bundle directly. `DefenseFx` accepts at most 40 newly created minor hit, shot, death-spark, and debris effects per rendered frame. SIEGE projectile/impact, HQ, building destruction, territory, and match-result feedback bypass the cap. Unit HP-bar visibility is refreshed directly from hit records; the renderer no longer compares every living unit's current HP against a Dictionary every frame.

## Rendering

The renderer preserves the current draw sorting and atlas animation selection. For each MultiMesh it creates one `PackedFloat32Array` in Godot's 2D interleaved layout: eight transform floats, four color floats when enabled, and four custom-data floats when enabled. It assigns `multimesh.buffer` once after setting instance count. Shadows follow the same path. Render timing is measured around `unit_renderer.sync()` in the stress scene.

## Visual corrections

The SIEGE bake reuses the CC0 KayKit catapult turret and arm but removes the stone tower mesh. A low wooden cart body, axle, and four wheels are assembled procedurally in the reusable bake scene, producing an unmistakable mobile catapult in all eight directions. Attack frames move the arm; walk frames add restrained wheel/cart motion.

Building sprites compute their destination from per-sprite opaque bounds recorded in `world_atlas.json`. The opaque bottom is placed on a single ground contact line at the tile center/front edge. A compact contact shadow and low diamond plinth remove any residual floating impression. Elevation remains supplied exclusively by `GridBoard.cell_to_world`.

## Verification

- Existing rules, flow, elevation, balance, and game-flow suites must pass unchanged.
- New tests cover 0.2-second territory caching, event ownership transfer, decision-group rotation, FX cap exemptions, one-buffer MultiMesh upload, SIEGE mobile-cart metadata, and building opaque-bottom grounding.
- Stress output reports before/after average and worst simulation milliseconds, subsystem breakdown, render-update milliseconds, target/AoE bounds, and balance scenarios.
- Fresh smoke captures must show the wheeled SIEGE silhouette and every building touching its tile/plinth.
- The GitHub Actions Godot 4.5 Android job must pass and publish the debug APK artifact.

