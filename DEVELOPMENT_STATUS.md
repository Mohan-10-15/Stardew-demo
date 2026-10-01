# Development Status

Game: **Hollowbrook Hollow** — stylized 3D farming / life-simulation, Godot 4.5, GDScript.
Dual first-person / third-person cameras, switchable at runtime.

Progress: **Groups 0–6 complete.** Group 7 (farming grid) is next.

Current baseline: **132/132 tests**, import clean, boot clean.

---

## Last completed group

```
GROUP: 6
NAME: Gameplay Defect Fixes (playtest regression batch)
STATUS: COMPLETE
```

Started from a hands-on playtest of the real windowed build rather than from a
ticket. Four player-visible symptoms, three genuine defects and two false
positives that the diagnostic itself produced.

### IMPLEMENTED
- **Two-yaw movement model** (`scripts/player/player_controller.gd`). `_look_yaw`
  is the aim direction and is written *only* by mouse and gamepad input;
  `_facing_yaw` is which way the mesh points, chased toward the direction of
  travel and eased back to the aim when idle. Movement input is read through
  `_aim_basis()` (`Basis(Vector3.UP, _look_yaw)`), never `global_transform.basis`.
  The camera rig counter-rotates by `look - facing` so aiming is untouched by
  strafing. New `set_yaw()` / `get_facing_yaw()` for tests and tools.
- **Third-person camera height** (`scripts/player/camera_rig.gd`): the camera is
  now placed at `(0, pivot_height, distance)` instead of `(0, 0, distance)`, and
  the occlusion ray pivot moved from world-up to the rig's own space
  (`global_transform * Vector3(0, pivot_height, 0)`) so ray and camera agree
  once the rig is pitched.
- **`FarmMailbox`** (`scripts/world/world_builder.gd`): a fourth demo interactable
  2.9 m from the spawn point. Off the spawn's Z axis so it cannot block the
  straight-down-Z sightline the interaction fixtures rely on.
- **`InteractionHUD` late binding** (`scripts/ui/interaction_hud.gd`): the probe
  lookup retries from `_process` instead of disabling the prompt permanently,
  and re-reads the current focus on attach so a target already under the
  crosshair is not left unlabelled. Insurance, not a fix — see below.

