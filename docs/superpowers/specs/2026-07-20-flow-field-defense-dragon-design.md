# Flow Field, Defense Tower, and Dragon Lair Design

## Scope

Keep the 22x44 isometric frontline simulation, economy, territory, match timer, and data-oriented unit model. Add smarter ground routing, a headquarters-only defense tower, an expensive dragon lair, and a substantially deeper zoom range. No external assets and no per-unit nodes.

## Chosen approach

Each team owns one cached weighted flow field. A Dijkstra integration grid starts at the opposing HQ and treats static obstacles plus living non-HQ buildings as impassable. Its step cost includes the periodically sampled friendly-unit density, so queues increase a route's cost and later units prefer a second opening. A cached normalized direction grid supplies the global advance vector; existing seek and separation remain local steering layers.

This is preferable to per-unit A* because hundreds of units share the same destination. It is also preferable to unweighted BFS plus local repulsion because congestion must influence route choice before a unit reaches a bottleneck.

## Simulation data

- `FlowField` is a `RefCounted` helper with `PackedFloat32Array costs` and `PackedVector2Array directions`.
- `BattleSimulation` owns red and blue flow fields, a density timer, and packed per-unit velocity and fixed flow-bias arrays.
- Flow fields rebuild at reset, after a building is built or destroyed, and every `CONGESTION_REBUILD_INTERVAL` using current team bucket density.
- Ground movement uses flow + seek + separation + reduced obstacle repulsion, then turns toward its target velocity at `UNIT_TURN_RATE`.
- A ground unit enters WAIT when a slow friendly unit blocks the forward probe. WAIT retains weak separation, decelerates to zero, and exits immediately after the probe clears.
- Flying dragons steer directly toward the opposing HQ, ignore static obstacles and building blockers, but retain target seeking and separation.

## Buildings and units

- Melee and ranged spawners remain available anywhere on owned, free territory.
- A defense tower costs 120 gold and is valid only inside the clipped 5x5 square centered on that team's HQ. It is a static building that attacks the nearest enemy unit in range using the same bucket index.
- A dragon lair costs 220 gold and produces the new flying dragon unit at a slower interval. Dragons have a distinct winged silhouette and ignore obstacles.
- Buildings block ground routing. Production selects a free forward-adjacent cell so newly produced ground units never start inside a blocked building cell.
- The four player choices are melee spawner, ranged spawner, defense tower, and dragon lair.

## View and feedback

- Raise `MAP_ZOOM_MAX` to 8.0 while retaining pinch, wheel, focus preservation, and pan clamping.
- Building silhouettes distinguish HQ, conventional spawner, turret, and winged dragon lair.
- Dragon batches use the existing MultiMesh renderer; no unit nodes are introduced.
- Tower shots use a bright tracer event. WAIT units are visually dimmed, and dragons use a brighter gold-accented team color.

## Verification

Rules tests cover flow detouring around a complete column closure, congestion causing a second opening to become cheaper, WAIT entry/release, HQ 5x5 tower placement, tower combat, dragon production/obstacle immunity, packed-array alignment, and maximum zoom. Stress measures 400+ units while congestion rebuilds. Smoke capture adds a bottleneck split scene. Full import, rules, flow, stress, and runtime smoke tests must pass before publishing.
