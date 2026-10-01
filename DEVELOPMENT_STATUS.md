# Development Status

Game: **Hollowbrook Hollow** — stylized 3D farming / life-simulation, Godot 4.5, GDScript.
Dual first-person / third-person cameras, switchable at runtime.

Progress: **Groups 0, 1, 2, 3 and 4 complete.** Group 5 (time and ambience) is next.

Current baseline: **92/92 tests**, import clean, boot clean.
Current baseline: **92/92 tests**, import clean, boot clean.

---

## Last completed group

```
GROUP: 3
NAME: Interaction System
STATUS: COMPLETE
```

### IMPLEMENTED
- **Interactable** (`scripts/interaction/interactable.gd`): reusable component, not hard-coded into the player. Any node becomes usable by having an `Interactable` in its subtree
  - `static resolve()` walks up from a hit collider, checking each ancestor's children, so both `body > Interactable` and `prop > body > Interactable` layouts work
  - Pull-based discovery, deliberately no global registry: a registry would need central list syncing across `free()`/reparent and would invert the dependency
- **ExamineInteractable**: generic concrete subclass, proving subclasses only override `can_interact()` / `interact()` and never touch input, HUD, or the player
- **InteractionProbe** (`scripts/interaction/interaction_probe.gd`): the only code that knows the `E` key exists
  - Raycasts from the **active camera**, not the player's chest, so the crosshair is the source of truth; this also works in third person where the camera sits behind the body
  - Excludes the player's own RID so the ray passes through the body
  - Gates: `is_available()` plus a `max_distance` check against `get_focus_point()`
  - Instant and timed (hold) interactions; switching targets restarts hold progress
  - Emits `EventBus.interactable_focused` / `interactable_unfocused` / `interaction_performed`
  - `get_action_label()` reads the InputMap, so a remap shows up in the HUD with no code change
- **InteractionHUD** (`scenes/ui/interaction_hud.tscn` + `scripts/ui/interaction_hud.gd`): prompt label and hold progress bar, driven only by `EventBus`; code-drawn crosshair (`scripts/ui/crosshair.gd`)
  - Spawned after the player, because it locates the probe at runtime; `PROCESS_MODE_ALWAYS` so the pause menu can draw
- Three data-driven demo props in `WorldBuilder` (`VillageWell`, `NoticeBoard`, `SupplyCrate`) built from plain dictionaries by one helper - zero per-prop code
- Interaction colliders are padded to at least 2.4m tall, otherwise a genuinely short prop (a 0.9m crate) sits below the ~1.62m crosshair and cannot be aimed at

### TESTS PERFORMED
`pwsh -File tools/check.ps1` - **3/3 stages OK**

| Stage | Result |
| --- | --- |
| `import` (full project rescan, zero parse/compile errors) | OK |
| `tests` (automated suite) | **92/92 passed** |
| `boot` (real main scene, headless) | OK - `game_ready` fired, `phase=PLAYING`, World/Player/HUD all built, config valid |

### BUGS FOUND AND FIXED DURING THIS GROUP
- `get_world_3d()` is `Node3D`-only, but the probe is a plain `Node` by design; now reads `get_viewport().world_3d`
- `super()` is GDScript 4 syntax; `super()` as a value is not - `super.interact(actor)` is correct
- `TestSuite.tree` is a property, not a method (`await tree.process_frame`, not `tree()`)
- Probe test fixtures never reset their rig, so cases accumulated worlds and players; `get_viewport().get_camera_3d()` then returned the *previous* case's camera and every case after the first aimed at nothing. `_build()` now resets the rig
- **`tools/boot_check.gd` false-positive, now fixed**: a dependency that fails to parse makes `main.tscn` instantiate as a bare `Node3D`, but the autoloads still exist and `GameState` still leaves `BOOTING`, so every check passed on a scene that did nothing. The boot check now asserts the script is attached and that `WorldRoot` / `PlayerController` / `CanvasLayer` children exist. Verified by planting a parse error in `WorldBuilder` and confirming exit code 1
- **Forest colliders and visuals disagreed**: both were generated from independent `rng.randf()` loops, so colliders landed in a completely different part of the forest - the player walked through visible trees. Both now come from one `_forest_sites()` generator
- `MultiMesh.get_instance_transform()` returns identity in a headless run (the buffer is GPU-side), so trunk positions are not readable in tests. `WorldBuilder` now records `forest_sites` as node metadata, which is what the alignment test asserts against

