# Hollowbrook Hollow

A stylized 3D farming / life-simulation game built with **Godot 4.5** and **GDScript**.

The game supports both **first-person** and **third-person** cameras, switchable
in-game at any time.

Art is either original procedural work generated at runtime, or a real modelled
CC0 pack (KayKit, Quaternius) recorded in [`docs/ART_LICENSES.md`](docs/ART_LICENSES.md).
Nothing is taken from any existing commercial game.

---

## Requirements

* Godot 4.x (developed against **4.5-stable**)
* No addons, no C# — plain GDScript

A portable copy lives in `tools/` (git-ignored). Nothing needs to be installed
system-wide; use that binary, or point your own Godot 4.5 at this folder.

## Running

From the repository root:

```powershell
# Open in the editor
& "val/val/tools/Godot_v4.5-stable_win64.exe" --editor --path "val/val"

# Play
& "val/val/tools/Godot_v4.5-stable_win64.exe" --path "val/val"
```

## Validating

One command runs everything — import, tests, and a real headless boot:

```powershell
pwsh -File val/val/tools/check.ps1
```

It exits non-zero if any stage fails or if the engine logs a script error.
`-SkipImport` is faster while iterating. See `AGENTS.md` in the repository root
for the full contract.

Individual stages, when you need one directly:

```powershell
# Import assets once
& "val/val/tools/Godot_v4.5-stable_win64_console.exe" --headless --path "val/val" --import

# Run the automated test suite
& "val/val/tools/Godot_v4.5-stable_win64_console.exe" --headless --path "val/val" --script res://tests/run_tests.gd

# Boot the real main scene headlessly and assert it is playable
& "val/val/tools/Godot_v4.5-stable_win64_console.exe" --headless --path "val/val" --script res://tools/boot_check.gd

# Rebuild the InputMap from source (edits project.godot)
& "val/val/tools/Godot_v4.5-stable_win64_console.exe" --headless --path "val/val" --script res://tools/rebuild_input_map.gd
```

Note the `_console_` suffix on the binary used for headless runs: it keeps
stdout clean so the pipeline can scan it for errors.

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
├── resources/         # .tres data definitions (config today; items/crops later)
│   └── legacy_content/  # inherited tuned JSON, not yet loaded by the game
├── assets/            # models/ (CC0 FBX)  audio/  animations/
│   ├── models/kaykit/       # 5 characters, 27 accessories
│   └── models/quaternius/   # 13 farm buildings and props
├── tests/             # headless test suite (self-discovering)
├── tools/             # generators, boot_check.gd, check.ps1, portable Godot
└── docs/
    ├── GDD.md              # design document
    ├── ART_LICENSES.md     # every asset, source URL, licence
    ├── SALVAGED_DESIGN.md  # calendar / inventory / farming rules from the old Unity sims
    └── LEGACY_CONTENT.md   # the inherited JSON and when to convert it
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