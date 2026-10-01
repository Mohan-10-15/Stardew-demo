# Architecture

How Hollowbrook Hollow is put together, and the rules that keep it that way.

Read `docs/GDD.md` for what the game is. This file is how it is built.

---

## 1. Shape of the project

The repository root is the Godot project root. `project.godot` sits at the top
level, so every invocation is `--path .` from the repo root.

```
.
├── project.godot          # autoloads, input map (generated), display, physics
├── scenes/                # .tscn by domain
├── scripts/               # .gd mirroring scenes/
├── resources/             # .tres + Resource subclasses; content is data
│   └── legacy_content/    # inherited JSON balance data, not yet loaded
├── assets/                # models/ (CC0 FBX), audio/, animations/
├── tests/                 # self-discovering headless suite
│   ├── run_tests.gd       # entry point
│   ├── test_suite.gd      # base class
│   └── suites/            # one file per domain
├── tools/                 # scene generators, boot_check.gd, check.ps1
├── docs/                  # design and process documents
└── AGENTS.md              # team rulebook
```

---

## 2. Layers

Strictly one direction. Nothing below knows anything above it.

```
        main.gd            boot sequence, scene assembly, wiring
             |
     managers / systems    world, time, audio, save, weather
             |
          gameplay         farming, inventory, tools, quests, combat
             |
              core         EventBus, GameState, Config, Log, InputActions
```

- **core** has no dependencies on anything. It is the vocabulary every other
  layer speaks.
- **gameplay** is pure logic. It does not need a scene tree, does not hold
  `Node` references for its rules, and must be unit-testable without building a
  world. Where it must touch the scene, it does so through the `EventBus` or an
  injected `Node`.
- **managers** own scene lifetime and glue. They are stateless: a manager
  registers itself and reacts to signals, so it can be added or removed without
  editing the systems it serves.
- **main** wires them together. It is the only place that knows the full list.

### Why gameplay is separate from world

The simulation lane in `AGENTS.md` owns farming, inventory, economy, skills and
mining as pure logic with no scene dependency. That is not tidiness for its own
sake: it is what makes those systems testable in milliseconds instead of
requiring a booted world, and it is what lets a bot simulation run thousands of
game-days cheaply.

---

## 3. The core globals

Five autoloads are registered in `project.godot`:

| Autoload | Script | Owns |
|---|---|---|
| `EventBus` | `scripts/core/event_bus.gd` | Every cross-system signal |
| `Log` | `scripts/core/log.gd` | Structured output, log levels, verbose toggle |
| `Config` | `scripts/core/config_service.gd` | Settings, persisted to `user://config.cfg` |
| `GameState` | `scripts/core/game_state.gd` | Phase machine, pause, scene transitions, fades |
| `Debug` | `scripts/core/debug_service.gd` | Dev overlay and dev-only console |

Plus one `class_name`, deliberately not an autoload:

| Name | Script | Owns |
|---|---|---|
| `InputActions` | `scripts/core/input_actions.gd` | The action-name registry |

`InputActions` is a `RefCounted` of `StringName` constants, not stateful, so an
autoload would give it a node it does not need.

### Two Godot traps that will bite you

Both of these have already cost real debugging time here.

1. **Autoloads are not global identifiers inside a `--script` run.** A script
   loaded with `--script` compiles before autoloads register, so `Log.info(...)`
   inside it is a compile error. Fetch from the tree root instead:

   ```gdscript
   var log: Node = root.get_node_or_null(^"Log")
   ```

   Do **not** "fix" this by giving the tool script a `class_name`. That pulls the
   dependent script into the tool's compile and reintroduces the error.

2. **Autoloads are not available before a node enters the tree.** Writing
   `global_position` on a parentless node logs an error every single boot.
   `add_child` first, then set the position.

---

## 4. The one hub rule

**Everything cross-cutting goes through `EventBus`.** No system holds a
reference to another system and calls into it.

