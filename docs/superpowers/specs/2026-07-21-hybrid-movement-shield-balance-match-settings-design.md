# Hybrid Movement, Shield Balance, and Match Settings Design

## Goal

Eliminate convex-corner unit traps and ranged-unit queues, add the requested shield/siege/dragon balance pass, and let the player edit and copy detailed unit tuning before a match without abandoning the data-oriented C# simulation or bulk rendering path.

## Locked interpretation

- The approved movement solution is the hybrid approach: clearance-aware flow navigation, deterministic stuck recovery, ranged firing-position reservation, and asymmetric friendly yielding.
- A MELEE unit is the shield soldier. It enters shield mode when a hostile RANGED unit is detected.
- Shield mode multiplies movement speed by `0.20` and damage received from RANGED attacks by `0.10`. MELEE, SIEGE, DRAGON, tower, and HQ damage are not reduced.
- Shield mode uses a `2.5` cell enter range and a `3.0` cell release range so the mode does not flicker at the boundary.
- SIEGE production throughput is increased by 40%, so its interval changes from `17.28` to `17.28 / 1.4 = 12.342857` seconds.
- SIEGE attack range changes from `7.0` to `14.0` cells and blast radius changes from `0.9` to `1.8` cells. Damage remains `55.8`.
- DRAGON production remains on a 45-second cycle but produces two units per completed cycle. At 299/300 population it produces one unit; at 300/300 it produces none.
- DRAGON HP changes from `260` to `520` and damage changes from `18` to `36`.
- Match settings apply identically to BLUE and RED. AI income level remains the separate difficulty control.
- The settings copy action exports canonical, sorted JSON. Import/paste is outside this request.

## Runtime settings architecture

`BattleConfig` remains the compile-time source of map, renderer, performance, and default values. A new `BattleMatchSettings` instance is owned by each `BattleSimulation`; simulations never share mutable tuning.

The settings object contains four unit profiles plus special rules and the class damage matrix. Each profile exposes:

- max HP
- attack damage
- attack interval
- maximum attack range
- detection range
- movement speed
- collision radius
- production interval
- units per production batch
- spawner cost
- damage multipliers against MELEE, RANGED, SIEGE, and DRAGON

Special fields are:

- MELEE: shield enter range, shield release range, shield speed multiplier, shield RANGED-damage-taken multiplier
- RANGED: standoff distance, high-ground range bonus, preferred firing-range ratio
- SIEGE: minimum range, blast radius, edge damage multiplier, projectile flight seconds

The C# / GDScript boundary remains bulk-only:

- `GetMatchSettingsSchema()` returns the UI field schema.
- `GetMatchSettings()` returns the current canonical settings dictionary.
- `ConfigureAndReset(Dictionary values)` validates the complete payload, atomically applies a normalized clone, resets the match, and returns `{ok, errors, normalized}`.

Invalid or non-finite values are rejected without partially changing the active profile. Cross-field validation enforces positive HP/damage/intervals, `min_range < range`, `standoff < range`, `detect_range >= range`, integer batch sizes of at least one, and bounded radii/multipliers.

## Movement and collision design

### Shared transition rules

Flow construction, reachability checks, obstacle response, and physical integration use one ground-transition predicate. It accounts for water, buildings, elevation difference, diagonal corner pinching, and the unit clearance class.

Ground navigation has two clearance classes:

- infantry for MELEE and RANGED
- heavy for SIEGE

DRAGON continues to ignore ground blocking.

The flow field stores both integration cost and the chosen next cell. Steering aims at a safe portal point inside that transition instead of using one constant direction for the whole source cell. Cliff transitions are treated as obstacles by local steering, and per-unit flow noise is suppressed near obstacles.

### Deterministic stuck recovery

