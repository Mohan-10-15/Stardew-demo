# Hollowbrook Hollow

A stylized 3D farming / life-simulation game in the spirit of Stardew Valley — an
original world, cast and story. Restore the Heartstone by completing the Valley
Collections: crops, fish, minerals, recipes, critters and friendships.

Built with **Godot 4.5** and **GDScript**. No addons and nothing installed
system-wide. One measured C# system (`scripts/sim/BalanceSweep.cs`) and a small
Windows launcher use .NET; see `docs/MULTI_LANGUAGE_ARCHITECTURE.md`.

## Running the game

Double-click **`Hollowbrook.exe`** in this folder. It starts the bundled portable
Godot with the right arguments — no terminal, no install. A Desktop shortcut
named **Hollowbrook** points at it.

> **There is an older copy of this project at `C:\mohan\projects\Stardew dmeo`.**
> It is stale (Group 17) and has no `tools/GodotSharp` folder. Launching the
> *Mono* Godot binary there produces an "unable to find the .NET assemblies
> directory" error. Always run the copy in `C:\mohan\Game\Stardew dmeo`, or the
> Desktop shortcut — the launcher uses the non-Mono engine and never loads C#.

A fresh `git clone` also needs the git-ignored portable dev tools copied into its
`tools/` folder before the headless pipeline will run: all four
`Godot_v4.5-stable_*.exe` binaries **and `GodotSharp/` (Api + Tools)**. Without
`GodotSharp/`, the Mono engine aborts with `.NET: Assemblies not found`. The
shipped game and launcher are unaffected — this is only for running `check.ps1`
on a clone. The exact steps are recorded at the top of
`docs/evidence/update2/w8-final-fresh-clone.log`.

From a terminal (PowerShell):

```powershell
cd "C:\mohan\Game\Stardew dmeo"
& ".\tools\Godot_v4.5-stable_win64_console.exe" --path . --rendering-driver opengl3
```

Do not pass `--headless` when you want a window; that flag is only for the
automated pipeline:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1
```

Controls: WASD move, mouse look, Space jump, E interact, K / left-click attack,
V camera, F5 save, F9 load, Esc pause, F3 log.

Both a **first-person** and a **third-person** camera, switchable in-game at any
time with `V`.

Art is either original procedural work generated at runtime, or a real modelled
CC0 pack (KayKit, Quaternius) recorded in [`docs/ASSET_LICENSES.md`](docs/ASSET_LICENSES.md).
Nothing is taken from any existing commercial game.

---

## Requirements

* Godot 4.x (developed against **4.5-stable**); a portable copy is in `tools/`
* No addons. The game is plain GDScript; one measured balance sweep uses C#,
  and the Windows launcher is a small .NET program. Neither is required to play.

A portable copy lives in `tools/` (git-ignored). Nothing needs to be installed
system-wide; use that binary, or point your own Godot 4.5 at this folder.

## Play it

This repository **is** the Godot project, so `--path .` from the repo root:

```powershell
# Play
& "tools/Godot_v4.5-stable_win64.exe" --path .

# Open in the editor
& "tools/Godot_v4.5-stable_win64.exe" --editor --path .
```

The Godot binary ships inside the repo at `tools/` and is git-ignored.

## Validate it

```powershell
pwsh -File tools/check.ps1
```

Runs the full pipeline — a clean project import, the automated test suite, and a
headless boot of the real main scene — and exits non-zero if anything fails or if
the engine logs a script error. `-SkipImport` is faster while iterating.

Current state: **620/620 tests passing**, import clean, boot clean, zero script
errors. See [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) for the per-milestone
record and [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) for what each M-number means.

Individual stages, when you need one directly:

```powershell
# Import assets once
& "tools/Godot_v4.5-stable_win64_console.exe" --headless --path . --import

# Run the automated test suite
& "tools/Godot_v4.5-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd

# Boot the real main scene headlessly and assert it is playable
& "tools/Godot_v4.5-stable_win64_console.exe" --headless --path . --script res://tools/boot_check.gd

# Rebuild the InputMap from source (edits project.godot)
& "tools/Godot_v4.5-stable_win64_console.exe" --headless --path . --script res://tools/rebuild_input_map.gd
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
| Journal / quests | `J` | Back |
| Toggle camera (1st ↔ 3rd) | `V` | RB |
| Pause / back | `Esc` | Start |
| Settings & accessibility | `F2` | — |
| Craft | `C` | — |
| Machines | `B` | — |
| Buildings | `N` | — |
| Save / load | `F5` / `F9` | — |
| Toggle log | `F3` | — |
| Hotbar 1–9 | `1`…`9` | — |
| Cycle hotbar | Mouse wheel | D-pad left/right |

