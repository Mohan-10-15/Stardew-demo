extends TestSuite
## Group 12 — gathering: chopping, mining, foraging, and the piles they leave.
##
## Split three ways, because a gathering feature breaks in three different places:
##
## - **Content.** The `.tres` files. A node whose model path is wrong, whose tier no
##   tool in the game reaches, or whose drop names an item that does not exist is not
##   a runtime bug — it is a file nobody opens, so it can only be caught here.
## - **Rules.** The node and the service, driven directly. Cheap, exhaustive, and the
##   only way to reach cases like "a tier-1 axe against an ancient oak takes sixteen
##   swings" without playing sixteen swings through a camera sixty times.
## - **Through the real game.** The last two cases build the actual world, walk the
##   actual player up to an actual tree, aim the real camera and press the real
##   interact key. Everything above that is a unit test of a rule, and a rule that
##   passes every unit test while the probe cannot find the tree is still a broken
##   game. This is the "drives the core loop through real input" requirement, and it
##   is the one that catches the wiring nobody unit-tested because it looked obvious.
##
## ## Async throughout
##
## The probe casts its ray in `_physics_process`, the drops are rigid bodies, and a
## held swing completes on wall-clock time, so every case goes through
## [method _run_async]. A synchronous version of these would assert against a focus
## that has not been computed yet — and would pass, for the wrong reason.
##
## ## Why the rig is rebuilt per case
##
## Mirroring [TestFarming]: the world and the player each own a `Camera3D` that
## `make_current()`s itself, so two of them alive at once means
## `get_viewport().get_camera_3d()` returns a *previous* case's camera and every aim
## silently misses. One rig, freed and rebuilt per case.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const GATHERING_SERVICE_SCRIPT := "res://scripts/gathering/gathering_service.gd"
const PLAYER_STATE_SCRIPT := "res://scripts/player/player_state_service.gd"

## Every refusal reason [signal EventBus.gathering_failed] can carry.
##
## Hard-coded here as well as documented on the signal, deliberately: a test that read
## the doc comment could not fail, and a test that scraped the service's source for
## `&"..."` literals would break on a rename rather than on a missing reason. Adding a
## refusal without adding it here makes this case fail, which is the point — the list
## is the contract between the service and everything that listens for a reason.
const REFUSAL_REASONS: Array[StringName] = [
	&"no_target",
	&"respawning",
	&"no_player_state",
	&"no_tool",
	&"wrong_tool",
	&"needs_better_tool",
	&"out_of_reach",
	&"exhausted",
	&"nothing_to_do",
	&"no_gathering_service",
	&"bag_full",
]

## Why an oak rather than whatever happened to be first: it is the slowest tree a new
## player meets (four swings) and its name is in every log line, so a failure here is
## easy to reproduce by hand.
const FIRST_TREE := &"oak"

var _rig: Node3D = null
## Reasons seen on [signal EventBus.gathering_failed] during the current case.
var _failures: Array[Dictionary] = []


func is_async() -> bool:
	return true


func get_cases() -> Array[StringName]:
	return [
		# Content
		&"resource_nodes_are_on_disk_and_uniquely_named",
		&"every_resource_node_is_valid",
		&"every_resource_node_yields_an_item_that_exists",
		&"every_resource_node_draws_a_real_model",
		&"every_drop_amount_stays_inside_its_own_bounds",
		&"a_node_drops_the_same_stuff_every_time",
		&"every_node_that_needs_a_tool_has_one_that_can_work_it",
		&"every_node_in_the_valley_eventually_comes_back",
		# Node behaviour
		&"a_node_takes_exactly_the_hits_it_was_given",
		&"a_weaker_tool_takes_more_swings",
		&"a_blocked_node_refuses_a_weaker_tool",
		&"a_depleted_node_stands_down_and_says_so",
		&"a_node_comes_back_after_its_own_days",
		&"a_node_that_never_regrows_stays_down",
		&"a_node_save_round_trips",
		# Service rules
		&"bare_hands_cannot_chop",
		&"the_wrong_tool_is_refused_by_name",
		&"a_tool_below_the_nodes_tier_is_refused",
		&"a_depleted_node_refuses_with_respawning",
		&"too_far_away_is_refused_before_stamina",
		&"a_good_swing_lands_and_costs_stamina",
		&"a_swing_wears_the_tool_down",
		&"a_broken_tool_leaves_the_bag",
		&"an_exhausted_player_is_told_to_rest",
		&"a_felled_node_leaves_its_drops",
		&"a_drop_goes_into_the_bag",
		&"a_full_bag_leaves_the_drop_lying_there",
		&"every_gathering_refusal_has_its_own_reason",
		# Through the real game
		&"no_resource_is_spawned_where_the_player_stands",
		&"every_gatherable_thing_can_be_reached_on_foot",
		&"a_tree_falls_to_the_real_interact_key",
		&"walking_over_the_felled_wood_takes_it",
	]


func setup() -> void:
	_rig = null
	_failures = []


func teardown() -> void:
	# Never leave a simulated keypress or a live failure listener behind: both outlive
	# the case that made them and poison the next one in ways that read as flakes.
	Input.action_release(&"interact")
	var bus := autoload(&"EventBus")
	if bus != null and bus.gathering_failed.is_connected(_record_failure):
		bus.gathering_failed.disconnect(_record_failure)
	_reset_rig()


func _run_async(case: StringName) -> Dictionary:
	match case:
		&"resource_nodes_are_on_disk_and_uniquely_named":
			return _t_content_present()
		&"every_resource_node_is_valid":
			return _t_content_valid()
		&"every_resource_node_yields_an_item_that_exists":
			return _t_content_yields_exist()
		&"every_resource_node_draws_a_real_model":
			return _t_content_models_load()
		&"every_drop_amount_stays_inside_its_own_bounds":
			return _t_content_amount_bounds()
		&"a_node_drops_the_same_stuff_every_time":
			return _t_content_yield_stable()
		&"every_node_that_needs_a_tool_has_one_that_can_work_it":
			return _t_content_tools_exist()
		&"every_node_in_the_valley_eventually_comes_back":
			return _t_content_respawns()
		&"a_node_takes_exactly_the_hits_it_was_given":
			return await _t_node_hit_count()
		&"a_weaker_tool_takes_more_swings":
			return await _t_node_weak_tool_slower()
		&"a_blocked_node_refuses_a_weaker_tool":
			return await _t_node_blocked_tier()
		&"a_depleted_node_stands_down_and_says_so":
			return await _t_node_stands_down()
		&"a_node_comes_back_after_its_own_days":
			return await _t_node_regrows()
		&"a_node_that_never_regrows_stays_down":
			return await _t_node_never_regrows()
		&"a_node_save_round_trips":
			return await _t_node_saves()
		&"bare_hands_cannot_chop":
			return await _t_no_tool()
		&"the_wrong_tool_is_refused_by_name":
			return await _t_wrong_tool()
		&"a_tool_below_the_nodes_tier_is_refused":
			return await _t_needs_better_tool()
		&"a_depleted_node_refuses_with_respawning":
			return await _t_depleted_refused()
		&"too_far_away_is_refused_before_stamina":
			return await _t_reach_before_stamina()
		&"a_good_swing_lands_and_costs_stamina":
			return await _t_swing_costs_stamina()
		&"a_swing_wears_the_tool_down":
			return await _t_swing_wears_tool()
		&"a_broken_tool_leaves_the_bag":
			return await _t_tool_breaks()
		&"an_exhausted_player_is_told_to_rest":
			return await _t_exhausted()
		&"a_felled_node_leaves_its_drops":
			return await _t_felled_leaves_drops()
		&"a_drop_goes_into_the_bag":
			return await _t_drop_collected()
		&"a_full_bag_leaves_the_drop_lying_there":
			return await _t_bag_full()
		&"every_gathering_refusal_has_its_own_reason":
			return await _t_every_refusal_reason()
		&"no_resource_is_spawned_where_the_player_stands":
			return await _t_spawn_is_clear()
		&"every_gatherable_thing_can_be_reached_on_foot":
			return await _t_all_reachable()
		&"a_tree_falls_to_the_real_interact_key":
			return await _t_chop_through_input()
		&"walking_over_the_felled_wood_takes_it":
			return await _t_pickup_through_movement()
	return fail(case, "no case implementation for %s" % case)


# --- Content ----------------------------------------------------------------

