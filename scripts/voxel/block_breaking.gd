class_name BlockBreaking
extends RefCounted
## Break time = hardness / tool speed, with a tier gate and a distinct refusal
## reason for every failure. Pure logic so a --script test can drive the whole
## matrix without a world.

## Multiplier for a tool of the exact tier; higher tiers work faster.
const TIER_SPEED := [0.0, 1.0, 1.6, 2.4, 3.4]

static func tool_tier(item_id: StringName) -> int:
	var definition := ItemRegistry.get_item(item_id)
	if definition == null:
		return 0
	return clampi(definition.tool_tier, 0, 4)


static func tool_kind(item_id: StringName) -> StringName:
	var definition := ItemRegistry.get_item(item_id)
	return definition.tool_action if definition != null else &""


static func can_break(block: BlockData, tool_id: StringName) -> StringName:
	if block == null:
		return &"no_block"
	var definition := ItemRegistry.get_item(tool_id)
	if definition == null:
		return &"no_tool"
	var tier := tool_tier(tool_id)
	if tier < block.minimum_tier:
		return &"tier_too_low"
	if not block.tool_kind.is_empty() and tool_kind(tool_id) != block.tool_kind:
		return &"wrong_tool"
	return &""


static func break_seconds(block: BlockData, tool_id: StringName) -> float:
	if block == null:
		return 0.0
	var tier := maxi(tool_tier(tool_id), 1)
	var speed: float = float(TIER_SPEED[clampi(tier, 1, 4)])
	return maxf(block.hardness / speed, 0.05)
