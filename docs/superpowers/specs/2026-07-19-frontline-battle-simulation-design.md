# Frontline Battle Simulation Pivot Design

## Scope

Replace the current tower-defense match with a two-army frontline simulation while retaining Godot 4.5, portrait presentation, procedural visuals, Android delivery, and the verified isometric projection/inverse-picking formulas in `GridBoard`. The board becomes 11 columns by 22 rows. Red owns the upper half, blue owns the lower half, the red HQ sits at the top, and the blue HQ sits at the bottom.

The match begins immediately and lasts at most 180 seconds. HQ destruction wins immediately. Reaching 90% territory also wins immediately. At timeout, territory share decides; if equal, normalized HQ health decides, then living army health, with an exact tie resolving as a player defeat so every match has a terminal result.

## Approaches Considered

1. Reusing pooled `Node2D` units would reduce allocation but retain node callbacks, signals, and scene-tree overhead. It conflicts with the explicit data-only unit requirement.
2. A structure-of-arrays simulation with two `MultiMeshInstance2D` renderers keeps simulation deterministic and makes rendering cost scale with two batches. This is the selected approach.
3. Managing every draw RID directly through `RenderingServer` offers more control but adds lifecycle complexity without a demonstrated need at the 300-unit target.

## Simulation Model

`BattleSimulation` is a single `RefCounted` model updated only through `tick(1.0 / 30.0)`. It owns:

- Unit structure-of-arrays: `PackedInt32Array` IDs/teams/states/targets, `PackedVector2Array` positions, and `PackedFloat32Array` HP/attack cooldowns.
- A unique-ID-to-index dictionary rebuilt once per tick so swap-removal never invalidates persistent targets.
- Grid buckets keyed by `row * GRID_COLUMNS + column`. Units inspect only adjacent buckets for targets, avoiding all-pairs scans.
- Low-count building records for spawners and HQs. Their `Node2D` views are projections of model state, never simulation authorities.
- Gold, passive income, AI build cadence, match clock, column frontlines, tile ownership, occupancy, and terminal result.
- A transient event queue drained by the view after each tick. Units never create nodes, emit per-unit signals, or run individual callbacks.

Units have one melee type. They advance vertically toward the opposing HQ, stop for the nearest in-range opposing unit, then opposing building/HQ, and attack on cooldown. Dead units are swap-removed. Spawners periodically insert units into the arrays near their logical cell.

## Territory and Frontline

Each column derives two anchors every tick:

- Red front: greatest row occupied by a living red unit or building in that column, falling back to the top HQ line.
- Blue front: smallest row occupied by a living blue unit or building in that column, falling back to the bottom HQ line.

The boundary is the midpoint between those anchors. Rows at or above it are red; rows below it are blue. A change in any tile emits a territory-change event, which `GridBoard` shows as a short color-transition pulse. Blue occupancy is blue-owned tiles divided by 242.

`GridBoard` keeps its `grid_to_screen`, `screen_to_grid`, `cell_to_world`, `world_to_cell`, and bounds math unchanged. Its build rule changes to consult the current ownership array, bounds, occupied building cells, and HQ exclusions. Blue taps can build only on blue territory; the red AI uses the same validation for red territory.

## Economy and AI

Tuning lives in `GameConfig`:

- Blue starts with 180 gold; red starts with 120.
- A spawner costs 60 gold.
- Both sides gain 3 gold per second and 6 gold per unit kill.
- Red AI evaluates a build every 14 seconds, maintains at most four spawners, and chooses a valid red tile close to the current frontline with deterministic seeded column selection.

No-blue-spawner play therefore yields no blue units while the AI expands and attacks. Spending the starting gold on forward blue spawners creates an early numerical and travel-distance advantage; passive income allows continued reinforcement.

## Locked Combat Tuning

- Simulation: 30 Hz fixed step, maximum eight catch-up ticks per rendered frame.
- Unit: 48 HP, 1.45 cells/second, 0.72-cell melee range, 10 damage, 0.65-second attack interval.
- Spawner: 240 HP, 2.6-second production interval.
- HQ: 1200 HP.
- Match: 180 seconds, 90% occupancy terminal threshold.

These values are export/config constants and can be changed without touching simulation algorithms.

## View and Input

`UnitRenderer` owns exactly two `MultiMeshInstance2D` children, one blue and one red. It builds a procedural `ArrayMesh` soldier silhouette once, sorts each team approximately by projected Y, and updates instance transforms/colors from the simulation arrays. No unit node or per-unit process exists.

`BattleBuilding` nodes are allowed because their count is small. They draw HQ/spawner silhouettes, health, damage flash, production pulse, and destruction collapse from model snapshots. `Main` converts touch/mouse positions with `world.to_local()` and the unchanged inverse projection before requesting a blue spawner build.

The 11 x 22 board is fitted below the HUD and centered. The HUD shows blue gold, both HQ HP values, remaining time, and a red/blue occupancy bar backed by the actual ownership array.

## Feedback Language

`BattleFx` consumes model events and keeps overlays above batched units/buildings:

1. Combat hit: short yellow-white cross spark.
2. Unit death: team-colored expanding square pop.
3. Spawner production: cyan/red circular pulse at the building.
4. Spawner damage/destruction: red-white flash followed by sinking fragments.
5. Frontline movement: changed diamonds brighten into their new team color.
6. HQ hit: strong white/red flash plus decaying whole-world shake.

Blue and red are used consistently for territory, units, buildings, HUD share, and FX. Warm yellow is reserved for impacts.

## Files and Boundaries

- Keep and adapt: `game_config.gd`, `grid.gd`, `main.gd`, `hud.gd`, `fx.gd` and corresponding scenes.
- Create: `battle_simulation.gd`, `unit_renderer.gd`, `battle_building.gd` and focused scenes.
- Remove: `enemy.gd`, `tower.gd`, `projectile.gd`, `wave_manager.gd`, `core.gd` and their scenes/UIDs.
- Rewrite: rule/game-flow tests, smoke capture, README.
- Preserve: Android preset and workflow, adding the stress suite and three unattended screenshots to CI.

## Verification

Rule tests cover unchanged projection round trips, territory/frontline calculations, team-aware build validation, economy, HQ/occupancy/timeout results, and absence of unit nodes. Game-flow tests simulate an unbuilt blue side to defeat and an actively reinforced blue side to victory. A stress runner inserts at least 360 units and reports average/max milliseconds per fixed tick; the acceptance ceiling is 16.67 ms average on the local/CI CPU, with the measured value recorded in README.

The unattended visual runner writes three 540 x 960 PNGs: opening, blue advantage, and blue disadvantage. CI performs Godot 4.5 import/tests/stress, Xvfb captures, debug APK export, and artifact upload. The verified artifact replaces `apk/godottest1.apk` without triggering a redundant APK-only build.