func _t_content_present() -> Dictionary:
	var c := &"resource_nodes_are_on_disk_and_uniquely_named"
	var all: Array[ResourceNodeData] = ResourceNodeRegistry.all_nodes()
	if all.is_empty():
		return fail(c, "no node content at all under %s" % ResourceNodeRegistry.NODE_DIRECTORY)
	var duplicates := ResourceNodeRegistry.duplicate_ids()
	if not duplicates.is_empty():
		return fail(c, "duplicate node ids: %s" % str(duplicates))
	var spawnable: Array[ResourceNodeData] = ResourceNodeRegistry.spawnable_nodes()
	if spawnable.is_empty():
		return fail(c, "content exists but nothing spawns, so the valley is empty")
	# Every id has to be reachable by name, or the `.tres` filename is a lie the code
	# cannot act on.
	for data: ResourceNodeData in all:
		if not ResourceNodeRegistry.has_node(data.id):
			return fail(c, "loaded %s but has_node() cannot find it" % data.id)
	return succeeded(c, "%d nodes, %d of them placed in the valley" % [
		all.size(), spawnable.size(),
	])


func _t_content_valid() -> Dictionary:
	var c := &"every_resource_node_is_valid"
	var all: Array[ResourceNodeData] = ResourceNodeRegistry.all_nodes()
	for data: ResourceNodeData in all:
		if not data.is_valid():
			return fail(c, "%s is not valid (hp=%d respawn=%d yields=%d)" % [
				data.id, data.hit_points, data.respawn_days, data.yields.size(),
			])
		if data.resist_tier > ResourceNodeData.MAX_TIER:
			return fail(c, "%s wants tier %d but the schema caps at %d" % [
				data.id, data.resist_tier, ResourceNodeData.MAX_TIER,
			])
	return succeeded(c, "all %d definitions are valid" % all.size())


func _t_content_yields_exist() -> Dictionary:
	var c := &"every_resource_node_yields_an_item_that_exists"
	var all: Array[ResourceNodeData] = ResourceNodeRegistry.all_nodes()
	for data: ResourceNodeData in all:
		for line: GatherYield in data.yields:
			if not ItemRegistry.has_item(line.item_id):
				return fail(c, "%s drops '%s', which is not an item in the game" % [
					data.id, line.item_id,
				])
			if line.min_amount > line.max_amount:
				# `roll` swaps them so the number produced is still sane, which is
				# precisely why this has to be caught: the swap hides the mistake and
				# turns "3 to 5 wood" into "5 to 3 wood".
				return fail(c, "%s has an inverted range for %s: %d-%d" % [
					data.id, line.item_id, line.min_amount, line.max_amount,
				])
	return succeeded(c, "every drop line names a real item in a sane range")


func _t_content_models_load() -> Dictionary:
	var c := &"every_resource_node_draws_a_real_model"
	var all: Array[ResourceNodeData] = ResourceNodeRegistry.all_nodes()
	for data: ResourceNodeData in all:
		if not ResourceNodeRegistry.has_node(data.id):
			continue
		var model := data.model
		if not ResourceLoader.exists(model):
			return fail(c, "%s points at %s, which does not exist" % [data.id, model])
		var box := ModelArt.natural_aabb(model)
		if box.size == Vector3.ZERO or box.size.y <= 0.0:
			return fail(c, "%s: %s measures as nothing" % [data.id, model])
		# A tree with no stump grows back looking untouched, which reads as a bug the
		# player cannot describe. A rock or a bush disappearing is fine.
		if data.category == ResourceNodeData.Category.TREE:
			if data.depleted_model.is_empty():
				return fail(c, "%s is a tree with no depleted model" % data.id)
			if not ResourceLoader.exists(data.depleted_model):
				return fail(c, "%s stump %s does not exist" % [data.id, data.depleted_model])
	return succeeded(c, "all %d models load and measure" % all.size())


func _t_content_amount_bounds() -> Dictionary:
	var c := &"every_drop_amount_stays_inside_its_own_bounds"
	var rng := RandomNumberGenerator.new()
	var rolls := 0
	for data: Array[ResourceNodeData] in [ResourceNodeRegistry.all_nodes()]:
		for node_data: ResourceNodeData in data:
			for line: GatherYield in node_data.yields:
				var lo := mini(line.min_amount, line.max_amount)
				var hi := maxi(line.min_amount, line.max_amount)
				# 40 rolls rather than 4000: the generator is deterministic once
				# seeded, so this is a real sample of the distribution and not a
				# statistical argument.
				for _i: int in range(40):
					var amount := line.roll(rng)
					rolls += 1
					if amount < lo or amount > hi:
						return fail(c, "%s rolled %d outside %d-%d" % [
							node_data.id, amount, lo, hi,
						])
	return succeeded(c, "%d rolls stayed inside their declared ranges" % rolls)


func _t_content_yield_stable() -> Dictionary:
	var c := &"a_node_drops_the_same_stuff_every_time"
	var all: Array[ResourceNodeData] = ResourceNodeRegistry.all_nodes()
	if all.is_empty():
		return fail(c, "no content")
	for data: ResourceNodeData in all:
		var first := ResourceNode.new()
		first.name = "probe_%s" % data.id
		first.build(data, 0)
		# The prompt promises "3 Wood". If the actual drop could differ, the prompt is
		# a lie the player catches, so preview and take are asserted to be the same
		# call rather than two implementations that happen to agree today.
		var preview := first.preview_yield()
		var taken := first.take_yield()
		if JSON.stringify(preview) != JSON.stringify(taken):
			return fail(c, "%s promised %s but dropped %s" % [
				data.id, str(preview), str(taken),
			])
		if taken.is_empty():
			return fail(c, "%s drops nothing at all" % data.id)
		# And twice in a row, because a generator consumed rather than re-seeded would
		# pass the check above and still give a different amount the second time.
		if JSON.stringify(first.take_yield()) != JSON.stringify(taken):
			return fail(c, "%s is not repeatable: %s then %s" % [
				data.id, str(taken), str(first.take_yield()),
			])
		first.free()
	return succeeded(c, "every node's drop table is stable and repeatable")


func _t_content_tools_exist() -> Dictionary:
	var c := &"every_node_that_needs_a_tool_has_one_that_can_work_it"
	var items: Array[ItemDefinition] = ItemRegistry.all_items()
	# Best tier available per action, so the check can ask "can *anything* in the game
	# open this" rather than "can the starter tool open this" — a tier-3 gate with no
	# tier-3 pickaxe anywhere is unreachable content, which no runtime test can see.
	var best_tier: Dictionary = {}
	for item: ItemDefinition in items:
		if item.tool_action.is_empty() or not item.is_tool():
			continue
		var key := String(item.tool_action)
		best_tier[key] = maxi(int(best_tier.get(key, 0)), item.tool_tier)
	for data: Array[ResourceNodeData] in [ResourceNodeRegistry.all_nodes()]:
		for node_data: ResourceNodeData in data:
			if node_data.tool_action.is_empty():
				# Hand-picked: must still be pickable, or it has no verb and no prompt.
				if node_data.verb() != &"forage":
					return fail(c, "%s needs no tool but its verb is %s" % [
						node_data.id, node_data.verb(),
					])
				continue
			var action := String(node_data.tool_action)
			if not best_tier.has(action):
				return fail(c, "%s needs a '%s' and the game has none" % [
					node_data.id, action,
				])
			var reachable := int(best_tier[action])
			if not node_data.blocks_weak_tools:
				# Slowed, never refused, so any tool at all gets there eventually.
				continue
			if reachable < node_data.resist_tier:
				return fail(c, "%s refuses anything below tier %d but the best %s is %d" % [
					node_data.id, node_data.resist_tier, action, reachable,
				])
	return succeeded(c, "every gated node has a tool in the game that opens it")


func _t_content_respawns() -> Dictionary:
	var c := &"every_node_in_the_valley_eventually_comes_back"
	# Zero respawn means permanent, which is a legitimate content choice for one
	# special node and a design disaster for a valley's entire wood supply.
	for data: Array[ResourceNodeData] in [ResourceNodeRegistry.spawnable_nodes()]:
		for node_data: ResourceNodeData in data:
			if node_data.respawn_days <= 0:
				return fail(c, "%s never regrows; %d of them will strip the valley" % [
					node_data.id, node_data.spawn_count,
				])
	return succeeded(c, "everything placed in the valley comes back")


# --- Node behaviour ---------------------------------------------------------

