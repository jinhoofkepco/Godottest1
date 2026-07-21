# DEFEND rally overflow egress implementation plan

1. Extend the existing DEFEND overflow rule test with a 28+1 fixture and verify the unfixed member remains stuck while the anchor advances.
2. Add rally-egress priority for non-defending marching members inside their source rally radius.
3. Initialize marching anchors from member positions and clamp their lead using allocation-free per-legion centroid caches.
4. Run rules, .NET contracts, game flow, counter matrix, balance, stress, smoke, Android export, and release-asset verification.
