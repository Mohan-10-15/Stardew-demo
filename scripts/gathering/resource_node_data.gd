class_name ResourceNodeData
extends Resource
## What one kind of gatherable thing is: a tree, a boulder, an ore vein, a berry bush.
##
## The gathering system's answer to "content is data". Nothing in
## [GatheringService] or [ResourceNode] switches on a node's id, so adding a new
## tree to the valley is one `.tres` in `resources/gathering/nodes/` and no code at
## all — which is the whole reason this exists rather than a match statement with
## fourteen arms.
##
## ## Why placement lives here too
##
## [member spawn_count] and [member spawn_region] read like they belong to the world
## generator, and an earlier draft of this schema put them there behind a
## `SpawnTable` resource per region. That was three classes to express "14 oaks in
## the wood" and a fourth thing to keep in step when the art changed. Where a thing
## grows is as much a fact about that kind of thing as how tough it is, so both live
## in one file here and [WorldBuilder] reads them like everything else.
##
## ## Tier resistance, in two parts
##
## [member resist_tier] is the tier at which a tool stops being slowed down, and
## [member weak_tool_multiplier] is what a below-tier tool costs instead — twice as
## many swings on a pine with a stone axe. [member blocks_weak_tools] is the other
## half, for the nodes where "slow" is not a punishment the player should have to
## sit through: an iron vein simply refuses. Both are data so the difference between
## "tedious" and "unavailable" is a content decision rather than a code branch.

enum Category { TREE, ROCK, FORAGE }

## Matches `tools/generate_gathering_data.gd`'s `MAX_TIER`, so a node can never ask
## for a tier no tool in the game has.
const MAX_TIER := 4

@export var id: StringName = &""
@export var display_name: String = "Resource"
@export var category: int = Category.FORAGE
## What has to be in hand for this to yield: `chop`, `mine`, or empty for anything
## picked by hand. A field rather than a subtype, for the same reason
## [member ItemDefinition.tool_action] is: the alternative is a `TreeNode` and a
## `RockNode` class that differ by nothing.
@export var tool_action: StringName = &""

@export_group("Art")
## The CC0 model this node draws. Required, not optional — a gatherable with no art
## is an invisible collider the player aims at and does not understand.
@export var model: String = ""
## What is drawn in its place once it is depleted. Empty means it simply disappears,
## which is right for forage and wrong for a tree: a wood that regrew with no stump
## in the way would look like the world forgot it was ever cut down.
@export var depleted_model: String = ""
## Multiplied over the model's own colours. White leaves the CC0 texture alone, which
## is what every tree and rock wants; ore veins use it because the nature pack has
## exactly two rock shapes and no ore in them.
@export var model_tint: Color = Color(1, 1, 1, 1)

@export_group("Work")
## Swings a well-matched tool needs to break it.
@export_range(1, 99, 1) var hit_points: int = 1
## Tool tier at or above which this node is worked at full speed.
@export_range(0, MAX_TIER, 1) var resist_tier: int = 0
## How many times as many swings a below-tier tool costs. 1 means a weak tool is as
## good as a strong one, which is what every forage plant wants.
@export_range(1, 9, 1) var weak_tool_multiplier: int = 1
## Whether a below-tier tool is refused outright instead of merely slowed.
@export var blocks_weak_tools: bool = false
## Seconds the interact key is held for one swing. Instant for anything picked by
## hand, longer for a trunk, because holding a key to swing an axe is the feedback
## that says "this is work".
@export_range(0.0, 3.0, 0.05) var hit_hold_seconds: float = 0.0

@export_group("Recovery")
## Whole days before it comes back. Zero means never, and a node that never returns
## is how a valley ends up stripped bare by the end of the first week.
@export_range(0, 60, 1) var respawn_days: int = 4

@export_group("Shape")
## Fraction of the model's own footprint that is solid enough to walk into.
##
## Read from [method ModelArt.natural_aabb] rather than typed in, so a collider
## cannot drift away from its artwork. Trees want a trunk (0.2 of a 2.7 m-wide
## canopy); a boulder wants nearly all of itself.
@export_range(0.0, 1.0, 0.01) var collider_radius_scale: float = 0.35
## Fraction of the footprint the probe's ray looks for, and its default. Wider than
## the solid part on purpose: you should be able to aim at a bush's foliage without
## its trunk being in the way.
@export_range(0.05, 1.0, 0.01) var aim_radius_scale: float = 0.6

@export_group("Where it grows")
## Centre of the patch this node is scattered around, in world XZ. A zero radius
## means the node is not scattered at all and is placed by hand.
@export var spawn_region: Vector2 = Vector2.ZERO
## How wide the patch is.
@export_range(0.0, 200.0, 0.5) var spawn_radius: float = 30.0
## How many of this node the generator places. Zero means "content exists, nothing
## spawns it", which is how a node can be authored for a future area or a cave.
@export_range(0, 200, 1) var spawn_count: int = 0
## Closest another gatherable may stand, in metres. Spacing is what stops a patch of
## forty trees from being forty trees inside one collider.
@export_range(0.0, 20.0, 0.25) var spawn_spacing: float = 4.0

## The drop table. At least one line, or the node would break and give the player
## nothing at all, which reads as a bug rather than as content.
@export var yields: Array[GatherYield] = []


## Whether this is a tree, a rock or something picked by hand. Read by the world
## generator for scatter rules and by [ResourceNode] for the prompt verb.
func verb() -> StringName:
	if not tool_action.is_empty():
		return tool_action
	return &"forage"


## What a tool of [param tier] needs to break this. The one place the tier maths
## lives, so the prompt, the service and the tests cannot each invent their own.
func hits_required(tier: int) -> int:
	if not blocks_weak_tools and tier < resist_tier:
		return maxi(hit_points * weak_tool_multiplier, 1)
	return maxi(hit_points, 1)


## Whether a tool of [param tier] may work on this node at all.
func accepts_tier(tier: int) -> bool:
	if not blocks_weak_tools:
		return true
	return tier >= resist_tier


func is_valid() -> bool:
	if id.is_empty() or display_name.is_empty() or model.is_empty():
		return false
	if hit_points <= 0 or respawn_days < 0:
		return false
	if hit_hold_seconds < 0.0 or weak_tool_multiplier <= 0:
		return false
	if yields.is_empty():
		return false
	for line: GatherYield in yields:
		if line == null or not line.is_valid():
			return false
	return true


## What a swing is called in the prompt: "Chop the Oak", "Mine the Boulder".
func describe_action() -> String:
	match verb():
		&"chop":
			return "Chop"
		&"mine":
			return "Mine"
		&"forage":
			return "Pick"
	return "Gather"


## "Oak" / "Copper Vein", never the raw id, so a typo in an id is visible in the
## prompt rather than hidden behind it.
func describe() -> String:
	return display_name