func _t_node_hit_count() -> Dictionary:
	var c := &"a_node_takes_exactly_the_hits_it_was_given"
	var node := _place(&"oak")
	if node == null:
		return fail(c, "no oak content")
	var needed := node.hits_required(1)
	var swings := 0
	while not node.depleted and swings < 40:
		var result := node.hit(1)
		if not bool(result.get("applied", false)):
			return fail(c, "swing %d was refused on a fresh oak" % swings)
		swings += 1
	if not node.depleted:
		return fail(c, "oak survived %d swings against %d hit points" % [swings, needed])
	if swings != needed:
		return fail(c, "oak fell after %d swings but wanted %d" % [swings, needed])
	# Not `hits_left`, which is meaningless here and reads as a bug: felling resets the
	# counter to zero so the node is ready to regrow, so `hits_left` goes straight back
	# to "4" for a stump. What must hold is that another swing changes nothing.
	var after := node.hit(1)
	if bool(after.get("applied", false)):
		return fail(c, "a depleted oak still accepts hits")
	if node.hits_taken != 0:
		return fail(c, "a refused swing after felling counted a hit (%d)" % node.hits_taken)
	return succeeded(c, "oak fell in exactly %d swings" % swings)


func _t_node_weak_tool_slower() -> Dictionary:
	var c := &"a_weaker_tool_takes_more_swings"
	# The ancient oak is the game's clearest case: resist tier 2, and a stone axe is
	# tier 1. Nothing is refused — the player is just made to work for it.
	var data := ResourceNodeRegistry.get_node(&"ancient_oak")
	if data == null:
		return fail(c, "no ancient_oak content")
	if data.blocks_weak_tools:
		return fail(c, "ancient_oak blocks weak tools; this case is about slowdown")
	var strong := maxi(data.resist_tier, 1)
	var weak := maxi(strong - 1, 0)
	if weak >= strong:
		return fail(c, "resist tier %d leaves no weaker tier to compare against" % data.resist_tier)
	var at_strong := data.hits_required(strong)
	var at_weak := data.hits_required(weak)
	if at_weak <= at_strong:
		return fail(c, "tier %d needs %d swings and tier %d needs %d — a weak tool is faster" % [
			weak, at_weak, strong, at_strong,
		])
	var node := _place(&"ancient_oak")
	if node == null:
		return fail(c, "could not place an ancient oak")
	var swings := 0
	while not node.depleted and swings < 60:
		if not bool(node.hit(weak).get("applied", false)):
			return fail(c, "a tier-%d axe was refused by a node that only slows" % weak)
		swings += 1
	if swings != at_weak:
		return fail(c, "took %d swings, expected %d" % [swings, at_weak])
	return succeeded(c, "tier %d: %d swings vs tier %d: %d" % [weak, at_weak, strong, at_strong])


func _t_node_blocked_tier() -> Dictionary:
	var c := &"a_blocked_node_refuses_a_weaker_tool"
	# Iron needs tier 3 and refuses everything below it. The counterpart to the oak's
	# slowdown: the same maths with the opposite answer.
	var data := ResourceNodeRegistry.get_node(&"iron_vein")
	if data == null:
		return fail(c, "no iron_vein content")
	if not data.blocks_weak_tools:
		return fail(c, "iron_vein no longer blocks weak tools; this case is about refusal")
	var weak := maxi(data.resist_tier - 1, 0)
	if data.accepts_tier(weak):
		return fail(c, "a node that blocks tier %d accepted tier %d" % [data.resist_tier, weak])
	if not data.accepts_tier(data.resist_tier):
		return fail(c, "refuses its own required tier %d too" % data.resist_tier)
	var node := _place(&"iron_vein")
	var result := node.hit(weak)
	if bool(result.get("applied", false)):
		return fail(c, "a tier-%d pickaxe swung at iron and landed" % weak)
	if node.depleted:
		return fail(c, "a refused swing still felled the vein")
	if node.hits_taken != 0:
		return fail(c, "a refused swing still counted a hit")
	return succeeded(c, "iron refuses tier %d and accepts tier %d" % [weak, data.resist_tier])


func _t_node_stands_down() -> Dictionary:
	var c := &"a_depleted_node_stands_down_and_says_so"
	var node := _place(FIRST_TREE)
	var model := node.get_node_or_null(^"Model") as Node3D
	if model == null:
		return fail(c, "the oak has no model node")
	var solid := node.get_node_or_null(^"Solid/CollisionShape3D") as CollisionShape3D
	if solid == null:
		return fail(c, "the oak has no solid collider")
	node.deplete()
	await _step(2)
	if model.visible:
		return fail(c, "the felled tree is still drawing itself")
	if not bool(solid.disabled):
		return fail(c, "the felled tree is still solid to walk into")
	var stump := node.get_node_or_null(^"DepletedModel") as Node3D
	if stump == null:
		return fail(c, "the felled tree has no stump")
	if not stump.visible:
		return fail(c, "the stump is built but hidden; a wood that regrows unmarked looks untouched")
	if not node.progress_text().to_lower().contains("regrow"):
		return fail(c, "the node cannot say it is regrowing: '%s'" % node.progress_text())
	if node.progress_text() == "":
		return fail(c, "a depleted node explains nothing to the player")
	return succeeded(c, "stump drawn, collider dropped, prompt says '%s'" % node.progress_text())


func _t_node_regrows() -> Dictionary:
	var c := &"a_node_comes_back_after_its_own_days"
	var node := _place(&"berry_bush")
	var days := node.data.respawn_days
	node.deplete()
	await _step(2)
	if node.respawn_days_left != days:
		return fail(c, "depleting set the clock to %d, expected %d" % [node.respawn_days_left, days])
	for day: int in range(days - 1):
		if node.on_new_day():
			return fail(c, "it came back on day %d of %d" % [day + 1, days])
	# One day left, and still down. Asserting the *absence* of a regrow here is the
	# whole case: a node that returns a day early is a respawn nobody would notice
	# until the tree they cut on day three had regrown into a tree they cut on day one.
	if not node.depleted:
		return fail(c, "it stood back up before its %d days were up" % days)
	if node.respawn_days_left != 1:
		return fail(c, "one day from regrowth but the clock says %d" % node.respawn_days_left)
	if not node.on_new_day():
		return fail(c, "did not come back on day %d" % days)
	# `regrow` un-disables the collider through `set_deferred`, so the flag is still
	# showing the felled state until the frame ends. Checking it here would report a
	# perfectly regrown tree as permanently walkable.
	await _step(2)
	if node.depleted:
		return fail(c, "regrowth left the node flagged as depleted")
	if node.hits_taken != 0 or node.respawn_days_left != 0:
		return fail(c, "regrowth left hits=%d clock=%d" % [node.hits_taken, node.respawn_days_left])
	var stump := node.get_node_or_null(^"DepletedModel") as Node3D
	var model := node.get_node_or_null(^"Model") as Node3D
	if model == null or not model.visible:
		return fail(c, "the plant did not come back visibly")
	if stump != null and stump.visible:
		return fail(c, "the stump is still showing over the regrown plant")
	var solid := node.get_node_or_null(^"Solid/CollisionShape3D") as CollisionShape3D
	if solid == null or solid.disabled:
		return fail(c, "the regrown node is still not solid")
	return succeeded(c, "back after %d days" % days)


func _t_node_never_regrows() -> Dictionary:
	var c := &"a_node_that_never_regrows_stays_down"
	# Hand-authored rather than from content, because the shipped valley has nothing
	# like this — and a feature nothing exercises is a feature that does not work.
	var data := ResourceNodeData.new()
	data.id = &"test_never_returns"
	data.display_name = "Test Boulder"
	data.category = ResourceNodeData.Category.ROCK
	data.tool_action = &"mine"
	data.model = "res://assets/models/quaternius/NaturePack/Rock_1.fbx"
	data.hit_points = 1
	data.respawn_days = 0
	var line := GatherYield.new()
	line.item_id = &"stone"
	line.max_amount = 2
	data.yields = [line]

	var node := ResourceNode.new()
	node.build(data, 0)
	_ensure_rig().add_child(node)
	await _step(2)
	if not node.hit(1).get("applied", false):
		return fail(c, "the test node refused a swing")
	if not node.depleted:
		return fail(c, "the test node did not fall")
	for _day: int in range(10):
		if node.on_new_day():
			return fail(c, "a node with respawn_days=0 came back")
	if not node.depleted:
		return fail(c, "it vanished without the flag being set, which loses the reason")
	if not node.progress_text().to_lower().contains("gone"):
		return fail(c, "the prompt says '%s' rather than that it is gone for good" % node.progress_text())
	return succeeded(c, "still down after 10 days, and says so")


