extends TestSuite
## Stamina, wallet, and shop trading.
##
## Group 13 — economy.
##
## Covers the three value-holding resources ([Stamina], [Wallet], [ShopDefinition]),
## the rules that move money and goods ([EconomyService]), and the world counter that
## exposes them. Every transaction asserts on both halves at once — what left the
## bag and what arrived in the wallet — because a trading bug that moves only one
## is a money printer or a silent loss, and checking the total alone passes both.

var _rig: Node = null


func is_async() -> bool:
	return true


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"a_new_stamina_pool_starts_full":
			return await _t_stamina_full()
		&"spending_stamina_reports_the_new_value":
			return await _t_stamina_spend()
		&"stamina_spend_is_all_or_nothing":
			return await _t_stamina_all_or_nothing()
		&"stamina_never_rises_past_its_maximum":
			return await _t_stamina_cap()
		&"a_save_round_trips_stamina":
			return await _t_stamina_save()
		&"a_new_wallet_starts_empty":
			return await _t_wallet_empty()
		&"a_wallet_refuses_to_go_negative":
			return await _t_wallet_no_negative()
		&"a_wallet_save_round_trips":
			return await _t_wallet_save()
		&"the_general_store_definition_loads":
			return await _t_shop_definition_loads()
		&"every_stocked_item_exists":
			return await _t_stock_items_exist()
		&"every_stocked_item_is_buyable":
			return await _t_stock_buyable()
		&"buying_debits_gold_and_credits_the_bag":
			return await _t_buy()
		&"buying_refuses_when_gold_is_short":
			return await _t_buy_too_poor()
		&"buying_refuses_an_item_the_shop_does_not_stock":
			return await _t_buy_unstocked()
		&"buying_refuses_a_crop_that_cannot_be_purchased":
			return await _t_buy_unpriced()
		&"a_failed_buy_leaves_gold_and_bag_untouched":
			return await _t_failed_buy_is_atomic()
		&"selling_credits_gold_and_removes_the_item":
			return await _t_sell()
		&"selling_refuses_when_the_shop_will_not_buy_it":
			return await _t_sell_refused()
		&"a_shop_will_not_buy_back_its_own_stock":
			return await _t_no_restocking()
		&"a_failed_sell_leaves_gold_and_bag_untouched":
			return await _t_failed_sell_is_atomic()
		&"a_tool_swing_refuses_when_stamina_is_short":
			return await _t_tool_exhaustion()
		&"a_refused_swing_changes_no_tiles":
			return await _t_exhaustion_leaves_tiles_alone()
		&"a_swing_that_changes_nothing_is_refunded":
			return await _t_no_op_swing_refunded()
		&"the_world_has_a_reachable_shop_counter":
			return await _t_shop_in_world()
		&"the_shop_counter_is_named_in_its_prompt":
			return await _t_shop_prompt()
		&"pressing_interact_at_the_counter_opens_it":
			return await _t_shop_interact()
		&"the_counter_trades_through_its_own_face":
			return await _t_shop_trade()
	return fail(case, "no case implementation for %s" % case)


func setup() -> void:
	_rig = null


func teardown() -> void:
	_reset_rig()


func get_cases() -> Array[StringName]:
	return [
		# --- stamina -----------------------------------------------------
		&"a_new_stamina_pool_starts_full",
		&"spending_stamina_reports_the_new_value",
		&"stamina_spend_is_all_or_nothing",
		&"stamina_never_rises_past_its_maximum",
		&"a_save_round_trips_stamina",
		# --- wallet ------------------------------------------------------
		&"a_new_wallet_starts_empty",
		&"a_wallet_refuses_to_go_negative",
		&"a_wallet_save_round_trips",
		# --- shop content ------------------------------------------------
		&"the_general_store_definition_loads",
		&"every_stocked_item_exists",
		&"every_stocked_item_is_buyable",
		# --- trading rules -----------------------------------------------
		&"buying_debits_gold_and_credits_the_bag",
		&"buying_refuses_when_gold_is_short",
		&"buying_refuses_an_item_the_shop_does_not_stock",
		&"buying_refuses_a_crop_that_cannot_be_purchased",
		&"a_failed_buy_leaves_gold_and_bag_untouched",
		&"selling_credits_gold_and_removes_the_item",
		&"selling_refuses_when_the_shop_will_not_buy_it",
		&"a_shop_will_not_buy_back_its_own_stock",
		&"a_failed_sell_leaves_gold_and_bag_untouched",
		# --- stamina gate on real tools ----------------------------------
		&"a_tool_swing_refuses_when_stamina_is_short",
		&"a_refused_swing_changes_no_tiles",
		&"a_swing_that_changes_nothing_is_refunded",
		# --- the counter in the world -------------------------------------
		&"the_world_has_a_reachable_shop_counter",
		&"the_shop_counter_is_named_in_its_prompt",
		&"pressing_interact_at_the_counter_opens_it",
		&"the_counter_trades_through_its_own_face",
	]


