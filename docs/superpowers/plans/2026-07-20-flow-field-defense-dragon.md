# Flow Field, Defense Tower, and Dragon Lair Implementation Plan

1. Add failing rule tests for the new constants, packed arrays, flow detour, congestion split, WAIT enter/release, building restrictions, tower attacks, dragon obstacle immunity, and zoom limit.
2. Add a data-only `FlowField` helper and integrate team-specific cached costs/directions into `BattleSimulation`.
3. Add packed velocity and flow-bias unit data, inertial ground movement, WAIT probing, building-aware collision, and flying movement.
4. Add defense tower targeting/fire cadence and dragon lair production, costs, validation, events, and enemy-safe building records.
5. Expand the HUD to four build selections and update main input/event routing, building drawing, MultiMesh dragon rendering, and tower tracers.
6. Add the bottleneck smoke capture, rerun the 400-unit stress benchmark, tune only combat/production constants as needed, and update README evidence.
7. Run headless import, rule/game-flow/stress/smoke suites and APK export; review the diff, commit, push main, verify GitHub Actions, and publish the verified APK link.