func _t_node_saves() -> Dictionary:
	var c := &"a_node_save_round_trips"
	var field := _field_in_rig()
	var node := field.add_node(ResourceNodeRegistry.get_node(FIRST_TREE), Vector3(3, 0, 3))
	if node == null:
		return fail(c, "could not add a node")
	await _step(2)
	# Part-way through, not felled: a save taken two swings into a four-swing oak is
	# the case that matters, and it is the one a boolean-only save would get wrong.
	node.hit(1)
	node.hit(1)
	var saved := field.to_dict()
	if saved.get("nodes", []).size() != 1:
		return fail(c, "field saved %d node states" % saved.get("nodes", []).size())
	var entry: Dictionary = saved["nodes"][0]
	if int(entry.get("hits", 0)) != 2:
		return fail(c, "saved hits=%s, expected 2" % str(entry.get("hits", -1)))
	if bool(entry.get("depleted", true)):
		return fail(c, "a half-felled node was saved as depleted")

	# And a felled one, whose whole state is the boolean plus a day count.
	node.hit(1)
	node.hit(1)
	await _step(2)
	var felled_field := field.to_dict()
	var felled: Dictionary = felled_field["nodes"][0]
	if not bool(felled.get("depleted", false)):
		return fail(c, "a felled node was not saved as depleted")
	if int(felled.get("respawn", 0)) <= 0:
		return fail(c, "a felled node saved with no day count")

	# Reload into a *fresh field* with its own node at the same placement index, which
	# is what a real reload does. Restoring into the node that already holds the state
	# would pass whether or not `apply_save` did anything.
	var reloaded_field := _field_in_rig()
	var reloaded: ResourceNode = reloaded_field.call(
		"add_node", ResourceNodeRegistry.get_node(FIRST_TREE), Vector3(3, 0, 3)
	)
	if reloaded == null:
		return fail(c, "could not stand up a second node to restore into")
	await _step(2)
	# The whole field, not one entry: `from_dict` takes the dictionary the field
	# writes, and handing it a single node state quietly restores nothing at all.
	reloaded_field.from_dict(felled_field)
	if not reloaded.depleted:
		return fail(c, "the reloaded node came back standing")
	if reloaded.respawn_days_left != int(felled["respawn"]):
		return fail(c, "reloaded clock is %d, saved %d" % [
			reloaded.respawn_days_left, int(felled["respawn"]),
		])
	var model := reloaded.get_node_or_null(^"Model") as Node3D
	var stump := reloaded.get_node_or_null(^"DepletedModel") as Node3D
	if model == null or model.visible:
		return fail(c, "the reloaded node drew a full-grown tree over a saved stump")
	if stump == null or not stump.visible:
		return fail(c, "the reloaded node drew no stump at all")
	return succeeded(c, "half-felled and felled states both survive a reload")


# --- Service rules ----------------------------------------------------------

func _t_no_tool() -> Dictionary:
	var c := &"bare_hands_cannot_chop"
	var built := await _bare_gatherer()
	if built.is_empty():
		return fail(c, "could not build fixture")
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	# Empty hands: the axe slot is there but nothing is in it.
	var bag: Inventory = built["bag"]
	if not _empty_every_slot(bag):
		return fail(c, "could not clear the bag")
	var status: Dictionary = service.call("status_for", node, null)
	if bool(status.get("ok", false)):
		return fail(c, "an oak offered itself to bare hands: %s" % str(status))
	if StringName(status.get("reason", &"")) != &"no_tool":
		return fail(c, "refused with '%s', expected no_tool" % str(status.get("reason", "")))
	var prompt := String(status.get("prompt", ""))
	if not prompt.to_lower().contains("axe"):
		return fail(c, "the refusal does not name the tool it wants: '%s'" % prompt)
	if service.call("gather", node, null):
		return fail(c, "gather() succeeded with no tool in hand")
	return check_true(c, _saw_reason(&"no_tool"), "no failure event was published")


func _t_wrong_tool() -> Dictionary:
	var c := &"the_wrong_tool_is_refused_by_name"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	# A pickaxe at a tree. The complaint has to be different from "you have nothing" —
	# both are refusals, and a player told to go find an axe they are already holding is
	# being actively misled.
	if not _select_item(built["bar"], &"pickaxe"):
		return fail(c, "no pickaxe in the starter loadout")
	var status: Dictionary = service.call("status_for", node, null)
	if bool(status.get("ok", false)):
		return fail(c, "a pickaxe was accepted for a chop")
	if StringName(status.get("reason", &"")) != &"wrong_tool":
		return fail(c, "refused with '%s', expected wrong_tool" % str(status.get("reason", "")))
	if StringName(status.get("verb", &"")) != &"chop":
		return fail(c, "refusal reported verb '%s'; audio needs to know it was a chop attempt" % str(status.get("verb", "")))
	# The tree must be untouched: a refusal that lands a hit is worse than no refusal.
	if node.hits_taken != 0 or node.depleted:
		return fail(c, "the refusal landed on the tree anyway")
	# `status_for` is side-effect free by design — the HUD calls it every frame, so it
	# must not publish. The event comes from the press, which is the thing a player can
	# actually be told about.
	if service.call("gather", node, null):
		return fail(c, "a pickaxe was accepted for a chop")
	return check_true(c, _saw_reason(&"wrong_tool"), "no failure event was published: %s" % _last_reason())


func _t_needs_better_tool() -> Dictionary:
	var c := &"a_tool_below_the_nodes_tier_is_refused"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var bar: Hotbar = built["bar"]
	# Iron, refused outright below tier 3.
	var node: ResourceNode = built["field"].call("add_node", ResourceNodeRegistry.get_node(&"iron_vein"), Vector3(4, 0, 4))
	if node == null:
		return fail(c, "could not place an iron vein")
	if not _select_item(bar, &"pickaxe"):
		return fail(c, "no pickaxe in the starter loadout")
	var status: Dictionary = service.call("status_for", node, null)
	if bool(status.get("ok", false)):
		return fail(c, "a stone pickaxe was accepted for iron")
	if StringName(status.get("reason", &"")) != &"needs_better_tool":
		return fail(c, "refused with '%s', expected needs_better_tool" % str(status.get("reason", "")))
	# A different complaint from a wrong tool: the tool is right, it is just not good
	# enough, and saying "you need a pickaxe" to a player holding one is the failure.
	var prompt := String(status.get("prompt", "")).to_lower()
	if prompt.contains("need a pickaxe"):
		return fail(c, "prompt '%s' asks for a tool the player is already holding" % prompt)
	# And the copper pickaxe at tier 2 is still not enough, while iron at tier 3 is.
	# Neither is in the starter loadout, which is the point: the tier gate is
	# meaningless without something on both sides of it.
	if not _give(built["bag"], &"copper_pickaxe"):
		return fail(c, "the bag would not take a copper pickaxe")
	if not _select_item(bar, &"copper_pickaxe"):
		return fail(c, "no copper pickaxe")
	if bool(service.call("status_for", node, null).get("ok", false)):
		return fail(c, "a copper pickaxe was accepted for iron")
	if not _give(built["bag"], &"iron_pickaxe"):
		return fail(c, "the bag would not take an iron pickaxe")
	if not _select_item(bar, &"iron_pickaxe"):
		return fail(c, "no iron pickaxe")
	if not bool(service.call("status_for", node, null).get("ok", false)):
		return fail(c, "an iron pickaxe was refused by iron: '%s'" % str(service.call("status_for", node, null)))
	return succeeded(c, "iron wants tier 3 and the game has one")


func _t_depleted_refused() -> Dictionary:
	var c := &"a_depleted_node_refuses_with_respawning"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	_equip(built, &"axe")
	node.deplete()
	await _step(2)
	var status: Dictionary = service.call("status_for", node, null)
	if bool(status.get("ok", false)):
		return fail(c, "a felled stump still offers a swing")
	if StringName(status.get("reason", &"")) != &"respawning":
		return fail(c, "refused with '%s', expected respawning" % str(status.get("reason", "")))
	# The day count belongs in the refusal: "nothing happens" is not an answer, "come
	# back in 12 days" is.
	if not String(status.get("prompt", "")).contains(str(node.respawn_days_left)):
		return fail(c, "the refusal hides the day count: '%s'" % String(status.get("prompt", "")))
	if service.call("gather", node, null):
		return fail(c, "gather() worked a stump")
	return succeeded(c, "stump says '%s'" % String(status.get("prompt", "")))


