# Mini Battle Agent AI Design

## Goal

Create a branch-only Godot 4.5 .NET experiment that stages 30 blue shield infantry against 30 red shield infantry around a deliberately congested central obstacle. Every unit owns independent perception, memory, utility scores, and action state. The experiment must show whether local decisions can produce useful frontage filling, yielding, flanking, and replacement behavior without unit Nodes or per-unit pathfinders.

## Isolation

- Work only on `codex/mini-battle-agent-ai`.
- Do not merge the experiment into `main`.
- Keep the existing production simulation and its scenes unchanged.
- Add an independent simulation and scene inside the existing Godot project so the branch reuses the verified Godot 4.5 .NET and Android setup.
- On this branch, make the experiment scene the default main scene so opening or running the branch starts the lab directly.

## Considered Approaches

### Modify `BattleSimulation`

This would provide the quickest visual integration but would mix an experimental paradigm with production legion, rally, economy, terrain, and AI behavior. It is rejected because a failed experiment would leave a large and ambiguous production diff.

### Create a nested Godot project

This gives complete filesystem isolation but duplicates the .NET project, export settings, CI assumptions, and project configuration. It is rejected because the branch already provides source isolation.

### Independent lab scene in the existing branch

This is the selected approach. A new C# simulation owns only the 60-agent experiment, a new GDScript presenter draws it procedurally, and dedicated tests exercise the lab. Existing production files remain available for regression checks but are not dependencies of the experiment core.

## Battlefield

- Logical arena: 28 columns by 36 rows.
- Team size: exactly 30 shield infantry per team.
- Blue starts in six staggered ranks at the bottom and advances upward.
- Red starts symmetrically at the top and advances downward.
- A horizontal central fortification creates a narrow central gate plus longer left and right bypasses.
- The central gate is intentionally the shortest route so naive agents pile into it.
- The two side routes remain viable so congestion-aware agents can choose to flank.
- Terrain and spawns are mirror-symmetric; deterministic personality variation is derived from unit ID and seed.

## Agent Model

All units share one C# decision implementation but keep independent data:

- position and velocity;
- HP, attack cooldown, and last damage time;
- current action and action commitment timer;
- current target;
- perceived friendly congestion and hostile pressure;
- stuck duration and last progress position;
- preferred flank side;
- aggression, discipline, and self-preservation traits;
- whether the unit has ever attacked, yielded, flanked, or crossed the choke.

No unit is a Godot Node. Arrays and fixed-capacity spatial buckets store all data.

## Perception

An agent only inspects nearby buckets and a bounded number of neighbours. It can perceive:

- the nearest attackable hostile;
- friendly density ahead, left, and right;
- hostile density in the same sectors;
- a stationary friendly blocker;
- open candidate velocities;
- local terrain obstruction;
- its own recent lack of progress.

Decisions run at 5 Hz and are staggered across five groups. Movement, cooldowns, and attacks remain on a 30 Hz fixed simulation tick.

## Utility Actions

Each decision assigns scores to these actions:

- `ADVANCE`: follow the shortest available route toward the opposing rear line;
- `ENGAGE`: close with and attack a reachable hostile;
- `FILL_GAP`: move toward a locally under-defended point of the contact front;
- `FLANK_LEFT` and `FLANK_RIGHT`: choose a side bypass when forward friendly congestion is high;
- `YIELD`: step aside when another friendly has greater forward priority;
- `HOLD`: preserve spacing when advancing would only deepen a jam;
- `RETREAT`: leave immediate contact at critically low HP.

The winner is selected by the highest score, subject to a short action commitment and hysteresis so actions do not oscillate every decision.

## Movement and Collision

- Three deterministic route fields guide the centre, left, and right approaches for each team.
- The chosen utility action selects a route field or a local combat target.
- Each agent samples a small fixed set of candidate velocities and scores progress, predicted collision, friendly pressure, and terrain validity.
- Two lightweight position-based separation passes correct actual overlap after integration.
- A moving unit can request passage; a holding or lower-priority unit yields laterally.
- Waiting does not erase the stuck timer. Lack of progress raises flank and yield scores.
- Agents accept approximate positions; there are no exact formation slots.

## Combat

- Shield infantry use short-range melee attacks with identical base statistics.
- Target saturation is limited so all rear units do not select the same opponent.
- Agents that cannot reach their target re-evaluate `FILL_GAP`, flank, yield, or hold instead of retaining a useless target.
- When a front fighter dies or retreats, nearby rear agents receive a strong `FILL_GAP` score.
- A holding rear agent remains purposeful: it faces the front and is counted separately from a pathological idle agent.

## Baseline Comparison

The same simulation supports a deterministic `BASELINE` mode:

- all units choose the central route;
- blockers cause simple waiting;
- there is no flank, passage negotiation, gap filling, or action hysteresis.

Both modes use the same terrain, spawn positions, HP, damage, timing, and seed. This makes the experiment a behavioral comparison rather than a balance comparison.

## Metrics

The lab records:

- alive count and result;
- units that ever attacked;
- units that crossed the centre line;
- flank decisions and side-route crossings;
- yield decisions;
- frontline replacements;
- pathological idle-agent seconds: alive, outside attack range, almost stationary, and making no progress for at least two seconds;
- maximum continuous stuck time;
- overlap violations after correction;
- average and worst fixed-tick time;
- per-action population counts.

The presenter shows the main metrics live and colors each shield rim by action.

## Acceptance Criteria

For the fixed seed 230723:

1. Both modes start with exactly 30 units per team in mirror-symmetric positions.
2. The baseline reproduces a visible central bottleneck and non-zero pathological idle time.
3. Agent mode produces flank or yield decisions and side-route use.
4. Agent mode has lower pathological idle time and more units that ever attack than baseline.
5. At least 70 percent of surviving agent-mode units either attack, cross the centre line, flank, yield, or intentionally hold near the front.
6. No unit remains overlapped below the allowed separation tolerance after correction.
7. The experiment reaches a result or the fixed 120-second scoring timeout.
8. Sixty-agent average simulation tick stays below 1 ms on the development machine with no managed GC collection during the measured run.

## Presentation

- Portrait 540 by 960 procedural scene.
- Dark muted arena, blue and red shield silhouettes, pale walls, and colored action rims.
- A legend explains action colors.
- HUD shows time, alive counts, active participation, idle seconds, action counts, average tick time, and result.
- Controls: `AGENT AI`, `BASELINE`, `PAUSE`, `1X/2X`, and `RESET`.
- A deterministic unattended capture records the congested mid-battle state for visual review.

## Non-Goals

- No economy, buildings, territory, dragons, ranged units, siege units, or player construction.
- No production balance changes.
- No neural network, LLM, GOAP search, or per-unit Godot physics body.
- No attempt to merge the experiment into the shipping game in this branch.
