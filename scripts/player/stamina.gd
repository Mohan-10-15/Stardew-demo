class_name Stamina
extends Resource
## How much work the player can still do before collapsing.
##
## A [Resource] of plain values, like [Inventory] and [Wallet]. [PlayerStateService]
## owns it and relays changes; this file never touches [EventBus], so it stays
## loadable from a `--script` run.
##
## Costs are not stored here — they live on the tool, in [member
## ItemDefinition.stamina_cost]. A player who switches from a scythe to a watering
## can must pay what the *can* costs, and a cost table kept here would be a second
## place to forget to add a tool.

## Emitted after any change to [member current].
##
## Not `changed`, because [Resource] declares that already. See `wallet.gd`.
signal stamina_changed(current: int, maximum: int)

## How much the player can spend in total.
@export var maximum: int = 100
## How much is left.
@export var current: int = 100


func _init(p_maximum: int = 100) -> void:
	maximum = maxi(p_maximum, 1)
	current = maximum


## Whether [param cost] can be paid right now.
func can_spend(cost: int) -> bool:
	return cost >= 0 and current >= cost


## Pays [param cost], if it can be paid.
##
## All-or-nothing, like [method Inventory.add] and [method Wallet.spend]. A
## partial charge would leave a hoe costing 2 to take the last 1 point of stamina
## and then swing for free, which reads as the game losing track of its own rules.
##
## Returns false and changes nothing when the player is too tired.
func spend(cost: int) -> bool:
	if cost <= 0:
		return true
	if not can_spend(cost):
		return false
	current -= cost
	stamina_changed.emit(current, maximum)
	return true


## Gives back [param amount], never past [member maximum].
func restore(amount: int) -> void:
	if amount <= 0:
		return
	var was := current
	current = mini(current + amount, maximum)
	if current != was:
		stamina_changed.emit(current, maximum)


## Refills to [member maximum]. This is what sleeping does.
func restore_full() -> void:
	if current == maximum:
		return
	current = maximum
	stamina_changed.emit(current, maximum)


## Whether there is nothing left to spend.
##
## `current <= 0` and not "cannot afford the next tool": the question here is whether
## the player is *out*, and an affordability check belongs at the swing, where the
## cost of the specific tool is known. A player with 1 point and a 2-point hoe is
## not out, and pretending otherwise would empty the bar for them instead of
## refusing one swing.
func is_exhausted() -> bool:
	return current <= 0


func to_dict() -> Dictionary:
	return {"maximum": maximum, "current": current}


func from_dict(data: Dictionary) -> void:
	maximum = maxi(int(data.get("maximum", 100)), 1)
	# Clamped on load: a save edited to hold more than the maximum would otherwise
	# make the player permanently unexhausted.
	current = clampi(int(data.get("current", maximum)), 0, maximum)
	stamina_changed.emit(current, maximum)


func copy() -> Stamina:
	var out := Stamina.new(maximum)
	out.current = current
	return out


func describe() -> String:
	return "%d/%d" % [current, maximum]