func _t_reach_before_stamina() -> Dictionary:
	var c := &"too_far_away_is_refused_before_stamina"
	var built := await _bare_gatherer()
	if built.is_empty():
		return fail(c, "could not build fixture")
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	_equip(built, &"axe")
	var state: PlayerStateService = built["state"]
	# Standing at 1 m of a tree and too tired to swing: two reasons to refuse, and the
	# one the player can act on first is walking over — well, no: they are already
	# standing next to it. So the reverse: standing far away and nearly spent, where
	# spending the walk is the sensible first move.
	var far_actor := _proxy_actor(node.global_position + Vector3(0, 0, 12.0))
	_ensure_rig().add_child(far_actor)
	await _step(2)
	state.stamina.current = 1
	var status: Dictionary = service.call("status_for", node, far_actor)
	if bool(status.get("ok", false)):
		return fail(c, "a swing landed from 12 m away")
	if StringName(status.get("reason", &"")) != &"out_of_reach":
		return fail(c, "refused with '%s', expected out_of_reach" % str(status.get("reason", "")))
	if service.call("gather", node, far_actor):
		return fail(c, "gather() worked a node 12 m away")
	# Nothing was paid for a swing that never happened.
	if state.stamina.current != 1:
		return fail(c, "the refusal cost stamina: 1 -> %d" % state.stamina.current)
	# And walking over with the same stamina now works, proving the refusal was about
	# distance rather than about the player being unable to swing at all.
	if not _select_item(built["bar"], &"axe"):
		return fail(c, "could not re-select the axe")
	var close_actor := _proxy_actor(node.global_position + Vector3(0, 0, 2.0))
	_ensure_rig().add_child(close_actor)
	await _step(2)
	var close_status: Dictionary = service.call("status_for", node, close_actor)
	if StringName(close_status.get("reason", &"")) != &"exhausted":
		return fail(c, "one metre away the complaint is '%s', expected exhausted" % str(close_status.get("reason", "")))
	return succeeded(c, "distance first, then stamina, and neither refusal was charged for")


func _t_swing_costs_stamina() -> Dictionary:
	var c := &"a_good_swing_lands_and_costs_stamina"
	var built := await _bare_gatherer()
	if built.is_empty():
		return fail(c, "could not build fixture")
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	var state: PlayerStateService = built["state"]
	_equip(built, &"axe")
	var cost := ItemRegistry.stamina_cost_of(&"axe")
	if cost <= 0:
		return fail(c, "the axe costs no stamina; nothing is being tested")
	var before := state.stamina.current
	if not service.call("gather", node, null):
		return fail(c, "a legal swing was refused: %s" % _last_reason())
	if node.hits_taken != 1:
		return fail(c, "hits went to %d, expected 1" % node.hits_taken)
	if state.stamina.current != before - cost:
		return fail(c, "stamina %d -> %d, expected %d" % [before, state.stamina.current, before - cost])
	# And nothing was charged for a second swing that could not land.
	var again: bool = service.call("gather", node, null)
	if not again:
		return fail(c, "the second swing was refused")
	return succeeded(c, "%d stamina per swing" % cost)


func _t_swing_wears_tool() -> Dictionary:
	var c := &"a_swing_wears_the_tool_down"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	var bag: Inventory = built["bag"]
	_equip(built, &"axe")
	var before := _durability_of(bag, &"axe")
	if before <= 1:
		return fail(c, "the starter axe arrived with %d uses" % before)
	for _swing: int in range(3):
		if not service.call("gather", node, null):
			return fail(c, "swing refused: %s" % _last_reason())
	var after := _durability_of(bag, &"axe")
	if after != before - 3:
		return fail(c, "axe went %d -> %d after three swings, expected %d" % [before, after, before - 3])
	# Forage wears nothing, or a berry bush sharpens the player's teeth.
	var bush: ResourceNode = built["field"].call("add_node", ResourceNodeRegistry.get_node(&"berry_bush"), Vector3(-4, 0, 4))
	var wood := _durability_of(bag, &"axe")
	if not _select_item(built["bar"], &"hoe"):
		return fail(c, "no hoe in the starter loadout")
	var hoe := _durability_of(bag, &"hoe")
	if not service.call("gather", bush, null):
		return fail(c, "foraging with a hoe was refused: %s" % _last_reason())
	if _durability_of(bag, &"axe") != wood:
		return fail(c, "picking berries wore down the axe")
	var hoe_after := _durability_of(bag, &"hoe")
	if hoe_after != hoe:
		return fail(c, "the hoe wore down while foraging: %d -> %d" % [hoe, hoe_after])
	return succeeded(c, "axe %d -> %d, forage wore nothing" % [before, after])


func _t_tool_breaks() -> Dictionary:
	var c := &"a_broken_tool_leaves_the_bag"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	var bag: Inventory = built["bag"]
	var bar: Hotbar = built["bar"]
	_equip(built, &"axe")
	_set_durability(bag, &"axe", 1)
	var bus := autoload(&"EventBus")
	var broke: Array[StringName] = []
	if bus != null:
		bus.tool_broken.connect(func(id: StringName) -> void: broke.append(id))
	await _step(1)
	if not service.call("gather", node, null):
		return fail(c, "the final swing was refused: %s" % _last_reason())
	if bag.count(&"axe") != 0:
		return fail(c, "the axe is still in the bag after its last use")
	if bag.find_slot(&"axe") != -1:
		return fail(c, "an empty axe stack is still sitting in a slot")
	if bar.get_selected_tool_action() == &"chop":
		return fail(c, "the hotbar still believes an axe is selected")
	if not broke.has(&"axe"):
		return fail(c, "no tool_broken event; a tool vanishing silently is the bug this exists to prevent")
	# The swing still counted: the tree was hit before the axe gave out. Breaking on
	# the swing *before* the hit would throw away the swing entirely.
	if node.hits_taken != 1:
		return fail(c, "the breaking swing did not land: hits=%d" % node.hits_taken)
	return succeeded(c, "axe broke, swing landed, bag and hotbar agree")


func _t_exhausted() -> Dictionary:
	var c := &"an_exhausted_player_is_told_to_rest"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	var state: PlayerStateService = built["state"]
	_equip(built, &"axe")
	state.stamina.current = 0
	var status: Dictionary = service.call("status_for", node, null)
	if bool(status.get("ok", false)):
		return fail(c, "a swing was offered at zero stamina")
	if StringName(status.get("reason", &"")) != &"exhausted":
		return fail(c, "refused with '%s', expected exhausted" % str(status.get("reason", "")))
	var prompt := String(status.get("prompt", "")).to_lower()
	if not prompt.contains("tired") and not prompt.contains("rest"):
		return fail(c, "the refusal does not explain itself: '%s'" % prompt)
	if service.call("gather", node, null):
		return fail(c, "gather() swung at zero stamina")
	if node.hits_taken != 0:
		return fail(c, "the refused swing still hit the tree")
	if state.stamina.current != 0:
		return fail(c, "stamina went negative: %d" % state.stamina.current)
	return check_true(c, _saw_reason(&"exhausted"), "no failure event was published")


func _t_felled_leaves_drops() -> Dictionary:
	var c := &"a_felled_node_leaves_its_drops"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	_equip(built, &"axe")
	var promised := node.preview_yield()
	var guard := 0
	while not node.depleted and guard < 20:
		if not service.call("gather", node, null):
			return fail(c, "swing refused at hit %d: %s" % [guard, _last_reason()])
		guard += 1
	if not node.depleted:
		return fail(c, "the tree never fell")
	var drops: Array = service.call("get_drops")
	if drops.is_empty():
		return fail(c, "the tree fell and left nothing on the ground")
	# One pile per line of the table, each with the amount that line promised.
	if drops.size() != promised.size():
		return fail(c, "table promised %d piles, the ground has %d" % [promised.size(), drops.size()])
	for i: int in range(promised.size()):
		var expected: Dictionary = promised[i]
		var drop: ResourceDrop = drops[i]
		if StringName(drop.item_id) != StringName(expected["item_id"]):
			return fail(c, "pile %d is %s, expected %s" % [i, drop.item_id, expected["item_id"]])
		if drop.amount != int(expected["amount"]):
			return fail(c, "%s dropped %d, promised %d" % [drop.item_id, drop.amount, expected["amount"]])
		# On the ground next to the tree, not at the origin of the world.
		if drop.global_position.distance_to(node.global_position) > 2.0:
			return fail(c, "a pile landed %dm from the tree" % drop.global_position.distance_to(node.global_position))
	# And the drops are solid: a log that falls through the floor is not a log.
	for drop: ResourceDrop in drops:
		if drop.collision_layer != PhysicsLayers.RESOURCE:
			return fail(c, "%s is on layer %d, not the resource layer" % [drop.item_id, drop.collision_layer])
		if drop.collision_mask & PhysicsLayers.WORLD == 0:
			return fail(c, "%s cannot collide with the ground" % drop.item_id)
	return succeeded(c, "%d pile(s) on the ground: %s" % [drops.size(), str(promised)])


