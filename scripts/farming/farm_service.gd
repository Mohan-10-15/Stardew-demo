class_name FarmService
extends Node
## The player-facing farming system: what the tools do, what the seeds cost, what
## comes back from a harvest.
##
## The one node that knows about soil, inventory and the hotbar at the same time.
## Everything below it is pure: [SoilTile] knows the rules for a tile, [Inventory]
## knows the rules for a bag, [CropData] knows what a crop is. This node's whole
## job is to ask each of them the right question and publish the outcome.
##
## It lives at the tree root as `FarmService` because
## [SoilTileInteractable] finds it by name. That lookup is deliberate rather than
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

## The player's bag.
@export var inventory: Inventory
## The player's nine slots.
@export var hotbar: Hotbar

## Kept as an id list rather than typed [Hotbar] references in the generator's
## docs: `class_name` cycles are the documented trap in `AGENTS.md`, and this is
## the only place that legitimately needs to name three other classes at once.

## How far the current tool reaches, in metres. Deliberately not the interact
## range: swinging a hoe should need you to be standing on the tile, which is what
## makes a 35-tile plot a chore rather than a formality.
@export var tool_reach: float = 1.9
## Radius of a tool's effect around the aimed tile. Greater than one tile so a
## hoe clears a 3x3, which is the one concession to not being tediously fiddly.
@export var tool_radius: float = 1.1

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if inventory == null:
		inventory = Inventory.new(24)
	if hotbar == null:
		hotbar = Hotbar.new(inventory)
	elif hotbar.inventory == null:
		hotbar.inventory = inventory
	if grid != null:
		grid.grid_origin = grid.global_position

	# One subscription, one direction. The service learns that a day began from
	# the clock; it never asks the clock anything.
	EventBus.day_started.connect(_on_day_started)
	EventBus.weather_changed.connect(_on_weather_changed)
	# The bag has no idea who owns it, so it publishes locally and this relays.
	# See the `contents_changed` signal's docs in `inventory.gd`.
	if inventory != null:
		inventory.contents_changed.connect(_on_inventory_changed)

	Log.info("FarmService", "Ready (%d tiles, %d bag slots)" % [
		grid.tile_count() if grid != null else 0,
		inventory.slot_count() if inventory != null else 0,
	])


## Registers the newly built grid. Called by `main.gd` after the world exists,
## because the grid is generated inside the world scene and there is nothing to
## attach to before then.
func attach_grid(value: FarmGrid) -> void:
	grid = value


## Gives the player a new game loadout: a hoe, a watering can and a few parsnip
## seeds, so the first minute of play can actually be played.
func grant_starter_loadout() -> void:
	if inventory == null:
		return
	inventory.add(&"hoe", 1)
	inventory.add(&"watering_can", 1)
	inventory.add(&"parsnip_seeds", 15)
	# Selecting the hoe by default means the player's first click on the field
	# does something, rather than the prompt saying "plant a seed" over a bag
	# that has no seeds in it.
	if hotbar != null:
		hotbar.select(0)
	Log.info("FarmService", "Granted starter loadout")


## The tool action the held slot provides, or empty when nothing is held.
##
## Read straight from the hotbar rather than cached, so switching slots and then
## swinging always uses the newly held tool.
func current_tool_action() -> StringName:
	if hotbar == null:
		return &""
	return hotbar.get_selected_tool_action()


## Swings the held tool at [param target], if the player is close enough.
##
## Returns how many tiles were actually changed. A zero return is the tool
## whiffing — out of reach, or aimed at nothing — and the caller decides whether
## that deserves a sound. Success and failure are published separately by the
## tile, so the HUD's "tilled 3 tiles" and the audio's "thunk" come from
## different places and cannot drift.
func use_tool(target: SoilTile) -> int:
	if target == null:
		tool_used.emit(&"", Vector2i(-1, -1))
		EventBus.farming_failed.emit(Vector2i(-1, -1), &"tool", "no_target")
		return 0

	var action := current_tool_action()
	var actor_node := _find_player()
	if actor_node == null or not _in_reach(actor_node as Node3D, target):
		tool_used.emit(action, target.tile_index)
		EventBus.farming_failed.emit(target.tile_index, action, "out_of_reach")
		return 0

	var affected := _affected_tiles(target)
	var changed := 0
	for tile: SoilTile in affected:
		if _apply_tool(tile, action):
			changed += 1

	tool_used.emit(action, target.tile_index)
	_spend_durability(action)
	return changed


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
## The yield only reaches the inventory if it fits. If the bag is full the crop
## stays in the ground and the refusal is published — losing a harvest because the
## bag was full, with a message saying "nothing happened", is worse than not
## having harvested.
func harvest(target: SoilTile, actor: Node) -> bool:
	if target == null:
		EventBus.farming_failed.emit(Vector2i(-1, -1), &"harvest", "no_target")
		return false
	var result := target.harvest()
	if not bool(result["ok"]):
		EventBus.farming_failed.emit(
			target.tile_index, &"harvest", StringName(str(result["reason"]))
		)
		return false

	var crop_id := StringName(str(result["crop_id"]))
	var amount := int(result["amount"])
	if inventory != null:
		var added := inventory.add(crop_id, amount)
		if added <= 0:
			# Too late — the crop is already off the plant. Put it back so the
			# player can clear a slot and come back for it.
			target.plant(crop_id)
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


func _spend_durability(action: StringName) -> void:
	if inventory == null or hotbar == null or action.is_empty():
		return
	var stack := hotbar.get_selected_stack()
	if stack == null:
		return
	var definition := ItemRegistry.get_item(stack.id)
	if definition == null or not definition.uses_durability:
		return
	# Durability is a property of the *stack*, not of the item definition, so two
	# hoes bought on different days can wear out at different times. Reduced
	# rather than modelled per-stack until the economy group needs the detail.
	if definition.durability <= 1:
		inventory.remove(stack.id, 1)
		tool_broken.emit(stack.id)
		Log.info("FarmService", "%s wore out" % definition.display_name)
	else:
		EventBus.inventory_changed.emit()


## Midnight on the farm.
##
## Crops grow only if they were watered during the day. The flag is *not* cleared
## first: a crop that was watered and grows today must keep its watered state for
## tomorrow's check, or nothing would ever grow twice. [method SoilTile.on_new_day]
## does the clearing, and it happens after this.
## The bag changed, so the world hears about it.
##
## One relay for the whole bag rather than a publish per mutating call site. The
## alternative — `EventBus.inventory_changed` sprinkled through `add`, `remove`,
## `move_slots`, `resize`, `set_contents` and `from_dict` — means adding a sixth
## mutator later silently forgets to notify, and the bug only shows up as a
## stale HUD.
##
## Note this file *can* use `EventBus`, unlike `inventory.gd`: it is only ever
## loaded as a scene node, never from a `--script` run.
func _on_inventory_changed() -> void:
	EventBus.inventory_changed.emit()


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


func _find_player() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"Main/Player")


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