All bindings are data-driven from `tools/rebuild_input_map.gd`. The settings
panel (F2) can rebind interact, inventory, craft, build, camera, log and attack
at runtime; the changes persist in `user://config.cfg` and the interaction
prompt's key label follows the new binding.

Controller and movement bindings are **data-driven**: they live in
`tools/rebuild_input_map.gd` and are written into `project.godot`.

## Layout

```
res://
├── project.godot
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
    ├── ARCHITECTURE.md     # how the project is put together
    ├── ROADMAP.md          # milestone sequence
    ├── TASKS.md            # current work item and queue
    ├── DECISIONS.md        # decisions and reasoning
    ├── ASSET_LICENSES.md   # every asset, source URL, licence
    ├── ACCEPTANCE.md       # what each milestone must do
    ├── CUTSCENE_GUIDE.md   # the cinematic system's contract
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

## Autoloads

| Name | Script | Purpose |
| --- | --- | --- |
| `EventBus` | `scripts/core/event_bus.gd` | Global signal hub |
| `Log` | `scripts/core/log.gd` | Timestamped, categorised logging |
| `Config` | `scripts/core/config_service.gd` | `user://config.cfg` settings |
| `GameState` | `scripts/core/game_state.gd` | Scene flow, pause, transitions |
| `Debug` | `scripts/core/debug_service.gd` | FPS/memory overlay, toggles |

## Docs

- [`AGENTS.md`](AGENTS.md) — team rulebook: how to build and verify, lanes, quality gates
- [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) — what is built, what was tested, what is next
- [`docs/GDD.md`](docs/GDD.md) — game design document
- [`docs/ASSET_LICENSES.md`](docs/ASSET_LICENSES.md) — every asset with source URL and licence
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — layers, autoloads, the hub rule, and the invariants that keep it together
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — the milestone sequence and its dependencies
- [`docs/TASKS.md`](docs/TASKS.md) — the current work item and the queue
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — decisions and the reasoning behind them
- [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) — what each milestone must do before it counts as done
- [`docs/CUTSCENE_GUIDE.md`](docs/CUTSCENE_GUIDE.md) — the cinematic system's contract
- [`docs/SALVAGED_DESIGN.md`](docs/SALVAGED_DESIGN.md) — calendar / inventory / farming rules recovered from the retired Unity sims
- [`docs/LEGACY_CONTENT.md`](docs/LEGACY_CONTENT.md) — the inherited JSON content and when to convert it

## Development progress


All milestones **M0–M19 are complete** (core, calendar, farming, economy,
dialogue, relationships, homestead, combat, seasons, cutscenes, buildings,
festivals, story, audio, accessibility, save, art, performance and balance).
See [`DEVELOPMENT_STATUS.md`](DEVELOPMENT_STATUS.md) for the per-milestone record.

## Release status

| Channel | Status |
| --- | --- |
| Windows — clickable launcher | **Works.** `Hollowbrook.exe` finds the project, starts the bundled non-Mono Godot with `--rendering-driver opengl3`, and needs no install. Verified on this machine. |
| Windows — standalone Godot export | **Works.** `build/Hollowbrook.exe` is a self-contained 148 MB executable (PCK embedded) — copy it anywhere and double-click; no repo, engine or .NET needed. Verified running here. |
| Web export | **Works.** `build/web/index.html` plus its `.wasm`, `.pck` and support files; serve the folder over HTTP and open `index.html`. The title screen renders in a browser. |
| Fresh clone | Clone the repo, keep `tools/` (the portable engine and `GodotSharp` assemblies are git-ignored, so copy them from an existing checkout), then double-click `Hollowbrook.exe` or run `tools/check.ps1`. To rebuild the exports, install Godot 4.5 export templates and run `godot --headless --path . --export-release "Windows Desktop" build/Hollowbrook.exe` (or `"Web" build/web/index.html`). |
| Fresh clone | Clone the repo, keep `tools/` (the portable engine and `GodotSharp` assemblies are git-ignored, so copy them from an existing checkout), then double-click `Hollowbrook.exe` or run `tools/check.ps1`. |
| Debug cheats | No cheat, god-mode or noclip action exists in the InputMap. F3 (log), F5/F9 (save/load) and the F2 settings panel are ordinary player-facing tools. |

Every shipped art, audio and font asset is traced with source URL and licence in
[`docs/ASSET_LICENSES.md`](docs/ASSET_LICENSES.md); audio is synthesised at
runtime by `AudioSynth`, so there are no untracked sound files.
