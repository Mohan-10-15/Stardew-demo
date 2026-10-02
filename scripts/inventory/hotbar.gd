class_name Hotbar
extends Resource
## The nine slots across the bottom of the screen, and which one is held.
##
## A view onto an [Inventory], not a second bag. Slots are indices into the
## inventory, so moving an item in the inventory moves it in the hotbar for free —
## two parallel containers is a bug factory, and the salvaged Unity build kept
## them in sync manually for years.
##
## Why nine: the input map already binds `hotbar_1` through `hotbar_9`, and the
## wheel. The count is therefore a consequence of the controls, and [constant SLOT_COUNT]
## exists to make that relationship explicit rather than to leave a magic number
## in three files.

## Matches `hotbar_1` .. `hotbar_9` in the InputMap, and the wheel's wrap-around.
const SLOT_COUNT := 9

## Emitted after the held slot changes.
##
## A local signal rather than a publish straight onto [EventBus], for the same
## reason [Inventory] has `contents_changed`: this is a plain [Resource] with no
## scene and no owner, so it cannot know who should hear about a selection — and
## reaching for an autoload from here makes the file impossible to load from a
## `--script` run, because autoloads are not global identifiers until they are in
## the tree (see `AGENTS.md`, "Two Godot-specific traps").
##
## [PlayerStateService] relays this to `EventBus.hotbar_selection_changed` once
## it has somewhere to publish from.
signal selection_changed(slot: int)

## The bag this hotbar shows. Null is allowed so a hotbar can be exercised in a
## test without an inventory; every accessor degrades to "empty" rather than
## crashing.
@export var inventory: Inventory

var _selected: int = 0


func _init(p_inventory: Inventory = null) -> void:
	inventory = p_inventory


## Index of the held slot. Always in `0..SLOT_COUNT-1`.
func get_selected() -> int:
	return _selected


## Holds a slot. Out-of-range values are wrapped rather than refused, because the
## wheel can produce a delta of -1 from slot 0 and a naive `+= delta` would leave
## the selection at -1 with no selected slot at all.
func select(index: int) -> void:
	if index == _selected:
		return
	_selected = posmod(index, SLOT_COUNT)
	selection_changed.emit(_selected)


## Moves the selection by [param delta], wrapping both ways.
func cycle(delta: int) -> void:
	select(_selected + delta)


func select_next() -> void:
	cycle(1)


func select_previous() -> void:
	cycle(-1)


## The stack in a hotbar slot, or null when the slot is empty or the slot index
## is past the end of a short inventory.
##
## Named `slot_stack` rather than the obvious `get_stack` because `get_stack` is
## an inherited [Object] method. GDScript resolves the native one inside this
## class, so a same-named function silently loses its argument and every call
## fails to parse with "Too many arguments for get_stack()", pointing at the
## caller rather than at the collision.
func slot_stack(slot: int) -> Inventory.ItemStack:
	if inventory == null or slot < 0 or slot >= SLOT_COUNT:
		return null
	return inventory.get_slot(slot)


func get_selected_stack() -> Inventory.ItemStack:
	return slot_stack(_selected)


## Text for one slot, for the HUD. Empty slots render as a dash rather than
## nothing at all, so the row reads as nine slots instead of looking broken.
func describe_slot(slot: int) -> String:
	var stack := slot_stack(slot)
	if stack == null or stack.is_empty():
		return "-"
	return stack.describe()


func describe_selected() -> String:
	return describe_slot(_selected)


## The tool action the held slot provides, or empty when the slot is not a tool.
##
## Returns a [StringName] rather than a bool so the farming system can switch on
## the action instead of on "is this a hoe", which is the difference between a
## data-driven tool set and one that grows a new branch per tool.
func get_selected_tool_action() -> StringName:
	var stack := get_selected_stack()
	if stack == null or stack.is_empty():
		return &""
	var definition := ItemRegistry.get_item(stack.id)
	if definition == null or not definition.is_tool():
		return &""
	return definition.tool_action


## The upgrade tier of the held tool, or 0 when nothing usable is held.
##
## The counterpart to [method get_selected_tool_action] for the other half of a tool
## match: what the player can *do* with the held item, and how *good* it is at it.
## Zero rather than 1 for an empty slot so "nothing in hand" cannot accidentally
## satisfy a tier-1 requirement — a hand is not a basic axe.
func get_selected_tool_tier() -> int:
	var stack := get_selected_stack()
	if stack == null or stack.is_empty():
		return 0
	var definition := ItemRegistry.get_item(stack.id)
	if definition == null or not definition.is_tool():
		return 0
	return definition.tool_tier


## The seed id the held slot provides, for planting. Empty when the slot is not
## a seed packet.
func get_selected_seed() -> StringName:
	var stack := get_selected_stack()
	if stack == null or stack.is_empty():
		return &""
	var definition := ItemRegistry.get_item(stack.id)
	if definition == null or definition.category != ItemDefinition.Category.SEED:
		return &""
	# A seed packet's *item id* is the thing it plants. Spelling it
	# `seed_id` on the definition keeps that mapping data instead of a naming
	# convention, because "parsnip_seeds grows parsnip" is a guess, not a fact.
	return definition.seed_id


func is_empty() -> bool:
	for slot: int in range(SLOT_COUNT):
		var stack := slot_stack(slot)
		if stack != null and not stack.is_empty():
			return false
	return true


## Fills the first [param count] slots from a starter loadout. Used by a new game
## so the player begins with a hoe and a watering can rather than nothing.
func apply_starter_loadout(loadout: Array) -> void:
	if inventory == null:
		return
	for i: int in range(mini(loadout.size(), SLOT_COUNT)):
		var entry: Variant = loadout[i]
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		inventory.add(
			StringName(str(row.get("id", ""))),
			int(row.get("amount", 1)),
			int(row.get("quality", Inventory.Quality.NORMAL))
		)