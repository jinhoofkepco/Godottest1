# KayKit Infantry Sprite Bake Design

## Scope

Keep the fixed-tick, packed-array battle simulation and the existing building/dragon presentation. Change only two combat rules and infantry rendering:

- HQs fire at the same cadence and range as a defense tower, for exactly three times tower damage.
- Melee infantry cannot select or retain flying dragon targets. Ranged infantry, towers, and HQs can target dragons.
- Melee and ranged infantry use baked KayKit sprites with direction and state animation, while remaining MultiMesh-rendered data rather than Nodes.

## Licensed source

Use KayKit Character Pack: Adventurers 1.0 from the creator's official GitHub repository. The repository states CC0 1.0 Universal and includes animated GLBs. `Knight.glb` is the melee silhouette and `Rogue_Hooded.glb` is the ranged silhouette. Commit the upstream license and a source note next to the selected models.

## Atlas contract

`tools/sprite_baker/bake_sprites.gd` is a reusable SceneTree CLI. Arguments select models, directions, camera pitch, animation mappings, frame size, output directory, and team colors. It loads each GLB in a transparent SubViewport, uses an orthographic isometric camera, rotates the model through eight 45-degree headings, samples idle/walk/attack/death clips, recolors material albedo before capture, and packs uniform cells.

Each team atlas is 16 columns by 16 rows. Each class occupies 128 cells. Within a class, every direction occupies 16 consecutive cells: idle 2, walk 6, attack 4, death 4. At 96 px per cell the atlas is 1536×1536, below the 2048² target. Metadata records source models, clip names, frame dimensions, state offsets/counts, directions, team colors, and cell layout.

## Runtime renderer

One globally Y-sorted infantry MultiMesh shares one quad mesh and a two-layer team texture array made from the two baked sheets. Instance custom data carries atlas cell coordinates while instance color carries team layer, HP brightness, and alpha. A CanvasItem shader chooses the layer and cell UV. Direction comes from velocity quantized to eight headings; attack uses lunge direction and cooldown phase; WAIT/zero velocity uses idle; movement uses walk. Renderer-only death ghosts consume enriched `unit_death` events and expire after the four-frame death sequence without delaying simulation removal.

A single extra MultiMesh draws translucent ellipse shadows beneath all live infantry and death ghosts. Dragons retain the existing procedural batched silhouette and remain clearly airborne.

## Verification

Rules tests prove HQ damage is exactly three tower shots, melee ignores dragons, and ranged/static defenses can attack them. Atlas validation checks 1536² bounds, uniform metadata, transparent corners, non-empty frames, and distinct directional samples. Smoke capture adds a close-up containing both classes and multiple headings. Existing game-flow and 400-unit stress tests remain gates; stress documentation records the new run.
