class_name FarmService
extends Node
## The player-facing farming system: what the tools do, what the seeds cost, what
## comes back from a harvest.
##
## The one node that knows about soil, the bag and the hotbar at the same time.
## Everything below it is pure: [SoilTile] knows the rules for a tile, [Inventory]
## knows the rules for a bag, [CropData] knows what a crop is. This node's whole
## job is to ask each of them the right question and publish the outcome.
##
## ## It does not own the bag
##
## It used to. [PlayerStateService] owns it now, because the shop also needs it
## and a shop that reached into the farm service would make the economy depend on
## farming. So the bag and hotbar below are *derived* — read through the owner,
## never held — and they are declared as getters rather than as fields so that
## every existing `service.inventory` still reads the real bag and nothing has to
## be threaded through by hand.
##
## That is a deliberate trade. A writable `inventory` field here would let a test
## or a scene point the farm at a bag the player does not have, and the resulting
## bug would be a hoe that spends seeds from nowhere.
##
## ## Why it lives at the tree root
##
## [SoilTileInteractable] finds it by group. That lookup is deliberate rather than
## a reference passed in at spawn: the interactable is created by the world
## generator, deep inside a scene tree, and threading a service reference into it
## would make the world depend on the player's inventory — exactly the inversion
## the lane rules forbid.

## Emitted when a tool is swung, whatever the outcome, so an audio layer can
## attach a "thunk" to every attempt rather than only the successes.
signal tool_used(tool_action: StringName, tile_index: Vector2i)
## Emitted when a tool breaks from wear.
signal tool_broken(item_id: StringName)

## The plot this service acts on. Set by [method _ready] from the scene, or
## injected by a test.
@export var grid: FarmGrid

## The owner of the player's bag, hotbar, purse and stamina.
##
## Optional: left null the service finds it by group on first use, which is how
## the shipped boot order works and how the tests use it. Set it directly when a
## test wants two isolated fakes in one tree.
@export var player_state: PlayerStateService = null

## The player's bag, read through [member player_state].
##
## Getter-only on purpose. See the class docs.
var inventory: Inventory:
	get: return _state().inventory if _state() != null else null

## The player's nine slots, read through [member player_state].
var hotbar: Hotbar:
	get: return _state().hotbar if _state() != null else null

## The player's stamina, read through [member player_state].
var stamina: Stamina:
	get: return _state().stamina if _state() != null else null

## How far the current tool reaches, in metres. Deliberately not the interact
## range: swinging a hoe should need you to be standing on the tile, which is what
## makes a 35-tile plot a chore rather than a formality.
@export var tool_reach: float = 1.9
## Radius of a tool's effect around the aimed tile, in metres.
##
## Tiles are 2 m apart, so 1.1 m reaches past nothing: the hoe affects the aimed
## tile only. It used to claim a 3x3 sweep here, which no value in this file can
## produce — neighbouring centres are a full 2 m out — and the comment had been
## wrong longer than the value had.
##
## Kept as a radius rather than hardcoded to one tile so a genuinely wide tool
## (a scythe clearing a row) can be added without touching `use_tool`.
@export var tool_radius: float = 1.1

var _rng := RandomNumberGenerator.new()


## Group this node registers under, so [SoilTileInteractable] can find it.
##
## Duplicated there as a literal because a shared constant would require naming
## one class from the other, which is the `class_name` cycle both files work to
## avoid.
const SERVICE_GROUP := &"farm_service"


func _ready() -> void:
	_rng.randomize()
	add_to_group(SERVICE_GROUP)

	# One subscription, one direction. The service learns that a day began from
	# the clock; it never asks the clock anything.
	EventBus.day_started.connect(_on_day_started)
	EventBus.weather_changed.connect(_on_weather_changed)

	Log.info("FarmService", "Ready (%d tiles)" % (
		grid.tile_count() if grid != null else 0
	))


## The player's state, injected or found.
##
## Falls back to a group search rather than requiring wiring, because this node is
## created by `main.gd` before the state service in some orders and by tests
## without one at all. The search runs at most once and is cached, so the getter
## above stays cheap in the per-tile paths.
func _state() -> PlayerStateService:
	if player_state != null and is_instance_valid(player_state):
		return player_state
	player_state = PlayerStateService.find()
	return player_state


## Registers the newly built grid. Called by `main.gd` after the world exists,
## because the grid is generated inside the world scene and there is nothing to
## attach to before then.
func attach_grid(value: FarmGrid) -> void:
	grid = value


