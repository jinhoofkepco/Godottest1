# Mini Battle Agent AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and measure a branch-only 30-versus-30 shield-infantry bottleneck battle in which each unit independently chooses advance, engage, gap-fill, flank, yield, hold, or retreat actions.

**Architecture:** A standalone C# Node owns a fixed-capacity, data-oriented simulation and exposes bulk snapshot and metrics dictionaries to Godot. A procedural GDScript scene renders the experiment and provides controls. Dedicated headless runners compare deterministic baseline and agent modes without calling the production `BattleSimulation`.

**Tech Stack:** Godot 4.5 stable .NET, C# net9.0 simulation, GDScript presenter/tests, fixed 30 Hz simulation, spatial buckets, procedural 2D drawing.

## Global Constraints

- Work only on `experiment/mini-battle-agent-ai`; do not merge into `main`.
- Exactly 30 blue and 30 red shield units spawn in a mirror-symmetric 28 by 36 arena.
- The map has a shortest central gate and viable left/right bypasses.
- No unit may be a Node, physics body, or independently processed Godot object.
- Decisions run at 5 Hz in five staggered groups; movement and combat run at 30 Hz.
- Agent mode actions are `ADVANCE`, `ENGAGE`, `FILL_GAP`, `FLANK_LEFT`, `FLANK_RIGHT`, `YIELD`, `HOLD`, and `RETREAT`.
- Baseline and agent modes use identical terrain, seed, spawn positions, HP, damage, and timing.
- All runtime art is procedural; no new external asset.
- The fixed-seed experiment lasts at most 120 simulated seconds.
- Responses and final report remain concise, but branch documentation records full metrics.

---

### Task 1: Headless Experiment Contract

**Files:**
- Create: `tests/test_agent_battle_lab.gd`
- Create: `tests/run_agent_battle_lab.gd`

**Interfaces:**
- Consumes: desired C# resource path `res://scripts/agent_lab/AgentBattleSimulation.cs`
- Produces: one headless runner that later tasks use as the RED/GREEN gate

- [ ] **Step 1: Write the failing contract test**

Create a test suite that first checks `ResourceLoader.exists()` for the C# simulation, then expects the instantiated simulation to expose:

```gdscript
const SIM_PATH := "res://scripts/agent_lab/AgentBattleSimulation.cs"

func run() -> Array[String]:
    _expect(ResourceLoader.exists(SIM_PATH), "agent lab C# simulation exists")
    if failures.is_empty():
        var simulation = load(SIM_PATH).new()
        for method in ["ResetExperiment", "Step", "RunTicks", "GetSnapshot", "GetMetrics"]:
            _expect(simulation.has_method(method), "simulation exposes %s" % method)
        simulation.free()
    return failures
```

The runner loads the suite, prints each failure, and exits non-zero on failure.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
/private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_agent_battle_lab.gd
```

Expected: exit 1 with `agent lab C# simulation exists`.

- [ ] **Step 3: Commit the proven failing test**

```bash
git add tests/test_agent_battle_lab.gd tests/run_agent_battle_lab.gd
git commit -m "test: define agent battle lab contract"
```

---

### Task 2: Deterministic Arena and Agent Data

**Files:**
- Create: `scripts/agent_lab/AgentBattleConfig.cs`
- Create: `scripts/agent_lab/AgentBattleSimulation.cs`
- Create: `scenes/agent_battle_simulation.tscn`
- Modify: `tests/test_agent_battle_lab.gd`

**Interfaces:**
- Produces: `ResetExperiment(int mode = 1, int seed = 230723)`, `Step(float delta)`, `RunTicks(int ticks)`, `GetSnapshot()`, and `GetMetrics()`
- Snapshot keys: `positions`, `velocities`, `teams`, `hp`, `actions`, `alive_blue`, `alive_red`, `time`, `result`, `blocked_cells`
- Metrics keys begin with zeroed counters and include `unit_count`, `blue_count`, `red_count`, `average_tick_ms`, and `worst_tick_ms`

- [ ] **Step 1: Extend the test for deterministic reset**

Expect exactly 60 units, 30 per team, mirrored positions, zero elapsed time, no result, and identical repeated resets for seed 230723.

- [ ] **Step 2: Run and verify RED**