# --- Stamina ----------------------------------------------------------------


func _t_stamina_full() -> Dictionary:
	var c := &"a_new_stamina_pool_starts_full"
	var pool := Stamina.new(80)
	return check_equals(c, pool.describe(), "80/80")


func _t_stamina_spend() -> Dictionary:
	var c := &"spending_stamina_reports_the_new_value"
	var pool := Stamina.new(100)
	var seen: Array = []
	pool.stamina_changed.connect(func(cur: int, _max: int) -> void: seen.append(cur))
	pool.spend(30)
	if pool.current != 70:
		return fail(c, "after spending 30 the player had %d" % pool.current)
	# The signal is how the HUD bar avoids polling every frame.
	if seen != [70]:
		return fail(c, "stamina_changed reported %s" % str(seen))
	return succeeded(c)


func _t_stamina_all_or_nothing() -> Dictionary:
	var c := &"stamina_spend_is_all_or_nothing"
	var pool := Stamina.new(10)
	pool.spend(4)
	if pool.spend(50):
		return fail(c, "a 50-point spend succeeded against 6 points of stamina")
	if pool.current != 6:
		return fail(c, "the refused spend still took 4 points (now %d)" % pool.current)
	# A partial charge is the failure mode worth naming: it makes the tool look
	# cheaper as the player gets tired.
	return succeeded(c)


func _t_stamina_cap() -> Dictionary:
	var c := &"stamina_never_rises_past_its_maximum"
	var pool := Stamina.new(10)
	pool.restore(500)
	if pool.current != 10:
		return fail(c, "restoring 500 left %d" % pool.current)
	return succeeded(c)


func _t_stamina_save() -> Dictionary:
	var c := &"a_save_round_trips_stamina"
	var pool := Stamina.new(120)
	pool.spend(75)
	var clone := Stamina.new()
	clone.from_dict(pool.to_dict())
	return check_equals(c, clone.describe(), "45/120")


# --- Wallet -----------------------------------------------------------------


func _t_wallet_empty() -> Dictionary:
	var c := &"a_new_wallet_starts_empty"
	return check_equals(c, Wallet.new().gold, 0)


func _t_wallet_no_negative() -> Dictionary:
	var c := &"a_wallet_refuses_to_go_negative"
	var purse := Wallet.new()
	if purse.spend(10):
		return fail(c, "spent 10 from an empty wallet")
	purse.add(100)
	if not purse.spend(30):
		return fail(c, "could not spend 30 with 100 in hand")
	if purse.gold != 70:
		return fail(c, "after spending 30 the wallet held %d" % purse.gold)
	if purse.spend(500):
		return fail(c, "spent 500 with 70 in hand")
	return check_equals(c, purse.gold, 70)


func _t_wallet_save() -> Dictionary:
	var c := &"a_wallet_save_round_trips"
	var purse := Wallet.new()
	purse.add(1234)
	var clone := Wallet.new()
	clone.from_dict(purse.to_dict())
	return check_equals(c, clone.gold, 1234)


# --- Shop content -----------------------------------------------------------