## The tool action the held slot provides, or empty when nothing is held.
##
## Read straight from the hotbar rather than cached, so switching slots and then
## swinging always uses the newly held tool.
func current_tool_action() -> StringName:
	if hotbar == null:
		return &""
	return hotbar.get_selected_tool_action()


## Swings the held tool at [param target], if the player can reach it and has the
## stamina for it.
##
## Returns how many tiles were actually changed. A zero return is the tool
## whiffing — out of reach, too tired, or aimed at nothing — and the caller
## decides whether that deserves a sound. Success and failure are published
## separately by the tile, so the HUD's "tilled 3 tiles" and the audio's "thunk"
## come from different places and cannot drift.
##
## Stamina is charged only when the swing actually did something. Charging a
## whiffed swing is how a player runs dry without having hoed a single tile, and
## it is the kind of bug that reads as "the stamina bar is broken" rather than as
## a rules question.
func use_tool(target: SoilTile) -> int:
	if target == null:
		tool_used.emit(&"", Vector2i(-1, -1))
		EventBus.farming_failed.emit(Vector2i(-1, -1), &"tool", "no_target")
		return 0

	var action := current_tool_action()
	var actor := _find_player()
	if actor == null or not _in_reach(actor, target):
		tool_used.emit(action, target.tile_index)
		EventBus.farming_failed.emit(target.tile_index, action, "out_of_reach")
		return 0

	# Affordability is checked *before* any tile is touched. It used to be charged
	# afterwards, which meant a swing that could not be paid for had already
	# tilled, watered or cleared the soil and only then announced the refusal —
	# free work, every time, exactly when the player was least able to notice.
	# The refusal publishes its own events, and the whiffing swing is still
	# reported through [signal tool_used].
	var charged := _charge_stamina()
	if charged < 0:
		tool_used.emit(action, target.tile_index)
		return 0

	var affected := _affected_tiles(target)
	var changed := 0
	for tile: SoilTile in affected:
		if _apply_tool(tile, action):
			changed += 1

	tool_used.emit(action, target.tile_index)
	# Stamina is already paid, but the refund question remains: a swing that reached
	# the tile and changed nothing — a hoe on already-tilled soil, a can on dry
	# ground — was not performed, and charging it is how a player runs dry without
	# having hoed a single tile.
	if changed == 0:
		_refund_stamina(charged)
		return 0
	_spend_durability(action)
	return changed


## Pays for one swing of the held tool, and complains if the player cannot.
##
## Returns the stamina charged, `0` when the swing was free, and `-1` when it was
## refused — and having published both [signal EventBus.farming_failed] and
## [signal EventBus.stamina_exhausted]. Two events on purpose: the first is the
## refusal the farming UI reports against the tile, the second is the player-level
## fact that a shop or a mine will need to raise later without sounding like a hoe.
##
## The three-way return rather than a bool because "refused" and "cost nothing" are
## different answers and a bool collapses them: a caller treating `false` as refused
## would report a free swing as a failure, and one treating it as free would let an
## exhausted player keep hoeing.
func _charge_stamina() -> int:
	var pool := stamina
	if pool == null:
		# No stamina in this tree — a bare farm service in a unit test, or a game
		# booted without player state. Farming still works; there is just nothing
		# to spend.
		return 0
	var cost := _held_stamina_cost()
	if cost <= 0:
		return 0
	if pool.can_spend(cost):
		pool.spend(cost)
		return cost
	EventBus.stamina_exhausted.emit()
	EventBus.farming_failed.emit(
		Vector2i(-1, -1), current_tool_action(), "exhausted"
	)
	return -1


## Gives back [param amount] taken by [method _charge_stamina].
##
## Only called when the swing reached the tile and changed nothing, so that the
## player is never charged for work that did not happen.
func _refund_stamina(amount: int) -> void:
	var pool := stamina
	if pool == null or amount <= 0:
		return
	pool.restore(amount)


## What one swing of the held item costs.
##
## Read from the held stack rather than from the tile being worked, because the
## cost belongs to the tool. Zero when nothing is held, or when what is held is not
## a tool — planting costs no stamina here, which is a deliberate simplification
## rather than an oversight: the only stamina-gated verb right now is `use_tool`.
func _held_stamina_cost() -> int:
	if hotbar == null:
		return 0
	var stack := hotbar.get_selected_stack()
	if stack == null:
		return 0
	return ItemRegistry.stamina_cost_of(stack.id)


