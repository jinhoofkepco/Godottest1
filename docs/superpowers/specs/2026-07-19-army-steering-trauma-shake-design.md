# Army Steering and Trauma Shake Design

## Scope

Keep the 11 x 22 frontline rules, packed-array unit model, fixed 30 Hz tick, two team MultiMeshes, dynamic territory, economy, AI, and terminal conditions. Change only unit locomotion/readability and screen shake: units may move freely in logical x/y, form combat clusters across columns, maintain readable personal space, lunge on attacks, and use smooth bounded trauma shake for HQ damage.

The user's numeric requirements are treated as the approved design. No new unit type, navigation graph, projectile, audio, external asset, or Node-per-unit system is introduced.

## Approaches Considered

1. **All-pairs boids:** simplest steering code, but detection and separation become O(n²) at 400 units. Rejected.
2. **Bucketed boids-lite:** reuse the existing 11 x 22 unit buckets, scan ±3 cells for hostiles and ±1 cell for close allies, then combine advance, seek, and separation. Selected because it changes only the simulation's local query and motion stage.
3. **Flow field plus formations:** can create polished lanes but adds navigation state and formation ownership beyond this scope. Rejected.

## Data Model

`BattleSimulation` remains a `RefCounted` structure-of-arrays model. Add packed arrays aligned with every unit index:

- `unit_speed_scales: PackedFloat32Array`, deterministically sampled from 0.9 through 1.1 at spawn.
- `unit_lunge_timers: PackedFloat32Array`, reset to the configured duration on a successful attack.
- `unit_lunge_directions: PackedVector2Array`, the logical direction toward the attacked target.

All arrays participate in spawn, swap-removal, resize, and stress tests. A reset-seeded RNG gives repeatable tests while applying x spawn variation in the range -0.3 through +0.3 cells. Positions are clamped inside the board.

## Steering and Combat

Every fixed tick rebuilds the existing grid buckets once. For each living unit:

1. Find the nearest hostile unit or building within `UNIT_DETECT_RANGE = 2.5` by scanning the necessary neighboring buckets and the low-count building list.
2. If the target is within `UNIT_ATTACK_RANGE = 0.72`, set attack state, stop translation, face the target, and attack when the cooldown is ready.
3. Otherwise combine normalized forces: forward along team y, seek toward the detected target in both x/y, and separation away from allies closer than `UNIT_SEPARATION_RADIUS = 0.35`.
4. Normalize the combined vector and move at `UNIT_SPEED * unit_speed_scales[index]`. Separation uses a deterministic opposite direction for exact overlaps so two coincident units cannot remain coincident.

Recommended weights are advance 0.70, seek 1.65, separation 2.20. These and all radii/variation/lunge values live in `GameConfig`. Detection retains a target only while it remains within detection range; attack state never advances.

The existing territory calculation continues to floor each freely moving unit's x into a column and use its y as that column's front anchor. Tests cover cross-column pursuit and territory validity after lateral movement.

## Batched Lunge Presentation

`UnitRenderer` still owns exactly two MultiMeshes. It derives a temporary logical lunge offset from each unit's timer and direction using a single out-and-back sine envelope, then projects `position + offset`. No unit node, tween, signal, or per-unit process is created. Hit sparks remain event-driven. Death rings and fragments are reduced to match the now-separated soldier silhouette.

## Trauma Shake

`DefenseFx` replaces random `screen_shake_strength` with:

- `trauma` clamped to 0 through 1.
- HQ hit addition 0.25, accepted no more often than once per 0.5 seconds.
- Normal maximum offset 3 px, scaled by `trauma²`.
- Linear trauma decay per second.
- A deterministic multi-frequency sine direction normalized before amplitude is applied.

HQ destruction calls a separate major-shake method capped at 6 px for 0.4 seconds. The ordinary HQ hit remains primarily a large red/white local flash and HP bar change. Tests sample repeated offsets and prove the ordinary magnitude never exceeds 3 px, trauma caps at 1, cooldown suppresses rapid additions, and trauma decays.

## Verification and Balance

Rule tests prove cross-column attack, exact-overlap separation, packed lunge state, and territory updates under lateral motion. Flow tests prove attack lunge rendering and bounded trauma routing. The automated no-spawner defeat and built-spawner victory paths must still terminate within 180 seconds; the active result time is recorded and combat tuning may change only unit HP, damage, or spawner production interval.

The stress runner keeps 400 data units, widens target scans, measures 300 ticks after warm-up, and retains the 16.667 ms average/p95 gate. Visual QA adds `smoke_cluster.png`, staging mixed teams near the center without replacing the existing opening/advantage/disadvantage captures. CI verifies all four 540 x 960 images and publishes the Godot 4.5 debug APK.
