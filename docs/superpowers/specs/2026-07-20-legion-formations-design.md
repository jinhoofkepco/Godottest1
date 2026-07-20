# Legion Formations Design

## Goal

Replace class-specific spawners with one barracks that repeatedly assembles a configured legion of at most twelve units. Legions gather into one of three geometric formations, march as a group, temporarily loosen during combat, reform after combat, and dissolve into the existing individual-unit fallback when fewer than thirty percent of their original members survive.

This change preserves the 22 x 44 isometric battlefield, elevation, flow fields, congestion, unit combat statistics, defense towers, economy income, territory, win conditions, C# simulation boundary, and bulk MultiMesh unit rendering.

## Considered Approaches

1. **Layer a Legion SoA over the existing Unit SoA (selected).** Units keep their existing IDs, combat state, spatial buckets, movement, and packed render buffers. Parallel legion arrays only supply an anchor, heading, group state, and rotated slot target. This gives formations without duplicating the simulation.
2. **Store units inside per-legion collections.** This makes group operations convenient but breaks the fixed unit pool, swap-removal, bucket indexes, and snapshot code. It is rejected because it would rewrite working systems.
3. **Represent legions as Node2D commanders.** This is rejected because simulation authority would cross into Nodes and violate the data-oriented architecture.

## Simulation Data

`BattleSimulation.Legions.cs` owns fixed-capacity arrays for 64 legions: ID, team, barracks ID, anchor, heading, waypoint, state, formation, configured counts, original member count, live member count, produced member count, current slot cursor, and gathering elapsed time. Legion states are `GATHERING`, `MARCHING`, `ENGAGED`, and `BROKEN`; formations are `LINE`, `WEDGE`, and `LOOSE`.

The existing unit SoA gains `legion_id` and `slot_offset`. `legion_id == -1` selects the existing ungrouped behavior. Slot offsets are calculated once from the assigned template and expressed in legion-local coordinates where negative local Y is the formation front. World slot position is `anchor + rotate(slot_offset, heading)`.

Template validation clamps the total to twelve, `SIEGE` to two, and `DRAGON` to one. Counts are never silently made negative. The three player presets are:

- Shield/LINE: 7 melee, 4 ranged, 1 siege, 0 dragon.
- Fire/LOOSE: 4 melee, 7 ranged, 1 siege, 0 dragon.
- Charge/WEDGE: 9 melee, 1 ranged, 1 siege, 1 dragon.

The enemy uses these three plus a mixed LINE template (6 melee, 4 ranged, 1 siege, 1 dragon) with deterministic weighted selection.

## Formation Geometry

Slots are stable and deterministic. Melee slots always have smaller local Y than ranged and siege slots, so rotating the formation cannot invert their tactical order.

- `LINE`: melee fills centered rows with 0.48-cell lateral spacing; ranged and siege fill two centered rear rows at 0.58-cell depth.
- `WEDGE`: melee fills the point then alternating left/right diagonal ranks; ranged, siege, and dragon form compact rear ranks.
- `LOOSE`: all roles use a centered grid with 0.96-cell lateral and depth spacing, twice the compact spacing. This reduces the number of unit radii intersecting a siege blast without adding an AoE resistance statistic.

## Barracks and Production

Build kind `BARRACKS` costs 100 and replaces melee, ranged, and siege spawner build choices. Towers remain build kind 2. Dragon lairs are removed from construction; dragons are produced only through a legion template. All ordinary barracks use the existing baked barracks art and building HP.

Each barracks owns one active gathering legion. Every 1.2 seconds it produces the next required unit in role order: melee, ranged, siege, dragon. The unit appears in the barracks-side gathering zone and immediately follows its slot. When all template members are present and within the readiness tolerance, or the gathering cap is reached, the legion changes to `MARCHING`. The cap is 15 seconds and therefore prevents blocked terrain from stalling the production loop. On deployment, the barracks immediately creates the next empty legion and resumes production.