## Uses the held seed packet on [param target].
##
## Planting is separate from [method use_tool] because planting needs an
## inventory item rather than a tool, and conflating them is how you end up with a
## "use" action that sometimes eats a seed and sometimes swings a hoe.
func plant(target: SoilTile, actor: Node) -> bool:
	if target == null:
		EventBus.farming_failed.emit(Vector2i(-1, -1), &"plant", "no_target")
		return false
	if hotbar == null:
		EventBus.farming_failed.emit(target.tile_index, &"plant", "no_hotbar")
		return false

	var seed_id := hotbar.get_selected_seed()
	if seed_id.is_empty():
		EventBus.farming_failed.emit(
			target.tile_index, &"plant", _plant_refusal(target)
		)
		return false

	# Check the tile can take it *before* consuming the seed. Consuming first and
	# failing second is the classic "my parsnip seeds vanished" bug.
	if not target.is_tilled:
		EventBus.farming_failed.emit(target.tile_index, &"plant", "needs_tilling")
		return false
	if not target.crop_id.is_empty():
		EventBus.farming_failed.emit(target.tile_index, &"plant", "occupied")
		return false
	if not CropRegistry.get_crop(seed_id).grows_in(_current_season()):
		EventBus.farming_failed.emit(target.tile_index, &"plant", "wrong_season")
		return false

	if inventory.remove(hotbar.get_selected_stack().id, 1) <= 0:
		EventBus.farming_failed.emit(target.tile_index, &"plant", "no_seed")
		return false

	target.plant(seed_id)
	EventBus.item_removed.emit(hotbar.get_selected_stack().id, 1)
	return true


## Harvests [param target] into the bag.
##
## The yield only reaches the inventory if it fits, so the bag is asked *before*
## the crop is pulled. That ordering is the whole point of this function.
##
## It used to harvest first and re-plant on failure. Two things came out of that
## undone. A regrowing crop's clock had already been rewound, and `plant` restarts
## it at zero, so a full bag cost the player a day of a tomato they still owned.
## Worse, `SoilTile.harvest` had already published `crop_harvested` and its own
## `harvested` signal — so the HUD and the audio announced a successful harvest,
## and the very next event was a refusal. [code]AGENTS.md[/code] requires success
## and failure to be clearly distinct; two contradictory events for one keypress
## is worse than either alone.
func harvest(target: SoilTile, actor: Node) -> bool:
	if target == null:
		EventBus.farming_failed.emit(Vector2i(-1, -1), &"harvest", "no_target")
		return false

	var preview := target.preview_harvest()
	if not bool(preview["ok"]):
		EventBus.farming_failed.emit(
			target.tile_index, &"harvest", StringName(str(preview["reason"]))
		)
		return false

	var crop_id := StringName(str(preview["crop_id"]))
	var amount := int(preview["amount"])
	if inventory != null and not inventory.can_fit(crop_id, amount):
		EventBus.farming_failed.emit(target.tile_index, &"harvest", "bag_full")
		return false

	var result := target.harvest()
	if not bool(result["ok"]):
		EventBus.farming_failed.emit(
			target.tile_index, &"harvest", StringName(str(result["reason"]))
		)
		return false

	if inventory != null:
		var added := inventory.add(crop_id, amount)
		if added <= 0:
			# Unreachable while `can_fit` is honest, and guarded rather than
			# asserted because this is the one branch where a mistake destroys a
			# player's crop. The crop is already lifted and its success event is
			# already out, so there is no clean undo — this branch exists to keep
			# the items out of a lost state, and says so loudly.
			Log.warn(
				"FarmService",
				"can_fit said yes but add refused %d %s; crop is now unreturnable"
				% [amount, crop_id]
			)
			EventBus.farming_failed.emit(target.tile_index, &"harvest", "bag_full")
			return false
		EventBus.item_added.emit(crop_id, added)
	return true


## Every tile the current tool would affect when aimed at [param target].
##
## A radius narrower than one tile still affects exactly one tile, because the
## player aimed at a specific square and "nothing happened" would be a bug. The
## check is against the tile's own width rather than a constant, so changing
## [member FarmGrid.tile_size] cannot leave the tool silently reaching nothing.
func _affected_tiles(target: SoilTile) -> Array[SoilTile]:
	if grid == null or tool_radius < target.tile_half_extent():
		return [target]
	return grid.tiles_in_radius(target.global_position, tool_radius)


## Applies one tool to one tile. Returns true when the tile's state changed.
func _apply_tool(tile: SoilTile, action: StringName) -> bool:
	match action:
		&"till":
			return tile.till()
		&"water":
			if tile.is_watered:
				return false
			if not tile.water():
				# Watering untilled soil is the single most common farming
				# mistake, and it deserves its own reason string rather than a
				# generic failure.
				EventBus.farming_failed.emit(tile.tile_index, action, "needs_tilling")
				return false
			return true
		&"":
			EventBus.farming_failed.emit(tile.tile_index, action, "no_tool")
			return false
	return false


