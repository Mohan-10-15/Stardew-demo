class_name PlayerStateService
extends Node
## Everything about the player that changes, is saved, and is not the player
## controller: the bag, the nine hotbar slots, the purse, and stamina.
##
## ## Why this exists
##
## The bag used to belong to [FarmService]. That worked until the shop needed to
## put items in it, and the two available answers were both bad: the shop could
## reach into the farm service, which makes the economy depend on farming; or the
## shop could own a bag of its own, which means two bags.
##
## So the bag moved out to a node whose only job is to be the owner. Farming and
## the economy both ask *it*, and neither depends on the other. [FarmService]
## resolves it by group, the same way [SoilTileInteractable] resolves the farm
## service.
##
## ## Why one node and not four
##
## Bag, hotbar, purse and stamina are four values, not four systems. They have no
## behaviour that needs to be removed and re-added independently, they share one
## save boundary, and splitting them would mean three of the four holding a
## reference to the fourth. [FarmService] holding a bag was already this shape;
## what was wrong was the *name* on it, not the grouping.
##
## ## What this node is not
##
## It holds no rules. [Inventory] knows how to merge stacks, [Wallet] knows what
## a price is, [Stamina] knows what exhaustion means. This node owns them, relays
## their signals onto [EventBus], reads the hotbar keys, and hands out the
## starting loadout. The rules live in the value objects.

## Group this node registers under, so other services can find the player's state.
##
## Duplicated as a literal in the services that look it up, because a shared
## constant would require naming one class from the other. `AGENTS.md` calls that
## the `class_name` cycle trap and it is a real one: the errors it produces point
## at innocent bystanders rather than at the cycle.
const SERVICE_GROUP := &"player_state"

## Emitted when the held slot changes. Relayed so audio and the HUD do not each
## walk the tree for the owner.
signal hotbar_selection_changed(slot: int)

## Size of the bag. 24 is two rows of twelve, and is the number the salvage notes
## recorded from the old build.
@export_range(4, 96, 1) var bag_slots: int = 24
## Slots on the hotbar. Matches `hotbar_1` .. `hotbar_9` in the input map; see
## [method _unhandled_input] for why it is derived rather than declared.
@export_range(1, 9, 1) var hotbar_slots: int = 9
## Gold the player starts a new game with. Enough for a handful of parsnip seeds,
## so the shop is reachable on the first day instead of after a week of foraging.
@export var starting_gold: int = 500
## Stamina ceiling for a new game.
@export_range(10, 500, 1) var max_stamina: int = 100

## The player's bag.
var inventory: Inventory = null
## The player's nine quick slots.
var hotbar: Hotbar = null
## The player's purse.
var wallet: Wallet = null
## The player's stamina.
var stamina: Stamina = null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	if inventory == null:
		inventory = Inventory.new(bag_slots)
	if hotbar == null:
		hotbar = Hotbar.new(inventory)
	elif hotbar.inventory == null:
		# A hotbar injected from a scene arrives without its bag. Pointing it at
		# the owner's inventory is the whole reason this node exists, so it is not
		# optional: a hotbar over a different bag shows the wrong nine slots while
		# looking completely healthy.
		hotbar.inventory = inventory
	if wallet == null:
		wallet = Wallet.new()
	if stamina == null:
		stamina = Stamina.new(max_stamina)

	# Relays. Each value object publishes locally because it cannot know who
	# should hear; EventBus is where cross-cutting listeners find it. Same
	# arrangement as FarmService's relay, moved here because the bag is no longer
	# its to relay.
	inventory.contents_changed.connect(_on_inventory_changed)
	wallet.gold_changed.connect(_on_gold_changed)
	stamina.stamina_changed.connect(_on_stamina_changed)
	hotbar.selection_changed.connect(_on_hotbar_selection_changed)

	# Sleep is the only thing that refills stamina, and the farm already listens
	# for the same moment to advance crops. One subscription, one direction.
	EventBus.day_started.connect(_on_day_started)

	Log.info("PlayerState", "Ready (%d bag slots, %d gold, %s)" % [
		inventory.slot_count(), wallet.gold, stamina.describe(),
	])


## Finds the owner's state anywhere in the tree.
##
## By group rather than by a hardcoded path, because `root/Main/PlayerState` is
## right in the shipped layout and wrong in every test that builds its own rig.
static func find() -> PlayerStateService:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search(scene_root)


static func _search(node: Node) -> PlayerStateService:
	if node is PlayerStateService:
		return node as PlayerStateService
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


