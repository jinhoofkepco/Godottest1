# Expanded Frontline, Ranged Units, and Zoom Design

## Goal

Expand the data-oriented frontline simulation to a 22×44 battlefield, remove all camera shake, make captured territory persistent, route edge-breakthrough units toward the enemy HQ, add selectable ranged spawners, add deterministic central obstacles, and support zoom/pan without introducing per-unit Nodes.

## Fixed interpretation

- “Four times the tiles” means doubling both dimensions: 11×22 → 22×44, for 968 total tiles.
- The player selects either a melee spawner or ranged spawner in the HUD, then taps an owned, unblocked tile to build it.
- Obstacles are blocked terrain. They are generated deterministically from a fixed seed in the central band, mirrored across the board center for fairness, and rendered procedurally.
- Zoom range is 1.0× overview to 2.5× detail. Default zoom is 1.35×. Touch uses pinch zoom and one-finger drag; desktop uses wheel zoom and left-drag. A stationary tap still builds.
- Existing match rules remain: 180-second limit, HQ/90% territory/time-up victory, passive income, kill rewards, and data-only units.

## Root causes being fixed

### Territory snap-back

`recalculate_territory()` currently reconstructs every tile from only the units and buildings present in each column at that instant. When the only forward unit leaves a column, that column falls back to the initial HQ-to-HQ midpoint in one tick. The fix must preserve ownership and apply only active conquest/recapture claims.

### Units stuck at the far edge

Movement clamps units to y=0.5 or y=rows−0.5. Target acquisition only considers hostiles inside `UNIT_DETECT_RANGE`, so a unit at the edge but several columns away from the HQ has no horizontal steering target. The fix must provide an enemy-HQ target after reaching the terminal band when no local hostile is available.

### Camera shake

`DefenseFx` still accumulates trauma and `DefenseMain` applies `get_screen_shake_offset()` to `World.position`. Both the producer and consumer will be removed from gameplay. HQ hit and destruction remain readable through the building flash, HP bar, rings, and collapse FX only.

## Considered territory approaches

1. **Persistent column supply lines — selected.** A forward unit claims the continuous cells behind it back toward its own HQ. Ownership is not reset when that unit changes column. An opposing advance overwrites the same cells and therefore recaptures them. This keeps a readable front, avoids holes, and directly fixes the disappearing-column bug.
2. **Individual tile paint trails.** Units claim only the tile under their feet. This is simple but produces scattered checkerboard ownership and makes 90% occupation impractical on 968 tiles.
3. **Continuous influence field.** Each unit contributes weighted influence to nearby tiles. This creates organic borders but costs more per tick, introduces tuning ambiguity, and is unnecessary for the requested lightweight simulation.

## Simulation architecture

### Persistent territory

- `ownership` remains initialized as red upper half and blue lower half.
- Each territory update starts from existing ownership instead of clearing it.
- For each column, compute the current furthest red front and blue front from living units and undestroyed buildings.
- Red claims from row 0 through its active front. Blue claims from its active front through row 43.
- If both active claim ranges overlap, split only that contested overlap at the midpoint of the two active fronts.
- If a team has no active claimant in a column, its previous ownership in that column remains untouched.
- Emit `territory_changed` only for cells whose owner actually changes. The HUD continues to count the same persistent ownership array.

### Expanded map and obstacles

- `GRID_COLUMNS = 22`, `GRID_ROWS = 44`.
- A `blocked` `PackedByteArray` is owned by `BattleSimulation` and exposed through `is_blocked(cell)` and `get_blocked_cells()`.
- Reset generates 16 mirrored obstacle pairs in rows 14–29 with seed 42517. HQ cells, the outer two rows, and the initial spawner rows remain clear. No row receives more than four blocked cells.
- Building checks reject blocked cells.
- Steering adds local obstacle repulsion. Final motion uses full movement first, then x-only/y-only slide candidates, and stops rather than entering a blocked cell.
- Obstacles affect navigation and building only; the tile beneath still has team ownership and counts toward occupation.

### HQ fallback

