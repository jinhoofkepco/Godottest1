# Elevation Terrain Design

## Goal

Add deterministic three-level terrain to the 22x44 isometric battlefield while preserving the data-oriented unit simulation, fixed-tick flow-field movement, dynamic territory rules, and mobile rendering budget.

## Chosen Architecture

`TerrainMap` is a data-only `RefCounted` that owns one `PackedByteArray` of elevation values. It generates mirrored hill clusters, validates HQ-to-deployment reachability, and exposes step legality and elevation lookups. `BattleSimulation` retains the public `elevation` array and delegates terrain rules to this helper. The old `blocked` array remains empty as a compatibility surface for older fixtures; ground blocking comes from buildings and elevation transitions only.

Alternatives considered:

- Keeping all generation and path rules inside `BattleSimulation` would minimize files but further enlarge an already broad class and couple map generation to combat.
- Making `GridBoard` own elevation would simplify drawing but leak view data into movement and flow-field logic.
- A separate terrain data object gives generation, reachability, and stepping one testable boundary and keeps the view read-only. This is the selected approach.

## Terrain Generation

- Elevation is exactly 0, 1, or 2 for every cell.
- A seeded generator stamps several soft level-1 hill clusters in the central band and a smaller level-2 summit inside selected hills.
- Every stamp is mirrored through the board center, so red and blue receive identical terrain after a 180-degree rotation.
- HQ cells and deployment corridors near both HQs remain level 0.
- A generation candidate is accepted only when all configured deployment candidate cells can reach the opposing HQ using eight-neighbor steps with elevation difference at most one. Failed candidates advance the deterministic seed and retry.
- Legacy prop blockers are removed from runtime rendering and movement. Elevation cliffs replace their tactical role.

## Movement and Flow

- Ground units can cross a cell boundary only when the absolute elevation difference is at most one. Dragons ignore elevation for movement.
- Entering a higher cell multiplies ground-unit speed by `UPHILL_SPEED_MULTIPLIER` (0.7); level and downhill movement retain normal speed.
- The flow field receives elevation and adds `UPHILL_COST` when its integration expansion represents a unit climbing from the sampled neighbor toward the current cell. Transitions with a difference of two are excluded. Existing distance and congestion terms remain additive.
- Collision sliding tests the full motion, then X-only, then Y-only while applying the same elevation transition rule.

## Combat

- Unit attack range is calculated from unit kind and current attacker cell. Ranged infantry on elevation 1 or 2 gains `RANGED_HIGH_GROUND_RANGE_BONUS` (0.5 cell).
- Unit attacks compare attacker and target cells. Higher-to-lower damage uses 1.25, lower-to-higher uses 0.75, and equal elevation uses 1.0.
- Building targets use their cell elevation. Static building attacks use the same elevation multiplier against their target unit.
- Hit events include a `high_ground` flag. The FX layer renders high-ground impact sparks slightly larger and brighter without changing gameplay timing.

## Rendering and Picking

- Flat isometric projection remains available as `grid_to_screen`. Elevated world positions subtract `ELEVATION_PIXEL_STEP` (half a tile height) per elevation.
- Tiles draw from back to front with elevation-adjusted top diamonds. Visible cliff edges receive dark side-wall polygons whose depth is derived from the neighboring lower cell.
- Territory colors are brightened by a small fixed step per elevation while remaining muted relative to actors. Front-line edges follow elevated tile vertices.
- Units, shadows, death ghosts, HP bars, buildings, placement feedback, projectiles, and hit effects all sample the relevant cell elevation before projection.
- Picking scans nearby candidate cells around the flat inverse and tests the elevated top-diamond polygon. Candidates use reverse visual depth priority, making the visible top surface the selected cell. `cell_to_world` returns the elevated center.
- Board bounds include the maximum upward height offset so fitting and panning do not clip summits.

## Tests and Performance

- Rule tests cover packed elevation shape/range, deterministic mirror symmetry, deployment-to-HQ reachability, cliff rejection, slope passage, uphill slowdown, elevation damage multipliers, ranged high-ground range, and elevated round-trip picking.
- Flow tests verify cliff exclusion and uphill cost preference.
- Game-flow tests verify building/unit/FX projection through the shared elevated conversion.
- Smoke capture adds an elevation overview and a high-ground engagement close-up.
- Stress measurement remains 400 mixed units and reports updated average, p95, maximum tick cost, and target candidate count.

## Scope Guard

No new unit types, economy changes, territory rule changes, building restrictions, height editing UI, fog, erosion, physics bodies, or 3D terrain are added.
