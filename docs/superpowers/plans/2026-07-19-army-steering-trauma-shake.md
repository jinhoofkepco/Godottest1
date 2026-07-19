# Army Steering and Trauma Shake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make packed-array units pursue and separate in two dimensions, add batched attack lunges, and replace random HQ jitter with smooth bounded trauma shake while preserving the frontline game.

**Architecture:** `BattleSimulation` adds aligned variation/lunge arrays and bucketed steering but remains the only gameplay authority. `UnitRenderer` projects a timer-derived lunge offset into the existing two MultiMeshes, while `DefenseFx` owns a deterministic trauma oscillator independent of simulation state.

**Tech Stack:** Godot 4.5 stable, GDScript, PackedArrays, MultiMeshInstance2D, fixed 30 Hz ticks, GitHub Actions Android debug export.

## Global Constraints

- No per-unit Node, signal, tween, scene instance, or process callback.
- Unit detection uses the existing grid buckets; no all-pairs target scan.
- Keep the 11 x 22 board, economy, AI, territory, HQ/90%/timeout outcomes, portrait input, and external-assets-zero rule.
- Ordinary HQ shake magnitude is at most 3 px; major terminal shake is at most 6 px for 0.4 seconds.
- Tune only unit HP, damage, or spawner production interval if match duration regresses.

---

### Task 1: Steering Contract and Packed State

**Files:**
- Modify: `scripts/game_config.gd`
- Modify: `scripts/battle_simulation.gd`
- Modify: `tests/test_rules.gd`

**Interfaces:**
- Produces `unit_speed_scales`, `unit_lunge_timers`, `unit_lunge_directions` packed arrays.
- Produces bucketed hostile detection within `UNIT_DETECT_RANGE` and separation within `UNIT_SEPARATION_RADIUS`.

- [ ] Add rule tests that spawn opposing units in adjacent columns, run fixed ticks, and require lateral convergence plus a hit event.
- [ ] Add a rule test that spawns two allies at the same position and requires their distance to grow beyond 0.20 cells without leaving bounds.
- [ ] Add packed-array alignment, speed variation range, lunge timer, lateral territory, and widened candidate-count assertions.
- [ ] Run `godot --headless --path . -s tests/run_rules.gd`; require failures from missing arrays/constants and cross-column behavior.
- [ ] Add exact steering/variation/lunge constants to `GameConfig`.
- [ ] Implement deterministic spawn variation, ±3 hostile bucket search, ±1 separation lookup, weighted 2D motion, attack stop, lunge timers, and swap-removal support.
- [ ] Re-run rules and require `RULE TESTS PASS`; commit.

### Task 2: Trauma Shake and Batched Lunge

**Files:**
- Modify: `scripts/fx.gd`
- Modify: `scripts/unit_renderer.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_game_flow.gd`

**Interfaces:**
- `DefenseFx.show_hq_hit(cell, team)` adds cooldown-gated trauma.
- `DefenseFx.show_hq_destroyed(cell, team)` starts the capped major pulse.
- `DefenseFx.get_screen_shake_offset()` returns a smooth bounded pixel vector.

- [ ] Add tests for trauma cap, 0.5-second retrigger suppression, decay, normal offset magnitude <= 3, major offset <= 6, and attack lunge timers.
- [ ] Run flow/rule tests and require RED against random 8 px shake and static unit transforms.
- [ ] Replace random shake with trauma² amplitude and normalized multi-sine direction; route HQ destruction separately from ordinary hit.
- [ ] Add the logical lunge offset inside MultiMesh transform synchronization and reduce death FX radius/fragment size.
- [ ] Run rule/flow suites and commit.

### Task 3: Balance, Stress, and Cluster Capture

**Files:**
- Modify: `tests/run_stress.gd`
- Modify: `tests/smoke_capture.gd`
- Modify: `.github/workflows/android.yml`
- Modify: `README.md`
- Modify only if required: `scripts/game_config.gd`

**Interfaces:**
- Stress output continues to report initial count, remaining count, average, p95, maximum, and candidate checks.
- Adds `build/smoke_cluster.png` at exactly 540 x 960.

- [ ] Instrument automated victory/defeat fixtures with elapsed match seconds and confirm both terminal paths remain within 180 seconds.
- [ ] Run the widened 400-unit benchmark; keep average and p95 below 16.667 ms and record the new result/environment.
- [ ] Stage a central mixed-team cluster across columns and save a fourth visual capture.
- [ ] Extend Xvfb CI dimension checks to all four images and update README behavior/shake/stress evidence.
- [ ] Run import, rules, flow, stress, 180-frame smoke, four captures, actionlint, asset/reference scans, and diff checks; inspect the cluster image; commit.

### Task 4: Review and Android Publication

**Files:**
- Replace after successful CI: `apk/godottest1.apk`

- [ ] Request an independent whole-branch review against the design and fix all Critical/Important findings.
- [ ] Fast-forward into `main`, repeat merged tests, and push source.
- [ ] Watch the Godot 4.5 workflow through all tests, four Xvfb captures, debug export, and artifact upload.
- [ ] Download the artifact and verify package ID, label/version, v2/v3 signature, size, and SHA-256.
- [ ] Replace `apk/godottest1.apk` with the exact artifact, push the APK-only commit, and verify authenticated GitHub download byte equality.