func _t_shop_definition_loads() -> Dictionary:
	var c := &"the_general_store_definition_loads"
	var definition := ShopRegistry.get_shop(&"general_store")
	if definition == null:
		return fail(c, "ShopRegistry has no general_store")
	if definition.display_name.is_empty():
		return fail(c, "the definition has no display name")
	if definition.stock.is_empty():
		return fail(c, "the general store stocks nothing")
	return succeeded(c, "%s: %s" % [definition.display_name, definition.describe()])


func _t_stock_items_exist() -> Dictionary:
	var c := &"every_stocked_item_exists"
	var definition := ShopRegistry.get_shop(&"general_store")
	var missing := EconomyService.invalid_stock(definition)
	if not missing.is_empty():
		return fail(c, "stocked but undefined: %s" % ", ".join(missing))
	return succeeded(c)


func _t_stock_buyable() -> Dictionary:
	var c := &"every_stocked_item_is_buyable"
	var definition := ShopRegistry.get_shop(&"general_store")
	var listed := EconomyService.buyable_stock(definition)
	# Silent prices would otherwise pass every other test here: the counter opens,
	# the bag is reachable, and nothing can be bought.
	var unpriced: Array[String] = []
	for item_id: StringName in definition.stock:
		if not listed.has(item_id):
			unpriced.append(String(item_id))
	if not unpriced.is_empty():
		return fail(c, "stocked with no price: %s" % ", ".join(unpriced))
	return succeeded(c, "%d items, all priced" % listed.size())


# --- Trading ----------------------------------------------------------------


## A rig with a player state, an economy service and a seeded bag.
##
## Resets first, so each case gets its own wallet. Reusing the rig would leave the
## previous case's coins in it — which does not merely leak state, it makes the
## affordability cases pass for the wrong reason.
func _make_trader(coins: int = 1000) -> Dictionary:
	_reset_rig()
	_ensure_rig()
	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.get("wallet").add(coins)

	var economy_script: GDScript = load("res://scripts/economy/economy_service.gd")
	var economy: Node = economy_script.new()
	economy.name = "EconomyService"
	_rig.add_child(economy)
	await _step(2)
	return {"state": state, "economy": economy}


func _fail_reason(result: Dictionary) -> String:
	return "%s (%s)" % [result.get("reason", "?"), result.get("item_id", "?")]


func _t_buy() -> Dictionary:
	var c := &"buying_debits_gold_and_credits_the_bag"
	var made := await _make_trader(1000)
	var state: Node = made["state"]
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	var unit := ItemRegistry.buy_price_of(&"parsnip_seeds")
	var before_gold: int = int(state.get("wallet").gold)

	var result: Dictionary = economy.call("buy", definition, &"parsnip_seeds", 3)
	if not bool(result.get("ok", false)):
		return fail(c, "buy refused: %s" % _fail_reason(result))
	if int(result["total"]) != unit * 3:
		return fail(c, "charged %d for 3 at %d each" % [int(result["total"]), unit])
	if int(state.get("wallet").gold) != before_gold - unit * 3:
		return fail(c, "wallet went %d -> %d" % [before_gold, int(state.get("wallet").gold)])
	var held: int = state.get("inventory").count(&"parsnip_seeds")
	if held != 3:
		return fail(c, "bag holds %d seeds" % held)
	return succeeded(c, "3 seeds for %d" % unit)


func _t_buy_too_poor() -> Dictionary:
	var c := &"buying_refuses_when_gold_is_short"
	var made := await _make_trader(5)
	var state: Node = made["state"]
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	var unit := ItemRegistry.buy_price_of(&"parsnip_seeds")

	var result: Dictionary = economy.call("buy", definition, &"parsnip_seeds", 2)
	if bool(result.get("ok", false)):
		return fail(c, "bought 2 seeds for %d with only 5 gold" % (unit * 2))
	if String(result.get("reason", "")) != "poor":
		return fail(c, "refused for %s" % _fail_reason(result))
	if int(state.get("wallet").gold) != 5:
		return fail(c, "the refused buy still cost money")
	return succeeded(c)


