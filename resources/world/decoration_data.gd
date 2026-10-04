class_name DecorationData
extends Resource
## Typed schema for one kind of scenery: something placed to make a place look like a
## place, and that no player can interact with.
##
## ## Why this is not a [ResourceNodeData]
##
## Because the difference is the whole point. A gatherable node is gameplay: it can be
## hit, it yields items, it blocks a tool, it respawns on a timer, it is saved. A
## decoration is scenery, and scenery that accidentally becomes harvestable is a bug
## that reaches a player's inventory. Keeping the two definitions apart in two
## directories means a decoration cannot grow a `tool_action` because a field was
## renamed.
##
## ## Why so many knobs for scenery
##
## The first version had a count and a model. The result was a uniform sprinkle of one
## kind of bush, which reads as *spawned* rather than as *growing* — the giveaway is
## that every instance is identical and evenly spaced. Scale and yaw jitter are what
## break that up, and they are one line each.
##
## ## Batched
##
## Grass tufts are cheap to draw individually and ruinous to draw as three hundred
## nodes, each with its own transform the CPU has to walk every frame. Setting
## [member batched] puts a decoration into a single [MultiMeshInstance3D]. Only worth it
## for props that are numerous, small and non-colliding — batching a tree means batching
## a tree you can no longer walk into.

@export var id: StringName = &""
@export var display_name: String = "Decoration"

@export_group("Art")
## The CC0 model this decoration draws.
@export var model: String = ""
## Multiplied over the model's own colours. White leaves the CC0 texture alone.
@export var model_tint: Color = Color(1, 1, 1, 1)
## Height in metres to draw the model at, or 0 for its imported size.
@export_range(0.0, 12.0, 0.05) var target_height: float = 0.0
## Multiplier on the measured natural height, so one kind can be scattered at several
## sizes from a single definition.
@export_range(0.5, 2.0, 0.05) var scale_jitter: float = 1.0

@export_group("Where it grows")
@export var spawn_region: Vector2 = Vector2.ZERO
@export_range(0.0, 200.0, 0.5) var spawn_radius: float = 70.0
## Inner bound, so a decoration can be scattered in a *ring* rather than a disc.
##
## Written because of reeds. Reeds belong at a pond's edge, and the pond's edge is
## inside [method WorldBuilder.is_reserved] — the basin and a shoreline margin are both
## keep-out. So a disc centred on the pond can only ever put reeds in the surrounding
## field, and a definition that wanted the shore had nowhere to say so.
@export_range(0.0, 200.0, 0.5) var spawn_inner_radius: float = 0.0
@export_range(0, 400, 1) var spawn_count: int = 0
## Minimum gap to anything already placed. Zero for scatter that may lie on the
## ground next to a rock.
@export_range(0.0, 20.0, 0.25) var spawn_spacing: float = 0.0

@export_group("Behaviour")
## Whether the player walks into it. False for anything under about knee height.
@export var collides: bool = true
## Fraction of the measured footprint that is solid, matching a gatherable node's.
@export_range(0.0, 1.0, 0.01) var collider_radius_scale: float = 0.3
## Drawn as one [MultiMeshInstance3D] instead of one node per instance.
@export var batched: bool = false
## Casts a shadow. Off for grass: a thousand shadow casters for scenery nobody walks
## through is a frame-time problem bought with nothing.
@export var casts_shadow: bool = true


func is_valid() -> bool:
	return not id.is_empty() and not model.is_empty()


## Height the model will be drawn at, before jitter, in metres.
func draw_height() -> float:
	if target_height > 0.0:
		return target_height
	return ModelArt.natural_height(model)