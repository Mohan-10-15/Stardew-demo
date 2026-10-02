class_name GatherYield
extends Resource
## One line in a resource node's drop table: "this many of that item".
##
## A resource rather than three parallel arrays on [ResourceNodeData], because the
## failure mode of the array version is a `.tres` where the amounts belong to a
## different item than the ids — which parses perfectly, passes every "is this
## valid" check, and hands the player the wrong thing.
##
## Not a script field either: a tool never drops wood, so the amount a node gives
## is a *balance* fact about that node, and belongs beside the node's other balance
## numbers rather than in a table the content author has to keep in step.
##
## Nothing here may reach for a registry. This file is compiled by
## `tools/generate_gathering_data.gd` in a `--script` run, where autoloads are not
## global identifiers — so naming [ItemRegistry] from here drags its `Log` calls
## into the tool's compile and the tool fails to load. Formatting a drop's name
## belongs at runtime anyway, and [ResourceNode] is where it happens.

## What comes out. Looked up through [ItemRegistry], which also answers for crops, so
## a node can drop a parsnip without the gather system knowing what a crop is.
@export var item_id: StringName = &""
## Fewest units the roll can produce.
@export_range(1, 99, 1) var min_amount: int = 1
## Most units the roll can produce. Swapped with [member min_amount] on roll, so an
## inverted definition still produces a sane number — but the content test compares
## the two directly, because a silent swap is how a "2 to 4 wood" node quietly
## becomes "4 to 2" and nobody notices until a player is short.
@export_range(1, 99, 1) var max_amount: int = 1


func is_valid() -> bool:
	return not item_id.is_empty() and min_amount > 0 and max_amount > 0


## Units of [member item_id] for one roll. Inclusive at both ends, and
## [member min_amount] is guaranteed to be reachable so a node is never a dud.
func roll(rng: RandomNumberGenerator) -> int:
	var lo := mini(min_amount, max_amount)
	var hi := maxi(min_amount, max_amount)
	if rng == null:
		return lo
	return rng.randi_range(lo, hi)