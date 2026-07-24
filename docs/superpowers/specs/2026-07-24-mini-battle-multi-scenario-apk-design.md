# Mini Battle Multi-Scenario Lab and Dedicated APK Design

**Status:** Approved in conversation on 2026-07-24  
**Branch:** `codex/mini-battle-agent-ai`

## Outcome

Extend the existing 30-vs-30 shield-infantry experiment into one interactive
portrait app with four deterministic terrain cases. The user must be able to
install it beside the production game, switch between `AGENT AI` and
`BASELINE`, observe the individual decisions, and download the exact branch
APK from a clearly named GitHub Actions artifact.

This remains a branch experiment. It does not merge into `main`, change the
production game's rules, or claim mobile performance before device profiling.

## Confirmed APK Delivery Root Cause

The experiment branch already points `run/main_scene` at
`res://scenes/agent_battle_lab.tscn`, but the production Android workflow runs
on `main` pushes only. GitHub has zero Android runs for the experiment branch;
the artifact the user downloaded was `godottest1-debug-apk` from production
commit `5562c27`. The branch also retained the production package ID and app
label, so even a manually dispatched branch build would be difficult to
distinguish and would replace the production app.

The permanent fix is a branch-specific app identity and branch-specific
workflow, not another link to the production artifact.

## Experiment Cases

All cases use the same 28×36 arena, mirrored 30-vs-30 spawn, unit stats, combat
rules, fixed 30 Hz tick, and three seeds: `230723`, `230724`, and `230725`.
Only terrain and route metadata differ between cases.

### Case 1: `BOTTLENECK`

- Preserve the current two-row wall at `y=17..18`, `x=3..24`.
- Keep the two-cell central gate at `x=13..14` and open outside bypass lanes.
- Purpose: reproduce a dense central queue and measure yield, flanking, route
  use, and replacement of fallen frontline units.
- 120-second Agent acceptance per seed:
  - units that actually attack: at least 48;
  - side-route crossings: at least 20;
  - pathological idle: at most 25% of the same-seed Baseline;
  - frontline replacements: at least 4;
  - maximum continuous stuck time: below 15 seconds;
  - overlap violations: zero.

### Case 2: `CORNER_TRAP`

- Widen the middle opening to `x=11..16`.
- Add a north protrusion at `x=11..13`, `y=14..16`.
- Add its 180-degree mirrored south protrusion at `x=14..16`, `y=19..21`.
- Purpose: force an S-shaped passage and test whether agents leave a protruding
  corner instead of oscillating or remaining trapped.
- A trap entry begins on first entry to `x=10.5..17.5`, `y=13.5..22.5`; escape
  occurs after crossing the opposite side of the fortification.
- 90-second Agent acceptance per seed:
  - trap entries: at least 12 total and at least 4 per team;
  - at least one physical opposite-side escape within 12 seconds;
  - non-purposeful idle: below 20 agent-seconds;
  - maximum no-progress interval: below 6 seconds;
  - units that actually attack: at least 36;
  - overlap violations: zero.

Raw escape ratio and maximum trap dwell remain reported diagnostics, not pass
criteria. Independent review found that these values include units deliberately
fighting or dying inside the defile, so treating every non-exit as a navigation
failure rewarded a scenario-only rule that disabled combat and retreat. The
revised criteria measure the actual defect—idle oscillation/no progress—while
all four scenarios retain identical decision and combat rules.

### Case 3: `ROUTE_CHOICE`

- Build a four-row wall at `y=16..19`.
- Open a left gate at `x=3..6`, a narrow center gate at `x=13..14`, and a
  right gate at `x=21..24`.
- Purpose: test whether independent agents distribute between a short crowded
  route and two longer wide routes.
- 90-second Agent acceptance per seed:
  - total route crossings: at least 24;
  - left and right crossings: at least 4 each;
  - no single route receives more than 70% of crossings;
  - pathological idle: at most 40% of the same-seed Baseline;
  - units that actually attack: at least 42;
  - overlap violations: zero.

### Case 4: `OPEN_CONTROL`

- Use no blocked cells.
- Purpose: detect over-steering. Agents should advance and fight without
  inventing unnecessary flanks or yields.
- 60-second Agent acceptance per seed:
  - flank decisions: at most 2;
  - side-route crossings: zero;
  - units that actually attack: at least 48;
  - pathological idle: below 60 agent-seconds;
  - maximum continuous stuck time: below 4 seconds;
  - surviving-unit difference between teams: at most 2;
  - remaining-HP difference: at most 8%;
  - overlap violations: zero.

## Simulation Architecture

`ResetExperiment(mode, seed, scenario)` becomes the only scenario entry point.
The scenario ID is validated to the range `0..3`; invalid input resets to
`BOTTLENECK`. `BuildScenario(scenario)` runs only during reset and fills:

- a fixed `int[1008]` blocked-cell buffer plus an active count;
- the existing fixed `bool[1008]` blocked mask;
- fixed region flags for trap and route crossing measurement;
- fixed mirrored route waypoints for both teams;
- per-unit waypoint cursor and route-crossing state.

The hot loop continues to read fixed arrays. It must not allocate per unit,
create unit Nodes, use LINQ, or rebuild terrain during battle. Collision
visibility checks use the active blocked mask instead of hard-coded knowledge
of the original wall. Team routes and waypoints are exact vertical mirrors;
this removes the current left/right path asymmetry as a possible source of the
`RED TIME` bias.