func _t_buy_unstocked() -> Dictionary:
	var c := &"buying_refuses_an_item_the_shop_does_not_stock"
	var made := await _make_trader(5000)
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	var result: Dictionary = economy.call("buy", definition, &"potato", 1)
	if bool(result.get("ok", false)):
		return fail(c, "the shop sold a harvested crop")
	# On the specific reason, not merely on failure. "refused for some reason" is
	# satisfied by a crash, a null bag and a real rules check alike, and would pass
	# long after the rule it was written for stopped working.
	if String(result.get("reason", "")) != "not_stocked":
		return fail(c, "refused for %s" % _fail_reason(result))
	return succeeded(c)


func _t_buy_unpriced() -> Dictionary:
	var c := &"buying_refuses_a_crop_that_cannot_be_purchased"
	var made := await _make_trader(5000)
	var economy: Node = made["economy"]
	# A farm-defined shop stocking a crop: real content, zero purchase price.
	var definition := ShopDefinition.new()
	definition.id = &"test_farm_stall"
	definition.display_name = "Test Stall"
	definition.stock = [&"parsnip"]

	var result: Dictionary = economy.call("buy", definition, &"parsnip", 1)
	if bool(result.get("ok", false)):
		return fail(c, "sold a crop for nothing")
	if String(result.get("reason", "")) != "unpriced":
		return fail(c, "reason %s" % _fail_reason(result))
	return succeeded(c, "refused as unpriced")


func _t_failed_buy_is_atomic() -> Dictionary:
	var c := &"a_failed_buy_leaves_gold_and_bag_untouched"
	var made := await _make_trader(50)
	var state: Node = made["state"]
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	var before_gold: int = int(state.get("wallet").gold)
	var before_bag: Dictionary = state.get("inventory").to_dict()

	economy.call("buy", definition, &"potato", 5)
	economy.call("buy", definition, &"parsnip_seeds", 500)
	if int(state.get("wallet").gold) != before_gold:
		return fail(c, "wallet moved from %d to %d on refused buys"
			% [before_gold, int(state.get("wallet").gold)])
	if str(state.get("inventory").to_dict()) != str(before_bag):
		return fail(c, "the bag changed on a refused buy")
	return succeeded(c)


func _t_sell() -> Dictionary:
	var c := &"selling_credits_gold_and_removes_the_item"
	var made := await _make_trader(0)
	var state: Node = made["state"]
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	state.get("inventory").add(&"parsnip", 4)
	var unit := ItemRegistry.sell_price_of(&"parsnip")

	var result: Dictionary = economy.call("sell", definition, &"parsnip", 2)
	if not bool(result.get("ok", false)):
		return fail(c, "sell refused: %s" % _fail_reason(result))
	if int(state.get("wallet").gold) != unit * 2:
		return fail(c, "wallet holds %d, expected %d" % [int(state.get("wallet").gold), unit * 2])
	var left: int = state.get("inventory").count(&"parsnip")
	if left != 2:
		return fail(c, "bag holds %d parsnips after selling 2" % left)
	return succeeded(c, "2 parsnips for %d" % (unit * 2))


func _t_sell_refused() -> Dictionary:
	var c := &"selling_refuses_when_the_shop_will_not_buy_it"
	var made := await _make_trader(0)
	var state: Node = made["state"]
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	# Worthless by definition: no sell price anywhere.
	state.get("inventory").add(&"parsnip_seeds", 5)

	var result: Dictionary = economy.call("sell", definition, &"parsnip_seeds", 1)
	if bool(result.get("ok", false)):
		return fail(c, "the shop bought back a seed packet for nothing")
	var seeds_left: int = state.get("inventory").count(&"parsnip_seeds")
	if seeds_left != 5:
		return fail(c, "the refused sale still removed seeds (%d left)" % seeds_left)
	if int(state.get("wallet").gold) != 0:
		return fail(c, "the refused sale still paid")
	return succeeded(c)