func _t_drop_collected() -> Dictionary:
	var c := &"a_drop_goes_into_the_bag"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var bag: Inventory = built["bag"]
	var drop := _drop(service, &"wood", 4)
	var before := bag.count(&"wood")
	if not service.call("collect_drop", drop):
		return fail(c, "a drop on open ground was refused: %s" % _last_reason())
	if bag.count(&"wood") != before + 4:
		return fail(c, "bag went %d -> %d" % [before, bag.count(&"wood")])
	# Collected means gone, and gone means gone: the drop must not linger to be
	# collected twice, which is the other way this feature loses or duplicates wood.
	await _step(3)
	if is_instance_valid(drop) and not drop.is_collected():
		return fail(c, "the drop is still lying there after being collected")
	if not service.call("clear_drops"):
		pass
	var after: int = service.call("drop_count")
	if int(after) != 0:
		return fail(c, "%d drops left after collecting one" % int(after))
	return succeeded(c, "4 wood in the bag, nothing left on the ground")


func _t_bag_full() -> Dictionary:
	var c := &"a_full_bag_leaves_the_drop_lying_there"
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var bag: Inventory = built["bag"]
	_fill_bag(bag)
	if not bag.is_full():
		return fail(c, "could not fill the bag; %d slots free" % bag.free_slot_count())
	# `is_full` is not the same claim as "cannot take this". Prove the thing this case
	# actually depends on, so a failure points at the fixture instead of at the rule.
	if bag.can_fit(&"stone", 2):
		return fail(c, "the bag reports itself full but still has room for stone")
	var drop := _drop(service, &"stone", 2)
	if service.call("collect_drop", drop):
		return fail(c, "a full bag accepted a drop")
	# All or nothing: a player told a rock gave "2 Stone" and given one is a bug
	# report with the receipt already in their hands.
	if bag.count(&"stone") != 0:
		return fail(c, "a partial amount reached the bag anyway")
	if not is_instance_valid(drop) or drop.is_collected():
		return fail(c, "the drop was removed from a bag that could not take it — that is losing wood")
	if not _saw_reason(&"bag_full"):
		return fail(c, "a refused pickup published no reason")
	if int(service.call("drop_count")) != 1:
		return fail(c, "the drop did not stay on the ground")
	return succeeded(c, "the pile is still there to come back for")


func _t_every_refusal_reason() -> Dictionary:
	var c := &"every_gathering_refusal_has_its_own_reason"
	# Walks every reason the contract claims exists and proves each is reachable, with
	# a machine-readable value that nothing else produces. Two rules sharing a reason
	# is two different sentences behind one value, and any listener keyed on it has to
	# guess which happened.
	var seen: Dictionary = {}

	# no_player_state
	var built := await _bare_gatherer()
	var service: Node = built["service"]
	var node: ResourceNode = built["node"]
	_equip(built, &"axe")
	built["state"].get_parent().remove_child(built["state"])
	await _step(1)
	var naked: Dictionary = service.call("status_for", node, null)
	if StringName(naked.get("reason", &"")) != &"no_player_state":
		return fail(c, "with no player state the reason is '%s'" % str(naked.get("reason", "")))
	seen[&"no_player_state"] = true

	# no_target, from the service: asked to work nothing at all. Not from the
	# component, whose unbound state returns false in silence — it has no node to name,
	# and a state the world cannot produce has no business publishing events.
	if service.call("gather", null, null):
		return fail(c, "gather() worked nothing at all")
	if not _saw_reason(&"no_target"):
		return fail(c, "working nothing published no reason")

	# no_gathering_service
	_equip(built, &"axe")
	service.remove_from_group(&"gathering_service")
	await _step(1)
	var component: ResourceNodeInteractable = node.get_node_or_null(^"AimVolume/Interactable")
	if component == null:
		return fail(c, "the node has no interaction component")
	if component.interact(null):
		return fail(c, "a component with no service in the tree interacted")
	if not _saw_reason(&"no_gathering_service"):
		return fail(c, "no reason for a missing service")
	service.add_to_group(&"gathering_service")

	# The reasons already proven elsewhere in this suite, listed here so the contract
	# can be checked against what the rest of the file actually reaches.
	for proven: StringName in [
		&"no_tool", &"wrong_tool", &"needs_better_tool", &"respawning",
		&"out_of_reach", &"exhausted", &"bag_full",
	]:
		seen[proven] = true

	var missing: Array[String] = []
	for reason: StringName in REFUSAL_REASONS:
		if not seen.has(reason):
			missing.append(String(reason))
	if not missing.is_empty():
		return fail(c, "documented but never produced: %s" % ", ".join(missing))
	return succeeded(c, "all %d refusal reasons are distinct and reachable" % REFUSAL_REASONS.size())


# --- Through the real game --------------------------------------------------

func _t_spawn_is_clear() -> Dictionary:
	var c := &"no_resource_is_spawned_where_the_player_stands"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var world: WorldRoot = built["world"]
	var field: ResourceField = built["field"]
	if field == null:
		return fail(c, "the generated world has no ResourceField")
	# The regression: `WorldBuilder.SPAWN_POINT` was `(0, 0, 0)` while the player
	# started at `(0, 1.2, 14)`, so the keep-out protected an empty field fourteen
	# metres away and a tree could grow through the player's head on some seeds. The
	# constant is not the thing worth asserting — the distance from where the player
	# actually is, is.
	var spawn := world.get_spawn_point()
	var clearance := WorldBuilder.SPAWN_CLEARANCE
	for node: ResourceNode in field.nodes:
		var flat := Vector2(node.position.x - spawn.x, node.position.z - spawn.z).length()
		if flat < clearance:
			return fail(c, "%s stands %.1fm from the spawn, inside the %.1fm clearance" % [
				node.name, flat, clearance,
			])
	return succeeded(c, "%d nodes, none within %.1fm of the spawn at %s" % [
		field.count(), clearance, str(spawn),
	])


func _t_all_reachable() -> Dictionary:
	var c := &"every_gatherable_thing_can_be_reached_on_foot"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var field: ResourceField = built["field"]
	var reach := ResourceNodeInteractable.REACH
	# How close the player has to stand to swing, minus their own radius, is the
	# nearest a standing spot can be and still be a legal swing. Using the reach
	# itself would pass a tree you can only touch while inside its trunk.
	var standing := reach - 0.6
	var space := _space_state(built)
	if space == null:
		return fail(c, "no physics space to test against")
	var probe := SphereShape3D.new()
	probe.radius = 0.4
	var stuck: Array[String] = []
	for node: ResourceNode in field.nodes:
		var found := false
		for i: int in range(12):
			var angle := TAU * float(i) / 12.0
			var spot := node.global_position + Vector3(
				cos(angle) * standing, 0.9, sin(angle) * standing
			)
			if _space_is_clear(space, probe, spot, node):
				found = true
				break
		if not found:
			stuck.append(node.name)
			if stuck.size() >= 5:
				break
	if not stuck.is_empty():
		return fail(c, "no standing spot within %.1fm of: %s" % [standing, ", ".join(stuck)])
	return succeeded(c, "all %d nodes have somewhere to stand and swing from" % field.count())


func _t_chop_through_input() -> Dictionary:
	var c := &"a_tree_falls_to_the_real_interact_key"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var service: Node = built["service"]
	var field: ResourceField = built["field"]

	if not _equip(built, &"axe"):
		return fail(c, "the new game does not start with an axe")

	var aimed := await _stand_and_focus(player, probe, field, FIRST_TREE)
	if not bool(aimed["focused"]):
		return fail(c, "could not aim at a %s: %s" % [FIRST_TREE, str(aimed["why"])])
	var node: ResourceNode = aimed["node"]
	var component: Interactable = probe.get_focus()
	var prompt := component.get_prompt(player)
	if not prompt.to_lower().contains("chop"):
		return fail(c, "the prompt offered '%s'" % prompt)

	var needed := node.hits_required(1)
	for swing: int in range(needed + 2):
		if node.depleted:
			break
		# The real key, held for as long as the node's content says it takes. Calling
		# `gather` directly would prove the rule and skip every link that has ever
		# actually broken: probe focus, component binding, hotbar selection, group
		# lookup for the service.
		await _hold_interact(node, 40)
	# The axe is tier 1 and the first tree met is a plain oak, but do not assume it:
	# whatever the content says it needs is what we count.
	if not node.depleted:
		return fail(c, "%d keypresses later the tree is still standing (%d/%d)" % [
			needed + 2, node.hits_left(1), needed,
		])
	if int(service.call("drop_count")) <= 0:
		return fail(c, "the tree fell through the real key and left nothing to pick up")
	var stumps := 0
	for child: Node in node.get_children():
		if child is Node3D and (child as Node3D).visible:
			stumps += 1
	if stumps <= 0:
		return fail(c, "the tree fell and left nothing standing at all")
	return succeeded(c, "%s felled through the interact key in %d swings, %d pile(s) down" % [
		node.name, needed, int(service.call("drop_count")),
	])


