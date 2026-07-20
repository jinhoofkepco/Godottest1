# .NET Simulation Core and SIEGE Rebalance Design

## Scope

Port the complete data-oriented battle simulation from GDScript to C# while keeping the portrait Godot 4.5 game, GDScript view/HUD/FX/input layers, fixed 30 Hz rules, terrain, flow fields, decision staggering, territory cache, and win/loss behavior. The only deliberate balance changes are the requested SIEGE production interval multiplier of 3, maximum range multiplier of 2, and damage multiplier of 1.8. The SIEGE atlas must render upright.

## Considered approaches

1. **Recommended: one C# facade with native C# internals.** `BattleSimulation.cs` is the only public simulation object. Internal C# terrain, flow-field, spatial-bucket, fixed-pool, snapshot, and event-channel types avoid cell- or unit-level language crossings. GDScript performs a few bulk calls and uploads returned buffers unchanged.
2. **Thin C# wrapper around the GDScript simulation.** This minimizes initial code movement, but every core operation still pays GDScript costs and violates the requested complete port. It is rejected.
3. **Keep public packed unit arrays for renderer compatibility.** This would preserve existing tests and renderer code, but retains the per-unit GDScript loop that the pass is meant to remove. Debug inspection instead uses an explicit bulk snapshot available only to tests and tooling.

## Public language boundary

`BattleSimulation` is a `[GlobalClass]` `RefCounted` C# class. The live game uses:

- `Reset()` once per match.
- `Step(delta)` once per rendered frame; fixed 30 Hz steps remain internal.
- `GetRenderSnapshot()` once per rendered frame. It returns preassembled interleaved `PackedFloat32Array` buffers plus counts for infantry, each dragon team, shadows, and compact HP-bar draw data. GDScript assigns each buffer directly to `RenderingServer.multimesh_set_buffer`.
- `DrainEvents()` once per frame. High-frequency hit/shot/death channels are typed packed arrays and structural events are a low-volume array.
- `GetHudSnapshot()` once per frame for gold, both HQ HP values, occupancy, time remaining, result, and unit count.
- `GetBoardSnapshot()` only when its version changes, containing ownership, blocked cells, elevation, and building records.
- `TryBuild(team, cell, buildKind)` for player/AI construction.

Tests use bulk `GetDebugSnapshot()` and `ApplyDebugCommand()` methods. They never require a GDScript loop of per-unit getters in the live renderer.

## C# core

The simulation stores unit state in reusable fixed-capacity arrays and an active count. Swap removal preserves O(1) deletion. Buildings remain a small C# record list exposed only through the board snapshot; the GDScript building views remain Nodes. Spatial buckets are fixed arrays of reusable integer lists. Flow integration/direction arrays and generated elevations are owned by C#, preventing cross-language calls during target search, movement, and path rebuilds.

Movement integration, cooldowns, attacks, siege impacts, death removal, income, and terminal checks run every fixed tick. Targeting, separation, WAIT, obstacle response, and flow decisions retain three-way staggering. Territory remains interval-cached and rebuilds immediately after relevant building events. Event arrays and render buffers are reused where Godot ownership permits; snapshot assembly reports its elapsed time and GC collection deltas.

## Render snapshot

C# reproduces the existing grid-to-screen and elevation offset math. It sorts compact draw entries by elevated screen Y, calculates atlas direction/state/frame, lunge position, brightness, render scale, and shadow transform, then writes Godot's 16-float 2D MultiMesh layout directly: eight transform floats, four color floats, and four custom-data floats.

SIEGE and infantry share the texture-array shader. Custom-data alpha is reserved as an atlas vertical-flip flag: SIEGE records set it to one, infantry records set it to zero, and the shader flips only the selected SIEGE frame UV. Dragon atlases retain their existing corrected vertical orientation.

HP-bar visibility timers move into C# and update on damage events. `GetRenderSnapshot()` includes only visible damaged-unit bar records, so the GDScript draw loop is proportional to visible bars rather than the full army.

## SIEGE balance

- SIEGE spawners use `SPAWNER_PRODUCTION_INTERVAL * 3`, reducing their production rate to one third without changing other spawners.
- Maximum attack range changes from 3.5 to 7.0 cells. Minimum range remains 1.2 cells.
- Base AoE damage changes from 31.0 to 55.8. Existing blast radius, falloff, attack interval, flight-time scaling, target-radius inclusion, and friendly-fire rules remain unchanged.
- Player and enemy AI SIEGE buildings use the same interval and combat constants.

## Determinism and regression strategy

Before deletion, the GDScript core runs a fixed seed and scripted input sequence to produce committed checkpoint data: fixed-tick number, unit count by team/type, HQ HP, gold, occupancy, and result. The C# test replays the same sequence and compares integral fields exactly and floats within a documented tolerance. Once green, `battle_simulation.gd`, `flow_field.gd`, and `terrain_map.gd` are deleted to prevent dual maintenance.

Rule tests are rewritten against bulk snapshots/debug commands. Stress tests run 600, 1500, and 3000-unit fixtures and report average/p95/worst fixed-tick time, render-snapshot assembly time, subsystem timings, and generation 0/1/2 GC deltas. Targets are 600 units at or below 1.5 ms per tick and 3000 units at or below 8 ms; misses are reported with the dominant measured subsystem rather than hidden.

## .NET and Android build

The project gains a Godot C# project targeting .NET 9 because Godot 4.5 Android C# export requires .NET 9 or newer. Local verification uses the official Godot 4.5 .NET editor and .NET export templates. The existing archived `dulvui/godot-android-export` action has no Mono option, so CI keeps it only for JDK/Android SDK setup, then explicitly installs .NET 9, the Godot 4.5 .NET editor, and matching .NET export templates before import, tests, smoke capture, and debug export.

Official references:

- Godot C# requirements: https://docs.godotengine.org/en/4.5/tutorials/scripting/c_sharp/c_sharp_basics.html
- Godot 4.5 downloads and .NET templates: https://godotengine.org/download/archive/4.5-stable/
- Archived Android action inputs: https://github.com/dulvui/godot-android-export

## Completion evidence

The final verification includes headless import/build, C# rules, determinism fixture, game-flow tests, atlas validation, 600/1500/3000 stress output, main-scene smoke, fresh close SIEGE capture, local .NET Android export, GitHub Actions success, artifact download, APK signature/integrity inspection, and publication at the stable repository APK path.
