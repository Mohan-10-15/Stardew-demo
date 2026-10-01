class_name ItemDefinition
extends Resource
## What one kind of item is for.
##
## The single item schema, deliberately generic: crops, seeds, tools, forage and
## fish are all items with different *behaviour*, and that behaviour attaches as
## a component rather than as a field here. A tool is an item whose
## [ItemDefinition.tool] block is filled in; everything else leaves it empty.
##
## This is what stops the codebase growing a `CropItem`, `ToolItem` and
## `FishItem` class hierarchy for the sake of a name and a price.

enum Category { CROP, SEED, TOOL, FORAGE, MATERIAL, FOOD }

@export var id: StringName = &""
@export var display_name: String = "Item"
@export var category: int = Category.CROP
## What the shipping bin pays per unit.
@export_range(0, 10000, 1) var sell_price: int = 0
## What the general store charges. Zero means the item is not sold in shops.
@export_range(0, 10000, 1) var buy_price: int = 0
@export var description: String = ""
## Tint used for the item's inventory swatch. Cheaper than shipping an icon per
## item and keeps the hotbar legible without a texture pipeline.
@export var icon_color: Color = Color(0.7, 0.7, 0.7)
## Whether the tool loses durability when used.
@export var uses_durability: bool = false
## Remaining uses on a fresh tool. Zero on a non-durability item.
@export_range(0, 999, 1) var durability: int = 0
## What the tool does on soil: `till`, `water`, or empty for a hand item.
## Read by [Hotbar.get_selected_tool_action] rather than switched on in the
## player, which is what keeps a new tool a data change.
@export var tool_action: StringName = &""
## For a seed packet, the crop id this packet plants. A field rather than a
## naming convention, because "parsnip_seeds grows parsnip" is a guess that
## breaks the first crop whose id does not follow it.
@export var seed_id: StringName = &""


## Stack cap. Consumables stack high; tools stack at one because two hoes in one
## slot is never what the player meant.
func max_stack() -> int:
	if category == Category.TOOL:
		return 1
	return 99


## Whether this is a tool the player can hold and swing.
func is_tool() -> bool:
	return category == Category.TOOL


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty()


func describe() -> String:
	if sell_price > 0:
		return "%s — sells for %dg" % [display_name, sell_price]
	return display_name


## "Parsnip", "Hoe (12 uses left)"
func describe_stack(amount: int) -> String:
	var label := display_name
	if amount > 1:
		label += " x%d" % amount
	if uses_durability and durability > 0:
		label += " (%d uses)" % durability
	return label