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


## Hands the player a hoe, a watering can and some parsnip seeds.
##
## Lives here rather than on [FarmService] because these are the *player's*
## things, and the loadout is decided by who the player is, not by which
## subsystem happens to run first. The farm only cares that a seed packet exists.
func grant_starter_loadout() -> void:
	if inventory == null:
		return
	inventory.add(&"hoe", 1)
	inventory.add(&"watering_can", 1)
	inventory.add(&"parsnip_seeds", 15)
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