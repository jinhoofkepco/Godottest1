# War Inc Style Tower Defense Demo Design

## Scope

Build one portrait-oriented, one-match tower-defense demo in Godot 4.5 stable with GDScript and procedural 2D drawing only. The board is a 9 x 14 top-down square grid. The first three rows are the purple enemy zone, rows 5 through 12 accept towers, and the final row is the green core line. Enemies remain in their spawn column and damage the shared core when they cross the bottom line; the core is drawn at bottom center to preserve the requested focal point without introducing pathfinding.

The locked economy is 150 starting gold, 50 gold per tower, 10 gold per kill, and 25 gold per cleared non-final wave. The core starts at 20 HP. Five increasingly dense and fast waves end in victory; core HP reaching zero ends in defeat.

## Visual and Interaction Design

The virtual canvas is 540 x 960 with `canvas_items` stretch and `keep` aspect. The board uses 54-pixel cells, leaving a 27-pixel side margin. A compact dark HUD occupies the top 108 pixels. The ally zone is green, enemy zone purple, interactive/weapon accents teal, and impacts orange. All visuals are drawn by `_draw()` methods or standard controls; there are no image, font, audio, or AI-generated assets.

Tapping or clicking an empty buildable ally cell places the only tower type when at least 50 gold is available. Occupied, enemy-zone, core-row, and insufficient-gold taps do nothing. The next-wave button is enabled only between waves. The restart button appears only after victory or defeat.

## Architecture

- `Main` owns match state, gold/core/win-loss transitions, scene wiring, camera shake, and restart.
- `Grid` owns geometry, cell conversion, buildability, occupancy, and board drawing.
- `WaveManager` owns five-wave schedules, spawn cadence, and wave completion detection.
- `Enemy`, `Tower`, and `Projectile` own their movement/combat behavior and communicate through signals or narrow setup methods.
- `Core` renders core health feedback; `Hud` renders data and emits button intentions.
- `Fx` owns procedural kill fragments and process-always hit-stop.
- `GameConfig` contains tuning constants and pure wave-scaling functions.

Entity scenes are instantiated into dedicated `Enemies`, `Towers`, and `Projectiles` containers. A tower queries the enemy container for the nearest valid target in range. A projectile retains a target reference, moves toward it, and applies damage on arrival. Enemy removal notifies both match economy and wave accounting exactly once.

## Game Flow

The match opens between waves with 150 gold and the next-wave button enabled. Starting a wave makes the wave manager spawn enemies in cycling columns. Defeated enemies award gold and trigger white flash, orange fragments, and about 60 ms of hit-stop. Enemies crossing the core line reduce core HP and trigger a small decaying world offset. When all scheduled enemies are gone, the cleared wave awards 25 gold; non-final waves enable the next-wave button and wave five shows victory. Core damage resolves before wave completion, so a final enemy that depletes the core produces defeat. Core HP zero immediately stops spawning and shows defeat.

Restart reloads the main scene. The design deliberately has no upgrades, tower selection, pathfinding, audio, persistence, menus, or extra game modes.

## Android and CI

The Android export preset is named `Android` and exports to `build/godottest1.apk`. The project requests portrait orientation, uses GLES3 compatibility rendering, and enables arm64 plus arm32 APK architectures.

GitHub Actions checks out the repository, creates a temporary standard Android debug keystore with `keytool`, exposes it through Godot's documented keystore environment variables, and invokes `dulvui/godot-android-export@v4.1.0` with Godot `4.5` on the `stable` channel. Because that action hardcodes an internal release export, the workflow then runs an explicit `--export-debug Android` with the installed toolchain and overwrites the final path. `actions/upload-artifact` publishes `build/godottest1.apk` as `godottest1-debug-apk`. No user secret is needed.

## Verification

Headless tests cover grid build rules, wave scaling, economy, tower placement, five-wave victory, and core-damage defeat. A separate main-scene smoke run catches parser and startup errors. `godot --headless --import` must exit without import errors. The GitHub Actions run must finish successfully and expose the APK artifact before delivery.
