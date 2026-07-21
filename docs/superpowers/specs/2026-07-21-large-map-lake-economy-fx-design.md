# Large Map, Lake, Economy, Construction, and Combat FX Design

## Goal

Expand the existing Godot 4.5 .NET frontline simulation to a 44-by-88 battlefield, add one strategically meaningful central lake, slow production, make construction visible and time-based, scale rally formations and building durability, cap each army at 300 living units, and expose a five-level enemy income control. The approved procedural flag and combat-effect cleanup is included in the same delivery. Existing data-oriented C# simulation, bulk snapshots, MultiMesh rendering, mobile portrait controls, combat rules not explicitly changed here, and GitHub Actions Android export remain intact.

## Locked Rule Changes

- The board grows from 22 by 44 to 44 by 88, for 3,872 cells.
- Advance rallies launch at 20 waiting units. Defend rallies hold 28 units and auto-launch overflow in groups of at most 20.
- RANGED maximum HP becomes 20.4, exactly 60 percent of the current 34.
- Every production rate is halved by doubling its interval: normal spawners 5.76 seconds, SIEGE spawners 17.28 seconds, and dragon lairs 45 seconds.
- Player-built construction time is `cost * 0.1` seconds: MELEE 6, RANGED 8, RALLY 8, TOWER 12, SIEGE 14, and DRAGON 22 seconds. The two starting HQs are complete immediately.
- All building maximum HP values, including both HQs, become five times their current values: spawner 1,200, rally 1,300, tower 1,600, dragon lair 1,500, and HQ 12,000.
- SIEGE damage against the shield-bearing MELEE class gains a `1.5` class multiplier. It multiplies with elevation and SIEGE blast falloff.
- Each team may own at most 300 living simulation units. Death presentation ghosts do not count.
- Every complete block of 30 living units subtracts 10 percentage points from that team's gold-income multiplier: 0-29 units is 100 percent, 30-59 is 90 percent, through 270-299 at 10 percent, and 300 at 0 percent.
- The unit-count multiplier applies to passive income and kill rewards. Fractional income is retained in the existing remainder accumulator so no value is lost merely because a tick or reward is fractional.
- Enemy income has a player-adjustable difficulty level from 1 through 5. The income multipliers are 1.0, 1.25, 1.5, 1.75, and 2.0. Level 3 is the default and therefore gives the requested 1.5 enemy-to-player income ratio before each team's unit-count penalty.
- Difficulty changes affect future passive income and kill rewards only. They do not rewrite current gold.

## Architecture

`BattleSimulation` remains the single rules authority. `BattleConfig` and `game_config.gd` expose matching constants. Water, construction progress, team counts, income multipliers, and AI difficulty are all C# simulation state. GDScript receives only bulk board, building, render, event, and HUD snapshots; it does not run timers or duplicate economy decisions.

The existing fixed 30 Hz step, spatial buckets, flow fields, decision staggering, unit SoA arrays, pooled impacts, board versioning, delta delivery, and one-buffer MultiMesh uploads remain. Debug-only stress injection may bypass the 300-unit gameplay cap so the existing 600, 1,500, and 3,000-unit profiling fixtures continue to measure the core. Normal spawners, normal debug gameplay commands, and AI cannot bypass the cap.

## Central Lake and Pathing

Terrain generation adds a fixed-size `PackedByteArray`/`byte[]` water mask beside elevation. One centered, point-symmetric lake occupies an irregular oval approximately 20 columns wide and 18 rows tall. The shoreline uses deterministic, mirrored edge variation from the terrain seed, but remains one connected body. It leaves broad reachable land corridors on both sides.

Water cells have these rules:

- Ground units cannot enter or cross them.
- Ground legion anchors, rally steering, spawn placement, and ground target repositioning use the same restriction.
- Buildings cannot be placed on them.
- Dragons ignore water for movement, just as they ignore ground obstacles.
- Water cells are neutral and excluded from the occupancy denominator. They cannot flip ownership or create frontline segments.
- Flow fields mark them impassable for ground armies. Required-path validation verifies both HQ regions still connect around the lake on at least one side, and the symmetric generator keeps both side routes fair.

