class_name EconomyService
extends Node
## The rules for buying and selling.
##
## ## Why this node and not a method on the shop
##
## Because there will be more than one shop and none of them should own a rule.
## The general store, a ranch counter and a shipping bin all obey the same
## ordering: check everything, then mutate. That ordering is the interesting part
## and it belongs in one place.
##
## ## The ordering, and why it is the whole design
##
## Nothing is mutated until every check has passed. This is not a style preference.
## [method FarmService.harvest] used to pull the crop first and re-plant it when
## the bag turned out to be full, which published a success event for a harvest
## that never happened and reset a regrowing crop's clock to zero. The same shape
## of bug is available here three times over — take the gold, then discover the bag
## is full; take the item, then discover it was not sellable — and the fix is the
## same each time: ask first, act once.
##
## ## What it does not do
##
## It does not own the purse, the bag, or the prices. [PlayerStateService] owns the
## first two, [ItemRegistry] and [CropRegistry] the third. This node is glue that
## asks each of them the right question and publishes the answer.

## Group this node registers under, so a [Shop] can find it.
##
## Duplicated as a literal in the lookup for the same `class_name` cycle reason
## documented on [FarmService].
const SERVICE_GROUP := &"economy_service"

## Emitted after money moves, on top of [signal EventBus.currency_changed], for a
## shop UI that wants a local nudge without listening to the whole bus.
signal trade_completed(kind: StringName, item_id: StringName, quantity: int, total: int)

var _state: PlayerStateService = null


func _ready() -> void:
	add_to_group(SERVICE_GROUP)


## The player's purse and bag, injected or found.
func state() -> PlayerStateService:
	if _state != null and is_instance_valid(_state):
		return _state
	_state = PlayerStateService.find()
	return _state


## Injects the owner. Used by `main.gd` and by tests that want an isolated purse.
func attach_state(value: PlayerStateService) -> void:
	_state = value


## What one of [param item_id] costs at [param shop].
##
## Zero means the item is not sold there, which is a real answer rather than a
## missing one: a parsnip has a sell price and no purchase price, because crops are
## not bought — their seeds are.
static func price_of(shop: ShopDefinition, item_id: StringName) -> int:
	return ItemRegistry.buy_price_of(item_id)


## What [param shop] pays for one of [param item_id], or -1 if it will not.
##
## Returns -1 rather than 0 for "will not buy", because 0 is a real price — an item
## can legitimately be worth nothing — and collapsing the two is how a shop ends up
## accepting a rock and paying nothing for it.
##
## The extra rule is that a shop will not buy back its own shelf. Seeds cost money
## and sell for nothing, so a general store that restocked its seeds would be a free
## infinite-money machine, and the loop is entirely mundane: buy seeds, sell seeds.
static func pays_for(shop: ShopDefinition, item_id: StringName) -> int:
	if shop == null:
		return ItemRegistry.sell_price_of(item_id)
	if not shop.buys_from_player:
		return -1
	if shop.stocks(item_id) and ItemRegistry.buy_price_of(item_id) > 0:
		return -1
	return ItemRegistry.sell_price_of(item_id)


## [param shop]'s stock, filtered to what can actually be bought.
##
## Filtered rather than returned raw because a stock entry with no price is a
## content mistake, and showing the player a row they cannot buy is worse than
## omitting it. [method invalid_stock] is what tells the author about it.
static func buyable_stock(shop: ShopDefinition) -> Array[StringName]:
	var out: Array[StringName] = []
	if shop == null:
		return out
	for item_id: StringName in shop.stock:
		if ItemRegistry.buy_price_of(item_id) > 0:
			out.append(item_id)
	return out


## Stock ids that name something no item definition claims.
##
## For a content test to assert is empty. Checks existence only — a shop stocking a
## real item at zero price is legal and just invisible, and
## [method buyable_stock] is the place that cares.
static func invalid_stock(shop: ShopDefinition) -> Array[StringName]:
	var out: Array[StringName] = []
	if shop == null:
		return out
	for item_id: StringName in shop.stock:
		if not ItemRegistry.has_item(item_id):
			out.append(item_id)
	return out


## Finds this service anywhere in the tree.
static func find() -> EconomyService:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search(scene_root)


static func _search(node: Node) -> EconomyService:
	if node is EconomyService:
		return node as EconomyService
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


