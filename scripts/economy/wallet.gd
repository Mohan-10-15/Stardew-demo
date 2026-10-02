class_name Wallet
extends Resource
## How much money the player is carrying.
##
## A [Resource] of plain values, like [Inventory]: it saves, compares and
## constructs without a scene, and it is unit-testable without a tree. The owner
## that publishes its changes to [EventBus] is [PlayerStateService], for the same
## reason [Inventory] has a local `contents_changed` — this file must stay
## loadable from a `--script` run, where autoloads are not identifiers yet.
##
## Deliberately one integer. Currency amounts, not a coin/bill breakdown: nothing
## in the design needs denominations, and a second unit would mean every caller
## has to decide how to split it.

## Emitted after any change to [member gold].
##
## Not named `changed` — [Resource] already declares that, and shadowing a native
## signal makes this file unparseable. See `inventory.gd`'s `contents_changed` for
## the longer version of the same trap.
signal gold_changed(amount: int)

## The player's money. Never negative; see [method spend].
@export var gold: int = 0


func _init(p_gold: int = 0) -> void:
	gold = maxi(p_gold, 0)


## Whether [param cost] is affordable right now.
func can_afford(cost: int) -> bool:
	return cost >= 0 and gold >= cost


## Takes [param cost] off the wallet, if it is there.
##
## All-or-nothing, matching [method Inventory.add]. Deducting what it can and
## returning the shortfall would let a shop hand over an item the player could
## only partly afford, and the "you still owe 40g" state has no representation
## anywhere in this design.
##
## Returns false and changes nothing when the cost is unaffordable. A zero or
## negative cost is treated as free and always succeeds, so a misconfigured item
## with no price reads as "free" instead of blocking the shop forever.
func spend(cost: int) -> bool:
	if cost <= 0:
		return true
	if not can_afford(cost):
		return false
	gold -= cost
	gold_changed.emit(gold)
	return true


## Adds [param amount] to the wallet and publishes it.
func add(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


## Sets the balance outright, as a load does.
##
## Publishes even when the value is unchanged, unlike [method add] and
## [method spend]. A save load is a wholesale replacement and the listener cannot
## tell it from a mutation, so it has to be told.
func set_gold(value: int) -> void:
	gold = maxi(value, 0)
	gold_changed.emit(gold)


func to_dict() -> Dictionary:
	return {"gold": gold}


func from_dict(data: Dictionary) -> void:
	set_gold(int(data.get("gold", 0)))


func copy() -> Wallet:
	return Wallet.new(gold)


func describe() -> String:
	return "%dg" % gold