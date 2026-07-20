# GLB to isometric sprite atlas

This Godot SceneTree CLI loads animated GLBs into a transparent `SubViewport`, samples named clips from an orthographic isometric camera, recolors the model materials for each team, and writes packed PNG atlases plus JSON metadata.

The committed infantry sheets preserve the original skin, metal, leather, and weapon materials. Only saturated cloth regions are hue-swapped after lighting, so team color retains the baked luminance and directional shading.

Default project bake:

```bash
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy \
  --path . -s tools/sprite_baker/bake_sprites.gd
```

Generic invocation:

```bash
godot --path . -s tools/sprite_baker/bake_sprites.gd -- \
  --models=guard:res://model_a.glb,archer:res://model_b.glb \
  '--animations=Idle,Walk,Slash,Death;Idle,Walk,Shoot,Death' \
  --teams=blue:62a7ff,red:ff6670 \
  --directions=8 --pitch=30 --cell=96 --output=res://assets/units
```

Use `inspect_model.gd -- <model-path>` to list imported animation names before choosing mappings. At the default two models, eight directions, and 16 frames per direction, the tool produces two 1536×1536 team atlases.

World sprite bake (dragon, five team building variants, rocks, and crate):

```bash
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy \
  --path . -s tools/sprite_baker/bake_world_sprites.gd -- \
  --output=res://assets/world
```

This produces a 512×512 static atlas, two 1536×768 animated dragon atlases, and `world_atlas.json`.

SIEGE catapult bake (vendored KayKit CC0 team models, eight headings, procedural walk/recoil/death motion):

```bash
godot --display-driver macos --rendering-method gl_compatibility --audio-driver Dummy --path . -s tools/sprite_baker/bake_siege_sprites.gd
```

This produces two 1536×1536 texture-array layers plus `assets/units/siege_atlas.json`.
