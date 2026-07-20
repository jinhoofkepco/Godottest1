# Rally Points, Slower Tempo, Counters, and AI Design

## Scope and Diagnosis

This phase replaces legion-producing barracks with continuous class spawners and rally-point-controlled legion assembly. The existing data-oriented unit storage, formation geometry, legion steering/state machine, flow fields, elevation rules, rendering pipeline, and combat readability remain in place.

The previous AI was not completely idle: the passive-player baseline lost in 123.3 seconds. Its strategy did stop after the opening, however, because `UpdateEnemyAi` returned permanently when `CountBarracks(TeamEnemy) >= 3`. It had no state for rally points, counter-picks, defensive posture, or forced spending, so gold and battlefield changes could not cause another decision after the first three buildings.

## Considered Architectures

1. **Rally-owned membership with existing legion SoA (selected).** Individual spawners create ungrouped units. Each unit caches the nearest friendly rally ID. A rally periodically collects arrived members and transfers their IDs into a new or defending legion. This keeps movement and rendering data-oriented and reuses formation slots without per-unit nodes.
2. **Spawner-to-rally delivery queues.** Every spawner would pick one rally and push produced unit IDs into a private queue. It is cheaper to query but gives unintuitive results when a nearer rally is built or destroyed and couples producers to formation policy.
3. **Virtual platoons before units exist.** Spawners would contribute abstract counts and instantiate units only at launch. It is efficient but violates the requirement that produced units visibly walk to and wait at a rally point.

The selected architecture makes rally reassignment and destruction fallback explicit while keeping the existing bulk C#/GDScript boundary.

## Buildings and Production

Building and build-kind IDs are stable and explicit:

- `0`: melee spawner, cost 60, creates MELEE.
- `1`: ranged spawner, cost 80, creates RANGED.
- `2`: defense tower, cost 120, restricted to the existing HQ 5x5 area.
- `3`: dragon lair, cost 220, creates DRAGON.
- `4`: siege workshop, cost 140, creates SIEGE.
- `5`: rally point, cost 80, buildable on any owned, unoccupied cell.

MELEE and RANGED use a 2.88-second production interval, SIEGE 8.64 seconds, and DRAGON 22.5 seconds. These are the restored 1.6/4.8/12.5-second periods multiplied by 1.8. Produced units start with `legion_id = -1` and choose the nearest live friendly rally. With no rally they immediately use existing individual flow-field movement.

## Rally Point State

Each rally building stores:

- `mode`: `ADVANCE = 0` or `DEFEND = 1`.
- `formation`: `LINE`, `WEDGE`, or `LOOSE`.
- cached `waiting_count` for snapshots and AI observation.

Each ungrouped unit stores `rally_point_id`. It follows the selected rally with existing steering, separation, obstacle avoidance, WAIT, and inertia. The arrival radius is 2.8 cells: the earlier 1.7-cell value admitted only the first three-to-four members of a stopped queue and could never reach the ten-member launch condition. A destroyed or invalid rally clears this ID, after which the unit reacquires the nearest live rally or advances individually.

In ADVANCE mode, ten arrived members are selected in stable unit-ID order, role counts are derived from those members, formation slots are assigned with the existing role-first geometry, and a MARCHING legion launches toward the enemy HQ. Remaining units form the next batch.

In DEFEND mode, up to fourteen arrived members form one rally-linked garrison legion. It stays in GATHERING and holds formation around the rally, changes to ENGAGED when a hostile enters the existing legion detection radius, then returns to GATHERING and reforms after the disengage delay. Any members beyond fourteen are grouped from the overflow and launched as a MARCHING legion immediately, even when the overflow group has fewer than ten.

Destroying a rally sets all units targeting it to `rally_point_id = -1`. Its GATHERING or ENGAGED garrison is changed to BROKEN and every surviving member becomes ungrouped, reusing the existing fallback.

## Legion Reuse

Legions retain anchor, heading, formation, GATHERING/MARCHING/ENGAGED/BROKEN, slot offsets, group speed, flow-field movement, engagement seek, separation, and post-combat reformation. The producer/source field is renamed from barracks ID to rally ID. Launched groups are no longer capped by a template; their derived role counts and member count are the source of formation slots. Existing maximum storage remains sufficient for a seven-minute match and stress fixtures.

## Tempo

- Match duration: 420 seconds.
- Occupancy victory: 92%.
- Passive income: 2.25 gold/second.
- HQ maximum HP: 2400 for both teams.
- MELEE speed: 1.015 cells/second.
- RANGED speed: 0.875 cells/second.
- SIEGE speed: 0.56 cells/second.
- DRAGON speed: 1.19 cells/second.