The initial board snapshot contains the water mask. It is immutable for a match and therefore needs no delta channel. The tile MultiMesh encodes water in instance custom data. Its shader renders muted deep blue with a low-amplitude time-based shimmer. A static shoreline layer draws a thin light rim once. No water node is created per cell.

The existing board-fit calculation automatically fits the larger diamond into the portrait frame. Pinch zoom, mouse wheel zoom, panning, elevation-aware picking, and maximum zoom remain available. Picking must return the displayed tile on land and water; build validation then rejects water.

## Construction State

The `Building` struct gains construction duration, remaining time, and completion state. `TryBuild` spends gold and reserves the cell immediately. An incomplete building blocks construction and ground movement, appears in building snapshots, can be targeted and destroyed, but cannot produce units, attack, act as a rally, or count as an active AI facility.

Construction begins at 20 percent of maximum HP and adds the remaining 80 percent evenly over the configured duration. Incoming damage subtracts normally and persists; construction HP gain does not restore damage faster than the scheduled build rate. If HP reaches zero before completion, the ordinary destruction path runs. Completion emits one structural event, initializes the production timer to its full interval, enables the building function, and rebuilds affected flow and AI caches only when needed.

The building view uses the existing atlas, darkens and lowers opacity while incomplete, and shows a compact construction-progress bar. A short procedural completion pulse replaces any opaque build flash. HQs never enter this state.

## Rally and Formation Scaling

`RallyLaunchSize` becomes 20 and `RallyDefenseCapacity` becomes 28. Runtime rally-created legions support these sizes even though legacy editable templates remain capped separately. Formation slot generation wraps large formations into bounded ranks instead of making one excessively wide row:

- LINE keeps MELEE in two broad front ranks and RANGED/SIEGE behind.
- WEDGE extends the existing triangle with additional rear ranks.
- LOOSE uses a wider multi-row grid with its current doubled spacing behavior.

Gathering units continue to ignore the ordinary forward WAIT gate so a crowded entrance cannot freeze the counter below its threshold. The rally badge and editor text show 20/28. Defend overflow launches in chunks up to 20 and never creates a zero-size or untracked legion.

## Unit Cap and Income Scaling

The simulation caches a living-unit count per team during the existing bucket rebuild. Gameplay spawning checks the relevant team count before allocating an ID. At 300, the spawner pauses with no backlog and retries on a short capped timer. Once a unit dies, production resumes without generating missed units in a burst.

The shared income function is:

`unit_factor = max(0.0, 1.0 - floor(living_units / 30) * 0.1)`

`team_income = base_income * unit_factor * (enemy_difficulty_multiplier if enemy else 1.0)`

The function is used for passive income and kill rewards. Refunds from failed construction and debug gold assignment are not income and are not multiplied. HUD snapshots expose ally/enemy living counts, ally income percent, AI difficulty level, and its multiplier in one bulk dictionary.

## Enemy Difficulty UI and AI

The status panel gains a compact `AI 3 x1.50` button and an `UNITS n/300 // INCOME p%` line. Pressing the AI button cycles 1 through 5 during an active match and calls one `SetAiDifficulty(level)` boundary method. The selection survives only until restart unless explicitly changed again; a restart defaults to level 3 for predictable review builds.

The AI uses only completed buildings when counting facilities and planning production. It may start another construction while earlier work is incomplete if it has gold and building capacity. Forced-spend logic remains, but cannot spend beyond available build cells or treat incomplete spawners as active. All enemy income sources use the chosen difficulty multiplier.

## Procedural Legion Flags

The current 18-by-24 solid `QuadMesh` is replaced with a small composite procedural mesh: dark pole, short top finial, notched cloth silhouette, and subtle underside/shadow. Instance color tints only the cloth strongly; the pole remains neutral. The flag is offset above the legion anchor, uses lower alpha than units, and has a dark edge so it remains readable without hiding soldiers.

The existing packed banner buffer remains one bulk upload. Legion state and formation stay in custom data. A compatibility-safe canvas-item shader adds only a slight cloth-wave offset and state-dependent brightness. ENGAGED is brighter, GATHERING is dimmer, and BROKEN still removes the banner. There are no banner nodes per legion.