Each ground unit keeps a small SoA progress timer. If desired speed is non-zero but movement stays below `0.05` cells for `0.40` seconds, the unit enters recovery. Recovery first chooses the legal neighboring transition with the lowest integration cost and a deterministic ID-based side tie-break. If that still cannot reduce cost, a bounded `9x9` local search selects a reachable cell up to four flow cells ahead. Only stuck units run this search.

During recovery, target seek noise and hard formation-slot following are reduced. A legion slot that lies in blocked terrain is projected to the nearest valid local point; narrow terrain temporarily compresses the formation rather than pulling members through a cliff.

### Ranged firing positions and yielding

Combat targeting and approach positioning are separate. RANGED keeps its selected combat target, but approaches a reserved point on a shallow annulus at the configured preferred range.

For a target, up to 16 deterministic candidates are sampled and scored by:

- passability and attack range
- flow/integration cost
- local friendly density
- distance from the unit
- reservation occupancy and angular separation

Reservations refresh at the existing staggered decision rate and expire when the target dies, leaves detection range, or the slot becomes unreachable. No per-unit Nodes or per-frame dictionaries are introduced.

An in-range attacker no longer skips all local movement. It can attack while applying low-strength separation and lateral slot correction. A unit moving to a valid firing slot receives higher yielding priority than a stationary friendly attacker; the blocker receives a small terrain-validated sideways displacement. WAIT is retained only when no legal lateral path or firing position exists.

## Shield simulation and rendering

Shield state is stored in a `PackedByte`-equivalent SoA array and updated on the staggered decision pass by querying existing spatial buckets. A RANGED hit may activate the shield immediately so the first encountered arrow receives the requested reduction.

The state is copied through swap-remove and exposed in debug/render snapshots. Infantry MultiMesh instance data carries the shield flag. The existing unit atlas shader draws a subtle translucent cyan shield rim over a shielded MELEE sprite, preserving one infantry draw call and making the mode readable without a new external asset.

AI counter scoring uses effective damage. While shield mode is relevant, `RANGED -> MELEE` is evaluated with the shield multiplier so the AI does not endlessly counter shield formations with archers.

## Production behavior

Spawner production loops over the configured batch count. Each individual spawn uses the existing team cap check and emits its own production event. Spawn positions use the existing ground/flying placement helper and therefore route both dragons independently to the closest rally point.

Production interval, batch count, costs, and construction time remain linked: changing a spawner cost in the match settings also changes construction time through the existing `cost * 0.1 seconds` rule. HUD build labels read the active runtime costs instead of fixed strings.

## Start settings UI

A new full-screen `MatchSettingsPanel` opens before simulation time begins. The map is visible but non-interactive behind an opaque dark panel. Four unit tabs contain a portrait-safe `ScrollContainer` of labeled numeric controls. Changed values are orange; invalid rows are red.

The fixed bottom actions are:

- `DEFAULTS`: restore the shipped profile
- `COPY JSON`: serialize the pending profile with a schema version and call `DisplayServer.clipboard_set`
- `START`: call `ConfigureAndReset`; only a successful atomic response closes the panel and enables map input

The result-screen restart returns to this same settings panel with the last values, allowing another tuned match without editing files.

## Verification

Automated tests must cover:

- physical traversal around a convex cliff protrusion, including a legion member footprint
- eight queued RANGED units forming a lateral firing line with at least four distinct shooters
- WAIT remaining stable in a genuinely single-width blocked corridor
- shield enter/release hysteresis, 20% speed, 10% RANGED damage, and no reduction for other classes
- SIEGE interval/range/blast defaults and expanded AoE behavior
- DRAGON two-unit batch, 299-cap partial batch, HP, and damage
- settings schema, per-simulation isolation, atomic validation, normalized apply/reset, and JSON round trip
- start modal pausing simulation and blocking map input until START
- 600-unit stress after firing reservations and expanded SIEGE searches

Godot runtime verification uses the official Godot 4.5 .NET executable. Test runners must fail if `BattleSimulation` does not load, preventing false PASS results from a non-.NET editor.