### TESTS PERFORMED
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` — **3/3 stages OK**

| Stage | Result |
| --- | --- |
| `import` | OK — zero parse/compile errors |
| `tests` | **132/132 passed** (6 new) |
| `boot` | OK — `game_ready` fired, `phase=PLAYING` |

Plus a real windowed run of the main scene: `V` toggled the camera mode
repeatedly and `[Examine] Interactable:` fired for both `NoticeBoard` and
`SupplyCrate`, with an empty stderr. Camera and interaction were confirmed by a
human playing, not only headlessly.

New cases, all of which fail against the pre-fix code:
- `third_person_camera_is_at_shoulder_height` — camera local Y equals
  `pivot_height`, and at least 1 m above the player's feet in world space
- `strafing_does_not_spin_the_body` — W+D settles on a ~45° facing instead of running away
- `strafing_keeps_moving_in_a_straight_line` — displacement stays within 25° of the requested diagonal
- `aim_yaw_is_independent_of_facing_yaw` — aim does not follow the body; the rig's *global* yaw returns to the aim heading
- `every_demo_prop_is_reachable_on_foot` — walks the real player to each real prop and asserts the real crosshair ray focuses it
- `something_is_interactable_from_the_spawn_point` — asserts a target exists within component reach of the spawn point, then aims at it

### BUGS FOUND AND FIXED DURING THIS GROUP
- **Holding W+D made the player spin instead of walking.** Movement read its
  input basis from `global_transform.basis` while writing `rotation.y` from the
  resulting direction. Turning toward "right" rotated the basis that interpreted
  "right", which rotated further: measured ~9° per frame, 56° in six frames, so
  the player circled and never travelled a straight line. Fixed by the two-yaw
  split above; the loop cannot close because nothing but the mouse writes the
  basis the input is read through.
- **The third-person camera rendered from the player's feet.** The rig node sits
  at the player origin, which is at the feet, and the third-person branch set
  `_camera.position = Vector3(0, 0, distance)`, never applying `pivot_height`.
  Measured camera height above the player origin: `0.000`. `pivot_height` was
  already declared and already used for the occlusion ray, so the bug was that
  only the ray knew about it.
- **Nothing was interactable anywhere near the start.** All three demo props sat
  26–44 m from the spawn point against a 3.2 m interaction range, so a new game
  opened on an empty field with no prompt and no hint that interaction existed.
  The component and the ray were both correct; the *placement* was the defect.
- **Test collateral:** `test_interaction` fixtures stand at `(0, 0.2, 12.5)` and
  aim down −Z at a fixture prop at `(0, 0, 10)`. The first mailbox placement at
  `(0, 0, 11)` sat directly on that sightline and broke five unrelated cases.
  Moved off-axis. Worth remembering: the mailbox is world content, and the
  fixtures assume an empty corridor.

### FALSE POSITIVES — investigated and dismissed
Recorded because two of these were reported as bugs before being disproved, and
a confident wrong diagnosis costs more time than a wrong fix.
- **"The third-person camera sees nothing / the body is invisible."** Body-mesh
  visibility was already correct and tested (`body_meshes_visible_in_third_person`).
  The real fault was only the camera *height*.
- **"Tree colliders block the interaction ray."** The ray genuinely hit a
  `@StaticBody3D@NN` — but the probe that produced that reading was aimed by a
  guessed heading, and was pointing past the side of the prop at scenery. Aiming
  correctly along the camera→prop vector focuses all four props with no
  occlusion problem, now pinned by `every_demo_prop_is_reachable_on_foot`. No
  collision-layer change was made; `3d_physics/layer_4="interactable"` remains
  unused and available.
- **"The interaction HUD could never find the probe."** The warning came from a
  temporary `tools/probe*.gd` diagnostic run, where `--script` compiles before
  autoloads register and the typed `InteractionProbe` check resolved false. The
  real boot path orders player-before-HUD and logs nothing. The retry added to
  `InteractionHUD` is defensive, not corrective.
- **"There is no physics."** There are 80 `StaticBody3D` and a correct ground
  collider; the player stands on it. There are no `RigidBody3D`/`Area3D`, which
  is a content gap for later groups, not a defect.

### KNOWN GAPS (not defects, not fixed here)
- **No hotbar.** `hotbar_1`–`hotbar_9`, `hotbar_next` and `hotbar_prev` exist in
  the input map with no consumer: no scene, no script, no node. Tools and items
  arrive with the farming group.
- **No dynamic physics objects.** No `RigidBody3D` or `Area3D` anywhere.

---

## Previously completed groups

```
GROUP: 5
NAME: Time System
STATUS: COMPLETE
```

### IMPLEMENTED
- **`WorldTime`** (`scripts/time/world_time.gd`): the calendar as a `Resource`
  value holding only primitives — year, season, day, hour, minute, weather,
  forecast, `passed_out`. Copied on every advance and serialised to a save, so a
  save can never capture a freed node reference.
- **`Clock`** (`scripts/time/clock.gd`): all the arithmetic, as static pure
  functions. No scene, no signals, no side effects, which is why 112 game-days
  simulate in microseconds and the whole calendar is testable without a tree.
  - Time is measured in **absolute minutes from the 6:00 AM day start**;
    `to_absolute_minutes` offsets pre-dawn display times by `+1080`, so 0:00–5:59
    AM is the *tail* of the current day rather than the head of the next one.
  - `advance` clamps at the 2:00 AM collapse, rolls the calendar there, and
    returns a transition dict (`day_rolled`, `season_rolled`, `year_rolled`,
    `passed_out`, `minutes_advanced`) so callers never diff old against new.
  - `to_game_minutes` is the monotonic HHMM scale authored NPC schedule windows
    are written against: 6:00 AM = 600, midnight = 2400, 2:00 AM = 2600.
  - `next_day_morning` (sleep, always rolls) and `wake_after_collapse` (carried
    home, does not roll) are separate operations. See D13b.
- **`TimeService`** (`scripts/time/time_service.gd`): the only thing that knows
  real seconds exist. Converts elapsed time to ticks and publishes transitions on
  `EventBus`. Freezes at 2:00 AM rather than rolling silently through empty days
  while the player is unconscious.
- **`DayNightCycle`** (`scripts/world/day_night_cycle.gd`): drives the sun and
  sky from the clock. Subscribes to `EventBus.time_minute_changed` and holds **no
  reference to `TimeService`** — the hub is the only channel, and the sun energy,
  colour, elevation and sky gradient are all interpolated from six key points
  across the day, held at their darkest through the 2:00–6:00 AM sleep window.
- **`ClockHUD`** (`scenes/ui/clock_hud.tscn` + `scripts/ui/clock_hud.gd`): date,
  time and weather in the corner, spawned by `main.gd` after the world so it can
  find the service. Reads `get_display_text()` once per repaint rather than
  reassembling a date from three partial signals, and repaints on the minute
  signal rather than every frame.
- Weather and forecast are carried on the time value from the start, so a save
  taken today is still readable after M9 adds the weather system.

### DESIGN DECISIONS THAT DEVIATED FROM THE SALVAGED NOTES
Full reasoning in `docs/DECISIONS.md` D13. In short:
- **The day rolls at the 2:00 AM collapse, not at midnight.** The salvaged doc
  says both "advancing at midnight rolls the day" and "at 2:00 AM the farmer
  collapses *and* the day rolls". Both cannot be the boundary. 2:00 AM is the
  last instant a player can occupy, so it wins. `SALVAGED_DESIGN.md` is annotated
  where it was superseded rather than edited to match the code.
- **`to_game_minutes` is HHMM, not minutes.** The salvaged values (600 / 2400 /
  2600) are not elapsed minutes; there is no scale where midnight is 2400
  minutes and 2:00 AM is 2600 minutes.
- **Monotonicity is scoped to one day walked chronologically.** A 24-hour sweep
  asserts 5:59 AM → 6:00 AM is increasing, which it is not (2950 → 600) — that is
  the start of the next day, not a step backwards. The first version of the test
  swept 0:00 → 23:59 and failed at 6:00 for exactly that reason.
- **A corrupt save degrades field by field** rather than being rejected whole.
  `posmod` and `clamp` disagree on negatives: a `season` of `-1` read with a
  modulo wrap lands on Winter, one short of every season-name array.

### TESTS PERFORMED
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1` — **3/3 stages OK**