## Hands the player a hoe, a watering can, an axe, a pickaxe and some parsnip seeds.
##
## Lives here rather than on [FarmService] because these are the *player's*
## things, and the loadout is decided by who the player is, not by which
## subsystem happens to run first. The farm only cares that a seed packet exists.
##
## The axe and pickaxe are not a gift, they are a minimum viable toolset: [Group 12]
## made the valley's trees and rocks gatherable, and a world full of resources the
## player cannot touch is a world that has told them what to do and then refused to
## let them do it. Both are tier 1, so the copper and steel tools still have
## something to be upgrades *over*.
func grant_starter_loadout() -> void:
	if inventory == null:
		return
	inventory.add(&"hoe", 1)
	inventory.add(&"watering_can", 1)
	# Seeds third, deliberately, and the two gathering tools after them. The
	# hotbar index of a starter item is effectively a save-file coordinate — it is
	# what a player's muscle memory is built on — so growing the loadout appends to
	# the end rather than inserting in the middle. Two farming tests hard-coded
	# "slot 2 is the parsnip seeds" and went red the moment an axe was inserted
	# ahead of them, which is the honest way to find out this mattered.
	inventory.add(&"parsnip_seeds", 15)
	inventory.add(&"axe", 1)
	inventory.add(&"pickaxe", 1)
	# Selecting the hoe by default means the player's first click on the field does
	# something, rather than the prompt offering to plant a seed they have not got.
	if hotbar != null:
		hotbar.select(0)
	Log.info("PlayerState", "Granted starter loadout")


## The whole of the player's saveable state, in one dictionary.
##
## One method rather than four so the save system has a single thing to call and
## cannot save the bag without the purse. Versioned by the caller, which owns the
## save file format — see `farm_grid.gd` for why each of those carries its own.
func to_dict() -> Dictionary:
	return {
		"inventory": inventory.to_dict() if inventory != null else {},
		"hotbar_slot": hotbar.get_selected() if hotbar != null else 0,
		"wallet": wallet.to_dict() if wallet != null else {},
		"stamina": stamina.to_dict() if stamina != null else {},
	}


## Restores from [method to_dict].
func from_dict(data: Dictionary) -> void:
	if inventory != null and data.has("inventory"):
		inventory.from_dict(data["inventory"])
	if wallet != null and data.has("wallet"):
		wallet.from_dict(data["wallet"])
	if stamina != null and data.has("stamina"):
		stamina.from_dict(data["stamina"])
	if hotbar != null and data.has("hotbar_slot"):
		hotbar.select(int(data["hotbar_slot"]))


## Wears down the tool in the held slot by one swing, and says what happened.
##
## The single implementation of tool wear, shared by [FarmService] and
## [GatheringService]. It lived on [FarmService] until gathering needed the same
## three rules, and copying them would have meant two places that each forget the
## `remove_stack` comment explaining why `remove` is wrong.
##
## Durability belongs to the *stack*, not the item definition: two hoes bought on
## different days wear out at different times, and a shop that sells a single "hoe"
## resource cannot express that. So the counter lives on the stack and [Inventory]
## is what stores it.
##
## Spending it unconditionally would be the simpler version and would be wrong: an
## unconditional call is exactly the "durability is a property of the item"
## assumption, and it deletes a fresh hoe on its first swing.
##
## [param action] is only used for the empty case — "nothing appropriate is in
## hand, so no tool was worn" — which is what lets a caller pass the verb it is
## trying to perform and get a truthful answer.
##
## Returns `{spent, broke, remaining, id}`:
## - `spent` — whether a swing was actually charged. False when nothing was held, or
##   what was held does not wear out (a hoe, a seed packet).
## - `broke` — whether that swing consumed the last of the tool's remaining uses.
## - `remaining` — uses left after the swing, or -1 when nothing was charged.
## - `id` — the item that wore, or empty. Carried so a caller with its own
##   `tool_broken` signal can relay without re-reading the hotbar and hoping the
##   player has not switched slots in between.
##
## Publishes [signal EventBus.tool_broken] on a break and
## [signal EventBus.inventory_changed] on every successful charge. The stack's amount
## does not change when it merely wears down, so nothing else would have said so, and
## a HUD showing remaining uses would keep showing the old number.
func spend_tool_durability(action: StringName = &"") -> Dictionary:
	var none := {"spent": false, "broke": false, "remaining": -1, "id": StringName()}
	if inventory == null or hotbar == null or action.is_empty():
		return none
	var stack := hotbar.get_selected_stack()
	if stack == null:
		return none
	var definition := ItemRegistry.get_item(stack.id)
	if definition == null or not definition.uses_durability:
		return none
	var remaining := inventory.get_durability(stack)
	if remaining <= 1:
		# `remove_stack`, not `remove`. `remove` spends the lowest quality first,
		# and two Normal watering cans are the same quality — so it would consume a
		# fresh can and leave the worn one in the bag forever, which is the exact
		# situation per-stack durability exists to make representable.
		inventory.set_durability(stack, 0)
		inventory.remove_stack(stack, 1)
		EventBus.tool_broken.emit(stack.id)
		Log.info("PlayerState", "%s wore out" % definition.display_name)
		return {"spent": true, "broke": true, "remaining": 0, "id": stack.id}
	inventory.set_durability(stack, remaining - 1)
	# The stack's amount did not change, so nothing else would have published
	# this. A HUD showing remaining uses has to be told.
	EventBus.inventory_changed.emit()
	return {"spent": true, "broke": false, "remaining": remaining - 1, "id": stack.id}