## Why planting was refused when no seed was held.
##
## Distinguishes "you are holding a hoe" from "that tile is not ready" from "it is
## winter", because they need different actions from the player and a single
## "cannot plant here" teaches nothing.
func _plant_refusal(target: SoilTile) -> StringName:
	if not target.is_tilled:
		return &"needs_tilling"
	if not target.crop_id.is_empty():
		return &"occupied"
	return &"no_seed"


## Wears down the held tool, and keeps this class's own [signal tool_broken] for
## listeners that were already watching it.
##
## The rules are not here any more — [method PlayerStateService.spend_tool_durability]
## owns them, because gathering wears tools down too and a second copy of this
## function is a second copy of the `remove_stack`-not-`remove` subtlety.
func _spend_durability(action: StringName) -> void:
	var result := _state().spend_tool_durability(action) if _state() != null else {}
	if result.get("broke", false):
		tool_broken.emit(StringName(result.get("id", &"")))
		Log.info("FarmService", "tool wore out while tilling")


## Midnight on the farm.
##
## The service walks the grid and asks every tile to advance; it does not decide
## what a tile does. Whether a crop actually grows is
## [method SoilTile.on_new_day]'s business, and it is decided there rather than
## here so the rule lives in exactly one place.
##
## The bag relay that used to live here has moved to [PlayerStateService], which
## owns the bag now. What is left is one subscription, one direction: the service
## learns that a day began from the clock and never asks the clock anything.
func _on_day_started(day: int) -> void:
	if grid == null:
		return
	for tile: SoilTile in grid.get_tiles():
		tile.on_new_day()
	Log.info("Farm", "Day %d: %d tiles advanced" % [day, grid.tile_count()])


## Rain waters the whole plot for free.
##
## Only rain and storm, not snow or wind: a snow day is a day you still have to
## carry a can around. This is the weather hook the time group left open.
func _on_weather_changed(weather: int) -> void:
	if grid == null:
		return
	if weather != WorldTime.Weather.RAIN and weather != WorldTime.Weather.STORM:
		return
	var wetted := 0
	for tile: SoilTile in grid.get_tiles():
		if tile.is_tilled and tile.water():
			wetted += 1
	if wetted > 0:
		# The reported tile is the plot's own centre: rain has no single origin,
		# but a listener still wants somewhere to point a message.
		var centre := grid.tile_at(grid.global_position)
		EventBus.soil_watered.emit(
			centre.tile_index if centre != null else Vector2i(-1, -1), wetted
		)


## Which season it currently is, so planting can refuse an out-of-season crop.
##
## Walks for the [TimeService] rather than reading the clock, because the rule is
## that nothing queries the clock directly — the service publishes the date and
## anything that needs it reads [member TimeService.time]. A save loaded at a
## fixed hour still reports its real season, which is the whole point.
func _current_season() -> int:
	var time_node := _find_time_service()
	if time_node != null:
		return int(time_node.time.season)
	return WorldTime.Season.SPRING


## Whether [param actor] is close enough to [param tile] to swing at it.
func _in_reach(actor: Node3D, tile: SoilTile) -> bool:
	if actor == null or tile == null:
		return false
	return actor.global_position.distance_to(tile.global_position) <= tool_reach + tile.tile_extent()


func _grid_tiles_in_radius(centre: Vector3, radius: float) -> Array[SoilTile]:
	if grid == null:
		return []
	return grid.tiles_in_radius(centre, radius)


## The player, found by type rather than by path.
##
## Was `root/Main/Player`, which happens to be right in the shipped boot layout
## and wrong everywhere else — including any test that builds the world and
## player itself, where the whole reach check silently failed and every tool
## reported "out of reach". Searching by type is what [method _find_time_service]
## already does here, for the same reason: node *names* are a scene's business,
## not a system's.
func _find_player() -> Node3D:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search_for_player(scene_root)


static func _search_for_player(node: Node) -> Node3D:
	if node is PlayerController:
		return node as Node3D
	for child: Node in node.get_children():
		var found := _search_for_player(child)
		if found != null:
			return found
	return null


static func _find_time_service() -> TimeService:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search_for_time(scene_root)


static func _search_for_time(node: Node) -> TimeService:
	if node is TimeService:
		return node
	for child: Node in node.get_children():
		var found := _search_for_time(child)
		if found != null:
			return found
	return null