Editing a barracks changes the template for its next legion. A currently gathering legion adopts the new template only when doing so does not invalidate already produced member counts; otherwise it finishes with its assigned copy. This keeps production deterministic and avoids deleting paid-time units.

## Group Movement and Combat

During `GATHERING`, the anchor is a passable point one cell toward the opponent from the barracks and units strongly follow their assigned slots. During `MARCHING`, the anchor samples the existing team flow field or first moves toward an optional waypoint. Its speed is the minimum base speed of all configured roles. Heading turns toward anchor velocity using the existing turn-rate discipline.

Units combine slot-follow steering with the existing separation, obstacle repulsion, waiting, velocity inertia, and movement integration. A legion becomes `ENGAGED` when an enemy is detected within its member envelope. Existing unit target selection, attack range, siege targeting, and damage remain authoritative; slot-follow weight is reduced while engaged. When no member has a valid hostile nearby for 1.2 seconds, it returns to `MARCHING` and reforms.

If survivors fall below 30 percent of the legion's deployed size, the legion becomes `BROKEN`, every survivor receives `legion_id = -1`, and the existing ungrouped flow/seek behavior resumes. Unit swap-removal preserves the new parallel arrays and legion live counts.

## Public Boundary and Snapshots

The existing low-frequency API remains. New bulk calls are:

- `TryBuildBarracks(team, cell, template, formation)` for construction.
- `ConfigureBarracks(buildingId, template, formation)` for future legions.
- `SetBarracksWaypoint(buildingId, cell)` and `DemolishBuilding(buildingId)`.
- `GetBarracksConfig(buildingId)` only when the edit panel opens.

`GetRenderSnapshot()` adds a packed `legion_banner_buffer`, banner count, and packed gathering ghost-slot records. GDScript uploads no per-unit calls. `GetBoardSnapshot` building records add template, formation, gathering progress, and legion ID only because buildings remain low count.

## Mobile UI

The lower bar contains `BARRACKS 100`, `TOWER 120`, and three template cards: Shield, Fire, Charge. Selecting a template determines the next barracks assignment. Tapping an existing allied barracks opens a compact edit panel above the bar. It contains four role rows with minus/count/plus controls, three formation buttons, `WAYPOINT`, and `DEMOLISH`. Controls enforce total and per-role caps before calling C#.

Waypoint mode consumes the next valid map tap instead of constructing. Building taps are resolved before empty-cell construction. The current gathering area displays translucent slot ghosts; marching and engaged legions display a small team banner at the anchor.

## Enemy AI

The existing timed builder constructs barracks at the same valid owned cells and under the same difficulty cap. It deterministically chooses from the four template pool entries and assigns a waypoint column offset from the direct HQ route. It uses exactly the same barracks, production, legion state, movement, and combat code as the player.

## Testing and Acceptance

Rule tests cover role ordering in LINE, rotation, LOOSE siege exposure, BROKEN, gathering within fifteen seconds, and repeated deployment. Flow tests cover building selection, panel editing, formation choice, waypoint consumption, and bulk banner/ghost rendering. Existing terrain, combat, board-delta, economy, tower, victory, and defeat tests continue to pass after replacing obsolete spawner assertions.

Stress verification creates twenty full twelve-member legions and records C# tick and render snapshot times. Balance runs cover passive defeat and active victory and must finish in two to four minutes. Smoke capture adds gathering, LINE march, engagement, and LOOSE frames at 540 x 960. GitHub Actions builds and signs the Godot 4.5 Mono debug APK and publishes the `godottest1-debug-apk` artifact.

## Self-review

- No Node represents a unit or legion.
- Formation effects remain geometric; no formation stat modifiers exist.
- Towers, terrain, territory, flow fields, congestion, and combat rules are reused.
- Every template limit, transition, public API, capture, and performance check has an explicit value or test.
- The scope is limited to the requested first-stage legion and formation conversion.
