class_name ShopDefinition
extends Resource
## What one shop sells.
##
## ## It is content and nothing else
##
## An id, a name, and a list of ids. It holds no prices and performs no lookups,
## and that is not squeamamness — it is load-bearing. A [Resource] that calls
## [ItemRegistry] cannot be loaded from a `--script` run, because `ItemRegistry`
## logs through `Log` and autoloads are not identifiers until they are in the tree
## (see `AGENTS.md`, "Two Godot-specific traps"). `generate_shop_data.gd` needs
## this class to write a shop, so a lookup here breaks the generator outright.
##
## It is also simply better separated: prices belong to the thing, not the counter.
## A parsnip has one sell price in the whole game, and a shop carrying its own
## price table would be a second place to update every time a crop's value
## changed. [EconomyService] resolves them.
##
## What genuinely *is* per-shop, and therefore what belongs here, is which items
## this particular counter stocks. A general store selling every seed in the game is
## a different shop from a ranch selling only what it raises, and neither is
## expressible without a per-shop list.

## Stable id, used by [ShopRegistry] and in saves.
@export var id: StringName = &""
## Shown on the shop's prompt and heading.
@export var display_name: String = "Shop"
## Item ids this shop sells. Order is the order the player sees.
@export var stock: Array[StringName] = []
## Whether the shop also buys what the player carries.
##
## False for a counter that only sells, so a future quest-only shop cannot be used
## to dump a rare item for gold by accident.
@export var buys_from_player: bool = true


## Whether this shop sells [param item_id].
func stocks(item_id: StringName) -> bool:
	return stock.has(item_id)


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty()


func describe() -> String:
	return "%s (%d items)" % [display_name, stock.size()]