Target selection uses a two-phase mirrored decision batch. First, every member
of the batch releases its old valid reservation. Second, Blue and Red use the
same local-unit order while the team processed first alternates by decision
epoch; every chosen target is immediately written to the live reservation
ledger. This preserves the hard limit of three attackers per target without a
scenario-specific exception or a permanently first team.

Snapshots add scenario ID/name and return only the active blocked-cell prefix.
Metrics add per-team participation and HP, three route-crossing counters, trap
entries, timely trap escapes, escape ratio, and maximum trap dwell.

## Controlled Tuning Protocol

Combat HP, damage, attack interval, range, spawn, and team count remain fixed.
Each case is first run with the current Agent constants and the same-seed
Baseline. A tuning change is allowed only when a case misses an acceptance
criterion.

Only one of these factors may change per experiment:

| Factor | Current value or rule | Expected effect |
|---|---:|---|
| Flank utility | `0.38 + congestion×0.36 + stuck×0.28` | Higher congestion/stuck weights cause earlier route changes |
| Personality bias | `±0.12`, empty-side bonus `+0.18` | Spreads agents without random per-tick motion |
| Yield prediction | `0.28 s` | Longer prediction negotiates collisions earlier but can over-yield |
| Forward block range | `0.95 cell` | Changes how early a queue is recognized |
| Action hysteresis | `0.18` | Higher values reduce action flicker but slow reactions |
| Commit durations | default `0.3 s`, flank `0.8 s`, yield `0.5 s` | Longer commitments prevent oscillation but can preserve a poor choice |
| Candidate collision penalties | friendly `2.3`, hostile `2.8` | Higher values preserve spacing but can make agents overly cautious |
| Target reservation | maximum 3 attackers per target | Lower values spread the frontline; higher values finish targets faster |

For each accepted change the report records:

1. failed case and metric;
2. old value and new value;
3. all other fixed conditions;
4. three-seed before/after results;
5. regressions or improvements in the other three cases.

Rejected trials are also summarized. No combined multi-variable change is
accepted without separately measuring each contributing change first.

## Mobile Presentation

The existing procedural renderer remains one `Node2D`; there are still no
per-unit presentation Nodes.

- Header: unmistakable `MINI BATTLE AI LAB` title, scenario name, mode, elapsed
  time, alive counts, participation, idle, stuck, and tick time.
- Arena: blocked geometry changes with the selected case. Units keep team body
  color, action-rim color, forward nose, HP bar, and real-hit pulse.
- Compact legend: the eight action colors remain visible.
- Scenario row: four large touch buttons, `1 GATE`, `2 CORNER`, `3 ROUTES`,
  `4 OPEN`.
- Control row: `AGENT AI`, `BASELINE`, `PAUSE`, `1X/2X`, `RESET`.
- Selecting a case or mode resets that exact case with seed `230723`.
- The selected scenario and mode buttons are visually disabled/highlighted.
- All controls remain within 540×960 and use at least 44 px touch height.

Four smoke captures are produced, one per Agent case, at a deterministic
contact point. A fifth capture verifies the Baseline bottleneck. Captures must
show the title, selected case, complete arena, action legend, and both control
rows without clipping.

## Dedicated Android App and CI

Branch-only identity:

- project and launcher name: `Mini Battle AI Lab`;
- package ID: `com.jinhoofkepco.godottest1.agentlab`;
- version name: `0.2.0-lab`;
- version code: `1`;
- export path: `build/mini-battle-ai-lab.apk`;
- artifact name: `mini-battle-ai-lab-debug-apk`.

A dedicated `.github/workflows/android-agent-lab.yml` runs on pushes to
`codex/mini-battle-agent-ai`. It reuses the verified
Godot 4.5 .NET Android setup but runs the lab import, lab rule suite, and lab
scene smoke before `--export-debug Android`. It verifies that the APK is
non-empty, contains the arm64 C# assembly, and passes `apksigner verify`.

The production `android.yml` remains unchanged. README links point to the
experiment branch workflow and label the production APK as unrelated. After
the first successful run, the handoff includes the exact Actions run URL and
artifact download location.

## Test and Reporting Contract

- Contract tests cover all scenario IDs, deterministic reset, expected blocked
  geometry, vertical symmetry, reachable routes, and invalid-scenario fallback.
- Behavioral tests execute `4 cases × 3 seeds × 2 modes` and print a
  machine-readable comparison table.
- Position/action/route state must reproduce for repeated equal inputs.
- A per-tick regression checks BOTTLENECK and OPEN_CONTROL for 900 ticks each
  and rejects any live target assigned more than three attackers.
- Existing production rule tests remain green.
- A development-machine timing table reports average and worst tick per case.
  Managed GC and physical-device frame time remain explicitly unmeasured unless
  instrumentation is added and run.
- The experiment report contains:
  - per-case Baseline versus Agent metrics;
  - every accepted and rejected tuning change;
  - remaining failures and team bias;
  - screenshots and exact APK retrieval instructions.

## Definition of Done

1. All four cases are selectable and visually distinct in the Android app.
2. Agent and Baseline can be switched for every case.
3. Scenario contract, deterministic, behavior, production-rule, and smoke
   tests pass.
4. The controlled-tuning report explains exactly what changed and why.
5. The app installs alongside production with the dedicated name and package.
6. GitHub Actions builds and signs `mini-battle-ai-lab.apk`.
7. The branch, successful Actions run, and exact artifact download link are
   provided without merging into `main`.