func _t_no_restocking() -> Dictionary:
	var c := &"a_shop_will_not_buy_back_its_own_stock"
	var made := await _make_trader(0)
	var state: Node = made["state"]
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	state.get("inventory").add(&"parsnip_seeds", 3)

	var result: Dictionary = economy.call("sell", definition, &"parsnip_seeds", 1)
	if bool(result.get("ok", false)):
		return fail(c, "restocked the shop — buy seeds, sell seeds, print money")
	return succeeded(c, "refused: %s" % _fail_reason(result))


func _t_failed_sell_is_atomic() -> Dictionary:
	var c := &"a_failed_sell_leaves_gold_and_bag_untouched"
	var made := await _make_trader(40)
	var state: Node = made["state"]
	var economy: Node = made["economy"]
	var definition := ShopRegistry.get_shop(&"general_store")
	state.get("inventory").add(&"parsnip_seeds", 2)
	var before_gold: int = int(state.get("wallet").gold)

	economy.call("sell", definition, &"parsnip_seeds", 1)
	if int(state.get("wallet").gold) != before_gold:
		return fail(c, "gold moved from %d to %d on a refused sale"
			% [before_gold, int(state.get("wallet").gold)])
	var seeds_left: int = state.get("inventory").count(&"parsnip_seeds")
	if seeds_left != 2:
		return fail(c, "seeds left the bag on a refused sale (%d left)" % seeds_left)
	return succeeded(c)


# --- Stamina in the farming loop --------------------------------------------


func _t_tool_exhaustion() -> Dictionary:
	var c := &"a_tool_swing_refuses_when_stamina_is_short"
	var made := await _make_farmer()
	var service: Node = made["service"]
	var state: Node = made["state"]
	var grid: FarmGrid = made["grid"]
	var stamina: Stamina = state.get("stamina")
	stamina.current = 1
	var bar: Hotbar = state.get("hotbar")
	bar.select(0)  # the hoe
	var tile := grid.get_tile(Vector2i(0, 0))
	tile.till()

	var changed: int = service.call("use_tool", tile)
	if changed != 0:
		return fail(c, "an exhausted player changed %d tiles" % changed)
	if stamina.current != 1:
		return fail(c, "the refused swing still cost stamina")
	return succeeded(c)


func _t_exhaustion_leaves_tiles_alone() -> Dictionary:
	var c := &"a_refused_swing_changes_no_tiles"
	var made := await _make_farmer()
	var service: Node = made["service"]
	var state: Node = made["state"]
	var grid: FarmGrid = made["grid"]
	var tile := grid.get_tile(Vector2i(1, 1))
	var stamina: Stamina = state.get("stamina")
	stamina.current = 0
	var bar: Hotbar = state.get("hotbar")
	bar.select(0)

	# This is the regression this whole case exists for. The swing used to apply
	# the tool and *then* discover the cost was unaffordable, so a tired player
	# got free tilling — and, since the refusal was swallowed, no complaint.
	service.call("use_tool", tile)
	if tile.is_tilled:
		return fail(c, "the tile was tilled for free at zero stamina")
	return succeeded(c)


func _t_no_op_swing_refunded() -> Dictionary:
	var c := &"a_swing_that_changes_nothing_is_refunded"
	var made := await _make_farmer()
	var service: Node = made["service"]
	var state: Node = made["state"]
	var grid: FarmGrid = made["grid"]
	var bar: Hotbar = state.get("hotbar")
	bar.select(0)  # the hoe
	var tile := grid.get_tile(Vector2i(2, 2))
	tile.till()
	var stamina: Stamina = state.get("stamina")
	var before: int = stamina.current

	# Hoeing soil that is already tilled changes nothing, so it must cost nothing.
	var changed: int = service.call("use_tool", tile)
	if changed != 0:
		return fail(c, "the hoe reported %d changes on tilled soil" % changed)
	if stamina.current != before:
		return fail(c, "a no-op swing cost %d stamina" % [before - stamina.current])
	return succeeded(c)


# --- The counter in the world -----------------------------------------------