## Buys [param quantity] of [param item_id] from [param shop].
##
## Checks, in this order and all before touching anything: the item is stocked,
## it has a price, the player can afford the lot, and the bag can take the lot.
## Then spends and adds, once.
##
## "The lot", not "some of it". A partial purchase would leave the player holding
## a quantity they did not ask for and did not agree to pay for.
##
## Returns a dictionary in the same shape [method SoilTile.harvest] uses, so
## callers have one convention for "did it work and why not":
## `{ok, reason, item_id, quantity, total}`.
func buy(shop: ShopDefinition, item_id: StringName, quantity: int = 1) -> Dictionary:
	var refusal := {
		"ok": false, "reason": "", "item_id": item_id,
		"quantity": quantity, "total": 0,
	}
	if shop == null:
		return _fail(&"buy", refusal, "no_shop")
	if quantity <= 0:
		return _fail(&"buy", refusal, "bad_quantity")
	if not shop.stocks(item_id):
		return _fail(&"buy", refusal, "not_stocked")

	var owner := state()
	if owner == null or owner.wallet == null or owner.inventory == null:
		return _fail(&"buy", refusal, "no_player_state")

	var unit := price_of(shop, item_id)
	if unit <= 0:
		return _fail(&"buy", refusal, "unpriced")

	var total := unit * quantity
	if not owner.wallet.can_afford(total):
		return _fail(&"buy", refusal, "poor")
	# Checked before spending, not after adding. `Inventory.add` is all-or-nothing
	# so the add cannot half-succeed, but discovering it afterwards would mean
	# taking the gold for an item that never arrived.
	if not owner.inventory.can_fit(item_id, quantity):
		return _fail(&"buy", refusal, "bag_full")

	if not owner.wallet.spend(total):
		# Unreachable while `can_afford` is honest; guarded because this is the
		# branch where being wrong destroys gold.
		return _fail(&"buy", refusal, "poor")
	var added := owner.inventory.add(item_id, quantity)
	if added <= 0:
		owner.wallet.add(total)
		return _fail(&"buy", refusal, "bag_full")

	EventBus.item_purchased.emit(item_id, added, total)
	trade_completed.emit(&"buy", item_id, added, total)
	return {
		"ok": true, "reason": "", "item_id": item_id,
		"quantity": added, "total": total,
	}


## Sells [param quantity] of [param item_id].
##
## [param shop] may be null, which means "any counter will do": a shipping bin pays
## the same rate as a shop. Passing the shop lets it refuse, through
## [method pays_for].
##
## Removes before paying, so a sale can never pay out for an item the player did
## not actually hand over. The reverse order would be a money printer.
func sell(shop: ShopDefinition, item_id: StringName, quantity: int = 1) -> Dictionary:
	var refusal := {
		"ok": false, "reason": "", "item_id": item_id,
		"quantity": quantity, "total": 0,
	}
	if quantity <= 0:
		return _fail(&"sell", refusal, "bad_quantity")

	var owner := state()
	if owner == null or owner.wallet == null or owner.inventory == null:
		return _fail(&"sell", refusal, "no_player_state")

	var unit := pays_for(shop, item_id)
	if unit < 0 or unit == 0:
		return _fail(&"sell", refusal, "not_sellable")

	var held := owner.inventory.count(item_id)
	if held <= 0:
		return _fail(&"sell", refusal, "no_item")
	# Clamped, and the clamp is silent on purpose. "Sell 9 of your 4 parsnips"
	# should sell the 4, not refuse: the alternative is the player counting their
	# own stack to work out a quantity the game already knows.
	var actual := mini(quantity, held)
	var taken := owner.inventory.remove(item_id, actual)
	if taken <= 0:
		return _fail(&"sell", refusal, "no_item")

	var total := unit * taken
	owner.wallet.add(total)
	EventBus.item_sold.emit(item_id, taken, total)
	trade_completed.emit(&"sell", item_id, taken, total)
	return {
		"ok": true, "reason": "", "item_id": item_id,
		"quantity": taken, "total": total,
	}


## What one of [param item_id] would fetch from [param shop], or -1.
##
## For a shop UI to label a row without attempting the trade. Kept beside the rules
## rather than in the UI so the label and the result cannot disagree.
func quote_sell(shop: ShopDefinition, item_id: StringName) -> int:
	return pays_for(shop, item_id)


## Whether [param shop] would sell [param quantity] of [param item_id] to this
## player right now. For a row's enabled state.
##
## A real check, not [method buy] with the result discarded — that would spend the
## player's gold and fill their bag every time a shop UI asked what a row cost.
## The conditions are therefore listed again here. The duplication is deliberate
## and the reason is in this comment: a predicate that has a side effect is not a
## predicate, and the alternative to restating four cheap comparisons is to have
## every UI open a transaction to display a price.
func can_buy(shop: ShopDefinition, item_id: StringName, quantity: int = 1) -> bool:
	if shop == null or quantity <= 0 or not shop.stocks(item_id):
		return false
	var owner := state()
	if owner == null or owner.wallet == null or owner.inventory == null:
		return false
	var unit := price_of(shop, item_id)
	if unit <= 0:
		return false
	return owner.wallet.can_afford(unit * quantity) \
		and owner.inventory.can_fit(item_id, quantity)


## Publishes a refusal and stamps the reason onto [param result].
##
## Always returns false, so callers can `return _fail(...)` from a branch without
## repeating the return.
func _fail(kind: StringName, result: Dictionary, reason: StringName) -> Dictionary:
	result["reason"] = reason
	EventBus.trade_failed.emit(
		kind, StringName(str(result["item_id"])), reason
	)
	Log.info("Economy", "%s refused: %s" % [kind, reason])
	return result