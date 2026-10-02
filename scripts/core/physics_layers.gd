class_name PhysicsLayers
extends RefCounted
## Bit masks for the physics layers declared in `project.godot`'s `layer_names`.
##
## Exists because three separate files were reaching for a bare `1 << 0` and a
## fourth would have had to guess what the numbers meant. The layer *names* are
## authored once in `project.godot`; this is the GDScript-side mirror of them,
## so a layer renamed in one place cannot silently keep the old bit here.
##
## A layer number is 1-based in `layer_names` and 0-based as a bit:
##
## | Constant | `layer_names` entry | Bit |
## |---|---|---|
## | [constant WORLD] | `3d_physics/layer_1` | `1 << 0` |
## | [constant PLAYER] | `3d_physics/layer_2` | `1 << 1` |
## | [constant NPC] | `3d_physics/layer_3` | `1 << 2` |
## | [constant INTERACTABLE] | `3d_physics/layer_4` | `1 << 3` |
## | [constant RESOURCE] | `3d_physics/layer_5` | `1 << 4` |
##
## [constant INTERACTABLE] is the interesting one. It carries colliders that
## exist *only* so a ray can find them: the padded interaction volumes on props,
## and the tall aim-boxes over soil tiles. Nothing solid is ever put on it, so a
## [CharacterBody3D] whose mask is [constant WORLD] walks straight through.
##
## [constant RESOURCE] exists for the same reason, one step further: a dropped log
## has to be *solid enough to land on the ground* and *invisible enough that the
## player is never shoved by a pickup*. Putting a [RigidBody3D] on [constant WORLD]
## achieves the first and fails the second.

## Solid world geometry: terrain, buildings, fences, props.
const WORLD := 1 << 0
## The player and anything else that moves under its own control.
const PLAYER := 1 << 1
## Villagers. Separate from [constant PLAYER] so schedules and collision can be
## reasoned about independently.
const NPC := 1 << 2
## Interaction-only volumes: findable by the probe, never solid.
const INTERACTABLE := 1 << 3
## Loose items on the ground: solid against the world, transparent to everything
## that walks.
const RESOURCE := 1 << 4

## What the player's movement collides with.
const PLAYER_MASK := WORLD
## What the interaction probe raycast looks for: solid world geometry plus the
## interaction-only layer.
const INTERACTION_MASK := WORLD | INTERACTABLE
## What a dropped item rests on. Deliberately not [constant RESOURCE]: two logs
## bouncing off each other in a heap that never settles is a worse artefact than
## logs that sink gently through one another.
const RESOURCE_MASK := WORLD