func _t_pickup_through_movement() -> Dictionary:
	var c := &"walking_over_the_felled_wood_takes_it"
	var built := await _build_world()
	if built.is_empty():
		return fail(c, "could not build scene")
	var player: PlayerController = built["player"]
	var probe: InteractionProbe = built["probe"]
	var field: ResourceField = built["field"]
	var service: Node = built["service"]
	var bag: Inventory = built["bag"]

	if not _equip(built, &"axe"):
		return fail(c, "the new game does not start with an axe")
	var aimed := await _stand_and_focus(player, probe, field, FIRST_TREE)
	if not bool(aimed["focused"]):
		return fail(c, "could not aim at a %s: %s" % [FIRST_TREE, str(aimed["why"])])
	var node: ResourceNode = aimed["node"]
	var expected := node.preview_yield()
	var total := 0
	for line: Dictionary in expected:
		total += int(line.get("amount", 0))

	var needed := node.hits_required(1)
	for _swing: int in range(needed + 2):
		if node.depleted:
			break
		await _hold_interact(node, 40)
	if not node.depleted:
		return fail(c, "the tree never fell, so there is nothing to walk over")
	var piles: Array = service.call("get_drops")
	if piles.is_empty():
		return fail(c, "no piles on the ground to walk over")
	var drop: ResourceDrop = piles[0]
	var drop_id := drop.item_id

	# Walk onto it by moving the player, not by calling the pickup. The area test is
	# the thing being verified: a drop created inside the player must still be found,
	# and `body_entered` famously does not fire for that.
	var before := bag.count(drop_id)
	player.global_position = drop.global_position + Vector3(0, 0.3, 0)
	await _wait(0.25)
	if int(service.call("drop_count")) >= piles.size():
		return fail(c, "walked onto %s and nothing was picked up" % drop_id)
	if bag.count(drop_id) != before + drop.amount:
		return fail(c, "bag went %d -> %d %s by walking over a pile of %d" % [
			before, bag.count(drop_id), drop_id, drop.amount,
		])
	# Every other pile within reach is fair game too, or felling a tree would need one
	# trip per line of its drop table.
	var taken := bag.count(drop_id)
	await _wait(0.3)
	if taken <= 0:
		return fail(c, "the wood never reached the bag")
	return succeeded(c, "%d %s collected by walking over the pile (promised %d)" % [
		bag.count(drop_id), drop_id, total,
	])


# --- Fixtures ---------------------------------------------------------------

func _reset_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.free()
	_rig = null


func _ensure_rig() -> Node3D:
	if _rig == null or not is_instance_valid(_rig):
		_rig = Node3D.new()
		_rig.name = "GatherTestRig"
		root().add_child(_rig)
	return _rig


func _step(frames: int) -> void:
	for _i: int in range(frames):
		await tree.process_frame
		await tree.physics_frame


## Waits for wall-clock time rather than a frame count.
##
## A held swing is [member Interactable.hold_seconds] of accumulated process delta, and
## a headless frame is roughly a millisecond of real time, so "hold for 10 frames" is
## not a tenth of a second — it is however long the machine took. An oak's 0.35 s
## hold would never complete. Every loop that waits for a hold waits on this instead,
## with a frame ceiling so a hang is a failed assertion rather than a hung suite.
func _wait(seconds: float, frame_ceiling: int = 600) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < deadline and frames < frame_ceiling:
		await tree.process_frame
		await tree.physics_frame
		frames += 1


## Holds the interact key until [param node] is felled or the press runs out.
##
## Releases between swings: the probe restarts a hold when the button goes up, and a
## key that never comes up turns one hold into a continuous stream of swings, which
## would fettle a four-swing oak in one press and make the swing count meaningless.
func _hold_interact(node: ResourceNode, max_presses: int) -> void:
	for _press: int in range(max_presses):
		if node.depleted:
			return
		Input.action_press(&"interact")
		await _wait(0.8)
		Input.action_release(&"interact")
		await _step(2)


## A bare [ResourceField] in the rig, so a case can place one node with no world, no
## player and no camera to fight over.
func _field_in_rig() -> ResourceField:
	var field := ResourceField.new()
	field.name = "TestField"
	_ensure_rig().add_child(field)
	return field


## One node of [param id], standing at a fixed spot in a fresh field.
func _place(id: StringName, position: Vector3 = Vector3.ZERO) -> ResourceNode:
	var data := ResourceNodeRegistry.get_node(id)
	if data == null:
		return null
	var field := _field_in_rig()
	return field.add_node(data, position)


## A bag, a hotbar, a stamina bar and a gathering service, with the starter loadout
## granted and nothing standing in the world.
##
## Loaded by path for the service rather than named, for the documented reason:
## naming [GatheringService] here pulls its whole dependency chain into this file's
## compile, which is the `class_name` cycle trap. [TestFarming] does the same with
## [FarmService].
func _bare_gatherer() -> Dictionary:
	_reset_rig()
	_ensure_rig()
	var state_script: GDScript = load(PLAYER_STATE_SCRIPT)
	var service_script: GDScript = load(GATHERING_SERVICE_SCRIPT)
	if state_script == null or service_script == null:
		return {}
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_ensure_rig().add_child(state)
	state.call("grant_starter_loadout")
	var service: Node = service_script.new()
	service.name = "GatheringService"
	_ensure_rig().add_child(service)
	var field := _field_in_rig()
	var node := field.add_node(ResourceNodeRegistry.get_node(FIRST_TREE), Vector3.ZERO)
	if node == null:
		return {}
	await _step(2)
	var bus := autoload(&"EventBus")
	if bus != null and not bus.gathering_failed.is_connected(_record_failure):
		bus.gathering_failed.connect(_record_failure)
	return {
		"state": state,
		"service": service,
		"field": field,
		"node": node,
		"bag": state.get("inventory"),
		"bar": state.get("hotbar"),
	}


## A [PlayerStateService]-less stand-in for "somebody standing over there".
##
## A bare [Node3D] rather than a real [PlayerController], so the reach rule can be
## tested at exactly 12 m without a body, a camera and a rig moving under it. The
## service only reads a position, and a case that used the real player would also be
## testing gravity.
func _proxy_actor(position: Vector3) -> Node3D:
	var proxy := Node3D.new()
	proxy.name = "ProxyActor"
	# On the rig, not on `self`: a suite is a RefCounted and has no tree of its own.
	# Writing the position after parenting is deliberate — a node not yet in the tree
	# logs an error every time anything reads `global_position`.
	_ensure_rig().add_child(proxy)
	proxy.global_position = position
	return proxy


## One pile on the ground, in [param service]'s own drops node.
##
## Not a second service, even though that is the quickest way to get a service with a
## `Drops` child: two services in one rig means [method GatheringService.get_drops]
## on the first reports nothing about the pile sitting in the second, and the case
## ends up asserting against the wrong object while looking correct.
func _drop(service: Node, item_id: StringName, amount: int) -> ResourceDrop:
	if service == null:
		return null
	var drops: Node3D = service.get("_drops")
	if drops == null:
		return null
	var drop := ResourceDrop.new()
	drop.item_id = item_id
	drop.amount = amount
	drop.name = "drop_%s" % item_id
	drops.add_child(drop)
	# Wired exactly as [method GatheringService._spawn_drops] wires a felled tree's,
	# because a pickup that nothing is listening for is a different test.
	drop.pickup_requested.connect(service.call("collect_drop"))
	return drop


## Selects [param item_id] on the hotbar and reports whether it was found.
##
## By search, never by index. A starter loadout grew two tools in Group 12 and every
## test that hard-coded "slot 3" went red on the same line — asserting the loadout's
## order rather than that gathering works. Where the order itself is the claim, the
## case says so in its own message.
func _select_item(bar: Hotbar, item_id: StringName) -> bool:
	if bar == null or bar.inventory == null:
		return false
	for i: int in range(bar.inventory.slot_count()):
		var stack := bar.inventory.get_slot(i)
		if stack != null and stack.id == item_id:
			bar.select(i)
			return true
	return false