---

## Previously completed groups

```
GROUP: 4
NAME: Procedural World
STATUS: COMPLETE
```

### IMPLEMENTED
- **WorldRoot** (`scenes/world/world.tscn`): deterministic seeded generation from a single RNG, so the same seed always rebuilds the same valley
- **WorldBuilder**: ground, farm plot, forest, pond + water plane + pond floor, dirt paths, five village houses, trees, rocks
- Procedural sun (`DirectionalLight3D`) and sky gradient (`ProceduralSkyMaterial` + `WorldEnvironment`)
- Collision for everything walkable: `StaticBody3D` + `CollisionShape3D`, no falling through the world
- Named spawn points and world regions exposed as an API for later groups (farming, NPCs, time)
- Collision shapes are explicitly named (`CollisionShape3D`); auto-generated names like `@CollisionShape3D@4` break `get_node_or_null` lookups
- `StandardMaterial3D.metallic_specular` used instead of the Godot 3 `specular` property, which logged a remap warning per material

### TESTS PERFORMED

| Stage | Result |
| --- | --- |
| `import` (full project rescan, zero parse/compile errors) | OK |
| `tests` (automated suite) | **69/69 passed** |
| `boot` (real main scene, headless) | OK - `game_ready` fired, `phase=PLAYING`, config valid |

---

## Previously completed groups

```
GROUP: 2
NAME: Dual Camera System
STATUS: COMPLETE
```

### IMPLEMENTED
- `CameraRig` switches between first-person and third-person at runtime on `V` (`toggle_camera_mode`) with no reparenting, so the player never teleports
- The rig is the **single owner** of the camera-mode action. `main.gd` no longer competes for it; two handlers racing the same action could consume a press without toggling
- Only discrete button presses toggle: the handler rejects axis drift, echo and synthetic mouse motion, which previously flipped the camera on its own at window startup
- Third-person uses an explicit `PhysicsRayQueryParameters3D` rather than `SpringArm3D`, so behaviour is deterministic and unit-testable headlessly
- Asymmetric pull-in / ease-back-out (`occlusion_snap_speed` vs `occlusion_recover_speed`) stops the camera drifting through a wall it failed to notice
- Player body meshes auto-discovered and hidden in first person so the camera never sits inside a floating torso
- `Config.settings.default_camera_mode` is now applied on spawn; FOV refreshes on `EventBus.settings_applied`

```
GROUP: 1
NAME: Player Character Controller
STATUS: COMPLETE
```

### IMPLEMENTED
- `PlayerController` (`CharacterBody3D`) + pure `PlayerMotion` math separated for testability without a physics world
- `MovementConfig` resource (`resources/config/movement_config.tres`) - all feel-tuning is a data change, not a code change
- Walk / sprint / crouch, jump with hold-gravity, terminal velocity, ground snap, separate ground and air acceleration
- Mouse look (yaw on the body, pitch on the rig) plus gamepad right-stick look with deadzone, exponential smoothing and pitch clamps
- Look actions (`look_left/right/up/down`) added to `InputActions`, the InputMap generator and the input-map test suite

### TESTS PERFORMED
| Stage | Result |
| --- | --- |
| `import` | OK |
| `tests` | **69/69 passed** (27 core/input, 19 motion, 23 integration) |
| `boot` | OK |

Integration coverage added for this batch:
- `player_does_not_sink_into_terrain` - grounded after settling, neither floating nor sunk
- `third_person_camera_is_behind_the_player` - camera sits behind the body at the expected distance
- `world_has_ground_surface` - named `CollisionShape3D` actually resolvable on `Ground`
- `v_key_press_toggles_the_camera_mode` - real `InputEventKey` through the InputMap; one press toggles, release does not
- `default_camera_mode_is_honoured_from_config` - rig honours the saved preference on spawn