- Normal nearest-hostile unit/building targeting remains unchanged inside detection range.
- When an ally reaches y≤1.25 or an enemy reaches y≥42.75 and has no local target, target the opposing HQ regardless of distance.
- The existing seek force then supplies both x and y steering until the unit enters attack range.
- Nearby enemies still take priority, so edge units do not ignore active combat.

### Unit kinds and combat

Units remain structure-of-arrays data. Add aligned `unit_kinds: PackedInt32Array`; no unit Nodes, signals, or individual process methods.

| Stat | Melee | Ranged |
|---|---:|---:|
| Spawner cost | 60 | 80 |
| HP | 48 | 32 |
| Speed | 1.45 | 1.25 |
| Attack range | 0.72 | 2.40 |
| Damage | 1.40 | 1.00 |
| Attack interval | 0.65 s | 0.90 s |

- `try_build_spawner(team, cell, unit_kind)` stores the selected kind on the building record.
- Spawners produce their recorded kind. Enemy AI alternates melee/ranged when funds allow.
- Ranged damage remains hitscan for simulation cost. Its attack event includes origin, target, and kind; FX draws a bright short tracer so ranged fire is unambiguous.
- Rendering uses four MultiMeshes (team × kind). Ranged units have a smaller diamond/launcher silhouette distinct from the melee soldier.
- Buildings display a melee blade mark or ranged diamond mark so the selected production type is visible after placement.

## View and input architecture

Create `MapView` on the existing `World` node. It owns only view transforms and gestures; simulation still uses logical grid coordinates.

- `setup(grid, frame_rect)` calculates fit scale and centers the board.
- `set_zoom_at(value, screen_focus)` preserves the logical point below the finger/cursor while zooming.
- `pan_by(delta)` moves the world and clamps it so the board cannot be lost outside the play frame.
- `screen_to_cell(screen_position)` uses the World inverse transform and the unchanged `GridBoard.world_to_cell()`.
- Mouse wheel changes zoom. Mouse/touch drag beyond 10 px pans and suppresses building. A release below that threshold emits `tile_tapped(cell)`.
- Two active touches drive pinch scale and midpoint pan. Pinch never emits a build tap.
- HUD controls consume their own events, so selecting a spawner does not pan or build behind the button.

## HUD and visual feedback

- Add MELEE 60 and RANGED 80 buttons above the bottom instruction strip.
- Selected type has the bright team-blue border; the other is dark. Default is melee.
- Main stores `selected_unit_kind` and passes it into `try_build_spawner`.
- Obstacles render as raised neutral charcoal diamonds with a teal-gray top edge.
- Ranged projectiles use a bright cyan-white line and a compact endpoint spark.
- HQ hit/destruction retain red/white local flashes, HP reduction, and collapse effects with exactly zero world offset.

## Testing and acceptance

### Rules

- Grid is 22×44 and ownership has 968 entries.
- Deterministic obstacle count/placement, symmetry, reserved rows, and build rejection.
- A blue unit claims a column, moves to a neighboring column, and the old claimed column remains blue.
- A red advance can recapture a previously blue cell.
- A unit at the far edge and far column acquires the enemy HQ and changes x toward it.
- Melee/ranged spawner costs, production kind, stat differences, and ranged attack beyond melee range.
- Obstacle avoidance never leaves a unit inside a blocked cell.

### Scene flow

- Four MultiMeshes, still zero per-unit children.
- HUD type selection changes the kind placed by the next tile tap.
- Ranged attacks route tracer feedback.
- HQ hit and HQ destruction offsets remain exactly `Vector2.ZERO` for all sampled frames.
- Zoom changes scale around a focus point; pan clamps; transformed tile picking remains exact.

### Performance and balance

- Stress remains at 400 data units for 300 measured ticks and keeps the existing candidate/time gates.
- Re-run no-spawner defeat and mixed-spawner victory paths; tune only unit stats, production period, AI spawner cap/build interval, and obstacle steering constants to keep both outcomes reachable within 120–180 seconds.
- Smoke captures become overview, zoomed mixed-unit battle, persistent captured flank, and obstacle-cluster scenarios at 540×960.

## Out of scope

- A* pathfinding, navigation meshes, projectile Nodes, fog of war, additional unit classes, upgrade trees, camera rotation, downloadable art, and changes to the fixed match-end rules.
