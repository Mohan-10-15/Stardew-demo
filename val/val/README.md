# Hollowbrook Hollow

A stylized 3D farming / life-simulation game built with **Godot 4.5** and **GDScript**.

The game supports both **first-person** and **third-person** cameras, switchable
in-game at any time.

All art, audio and text in this project is original placeholder/procedural work.
No assets are taken from any existing commercial game.

---

## Requirements

* Godot 4.x (developed against **4.5-stable**)
* No addons, no C# — plain GDScript

A portable editor copy lives in `tools/` (git-ignored). To use your own install,
just point Godot at this folder.

## Running

```bash
# Open in the editor
godot --editor --path .

# Run directly
godot --path .
```

## Headless / CI

```bash
# Import assets once
godot --headless --path . --import

# Run the automated test suite
godot --headless --path . --script res://tests/run_tests.gd

# Rebuild the InputMap from source (edits project.godot)
godot --headless --path . --script res://tools/rebuild_input_map.gd
```

## Controls

| Action | Keys | Gamepad |
| --- | --- | --- |
| Move | `W` `A` `S` `D` / arrows | Left stick |
| Sprint | `Shift` | L3 |
| Crouch | `Ctrl` | R3 |
| Jump | `Space` | A |
| Interact | `E` / Left click | X |
| Inventory | `Tab` | Y |
| Quest journal | `J` | Back |
| Toggle camera (1st ↔ 3rd) | `V` | RB |
| Pause / back | `Esc` | Start |
| Hotbar 1–9 | `1`…`9` | — |
| Cycle hotbar | Mouse wheel | D-pad left/right |

Controller and movement bindings are **data-driven**: they live in
`tools/rebuild_input_map.gd` and are written into `project.godot`.

## Project layout

```
res://
├── scenes/            # .tscn files, grouped by domain
│   ├── core/          # main scene, bootstrap
│   ├── player/        # player rig, cameras
│   ├── world/         # terrain, regions, props
│   ├── farming/       # soil tiles, crop visuals
│   ├── npc/           # NPC bodies, schedules
│   ├── buildings/     # structures
│   ├── ui/            # HUD, menus, dialogue
│   └── items/         # item definition resources
├── scripts/           # .gd files, mirroring scenes/
│   ├── core/          # autoloads, config, events, logging, debug
│   ├── player/  world/  farming/  npc/  inventory/  items/  ui/  save/
├── resources/         # .tres data definitions (items, crops, characters, config)
├── assets/            # models/ textures/ audio/ animations/  (placeholder art)
├── tests/             # headless test suite
├── tools/             # build-time generators (InputMap, scenes)
└── docs/
```

## Architecture rules

1. **No system talks directly to every other system.** They communicate through
   the `EventBus` autoload, which is the single global signal hub.
2. **No hard-coded item / crop / NPC / quest logic.** Definitions live in
   `Resource` subclasses (`resources/`) and are looked up by ID at runtime.
3. **Behaviour attaches via components.** A node opts in by adding a script that
   implements a known method (e.g. `interact()`); the player never switches on
   node type.
4. **Managers are stateless glue.** Systems register themselves and react to
   `EventBus` signals, so they can be added and removed freely.
5. **Saves are versioned** (`SAVE_VERSION`) with a migration path, so new fields
   never break old save files.

## Development progress

See [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) for what is implemented,
what was tested, and what comes next. Work proceeds in 33 sequential groups;
each group must launch and test clean before the next begins.

## Autoloads

| Name | Script | Purpose |
| --- | --- | --- |
| `EventBus` | `scripts/core/event_bus.gd` | Global signal hub |
| `Log` | `scripts/core/log.gd` | Timestamped, categorised logging |
| `Config` | `scripts/core/config_service.gd` | `user://config.cfg` settings |
| `GameState` | `scripts/core/game_state.gd` | Scene flow, pause, transitions |
| `Debug` | `scripts/core/debug_service.gd` | FPS/memory overlay, toggles |