### BUGS FOUND AND FIXED IN THIS BATCH
| Bug | Cause | Fix |
| --- | --- | --- |
| 21 integration cases silently vanished while the run still reported "All tests passed" | A suite that fails to compile was logged as `SKIPPING` and excluded from totals | Broken suites are now a **hard failure**: `BROKEN (failed to compile)`, counted in `failed`, exit code 1 |
| Physics assertions read `y=1.200000`, exactly the spawn height | `await_step()` is a coroutine but was called without `await`, so no frames were ever awaited | `await await_step(...)` at every call site |
| Players pinned at spawn height and never grounded | Test rig was created once per suite, so all 21 cases stacked a world + player at the same spawn point and shoved each other | `_reset_rig()` per case |
| `Ground has no CollisionShape3D child` | Collision shapes were auto-named `@CollisionShape3D@4` | Every shape explicitly named `CollisionShape3D` |
| `look_*` actions absent from the InputMap | Constants were added to `InputActions` but never to `tools/rebuild_input_map.gd` | Added to key/axis/deadzone/all-actions lists; map regenerated to **29 actions** |
| `Vector3.distance_to(Vector2)` in rock generation | Wrong vector dimension | `.distance_to(to)` |
| `.z` read on a `Vector2` | Wrong component | `.y` |
| Unqualified `THIRD_PERSON` | Enum needs its class scope | `CameraRig.Mode.THIRD_PERSON` |
| Runtime `owner` assignment on a parentless node | `owner` must already be an ancestor | `_finish()` adds the child first, then sets `owner` |
| Boot logged `Condition "!is_inside_tree()" is true` every launch | `player.global_position` written before `add_child` | Position applied after the node enters the tree |
| `GlobalSettings.specular` remap warning per material | Godot 3 property name in a Godot 4 project | `metallic_specular` |
| Player settled "too low" at `y≈0` | Test assumed the capsule was centred on the origin; it is offset so the body origin sits at the feet | Assertion rewritten to check `is_on_floor()` plus a band around `y=0` |

### HARNESS HARDENING
- `TestSuite.skip()` added so a deliberately-unrunnable case can never quietly satisfy a requirement
- Verified the broken-suite guard actually fires: an intentionally malformed suite produced `failed: 1` and exit code `1`

```
GROUP: 0
NAME: Project Foundation
STATUS: COMPLETE
```

### IMPLEMENTED
- Godot 4.5-stable project with autoloads, input map, layer names, physics and rendering settings
- Full folder structure (`scenes/`, `scripts/`, `resources/`, `assets/`, `tests/`, `tools/`, `docs/`) mirroring the domain split
- **Main scene** `scenes/core/main.tscn` with an async boot sequence; reaches `GameState.Phase.PLAYING` and emits `EventBus.game_ready`
- **GameState** autoload: phase machine (`BOOTING → TITLE → LOADING → PLAYING → PAUSED → GAME_OVER`), pause handling, scene transitions with fade, `tree.paused` management
- **EventBus** autoload: 27 declared signals across core / time / farming / inventory / interaction / economy. All cross-system communication goes through here
- **Config** autoload: typed `GameConfig` resource, `user://config.cfg` persistence, applies window size, fullscreen, vsync and master volume; emits `config_changed` / `settings_applied`
- **Input system**: `InputActions` constant registry — no string literals for actions anywhere. 29 actions bound to keyboard + mouse + gamepad, generated into `project.godot` from source
- **Log** autoload: 5 severity levels, per-category level filtering, timestamps, `user://hollowbrook.log` file output, `quiet()` for tests
- **Debug** autoload: FPS / memory overlay, toggled from config
- **Automated test harness**: self-discovering suite runner (`tests/run_tests.gd`), `TestSuite` base class with ~14 assertion helpers
- **Boot verification tool**: launches the real main scene headlessly and asserts it reaches a playable state
- **`tools/check.ps1`**: one-command validation pipeline (import → tests → boot), each stage under a hard timeout so a wedged engine can never hang the run

### FILES ADDED
```
project.godot
.gitignore
README.md
DEVELOPMENT_STATUS.md

resources/config/game_config.gd

scripts/core/event_bus.gd
scripts/core/log.gd
scripts/core/config_service.gd
scripts/core/game_state.gd
scripts/core/debug_service.gd
scripts/core/input_actions.gd
scripts/core/main.gd

scenes/core/main.tscn

tests/run_tests.gd
tests/test_suite.gd
tests/suites/test_core.gd
tests/suites/test_input_map.gd

tools/rebuild_input_map.gd
tools/generate_main_scene.gd
tools/boot_check.gd
tools/check.ps1
```

