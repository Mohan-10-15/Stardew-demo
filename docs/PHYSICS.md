# Physics and game feel (Update 2, W5)

## Engine

`physics/3d/physics_engine = "Jolt Physics"`,
`physics/common/physics_interpolation = true`, both written by
`tools/apply_project_settings.gd`. D22 records the measurement: the full suite
stayed at 669/0 after the switch. Any teleport (respawn, mine descent, cutscene
cut) must call `reset_physics_interpolation()` to avoid a one-frame smear.

## Layer / mask matrix

| Layer | Bit | Used by |
|---|---|---|
| WORLD | 0 | terrain, buildings, props, voxel chunk collision |
| PLAYER | 1 | the player body |
| NPC | 2 | villagers — mask is WORLD only, so story gates never block schedules |
| INTERACTABLE | 3 | aim volumes, never solid |
| RESOURCE | 4 | loose drops, solid against WORLD only |
| GATE | 5 | player-only story barriers; PLAYER_MASK includes it |

PLAYER_MASK = WORLD | GATE. INTERACTION_MASK = WORLD | INTERACTABLE | GATE.

## Movement numbers

All of these live in `resources/config/movement_config.tres` (the schema is
`resources/config/movement_config.gd`); code has no locomotion constants.

| Value | Default | Meaning |
|---|---|---|
| walk / sprint / crouch speed | 4.0 / 7.5 / 2.0 m/s | chosen by the move mode |
| jump velocity | 8.0 m/s | apex 1.33 m at gravity 24 — clears a 1 m block |
| jump hold factor | 0.55 | release early to cut the arc |
| fall gravity scale | 1.35 | heavier descent than ascent |
| terminal velocity | 55 m/s | prevents tunnelling at extreme falls |
| coyote time | 0.10 s | a jump just after leaving a ledge still fires |
| jump buffer | 0.12 s | a press just before landing fires on touchdown |
| step-up height | 0.35 m | ledge climb without a jump |
| floor max angle | 46° | steeper slopes slide |

`tests/suites/test_physics_feel.gd` pins these as pure math, independent of the
physics engine and the display rate.

## How to tune

Edit the `.tres`, never the script. Re-run `check.ps1`; the feel suite will fail
if a change makes a 1 m block unclearable or breaks the coyote/buffer windows.

## Still open (W5.3–W5.4)

Resource-drop impulse/merge/cap, destructibles, the pond WaterVolume and swim
mode, knockback/hit-stop, screen shake, FOV kick and head-bob. These are not
implemented yet and are not claimed here.