`EventBus` currently declares 27 signals covering time, farming, inventory,
economy, camera, interaction and lifecycle. Several of them belong to systems
that do not exist yet — see "Signals already reserved for unbuilt systems"
below.

The failure this rule prevents: farming needs to know the day changed, time needs
to know a crop was planted, the HUD needs to know both. Three pairwise
references become a mesh. A hub keeps it a star.

### Signals already reserved for unbuilt systems

`EventBus` declares signals for systems that do not exist yet
(`soil_tilled`, `crop_planted`, `currency_changed`, `item_purchased`,
`item_sold`, `day_ended`, `season_changed`, `year_changed`, and the time
signals). They are declared now so the contract is fixed before the first
implementation forces a choice. Adding a signal later is cheap; renaming one
after five systems depend on it is not.

---

## 5. Content is data

No hard-coded item, crop, NPC or quest definitions. Each is a `Resource`
subclass under `resources/`, looked up by ID.

```gdscript
var crop := CropDatabase.get_crop(crop_id)
if crop == null:
    return fail(case, "unknown crop %s" % crop_id)
```

A new crop is a new `.tres` file. It is not a new `if` statement.

`resources/legacy_content/` holds the balance data inherited from the retired
Unity build — several hundred tuned JSON definitions. They are not loaded yet;
`docs/LEGACY_CONTENT.md` records what each file holds and when it converts.

---

## 6. Behaviour attaches via components

A node becomes interactive by having an `Interactable` in its subtree. The
player never switches on node type.

```gdscript
# In PlayerController — there is no `if node.name == "well"` anywhere.
var target := Interactable.resolve(hit.collider)
```

`Interactable.resolve()` walks *up* from the hit collider, so both
`body > Interactable` and `prop > body > Interactable` layouts work. Discovery
is deliberately pull-based: a central registry would need list syncing across
`free()` and reparent, and would invert the dependency so that props know about
the player.

The player cannot be extended with "and also if you look at a fishing spot".
Fishing spots get their own `Interactable` subclass.

---

## 7. Visual geometry and collision come from one source

This is the invariant the Group 4B pond fix established, and it is the reason
the fix is not just "made the pond a hole".

`WorldBuilder` calls `terrain_height(x, z)` — a pure, deterministic function — and
generates **both** the visual `ArrayMesh` and the `ConcavePolygonShape3D`
collider from the same vertex buffer in a single pass.

Before the fix these were two independently authored flat pieces. That is how
the pond ended up with walkable dry land at `y=0` directly over water at
`y=-0.8`, with the water hidden under opaque grass. Nothing in the codebase
represented a depression, so nothing could disagree about one.

**The general rule:** if a player can stand on it, its collision surface is
derived from the same values as its mesh, in the same function. Never author
them separately.

### Winding differs between the two consumers

`ConcavePolygonShape3D` treats a clockwise face (viewed from above) as its
front; the renderer's front face is counter-clockwise. The collision face list is
therefore expanded in reverse relative to the render index buffer. Feed the
render winding straight through and you get a mesh that looks perfect and
collides with nothing.

Also: `ConcavePolygonShape3D.set_faces()` takes three vertices per face. The
`data` property looks like the obvious assignment and silently reinterprets a
flat vertex array as consecutive face triples — a 3875-vertex grid becomes 1291
arbitrary triangles plus two orphans, and nothing collides.

---

## 8. Input

`InputActions` is the single registry of action names. No string literals for
input anywhere else. Bindings live in `tools/rebuild_input_map.gd` and are
generated into `project.godot`.

```bash
godot --headless --path . --script res://tools/rebuild_input_map.gd
```

A remap therefore shows up in the HUD with no code change, because
`InteractionProbe.get_action_label()` reads the `InputMap` rather than
hard-coding a key.

---

## 9. Scenes are generated, not hand-placed

Every scene in this project is written by a script under `tools/` and run
headlessly. There are no `.tscn` files to drag nodes into.

