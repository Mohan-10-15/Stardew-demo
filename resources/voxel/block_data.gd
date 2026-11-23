class_name BlockData
extends Resource
## One voxel block type. Content, not code: authored by
## tools/generate_block_data.gd and looked up by id through BlockRegistry.
## Art is detailed by default; a texture pack swaps the tile ids at runtime.

@export var id: StringName = &""
@export var display_name: String = ""
@export var tile_top: StringName = &""
@export var tile_side: StringName = &""
@export var tile_bottom: StringName = &""
## Seconds of continuous work with the correct tier-1 tool.
@export_range(0.05, 30.0, 0.05) var hardness: float = 1.0
@export var tool_kind: StringName = &"pickaxe"
@export_range(0, 4, 1) var minimum_tier: int = 1
@export var drops: Array[StringName] = []
@export var place_item: StringName = &""
@export var sound_set: StringName = &"stone"
@export var transparent: bool = false
@export var light_emission: int = 0
@export_enum("solid", "water", "air") var collision_kind: String = "solid"
@export var replaceable: bool = false


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and not tile_side.is_empty() and hardness > 0.0 \
		and minimum_tier >= 0
