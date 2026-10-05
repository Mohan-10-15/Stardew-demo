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

## The name for more than one, when a plain "s" would be wrong or ugly.
##
## Left empty, [method plural] appends one. Set it for the mass nouns and the irregulars,
## which is most of the gathering list: "20 Wood" not "20 Woods", "2 Stone" not "2
## Stones". Guessing in code instead would mean every quest line reads "Bring 5 Parsnips"
## correctly and "Bring 20 Woods" wrongly, which is exactly the sort of thing that survives
## a green test run because the tests assert on the id, not the prose.
@export var plural_name: String = ""
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
## Stamina one swing of this tool costs.
##
## On the tool rather than in a table inside [Stamina], so adding a tool is a
## content change and nothing else. Zero is meaningful and free: it is how a
## starting tool stays usable, and how a non-tool stays at no cost.
@export_range(0, 100, 1) var stamina_cost: int = 0
## What the tool does on soil: `till`, `water`, or empty for a hand item.
## Read by [Hotbar.get_selected_tool_action] rather than switched on in the
## player, which is what keeps a new tool a data change.
@export var tool_action: StringName = &""
## Which upgrade tier this tool is, 1 to 4.
##
## Read by [Hotbar.get_selected_tool_tier] and compared against a resource node's
## [member ResourceNodeData.resist_tier], which is how "a copper axe is slower on a
## pine than an iron one" is a data fact rather than a chain of `if id == ...`.
##
## Zero on a non-tool, and treated as no tier at all: a bare hand picking berries is
## not a tier-0 tool that gets outclassed the moment better gloves appear.
@export_range(0, 4, 1) var tool_tier: int = 0
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


## The name for [param amount] of these, in a sentence.
##
## One is always [member display_name]; more than one is [member plural_name] when the item
## supplies one, and otherwise [member display_name] with an "s" on the end.
func plural(amount: int) -> String:
	if amount <= 1:
		return display_name
	return plural_name if not plural_name.is_empty() else "%ss" % display_name


## "Parsnip", "Hoe (12 uses left)"
func describe_stack(amount: int) -> String:
	var label := display_name
	if amount > 1:
		label += " x%d" % amount
	if uses_durability and durability > 0:
		label += " (%d uses)" % durability
	return label