| Generator | Writes |
|---|---|
| `generate_main_scene.gd` | `scenes/core/main.tscn` |
| `generate_player_scene.gd` | `scenes/player/player.tscn` |
| `generate_world_scene.gd` | `scenes/world/world.tscn` |
| `generate_hud_scene.gd` | `scenes/ui/interaction_hud.tscn` |
| `rebuild_input_map.gd` | the `[input]` section of `project.godot` |

If a task would normally mean dragging a node into a scene or wiring an Inspector
reference, it must instead be a `@tool` or plain script that writes the `.tscn`.
If it cannot be expressed that way, the task is wrong — restructure it. Never
leave a note asking a human to finish something by hand, because on a headless
box nobody will.

---

## 10. Saves

Versioned via `SAVE_VERSION`, with a migration path for every prior version. A
save that cannot be loaded is a bug, not a fallback.

Design constraints already established:

- Gameplay state is a value tree, not live node references. Rebuilding the
  scene must not invalidate it.
- The world is regenerated from its seed, not saved as geometry.
- Every system that owns state implements `to_dict()` / `from_dict()` behind a
  `Resource`, so save and load are testable without booting the game.

---

## 11. Module ownership

Every file has an owner. Do not edit another lane's module without
coordinating. The lane table is in `AGENTS.md` section 2.

| Lane | Owns |
|---|---|
| World & Engine | `scripts/world/`, terrain, props, lighting, weather VFX, art pipeline, animation, performance |
| Simulation | time, calendar, farming, inventory, tools, economy, skills, crafting, fishing, mining — pure logic, no scene dependency |
| People & Interface | `scripts/npc/`, schedules, dialogue, quests, festivals, `scripts/ui/`, audio, settings, tutorial |
| core | project setup, `GameState`/`EventBus`, resource schemas, generator conventions, build/test scripts, docs, integration, git |

Only core runs git commits.

---

## 12. Tests

Self-discovering. Drop a `.gd` in `tests/suites/` extending `TestSuite`; nothing
else to register.

```gdscript
extends TestSuite

func get_cases() -> Array[StringName]:
    return [&"my_feature_works"]

func _run(case: StringName) -> Dictionary:
    return check_equals(case, 1 + 1, 2)
```

`is_async()` returns true when a case must await frames — anything that builds a
scene or queries physics.

### Assert relationships, not literals

Re-tuning the valley should not invalidate the suite. Where possible, assert
that one generated thing is above or below another, not that it sits at a magic
number. Where a measurement is genuinely needed, measure it through the same
interface a player would use: the pond tests raycast the real collider rather
than reading node positions, because a raycast is what "where do I stand" means.

### Do not weaken assertions to make a suite pass

If a test fails, work out whether the code or the test is wrong, and say which.
During the Group 4B fix, four unrelated tests failed while the collider was
broken. They were right; the geometry was wrong.

---

## 13. Validation

One command, three stages, non-zero on any failure:

```bash
pwsh -File tools/check.ps1
```

| Stage | Proves |
|---|---|
| `import` | the project rescans with zero parse/compile errors |
| `tests` | the suite passes, with a real pass/fail count |
| `boot` | the real main scene launches headlessly and reaches a playable state |

Zero `SCRIPT ERROR` lines in stderr is part of passing. A stage that exits 0
while logging a compile error is a broken stage.

Note: `check.ps1` uses `pwsh`. On a machine with only Windows PowerShell 5.1,
run `powershell -ExecutionPolicy Bypass -File tools/check.ps1` instead; the
script itself is compatible.

---

## 14. Art

Real modelled assets from CC0 packs — KayKit for characters, Quaternius for
buildings and nature. Stylized and detailed, not blocky primitives. Every pack is
logged in `docs/ASSET_LICENSES.md` with source URL and licence, and the licence
file ships inside the imported folder as the authoritative copy.

Original IP only. Genre-inspired, never another game's names, art or specific
mechanics.