All construction costs remain unchanged. A fully responding match must finish between 300 and 420 seconds; a player who never constructs anything may be defeated earlier. Balance validation records both the passive defeat and a 300-to-420-second active victory path.

## Class Counter Matrix

`ClassDamageMultiplier(attackerKind, targetKind)` is applied only to unit targets and is multiplied with elevation and AoE falloff. Initial non-default values are:

| Attacker | Target | Multiplier |
|---|---|---:|
| RANGED | MELEE | 1.5 |
| MELEE | SIEGE | 1.6 |
| MELEE | RANGED | 1.4 |
| RANGED | SIEGE | 0.7 |
| RANGED | DRAGON | 1.4 |
| DRAGON | RANGED | 1.5 |
| DRAGON | SIEGE | 1.5 |
| MELEE | DRAGON | 0.6 |

All other pairs are 1.0. Final permitted tuning moved RANGED→MELEE to 1.7, MELEE→RANGED to 1.2, RANGED→DRAGON to 1.2, and DRAGON→RANGED to 1.7; every other listed value stayed at its initial value. SIEGE splash applies its attacker/target-kind multiplier per affected unit. A packed hit flag marks multipliers above 1.0 so FX can use the warm strong-hit color without adding dictionary events.

The automated matrix uses equal-gold groups, multiple deterministic seeds, and reports the advantaged side's win rate. Each named favorable matchup must reach at least 75%; values may move by at most 0.2 from the table if the initial geometry produces a lower result.

## AI State Machine

One reusable controller state is stored per team so debug tests can run enemy-vs-passive and AI-vs-AI without a second simulation implementation.

1. **Economy:** keep one rally point early, add a second after four spawners, and spend affordable gold on class spawners. Rally placement searches outward from the center column so queues do not cross the entire map. There is no three-building terminal guard.
2. **Counter-pick:** every decision interval, count hostile MELEE/RANGED/SIEGE/DRAGON units. Weight the build kind that has the highest summed favorable multiplier, with a small base weight for every class.
3. **Battlefield response:** set rallies to DEFEND when that team's occupancy is below 45%, otherwise ADVANCE. A defending rally may be rebuilt closer to the HQ when lost.
4. **Forced spending:** above the configured gold threshold, skip the normal cadence and repeatedly attempt the cheapest useful spawner, a missing rally, or an HQ-zone tower until gold falls below the threshold or no legal cell exists.

AI diagnostics expose decision count, successful builds, failed build searches, forced-spend count, maximum observed gold, and last decision reason in the debug snapshot. Normal gameplay enables enemy AI only; test commands can enable either team and set a deterministic AI seed.

## UI and Rendering

The bottom construction bar contains six compact selectors: MELEE 60, RANGED 80, SIEGE 140, DRAGON 220, RALLY 80, and TOWER 120. Tapping a friendly rally opens a compact editor with ADVANCE/DEFEND, LINE/WEDGE/LOOSE, and DEMOLISH.

Rally snapshots provide mode, formation, waiting count, and team. The board overlay draws an elevated team-colored rally marker. ADVANCE uses a flag plus forward arrow; DEFEND uses a shield-like ring. A top-layer count badge shows waiting members and therefore remains readable through unit occlusion. Existing legion banners continue for launched formations.

## Events and Failure Handling

Spawner production continues to use `unit_produced`. Rally changes use structural `rally_mode_changed`, `legion_launched`, and existing building hit/destroyed events. Invalid construction, edits on enemy/destroyed buildings, and demolition of HQ/tower/spawners are rejected by the public rally editor API. When fixed storage is full, production retries after a short interval without spending or corrupting membership.

## Verification

- Rule tests cover nearest-rally assignment, no-rally advance, ADVANCE launch at ten, DEFEND cap fourteen, overflow launch, rally destruction fallback, defense engage/reform, all three formations, tempo constants, and multiplier composition.
- The counter matrix runs equal-gold matchup trials and requires at least 75% for each favorable matchup.
- AI health runs 50 enemy-vs-passive matches, 50 AI-vs-AI matches, and a full-match gold/build audit. Passive must lose every match. AI-vs-AI uses the standard half-point score for 420-second time-limit draws and requires a 40-60% blue score, 300-420-second average duration, and no construction stall above the forced-spend threshold.
- Smoke captures add a DEFEND garrison and an ADVANCE launch, with visibly different ring/arrow markers and waiting counts.
- Existing deterministic, terrain, flow, siege, stress, board-delta, atlas, render, and Android export checks remain green.