## Everything a system needs to know about the item in the selected hotbar slot.
##
## One method rather than three because "what is the player holding" is asked by more
## than one system and each of them wanted a slightly different shape:
##
##     {"id": StringName, "item": ItemDefinition, "amount": int, "display_name": String}
##
## `id` is empty when the slot is empty or holds nothing that resolves to an
## [ItemDefinition]; `item` is null in exactly that case, so a caller that only wants
## to check "is there anything to take" tests [member item]'s null-ness and one that
## wants to name the thing tests `display_name`.
##
## The NPC system is the reason this exists: "is the player holding something worth
## giving away, and what is it called" is a question no earlier caller needed answered
## in one place, and re-deriving it per system is how two prompts end up disagreeing
## about what the player is holding.
func held_item_id(_actor: Node = null) -> Dictionary:
	var none := {"id": StringName(), "item": null, "amount": 0, "display_name": ""}
	if hotbar == null:
		return none
	var stack := hotbar.get_selected_stack()
	if stack == null or stack.is_empty():
		return none
	var definition := ItemRegistry.get_item(stack.id)
	return {
		"id": stack.id,
		"item": definition,
		"amount": stack.amount,
		"display_name": definition.display_name if definition != null else String(stack.id),
	}


## Selects a hotbar slot by index, clamped, and ignores a no-op.
##
## The clamp and the equality check are here because both callers — the number
## keys and the wheel — can legitimately produce an out-of-range or repeated
## request, and a repeat should not spam the HUD with a selection it already has.
func select_slot(index: int) -> void:
	if hotbar == null:
		return
	var wanted := clampi(index, 0, maxi(hotbar_slots - 1, 0))
	if wanted == hotbar.get_selected():
		return
	hotbar.select(wanted)


func select_next_slot() -> void:
	if hotbar != null:
		hotbar.select_next()


func select_previous_slot() -> void:
	if hotbar != null:
		hotbar.select_previous()


## Hotbar keys and the scroll wheel.
##
## These actions have existed in the input map since Group 2 and, until this node,
## **nothing consumed them** — `test_input_map.gd` asserted they were bound, which
## is not the same as asserting anything happens when they are pressed. The
## bindings were reachable and the behaviour was missing.
##
## Unhandled rather than `_input`, so a focused menu takes the keys first. A shop
## dialog that swallowed `hotbar_3` because the hotbar answered first would be
## maddening.
func _unhandled_input(event: InputEvent) -> void:
	if hotbar == null:
		return
	if event.is_action_pressed(InputActions.HOTBAR_SLOT_NEXT):
		select_next_slot()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.HOTBAR_SLOT_PREV):
		select_previous_slot()
		get_viewport().set_input_as_handled()
		return
	# A nine-way match rather than a loop over the actions: the actions are
	# constants, so the mapping stays checkable against `InputActions` by the
	# compiler instead of by a substring test at runtime.
	var slot := -1
	if event.is_action_pressed(InputActions.HOTBAR_1):
		slot = 0
	elif event.is_action_pressed(InputActions.HOTBAR_2):
		slot = 1
	elif event.is_action_pressed(InputActions.HOTBAR_3):
		slot = 2
	elif event.is_action_pressed(InputActions.HOTBAR_4):
		slot = 3
	elif event.is_action_pressed(InputActions.HOTBAR_5):
		slot = 4
	elif event.is_action_pressed(InputActions.HOTBAR_6):
		slot = 5
	elif event.is_action_pressed(InputActions.HOTBAR_7):
		slot = 6
	elif event.is_action_pressed(InputActions.HOTBAR_8):
		slot = 7
	elif event.is_action_pressed(InputActions.HOTBAR_9):
		slot = 8
	if slot >= 0:
		select_slot(slot)
		get_viewport().set_input_as_handled()


## A new day refills stamina.
##
## Unconditional, including at full: the cost of publishing on every day is one
## signal, and the alternative — publishing only when it changed — needs this to
## ask whether the player was already full, which is a question about the past
## that a restore cannot answer.
func _on_day_started(_day: int) -> void:
	if stamina != null:
		stamina.restore_full()


func _on_inventory_changed() -> void:
	EventBus.inventory_changed.emit()


func _on_gold_changed(amount: int) -> void:
	EventBus.currency_changed.emit(amount)


func _on_stamina_changed(current: int, maximum: int) -> void:
	EventBus.stamina_changed.emit(current, maximum)


func _on_hotbar_selection_changed(slot: int) -> void:
	EventBus.hotbar_selection_changed.emit(slot)
	hotbar_selection_changed.emit(slot)