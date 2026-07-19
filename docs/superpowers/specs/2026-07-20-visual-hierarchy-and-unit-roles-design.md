# Visual Hierarchy and Unit Roles Design

## Scope

Preserve the existing fixed-step, packed-array battle simulation and 2D batched renderer. Change only unit role ratios, per-kind detection, presentation assets, health-bar visibility, board palette, blockers, and building visuals.

## Unit roles

Define neutral base combat values and derive class values so the requested ratios are executable contracts:

- Melee: base HP x2, base damage x0.5, base range.
- Ranged: base HP x0.5, base damage x1.5, base range x2.
- Dragon: ranged attack range x1.5 and common detection range x1.5. Dragons keep their existing HP, damage, speed, flight, and obstacle immunity.
- Melee still cannot acquire dragons; ranged units and static defenses still can.

The simulation selects a detection radius per unit kind. Bucket traversal expands to the selected radius without changing the spatial-hash architecture.

## Asset pipeline

Keep KayKit Adventurers for infantry and add two CC0 sources:

- Quaternius LowPoly Animated Monsters: animated dragon.
- KayKit Medieval Hexagon Pack: blue/red castle, barracks, archery range, catapult tower, rocks, and crates.

The infantry baker keeps original textures and material luminance. It applies team color only to identified team-color pixels/material regions, under a fixed upper-left key light and low ambient fill. A second generalized static/animated bake tool produces transparent dragon, building, and obstacle atlases. Source licenses and exact upstream revisions/URLs live beside the source files. Android export excludes source 3D files and includes only runtime atlases.

## Renderer and visual hierarchy

- Infantry remains one globally Y-sorted MultiMesh atlas batch; team atlases preserve material shading.
- Dragon becomes an animated atlas batch with 8-direction flight/attack/death presentation and a larger footprint.
- Buildings remain low-count Node2D views but draw their baked team/kind sprite with procedural hit flash, collapse, and permanent HP bar overlays.
- Obstacles use baked rock/crate sprites selected deterministically from cell coordinates and a soft offset shadow.
- Infantry width is 42 px, approximately 66% of the 64 px tile width. Sprite transforms are foot-anchored to logical positions.

## Board and overlays

Territory colors use muted blue/red values at roughly half the previous visual intensity. Checker variation and grid-line contrast are reduced. A thin bright line is drawn only where adjacent ownership differs.

Unit HP bars are hidden at full health. Damage resets a three-second renderer-only visibility timer; the final 0.6 seconds fade out. Bars are 18x2 px and sit close above the head. Building and HQ bars remain always visible.

Unit shadows are soft elliptical sprites at 0.35 alpha. Blockers have visible vertical mass and offset shadows, so they cannot read as unit shadows.

## Verification

Rules tests lock the combat ratios, per-kind detection, melee air exclusion, and ranged/dragon targeting. Renderer tests lock HP-bar timing state, foot anchors, batch counts, atlas presence, and persistent building bars. Atlas validation checks dimensions, transparency, non-empty frames, directional variation, and luminance range. Smoke capture adds a visual-hierarchy close-up containing full-health and damaged units, dragon, buildings, blockers, muted board, frontier line, and shadows. Existing rules, game-flow, balance, 300+ stress, headless smoke, Android export, and signing checks remain mandatory.