### FILES MODIFIED
- `project.godot` — autoload registrations, InputMap (29 actions), layer names, gravity, window settings, `main_scene`

### TESTS PERFORMED
`pwsh -File tools/check.ps1` — **3/3 stages OK**

| Stage | Result |
| --- | --- |
| `import` (full project rescan, zero parse/compile errors) | OK |
| `tests` (automated suite) | **27/27 passed** |
| `boot` (real main scene, headless) | OK — `game_ready` fired, `phase=PLAYING`, config valid |

Automated coverage:
- `autoloads_are_registered` — all 5 singletons present in the tree root
- `event_bus_signals_exist` — all 27 signals declared
- `event_bus_has_no_self_connections`
- `config_defaults_are_sane`, `config_set_value_persists` (verified by re-reading from disk), `config_reset_restores_defaults`
- `log_file_is_written`, `log_respects_category_level` (INFO/WARN suppressed, ERROR emitted)
- `game_state_pause_roundtrip` — `tree.paused` toggles correctly
- 19 × input-map cases — every action registered with ≥1 binding

Bugs found and fixed during Group 0 validation:
- `Connection` is not a GDScript type → use untyped `Dictionary`
- `DisplayServer.WindowMode` ≠ `Window.Mode` for `window.mode`
- `process_mode_changed` does not exist in Godot 4.5 → removed
- `pass` is a reserved keyword → assertion helper renamed to `succeeded()`
- `FileAccess.open(..., READ_WRITE)` does not create a missing file → `WRITE_READ`
- `SceneTree` has no `_process` / `set_process` / `get_process_delta_time` → use `create_timer()`
- `tree_exiting` is a `Node` signal, not `SceneTree` → `_exit_tree()`
- **Autoloads are not global identifiers in a `--script` run** (script compiles before autoloads register) → fetch from tree root by name
- **Harness hang:** a suite failing to parse aborted `_run_all()` before `quit()`, leaving 4 orphaned Godot processes. Fixed with `can_instantiate()` guard + frame-delay before tests run

### KNOWN ISSUES
- None

### NEXT GROUP
**Group 1 — Player Controller** (`CharacterBody3D`: walk, run, jump, gravity, collision, acceleration/deceleration, mouse look, keyboard + gamepad, configurable movement)

---
## Group roadmap

| # | Group | # | Group |
| --- | --- | --- | --- |
| 0 | ~~Project Foundation~~ | 17 | Friendship |
| 1 | Player Controller | 18 | Quest System |
| 2 | Camera System (1st + 3rd person) | 19 | Crafting |
| 3 | Interaction System | 20 | Buildings |
| 4 | World | 21 | Fishing |
| 5 | Time System | 22 | Mining |
| 6 | Day / Night Cycle | 23 | Weather |
| 7 | Farming Grid | 24 | Seasons |
| 8 | Crop Data | 25 | UI |
| 9 | Plant / Water / Harvest | 26 | Save / Load |
| 10 | Inventory | 27 | Audio |
| 11 | Tools | 28 | Art / Animation Polish |
| 12 | Resource Gathering | 29 | Performance |
| 13 | Economy | 30 | Testing |
| 14 | NPC System | 31 | Final Integration |
| 15 | NPC Schedules | 32 | Final Quality Pass |
| 16 | Dialogue | | |

---
## How to validate

```bash
pwsh -File tools/check.ps1            # import + tests + boot
pwsh -File tools/check.ps1 -SkipImport
godot --path .                        # play
```

Add `--verbose` or raise `-TimeoutSeconds` if needed. The script kills any
orphaned Godot process on exit, so a broken run never leaves the machine stuck.

### Adding tests
Drop a new `.gd` file in `tests/suites/` extending `TestSuite`. It is discovered
automatically — no registry to update.

```gdscript
extends TestSuite

func get_cases() -> Array[StringName]:
    return [&"my_feature_works"]

func _run(case: StringName) -> Dictionary:
    return check_equals(case, 1 + 1, 2)
```

### Regenerating derived files
```bash
godot --headless --path . --script res://tools/rebuild_input_map.gd   # writes project.godot
godot --headless --path . --script res://tools/generate_main_scene.gd # writes main.tscn
```