## Transparent Combat FX

The FX layer retains its 40-minor-effect frame budget and all current event meanings. External bitmap effects are unnecessary. Procedural changes follow these readability rules:

- RANGED, tower, and HQ shots use a thin team-colored trail at low alpha plus a shorter bright core. They no longer draw a five-pixel opaque beam across the battlefield.
- Unit hits use four to six tapered directional rays and a small center flash. Strong class-counter hits remain warm orange; ordinary and high-ground hits remain visually distinct.
- SIEGE flight keeps the gameplay telegraph, but the ground ring is thinner, segmented, and mostly transparent. The projectile has a small bright head, fading arc trail, and separate ground shadow.
- SIEGE impact uses a brief center flash, expanding translucent ring, and soft dust fragments. It does not cover units with a filled opaque disk.
- Unit death uses a compact contracting pop and small fading shards. Rectangular opaque fragments are removed.
- Construction completion, production, building damage, and HQ damage keep distinct silhouettes with lower fill opacity. Screen shake remains absent.

Durations and peak alpha are centralized as tuning constants. Minor effects peak below 0.72 alpha; large SIEGE/HQ center flashes may reach 0.85 only for their first few frames. Effects remain on the high-z overlay so terrain and unit sorting are unchanged.

## Snapshot and Rendering Changes

The initial board snapshot adds `water`. Building snapshots add `construction_progress` and `complete`. HUD snapshots add the new counts and difficulty fields. Board deltas continue to carry only mutable ownership, blocked cells, and building records. Water never causes a board-version update after reset.

The 3,872 tile transforms are still written once at initialization. Ownership changes update only changed instance colors/custom data. Frontline construction ignores water edges. Static cliff and shoreline geometry builds once. Unit and flag buffers remain bulk C# arrays, and GDScript performs no per-unit C# calls.

## Validation

Automated rule and integration coverage will include:

1. The board contains exactly 44 by 88 cells and one connected, symmetric central water body of the configured scale.
2. Ground movement, flow, building, rally anchors, and ground spawning reject water while dragons cross it.
3. Both HQ regions remain reachable by ground paths around the lake.
4. Water is excluded from occupancy and cannot emit ownership/frontline deltas.
5. Rally advance launches at 20, defense holds 28, overflow launches, and crowded gathering does not stall below threshold.
6. RANGED HP is 20.4 and all production intervals are doubled.
7. Every building type uses `cost * 0.1` construction time, stays inactive while incomplete, and activates exactly once.
8. Building/HQ maximum HP values are five times the previous values.
9. SIEGE-to-MELEE class damage is 1.5 before terrain and falloff multiplication.
10. Each side stops normal spawning at 300 and resumes after a death without backlog burst.
11. Income percentages match every 30-unit boundary, and difficulty levels map to the five locked enemy multipliers for passive and kill income.
12. Restart restores AI level 3 and the HUD button changes future income without modifying current gold.
13. Renderer contracts prove the banner is no longer a QuadMesh, banner alpha is bounded, and no per-legion node/getter loop is introduced.
14. FX contracts cover peak alpha, thin tracer widths, distinct strong-hit color, SIEGE telegraph lifetime, frame cap, and zero shake.

Smoke captures add a full-map lake overview, ground armies splitting around both shores with dragons crossing, an in-progress and completed building pair, a 20-unit launch, a 28-unit defense formation, a close flag view, and a large battle with the revised transparent FX. Existing rule, flow, elevation, AI health, counter-matrix, stress, board-delta, atlas, headless import, scene smoke, and Android export checks remain required. Stress fixtures retain their debug cap bypass and add a normal 300-versus-300 capped battle case on the 3,872-cell board.

## Delivery

After local import, rules, smoke, render, and stress verification, changes are committed and pushed to `jinhoofkepco/godottest1` on `main`. The existing Android GitHub Actions workflow builds the Godot 4.5 .NET debug APK and uploads `godottest1-debug-apk`. A direct GitHub release APK is updated only after the workflow artifact succeeds.
