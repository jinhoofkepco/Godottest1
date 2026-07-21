# DEFEND rally overflow egress design

## Problem

A DEFEND rally holds 28 units in a stationary garrison. Every later arrival is intentionally launched immediately, but the new marching unit sees that garrison as a slow friendly blocker and enters WAIT forever. WAIT also resets navigation recovery. The legion anchor continues to follow the flow field independently, so its banner advances while the member remains inside the crowd.

## Locked behavior

- Keep the 28-unit defense capacity.
- Keep immediate auto-launch for every overflow unit; do not add a second 20-unit gathering threshold.
- Keep combat, production, income, formations, and rally costs unchanged.

## Design

An overflow member belonging to a non-defending marching legion receives rally-egress priority while it remains inside its source rally's 4.2-cell arrival radius. Egress priority bypasses friendly WAIT and uses the existing lower WAIT separation weight, allowing forward slot steering to win without removing collision-aware movement elsewhere.

Each tick performs one allocation-free O(unit count) pass into fixed legion position-sum/count arrays. A marching anchor is clamped to at most 1.75 grid cells ahead of its live-member centroid. New marching legions start at their member centroid, while the defending garrison remains anchored to the rally. Because the renderer already draws banners at the legion anchor and suppresses non-live legions, this makes the visual banner follow real force progress without a rendering special case.

## Verification

The deterministic regression uses one DEFEND rally, 28 garrison members, and one overflow member. It proves the single overflow legion has one real member and one corresponding banner, then advances six simulated seconds and requires both member movement and a maximum two-cell member-to-anchor gap. Existing destruction fallback, formations, balance paths, and 600/1500/3000-unit stress suites remain required.