Run the agent lab runner. Expected: C# resource or required snapshot contract failure.

- [ ] **Step 3: Implement the minimal data-oriented simulation shell**

Add fixed arrays for 60 units, generate the symmetric spawns and central fortification, implement the public APIs, and expose packed bulk snapshots. `Step` initially advances time and profiling only.

- [ ] **Step 4: Build and run GREEN**

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
  /private/tmp/godottest1-dotnet9/dotnet build --nologo
/private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . --import
/private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_agent_battle_lab.gd
```

Expected: build with 0 warnings/0 errors and `AGENT BATTLE LAB TESTS PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/agent_lab scenes/agent_battle_simulation.tscn tests/test_agent_battle_lab.gd
git commit -m "feat: add deterministic 30v30 agent arena"
```

---

### Task 3: Individual Utility Decisions and Congestion Movement

**Files:**
- Create: `scripts/agent_lab/AgentBattleSimulation.Decision.cs`
- Create: `scripts/agent_lab/AgentBattleSimulation.Movement.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.cs`
- Modify: `tests/test_agent_battle_lab.gd`

**Interfaces:**
- Consumes: fixed unit arrays and arena occupancy from Task 2
- Produces: staggered utility decisions, local spatial buckets, three route choices, candidate-velocity movement, yield negotiation, and overlap correction
- Adds metrics: `action_counts`, `flank_decisions`, `yield_decisions`, `side_crossings`, `idle_agent_seconds`, `maximum_stuck_seconds`, and `overlap_violations`

- [ ] **Step 1: Add failing behavioral tests**

For fixed seed 230723, assert after 45 simulated seconds:

```gdscript
_expect(int(agent_metrics.flank_decisions) > 0, "agents independently choose a flank")
_expect(int(agent_metrics.yield_decisions) > 0, "blocked agents negotiate passage")
_expect(int(agent_metrics.side_crossings) > 0, "agents use a viable side route")
_expect(float(agent_metrics.maximum_stuck_seconds) < 12.0, "no agent remains permanently stuck")
_expect(int(agent_metrics.overlap_violations) == 0, "position correction preserves minimum separation")
```

Also verify two resets with the same seed produce identical positions and action arrays after the same tick sequence.

- [ ] **Step 2: Run and verify RED**

Expected: missing flank/yield/side-crossing metrics or zero behavior counts.

- [ ] **Step 3: Implement decisions and movement**

Implement:

- five staggered decision groups;
- bounded spatial buckets;
- utility scoring with action commitment and hysteresis;
- centre/left/right route intent;
- nine fixed candidate velocities;
- forward-priority yield rules;
- two overlap-correction passes;
- stuck accumulation that continues through `HOLD`.

Keep all arrays preallocated and avoid per-tick LINQ and collection creation.

- [ ] **Step 4: Run GREEN and refactor**

Run build plus the agent lab runner. Expected: all movement assertions pass. Extract only duplicated scoring or bucket code while preserving passing tests.

- [ ] **Step 5: Commit**

```bash
git add scripts/agent_lab tests/test_agent_battle_lab.gd
git commit -m "feat: add per-unit utility movement"
```

---

### Task 4: Autonomous Melee Combat and Baseline Comparison

**Files:**
- Create: `scripts/agent_lab/AgentBattleSimulation.Combat.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.Decision.cs`
- Modify: `scripts/agent_lab/AgentBattleSimulation.cs`
- Modify: `tests/test_agent_battle_lab.gd`

**Interfaces:**
- Produces: local target selection with saturation, attacks, retreat, gap filling, frontline replacement, timeout scoring, and mode comparison
- Adds metrics: `units_ever_attacked`, `frontline_replacements`, `crossed_center`, `intentional_hold_seconds`, `result`, and `elapsed_seconds`

- [ ] **Step 1: Add failing comparison tests**

Run baseline and agent modes with the same seed for 120 simulated seconds and require:

```gdscript
_expect(float(baseline.idle_agent_seconds) > 0.0, "baseline reproduces central idle congestion")
_expect(float(agent.idle_agent_seconds) < float(baseline.idle_agent_seconds), "agent decisions reduce pathological idle time")
_expect(int(agent.units_ever_attacked) > int(baseline.units_ever_attacked), "more autonomous agents participate in combat")
_expect(int(agent.frontline_replacements) > 0, "rear agents replace fallen front fighters")
_expect(String(agent.result) != "", "agent battle resolves or scores at the fixed timeout")
_expect(float(agent.active_participation_ratio) >= 0.70, "agent mode keeps at least 70 percent purposefully active")
```

- [ ] **Step 2: Run and verify RED**

Expected: combat metrics absent or comparison assertions fail.

- [ ] **Step 3: Implement combat and scoring**

Add bounded local targeting, target saturation, attack cooldown and damage, gap-fill utility bonuses after nearby deaths, low-HP retreat, and fixed-time score resolution. Purposeful `HOLD` near contact is tracked separately from pathological idle time.

- [ ] **Step 4: Run GREEN**

Run the full agent lab test and record the exact baseline/agent metrics printed by the runner.

- [ ] **Step 5: Commit**

```bash
git add scripts/agent_lab tests/test_agent_battle_lab.gd
git commit -m "feat: add autonomous shield combat"
```

---

### Task 5: Branch-Default Visual Battle Lab

**Files:**
- Create: `scripts/agent_battle_lab.gd`
- Create: `scenes/agent_battle_lab.tscn`
- Create: `tests/smoke_agent_battle_lab.gd`
- Modify: `project.godot`
- Modify: `tests/test_agent_battle_lab.gd`

**Interfaces:**
- Consumes: bulk snapshots and metrics from `AgentBattleSimulation`
- Produces: a portrait procedural presentation, live diagnostic HUD, mode/reset/pause/speed controls, and `build/smoke_agent_battle_lab.png`

- [ ] **Step 1: Add a failing scene contract**

Require the scene and presenter to exist, contain one simulation Node, expose `set_mode`, `reset_lab`, and `get_metrics_text`, and make the project main scene point to the lab.

- [ ] **Step 2: Run and verify RED**

Expected: missing scene/presenter assertion.

- [ ] **Step 3: Implement the presenter**

Draw the battlefield, fortification, shield units, action rims, attack pulses, and front direction procedurally. Add touch/mouse controls for `AGENT AI`, `BASELINE`, `PAUSE`, `1X/2X`, and `RESET`. Do not create unit Nodes.

- [ ] **Step 4: Implement unattended capture**

Run agent mode to the congested contact phase, save one 540 by 960 PNG, and verify its dimensions and non-empty file size.

- [ ] **Step 5: Run GREEN**

Run the headless contract test and the display-backed smoke capture.

- [ ] **Step 6: Commit**

```bash
git add project.godot scripts/agent_battle_lab.gd scenes/agent_battle_lab.tscn tests
git commit -m "feat: add visual individual AI battle lab"
```

---

### Task 6: Measurement Report and Branch Verification

**Files:**
- Create: `docs/agent-battle-lab-results.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: deterministic test output, profiling counters, and smoke capture
- Produces: exact baseline-versus-agent table, launch instructions, limitations, and experiment conclusion

- [ ] **Step 1: Run fresh full verification**

Run:

```bash
DOTNET_ROOT=/private/tmp/godottest1-dotnet9 \
  /private/tmp/godottest1-dotnet9/dotnet build --nologo
/private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . --import
/private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_agent_battle_lab.gd
/private/tmp/godot45mono/app/Godot_mono.app/Contents/MacOS/Godot \
  --headless --path . -s tests/run_rules.gd
```

Then run the Xvfb/macOS display smoke capture and inspect the image.

- [ ] **Step 2: Record results honestly**

Document exact baseline and agent metrics, average/worst tick time, whether every acceptance criterion passed, observed visual behavior, and remaining limitations. Do not soften failed criteria.

- [ ] **Step 3: Review the complete branch**

Review the full diff from `main` for production leakage, Node-per-unit violations, allocations in hot loops, test quality, and documentation accuracy. Resolve Critical and Important findings and re-run relevant tests.

- [ ] **Step 4: Commit and push the experiment branch**

```bash
git add README.md docs/agent-battle-lab-results.md
git commit -m "docs: report individual agent battle results"
git push -u origin experiment/mini-battle-agent-ai
```

Do not merge or open a merge PR unless the user asks.