| Stage | Result |
| --- | --- |
| `import` | OK — zero parse/compile errors |
| `tests` | **126/126 passed** (27 in `test_time.gd`) |
| `boot` | OK — `game_ready` fired, `phase=PLAYING`, clock HUD spawned |

`tests/suites/test_time.gd` (27 cases) covers every edge case the retired Unity
build pinned down, plus the ones found while building it:
- 6:00 AM is absolute minute zero; midnight is 1080; 2:00 AM is 1200
- pre-dawn times split correctly: 0:00–2:00 AM is the playable tail, 2:01–5:59
  is the player asleep and lands past the collapse point
- crossing midnight does **not** roll the day; reaching 2:00 AM does
- advancing past 2:00 AM clamps, rolls exactly one day, and lands on 6:00 AM
- `passed_out` is sticky — a later tick cannot revive the player
- 120 ten-minute ticks is exactly one day
- the season rolls on day 29; the year rolls after winter
- `next_day_morning` and `wake_after_collapse` are both copy-then-mutate
- sleeping rolls the day, waking from a collapse does not
- the service freezes at 2:00 AM and resumes on the same morning
- weather and forecast survive a rollover
- `day_of_week` stays in range across a whole 112-day year
- `to_game_minutes` hits 600 / 2400 / 2600 and never goes backwards within a day
- save round-trip is field-exact; empty, partial, out-of-range and negative
  payloads all load safely
- the lighting cycle tracks the clock through real `EventBus` emissions, is
  darkest at 2:00 AM, and holds through the sleep window
- the clock HUD renders the real date and time and repaints on a tick

### BUGS FOUND AND FIXED DURING THIS GROUP
- **`to_game_minutes` was not the documented scale.** It returned
  `to_absolute_minutes + 360`, which gives midnight as 1440 and 2:00 AM as 1560.
  Neither matches the 2400 / 2600 that authored schedule windows are written
  against, so any schedule using them would have inverted at midnight.
- **`passed_out` was only set when the advance was *clamped*.** Reaching exactly
  the collapse point moved the full requested amount, so `moved < requested` was
  false and the player never collapsed — they just sat at 2:00 AM forever.
- **`advance` could rewind the day.** A clock already at or past the collapse got
  a negative playable budget, so a tick moved time backwards. Now `maxi(..., 0)`.
- **`passed_out` was cleared by the next advance.** It was assigned rather than
  accumulated, so a tick after the collapse quietly revived the player. Now
  `result.passed_out or target >= PASS_OUT_ABSOLUTE`.
- **`sleep_until_morning` had a tautology.** `var rolled := time.day_of_month > 0`
  is always true, and the day it emitted was the *new* one, not the day that
  finished. Sleeping also rolled the calendar a second time after a collapse,
  which cost the player a day for having passed out. Split into
  `sleep_until_morning` and `wake_after_collapse`.
- **The service spun through empty days at 2:00 AM.** Nothing stopped the clock
  once the player was unconscious, so a 10-minute day became hundreds of days of
  nothing while the game waited for the prompt. `advance_tick` is now a no-op
  while `passed_out`.
- **`set_time` announced a day that never ended.** It emitted `day_started` on
  every load. It now compares dates first, so loading a mid-morning save is
  silent.
- **The clock HUD labels were empty.** `get_node_or_null("Panel/DateLabel")` did
  not match the generated `Panel/Column/DateLabel`. The labels were null, so
  `_refresh` silently did nothing. Caught by rendering through the real scene.
- **Two lighting rigs were alive at once.** The first lighting test used
  `queue_free()`, and the harness runs cases synchronously without pumping a
  frame, so the freed node was still in the tree and the second case found two
  suns. Now `free()`.
