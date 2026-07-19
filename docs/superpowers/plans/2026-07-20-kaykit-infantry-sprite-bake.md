# KayKit Infantry Sprite Bake Implementation Plan

1. Add failing rules for HQ attack strength and ground-only melee targeting.
2. Add configuration constants and implement shared HQ/tower static defense targeting plus air filtering.
3. Vendor the two official CC0 KayKit GLBs and license with provenance notes.
4. Implement the generic Godot sprite baker, inspect upstream animation names, and bake blue/red atlases plus JSON metadata.
5. Add atlas validation and run it against committed outputs.
6. Replace procedural infantry meshes with textured MultiMesh quads, custom-data atlas UV selection, direction/state frames, renderer-only death playback, and one batched blob-shadow layer.
7. Enrich death events and route them from Main to UnitRenderer without changing rule timing.
8. Add a close-up smoke scenario and update CI visual checks.
9. Run import, rule, game-flow, stress, runtime smoke, atlas validation, and visual capture gates; inspect captures.
10. Update README performance/licensing/visual notes, build and verify the debug APK, commit, push, verify Actions, and publish the stable direct APK copy.
