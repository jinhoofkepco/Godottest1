# Siege and Army Scaling Design

## Scope

Add a fourth packed-data unit kind, SIEGE, while preserving the 22x44 elevation battlefield, fixed-tick simulation, bucket targeting, 2-3 minute match, building nodes, and batched unit renderer. Fix the existing dragon atlas presentation by vertically flipping only the dragon atlas frame UV.

## Simulation

`GameConfig` owns radius, combat, movement, production, projectile, and render-scale constants. `BattleSimulation.get_unit_radius(kind)` is the single source for separation, ordinary range contact, AoE contact, renderer width, shadows, and HP bars. Separation activates inside `(radius_a + radius_b) * 1.2`; ordinary unit hits accept `attack_range + target_radius`.

SIEGE selects the highest-scoring hostile bucket center between 1.2 and 3.5 cells, using nearby hostile counts as density and deterministic distance/id tie-breaking. Firing appends a data-only pending impact with origin, target, team, damage, elapsed time, and duration. Impact queries only buckets intersecting `0.9 + maximum_target_radius`, applies linear 100%-40% falloff using surface distance, damages hostile buildings in the same radius, and never damages allies. SIEGE does not flee when enemies enter its minimum range. Dragons remain valid splash targets.

Enemy build AI cycles MELEE, RANGED, SIEGE. Ground SIEGE follows the existing elevation-aware flow field. Spawner production changes to 1.6 seconds; dragons retain their dedicated lair interval.

## View and feedback

Ground units share one globally Y-sorted MultiMesh and a team texture array. The atlas gains a third 8-direction class baked from the already-vendored CC0 KayKit catapult model; static source motion is enhanced with per-frame bob/recoil in the baker. The dragon-only atlas shader flips frame UV vertically, leaving infantry, direction mapping, grounding, and shadow transforms unchanged.

SIEGE launch emits a projectile event. `fx.gd` stores the shot for its flight duration and draws a ground shadow moving linearly, a projectile following a screen-space parabolic arc, and a persistent orange landing ring. Impact emits a larger flash plus muted earth fragments. These are visibly distinct from straight ranged tracers and ordinary hit sparks.

Five HUD choices remain within 480px. Unit render width derives from radius so MELEE/RANGED are approximately 0.35-0.40 tile width, SIEGE larger, and DRAGON largest. Height, foot anchor, blob shadow, HP-bar width, and death FX follow the same scale family.

## Validation

Rules tests cover radius constants, ordinary contact radius, pair-radius separation, SIEGE minimum range, density selection, delayed impact, AoE target-radius inclusion, falloff, five-unit splash, no friendly fire, building damage, AI SIEGE construction, and four balance scenarios. Game-flow tests cover dragon vertical flip, five-button selection, SIEGE batch/atlas, telegraph/projectile/impact feedback, and radius-derived render scale. Smoke capture adds large-army and SIEGE-impact frames. Stress uses 600 mixed units and includes live SIEGE impacts with bucket-bounded candidate counts.