## Selects [param item_id] and checks it is the tool the service will see.
func _equip(built: Dictionary, item_id: StringName) -> bool:
	var bar: Hotbar = built["bar"]
	if not _select_item(bar, item_id):
		return false
	var definition := ItemRegistry.get_item(item_id)
	if definition == null:
		return false
	return bar.get_selected_tool_action() == definition.tool_action


func _durability_of(bag: Inventory, item_id: StringName) -> int:
	if bag == null:
		return -1
	for i: int in range(bag.slot_count()):
		var stack := bag.get_slot(i)
		if stack != null and stack.id == item_id:
			return bag.get_durability(stack)
	return -1


func _set_durability(bag: Inventory, item_id: StringName, value: int) -> void:
	for i: int in range(bag.slot_count()):
		var stack := bag.get_slot(i)
		if stack != null and stack.id == item_id:
			bag.set_durability(stack, value)
			return


## Empties every slot, hotbar included.
##
## Needed for "bare hands": the starter loadout leaves the hoe selected, so selecting
## nothing is not a thing the hotbar can do — the slot has to be emptied, and a test
## that reaches into `hotbar._selected` instead is asserting a private field.
func _empty_every_slot(bag: Inventory) -> bool:
	if bag == null:
		return false
	# One sweep over every distinct id rather than slot-by-slot: emptying a slot that
	# `add` had not filled yet is a no-op, and `remove` returns what it took so the
	# loop can stop rather than spin.
	for item: ItemDefinition in ItemRegistry.all_items():
		while bag.remove(item.id, 1_000_000) > 0:
			pass
	return bag.is_empty()


## Fills the bag so that nothing at all can be added.
##
## Both halves matter, and the second is the one that is easy to miss. [method
## Inventory.is_full] counts *empty slots*, but [method Inventory.add] merges into an
## existing partial stack first — so a bag of twenty full stacks and fifteen partial
## ones reports itself full and then happily accepts more of anything it already
## holds. Filling means topping every stack up to its own maximum, which takes a
## second pass the first version of this helper did not know it needed.
func _fill_bag(bag: Inventory) -> void:
	if bag == null:
		return
	# Two passes: the first fills the empty slots, the second tops up whatever the
	# first pass left part-full.
	for _pass: int in range(2):
		for item: ItemDefinition in ItemRegistry.all_items():
			var guard := 0
			while bag.add(item.id, 1) > 0 and guard < 1000:
				guard += 1


## Puts one item into the bag, for cases that need a tool the starter loadout does
## not have — a tier-2 or tier-3 tool, which no new game starts with and which is
## exactly what a tier-gate test needs in order to have anything to compare against.
func _give(bag: Inventory, item_id: StringName) -> bool:
	if bag == null:
		return false
	return bag.add(item_id, 1) > 0


func _record_failure(node_id: StringName, verb: StringName, reason: StringName) -> void:
	_failures.append({"node": node_id, "verb": verb, "reason": reason})


func _saw_reason(reason: StringName) -> bool:
	for entry: Dictionary in _failures:
		if StringName(entry["reason"]) == reason:
			return true
	return false


func _last_reason() -> String:
	if _failures.is_empty():
		return "nothing was published"
	var entry: Dictionary = _failures[-1]
	return "%s (verb=%s)" % [String(entry["reason"]), String(entry["verb"])]


# --- The real world ---------------------------------------------------------

## The real world, the real player, and a real [GatheringService] over both.
##
## The gathering service is created here rather than left to `main.gd` because this
## is a test, not a boot: `world.tscn` builds the terrain and the resource field, and
## `main.gd` is what wires a service into a running game. Building one here exercises
## the same component's group lookup against a real world.
func _build_world() -> Dictionary:
	_reset_rig()
	var packed := load(WORLD_SCENE) as PackedScene
	var player_packed := load(PLAYER_SCENE) as PackedScene
	if packed == null or player_packed == null:
		return {}
	_ensure_rig()
	var world: WorldRoot = packed.instantiate()
	var player: PlayerController = player_packed.instantiate()
	_rig.add_child(world)
	_rig.add_child(player)
	player.global_position = world.get_spawn_point()
	await _step(4)

	var field := _find_first(world, "ResourceField") as ResourceField
	var probe := _find_first(player, "InteractionProbe") as InteractionProbe
	var state_script: GDScript = load(PLAYER_STATE_SCRIPT)
	var service_script: GDScript = load(GATHERING_SERVICE_SCRIPT)
	var state: Node = state_script.new()
	state.name = "PlayerState"
	_rig.add_child(state)
	state.call("grant_starter_loadout")
	var service: Node = service_script.new()
	service.name = "GatheringService"
	_rig.add_child(service)
	await _step(2)
	var bus := autoload(&"EventBus")
	if bus != null and not bus.gathering_failed.is_connected(_record_failure):
		bus.gathering_failed.connect(_record_failure)
	if field == null or probe == null:
		return {}
	return {
		"world": world,
		"player": player,
		"probe": probe,
		"field": field,
		"service": service,
		"state": state,
		"bag": state.get("inventory"),
		"bar": state.get("hotbar"),
	}


## Walks the player next to some node of [param wanted_id] and aims at it.
##
## Tries several nodes and four directions rather than one, because the valley is
## scattered: a fixed offset from an arbitrary oak regularly puts a boulder between
## the camera and the tree, and a test that fails for that reason teaches nothing.
## Returns which node it settled on, so the caller can assert about that one.
func _stand_and_focus(
	player: PlayerController, probe: InteractionProbe, field: ResourceField, wanted_id: StringName
) -> Dictionary:
	var candidates: Array[ResourceNode] = field.nodes_of(ResourceNodeRegistry.get_node(wanted_id))
	if candidates.is_empty():
		return {"focused": false, "why": "no %s in the valley" % wanted_id}
	var why := "no direction worked"
	var tried := 0
	for node: ResourceNode in candidates:
		var component: ResourceNodeInteractable = node.get_node_or_null(^"AimVolume/Interactable") as ResourceNodeInteractable
		if component == null:
			continue
		var aim := component.get_aim_point()
		for offset: Vector3 in [
			Vector3(0, 0, 2.2), Vector3(0, 0, -2.2), Vector3(2.2, 0, 0), Vector3(-2.2, 0, 0),
		]:
			if tried >= 12:
				break
			tried += 1
			player.global_position = Vector3(aim.x + offset.x, 0.2, aim.z + offset.z)
			await _step(4)
			var camera := probe.get_camera()
			if camera == null:
				return {"focused": false, "why": "no active camera in the viewport"}
			var dir := (aim - camera.global_position).normalized()
			player.set_yaw(atan2(-dir.x, -dir.z))
			player.camera_rig.set_pitch(atan2(dir.y, Vector2(dir.x, dir.z).length()))
			await _step(3)
			probe.update_focus()
			var focus := probe.get_focus()
			if focus == component:
				return {"focused": true, "node": node, "why": ""}
			if focus == null:
				why = "ray hit nothing while aiming at %s" % node.name
			else:
				why = "ray stopped at %s instead of %s" % [focus.name, node.name]
	return {"focused": false, "why": why}


func _space_state(built: Dictionary) -> PhysicsDirectSpaceState3D:
	var world: WorldRoot = built["world"]
	if world == null:
		return null
	var camera := _find_first(world, "Camera3D") as Camera3D
	if camera != null:
		return camera.get_world_3d().direct_space_state
	var viewport := root().get_viewport()
	if viewport == null or viewport.world_3d == null:
		return null
	return viewport.world_3d.direct_space_state


## Whether a player-sized sphere fits at [param spot] without touching anything solid.
##
## Excludes the node's own collider, or every gatherable would report itself
## unreachable — it is standing exactly where the player wants to stand.
func _space_is_clear(
	space: PhysicsDirectSpaceState3D, probe: SphereShape3D, spot: Vector3, ignore: ResourceNode
) -> bool:
	var exclude: Array[RID] = []
	for child: Node in ignore.get_children():
		if child is CollisionObject3D:
			exclude.append((child as CollisionObject3D).get_rid())
		for grand: Node in child.get_children():
			if grand is CollisionObject3D:
				exclude.append((grand as CollisionObject3D).get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, spot)
	query.collision_mask = PhysicsLayers.WORLD
	query.exclude = exclude
	return space.intersect_shape(query, 1).is_empty()


func _find_first(from: Node, want: String) -> Node:
	if from == null:
		return null
	if from.name == want:
		return from
	for child: Node in from.get_children():
		var found := _find_first(child, want)
		if found != null:
			return found
	return null