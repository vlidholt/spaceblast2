# Flutter & Serverpod project

This project is a Flutter app (frontend) backed by a Serverpod server (backend). Always build the app's backend with Serverpod.
Build for multiple users, use Serverpod's built-in authentication, which is already set up in `lib/server.dart`.

The user starts the server and Flutter app with `serverpod start`. There is no need to check if the server is running: make the changes and call the `serverpod` MCP tools as needed. If the server is not running, an informative error message will be received from the MCP server. Then STOP and ask the user to start it. NEVER start the server yourself. The Flutter app is started along with it, or can be launched from the MCP tool `spawn_flutter_app`.

While running, `serverpod start` watches for file changes to run incremental code generation and hot reload both the server and the Flutter app.

Calling `serverpod generate` directly is not needed, but might be useful to troubleshoot when an incremental generation fails.

ALWAYS use the MCP server instead of the command line. Use the MCP server to:

- `create_migration` and `apply_migrations` for database (after you change data models).
- `create_repair_migration` if the database has drifted out of sync with the migrations.
- `tail_server_logs` to read logs from the server.
- `tail_flutter_logs` to read the raw stdout/stderr of the Flutter app.
- `hot_reload` / `hot_restart` to reload or restart the server and the Flutter app. ALWAYS call `hot_restart` after doing changes in the Flutter app that may not work with normal hot reload (which is automatically applied).
- `spawn_flutter_app` to start a Flutter app declared under `serverpod: flutter_apps:` in the server `pubspec.yaml`.
- `get_flutter_app_dtd` (Dart tooling daemon) for connecting to the app through the `dart` MCP.

NEVER edit generated code. The server's `lib/src/generated/` directory and the whole `spaceblast2_client` package are rewritten by the code generator. Change the `.spy.yaml` models, the endpoints, or `lib/server.dart` instead.

Migrations are a narrow exception: the `migration.sql` of a generated migration MAY be edited by hand when the generated SQL would lose data — to add a data transformation, or to reach a destructive change through non-destructive steps. Never touch the other files in the migration directory, and keep the schema the SQL ends up with identical to `definition.sql` — new databases are created from that file and never run `migration.sql`.

Only when the server cannot be started at all, fall back to the CLI in the server package:

- `serverpod generate` to regenerate the client and the generated server code.
- `serverpod create-migration` after changing a model with a `table` (add `--force` for destructive changes). It only writes the migration; `serverpod start` applies pending migrations when it boots the server.

Tests need no Docker. `config/test.yaml` sets `database.dataPath`, so Serverpod starts and manages the test database (an embedded PostgreSQL) itself, and the project's `docker-compose.yaml` is not used for it. Just run `dart test` in the server package.

Checklist after doing changes, in this order:

- `dart analyze` (CLI)
- `dart format` (CLI). `reference/` is vendored and is a link to `.reference`, which `dart format` skips. Do not format that tree, and do not pass `reference` or `.reference` as a format path.
- `create_migration` and `apply_migrations` (MCP - only if necessary)
- Do `serverpod` MCP `hot_restart` if required (hot reload is done automatically). Will also hot restart Flutter app
- Run tests, if applicable (`dart test` in the server package)
- Check `serverpod` MCP `tail_server_logs` and `tail_flutter_logs` for any issues.

If the user asks you to test the app:

1. Use `get_flutter_app_dtd` (`serverpod` MCP) to get the Flutter app's DTD
2. Pass the DTD to `connect_dart_tooling_daemon` (`dart` MCP) to connect to the app
3. Use `flutter_driver` (`dart` MCP) to navigate through the app

The app is launched from `spaceblast2_flutter/lib/driver.dart`, which starts the Flutter driver extension with text entry emulation turned off so the app stays usable by hand. To let the driver type, set `enableTextEntryEmulation: true` there and `hot_restart` the app.

## The app: Space Blast (3D)

A 3D remake of the 2D SpriteWidget game in `reference/spaceblast`, built with `flutter_scene` (primary target: Flutter web). There is no server connection yet; the game is entirely client side in `spaceblast2_flutter`.