- `Weather.size()` on an enum dictionary and `posmod` on corrupt enum values both
  misbehave under negative input; both are clamped now.

---

## Previously completed groups

```
GROUP: 4B
NAME: Procedural World - pond basin fix
STATUS: COMPLETE
```

A defect was found in Group 4 during the Phase 1 audit: the ground was a single
flat face, so the pond had no basin. The player walked on dry land at `y=0`
directly over the water plane at `y=-0.8`, and the water itself was hidden
underneath the opaque grass. Both symptoms came from the same cause — the visual
ground and the ground collider were two independently authored flat pieces, so
nothing anywhere represented a depression.

### IMPLEMENTED
- `WorldBuilder.terrain_height()` (`scripts/world/world_builder.gd`): a pure,
  deterministic height function. Flat at `y=0` everywhere except inside a
  smoothstep basin over the pond, sloping to `-2.2` at its centre.
- The ground is now one 44x44 vertex grid displaced by that function. The
  `ConcavePolygonShape3D` and the `ArrayMesh` are built from the **same**
  vertex buffer in one pass, so what the player walks on is exactly what they
  see. They cannot drift apart again.
- Smooth area-weighted vertex normals, so the basin walls actually shade as a
  slope instead of reading as flat horizontal ground.

### TESTS PERFORMED
`powershell -ExecutionPolicy Bypass -File tools/check.ps1` — **3/3 stages OK**

| Stage | Result |
| --- | --- |
| `import` | OK |
| `tests` | **99/99 passed** |
| `boot` | OK — `game_ready` fired, `phase=PLAYING` |

New suite `tests/suites/test_world_geometry.gd` (7 cases) covers the
relationships that were broken: the ground answers raycasts across the valley,
the valley floor is still flat away from the pond, the pond centre is genuinely
below the valley floor, the water plane sits between the basin floor and the
grass, and the pond floor collider backs up the terrain without poking through
it.

### BUGS FOUND AND FIXED DURING THIS GROUP
- **`ConcavePolygonShape3D.data` is not a vertex array.** Assigning a flat
  `PackedVector3Array` to `data` reinterprets it as consecutive face triples, so
  a 3875-vertex grid silently became 1291 arbitrary triangles plus two leftover
  vertices — and nothing collided. `set_faces()` is the correct call. Confirmed
  by probe: `data =` misses a downward ray, `set_faces()` hits it at `y=0`.
- **Trimesh collision winding is opposite the render winding.** Feeding the
  render indices straight through produces a mesh that looks perfect and
  collides with nothing; the player fell through the world. The collision face
  list is now expanded in reverse order. Reverse the *whole* thing instead and
  the mesh renders inside out, so it is done on the collider side only.
- `add_surface_from_arrays` failed with `index_array_len==NO_INDEX_ARRAY`
  because the index buffer was still empty at that point; the winding fix moved
  the index generation and the visual mesh silently lost its indices. Caught by
  reading the errors rather than trusting the test pass.
- `player_does_not_sink_into_terrain`, `ground_supports_the_spawn_point`,
  `world_has_ground_surface` and the interaction tests all failed while the
  collider was broken. They were correct; the geometry was not.

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

## Phase status

Phases come from `prompt.md`; milestones from `docs/ROADMAP.md`; groups from the
table below. See `docs/ROADMAP.md` for why groups and milestones are two
different numbering schemes.

| Phase | Name | Status |
|---|---|---|
| 1 | Audit | **COMPLETE** — pond defect reproduced, root-caused, fixed, regression-tested |
| 2 | Foundation | **COMPLETE** — docs established, lanes, roadmap, acceptance criteria, schemas |
| 3 | Complete game | IN PROGRESS — M2 (time and calendar) **COMPLETE**; M3 (farming) next |

---

## Known gaps

Carried forward so they are not rediscovered as bugs later:

| Gap | Status |
|---|---|
| Hotbar / tool belt | Not built. Actions exist in the input map, no consumer. Arrives with the farming group. |
| Dynamic physics | No `RigidBody3D` or `Area3D` in the world. Static collision is complete. |
| `3d_physics/layer_4="interactable"` | Declared but unused. Available when props need to be aimable without being solid. |

---

## Group roadmap

| # | Group | # | Group |
| --- | --- | --- | --- |
| 0 | ~~Project Foundation~~ | 17 | Friendship |
| 1 | Player Controller | 18 | Quest System |
| 2 | Camera System (1st + 3rd person) | 19 | Crafting |
| 3 | Interaction System | 20 | Buildings |
| 4 | World | 21 | Fishing |
| 5 | ~~Time System~~ | 22 | Mining |
| 6 | ~~Day / Night Cycle~~ | 23 | Weather |
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