func _t_shop_in_world() -> Dictionary:
	var c := &"the_world_has_a_reachable_shop_counter"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build the world")
	var world: Node3D = built["world"]
	var counter := world.find_child("GeneralStore", true, false) as Node3D
	if counter == null:
		return fail(c, "the world has no GeneralStore")
	var economy: Node = (built["economy"])
	var definition: ShopDefinition = counter.get("shop")
	if definition == null:
		return fail(c, "the counter has no ShopDefinition")
	# The player has to be able to stand in front of it, not merely see it.
	var blocked := false
	var space := world.get_world_3d().direct_space_state
	for offset: float in [1.2, 1.8, 2.4]:
		var from := counter.global_position + Vector3(0, 1.0, offset)
		var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, 0.1, from.z))
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			blocked = true
			break
	if blocked:
		return fail(c, "the approach to the counter is obstructed")
	if economy == null:
		return fail(c, "the world was built with no economy service")
	return succeeded(c, "counter at %s" % counter.global_position)


func _t_shop_prompt() -> Dictionary:
	var c := &"the_shop_counter_is_named_in_its_prompt"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build the world")
	var world: Node3D = built["world"]
	var component := world.find_child("ShopInteractable", true, false) as Interactable
	if component == null:
		return fail(c, "the counter has no interaction component")
	var prompt := component.get_prompt(null)
	if prompt == "Interact":
		return fail(c, "the counter kept the default prompt")
	# The name has to be in the text, so the player can tell which shop they are at.
	if not prompt.contains("General Store"):
		return fail(c, "prompt %s does not name the shop" % prompt)
	return succeeded(c, "'%s'" % prompt)


## The real player, the real crosshair and the real `E` key on the real counter.
##
## Everything below this point so far has been a service call. This walks the
## actual player to the actual shop and presses the actual key, because a shop
## that trades correctly when handed a direct reference and cannot be *opened* is
## not a shop a player can reach.
func _t_shop_interact() -> Dictionary:
	var c := &"pressing_interact_at_the_counter_opens_it"
	var built := await _build_world_with_player()
	if built.is_empty():
		return fail(c, "could not build the scene")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var shop: Shop = built["shop"]
	if shop == null or probe == null:
		return fail(c, "shop=%s probe=%s" % [shop, probe])

	var opened: Array = []
	shop.opened.connect(func(counter: Shop, _actor: Node) -> void: opened.append(counter))

	# Stand in front of the counter and look at it. Aimed the same way the farming
	# suite aims: computed from the camera-to-target vector, not a guessed heading,
	# and pitched with the sign the player's camera actually uses.
	var aim: Vector3 = (built["component"] as Interactable).get_aim_point()
	player.global_position = Vector3(aim.x, 0.2, aim.z + 1.6)
	await _step(5)
	var camera := probe.get_camera()
	if camera == null:
		return fail(c, "the probe has no camera")
	var dir := (aim - camera.global_position).normalized()
	player.set_yaw(atan2(-dir.x, -dir.z))
	player.camera_rig.set_pitch(atan2(dir.y, Vector2(dir.x, dir.z).length()))
	await _step(4)
	probe.update_focus()
	await _step(2)
	if probe.get_focus() == null:
		return fail(c, "the crosshair did not focus the counter")

	Input.action_press(&"interact")
	await _step(3)
	Input.action_release(&"interact")
	await _step(2)

	if opened.is_empty():
		return fail(c, "E at the counter opened nothing")
	return succeeded(c, "counter focused and opened by the interact key")