Architecture (`spaceblast2_flutter/lib/game/`):

- `sim/` is a pure-Dart, step-for-step port of the original gameplay (`GameDemoNode`, `GameObjectFactory`, `game_objects.dart`, `PlayerState`, `PersistantGameState`). It runs at a fixed 60 steps per second (`GameWorld.step()`), keeps the original coordinate system (320 units wide, y down, level scrolls by `scroll`), the original approximations (`GameMath.atan2`, approximate distance) and even the original collision quirks. Never change gameplay numbers here without checking the reference. It emits `GameEvent`s (sounds, explosions, flashes, score) and never depends on rendering. Tests: `spaceblast2_flutter/test/sim_test.dart` (`flutter test`).
- `render/` turns the simulation into a `flutter_scene` scene. 1 world unit = 100 game units (`kWorld`), so models use the original sprite scale (0.3/0.32) directly. The gameplay camera (`game_camera.dart`) uses a lens-shifted `PerspectiveProjection` subclass: the playfield plane maps exactly onto the original 2D screen while the camera sits south of center and sees the models at an angle. Objects are interpolated between fixed steps. Effects are CPU particles written into instanced `BillboardGeometry` batches (`sprite_batch.dart`, `effects.dart`). The background is two `.fmat` shaders (`assets/materials/`) on planes at depth, so parallax comes from real depth. Lighting is deliberately dark and dramatic (low ambient, raking key light, colored rims); everything that glows (explosions, fires, lasers, engine, crystals, pickups) requests point lights from `light_pool.dart` each frame. Depth of field is only used for the menu shot: in gameplay it would blur transparent objects like the crystals, so background blur is faked (mip-biased textures, soft distant stars). `SpriteBatch.add` takes counter-clockwise rotations (the billboard shader itself rotates clockwise).
- `game_controller.dart` owns sim + renderer + audio, drives phases (menu → launching → playing → returning) and the camera shots.
- `ui/` is the Flutter overlay: menu, HUD, world-anchored 2D (level titles, boss bar, coin flights, joystick) and `AppFrame` (keeps the 1.5:1 mobile aspect, animated mood border on wide screens).
- `audio.dart` uses `flutter_soloud` (web needs the two script tags in `web/index.html`; audio starts on the first user gesture).

Assets: models load at runtime from `spaceblast2_flutter/models/*.glb` (kept outside `assets/` so the flutter_scene hook does not also convert them to large `.fsceneb` files). Their textures are NOT embedded: Safari cannot decode images embedded in a `.glb` on the web, so `tool/split_glb_textures.dart` moves them to `models/textures/` and writes `models/textures.json`; `ModelLibrary` assigns them after import. Re-run it when models change: `dart run tool/split_glb_textures.dart ../reference/spaceblast_assets/models`. Phones/tablets use a lighter render profile (`GameRenderer.isMobile`: 1.5x pixel ratio cap, FXAA, no depth of field) because mobile Safari kills tabs that use too much GPU memory. Sprites, textures, audio and fonts come from the original game.

Dev notes:

- Build hooks (`.fmat` materials) only run on a full build, not on hot restart. After editing a `.fmat`, restart `serverpod start` (or run `flutter build web` once) so `flutter_scene_generated/` is refreshed.
- On web, hot restart can leave flutter_scene's GPU state stale; reload the browser page if the scene stays black.
- `lib/driver.dart` registers dev-only service extensions (`lib/dev/`): `ext.spaceblast.cmd` (play, joystick, power-ups, skip, boom, hideui, reload), `ext.spaceblast.snap` (posts a PNG screenshot to `http://127.0.0.1:8765/snap`) and `ext.spaceblast.logs`. The Flutter Driver screenshot command does not work on the web-server device. For browsers that cannot be driven (Safari, the iOS Simulator), build `lib/dev/diag_main.dart` in release mode: it posts logs and screenshots tagged with the user agent to the same local receiver every few seconds (`?autoplay=1` starts a shielded run).