## Trading through the [Shop] facade rather than [EconomyService] directly.
##
## The facade is what a future UI will call, and it is the layer that knows which
## counter is which. Exercising the service instead would leave the wrapper —
## the part a UI actually touches — completely untested.
func _t_shop_trade() -> Dictionary:
	var c := &"the_counter_trades_through_its_own_face"
	var built := await _build_world_with_player()
	if built.is_empty():
		return fail(c, "could not build the scene")
	var shop: Shop = built["shop"]
	var state: Node = built["state"]
	if shop == null:
		return fail(c, "no shop")
	var wallet: Wallet = state.get("wallet")
	wallet.set_gold(1000)
	var bag: Inventory = state.get("inventory")

	var result: Dictionary = shop.buy(&"parsnip_seeds", 2)
	if not bool(result.get("ok", false)):
		return fail(c, "buy through the counter refused: %s" % _fail_reason(result))
	if bag.count(&"parsnip_seeds") != 2:
		return fail(c, "bag holds %d seeds after the counter sold 2"
			% bag.count(&"parsnip_seeds"))
	var after_buy: int = wallet.gold

	# And back out again, so the loop closes.
	bag.add(&"parsnip", 3)
	var sold: Dictionary = shop.sell(&"parsnip", 1)
	if not bool(sold.get("ok", false)):
		return fail(c, "sell through the counter refused: %s" % _fail_reason(sold))
	if bag.count(&"parsnip") != 2:
		return fail(c, "bag holds %d parsnips after selling 1" % bag.count(&"parsnip"))
	if wallet.gold <= after_buy:
		return fail(c, "the sale paid nothing (gold %d -> %d)" % [after_buy, wallet.gold])
	return succeeded(c, "bought and sold through the counter")


## The real world, the real player, a real player state and a real economy
## service — everything the interact path needs, and the player with a live camera
## so the crosshair has something to aim.
func _build_world_with_player() -> Dictionary:
	_reset_rig()
	var packed := load("res://scenes/world/world.tscn") as PackedScene
	var player_packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null or player_packed == null:
		return {}
	_ensure_rig()
	var world := packed.instantiate()
	var player: PlayerController = player_packed.instantiate()
	_rig.add_child(world)
	_rig.add_child(player)

	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)

	var economy_script: GDScript = load("res://scripts/economy/economy_service.gd")
	var economy: Node = economy_script.new()
	economy.name = "EconomyService"
	_rig.add_child(economy)
	await _step(4)

	return {
		"world": world,
		"player": player,
		"probe": _find_first(player, "InteractionProbe"),
		"state": state,
		"economy": economy,
		"shop": world.find_child("GeneralStore", true, false),
		"component": world.find_child("ShopInteractable", true, false),
	}


## First descendant named [param node_name], breadth-first enough for our trees.
func _find_first(from: Node, node_name: String) -> Node:
	if from == null:
		return null
	for child in from.get_children():
		if child.name == node_name:
			return child
		var deeper := _find_first(child, node_name)
		if deeper != null:
			return deeper
	return null


# --- Fixtures ----------------------------------------------------------------


func _ensure_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		return
	_rig = Node3D.new()
	_rig.name = "EconomyTestRig"
	root().add_child(_rig)


func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _step(frames: int) -> void:
	# `tree`, not `get_tree()`: a TestSuite is a RefCounted and has none of its own.
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


## The real world, a real player state, and a real [EconomyService].
func _build_world() -> Dictionary:
	_reset_rig()
	var packed := load("res://scenes/world/world.tscn") as PackedScene
	if packed == null:
		return {}
	_ensure_rig()
	var world := packed.instantiate()
	_rig.add_child(world)

	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)

	var economy_script: GDScript = load("res://scripts/economy/economy_service.gd")
	var economy: Node = economy_script.new()
	economy.name = "EconomyService"
	_rig.add_child(economy)
	await _step(4)
	return {"world": world, "state": state, "economy": economy}


## A farm grid with a player state and a farm service, for the stamina cases.
##
## Loaded by path throughout, per the `class_name` cycle rule in `AGENTS.md`:
## naming `FarmService` directly would drag the farming stack into this file's
## compile.
func _make_farmer() -> Dictionary:
	_reset_rig()
	_ensure_rig()
	var grid_script: GDScript = load("res://scripts/farming/farm_grid.gd")
	var grid: FarmGrid = grid_script.new()
	grid.name = "FarmGrid"
	grid.columns = 4
	grid.rows = 4
	_rig.add_child(grid)

	var state_script: GDScript = load("res://scripts/player/player_state_service.gd")
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.call("grant_starter_loadout")

	var service_script: GDScript = load("res://scripts/farming/farm_service.gd")
	var service: Node = service_script.new()
	service.name = "FarmService"
	_rig.add_child(service)
	service.call("attach_grid", grid)
	await _step(3)
	return {"grid": grid, "state": state, "service": service}
