extends Interactable
class_name SoilTileInteractable
## Makes one [SoilTile] usable by aiming at it and pressing the interact key.
##
## A component like every other interactable: the player never learns that soil
## tiles exist, and the tile never learns what the interact key is. The probe
## finds this by walking up from the collider it hit, so the layout is
##
##     SoilTile
##     |-- SoilMesh
##     |-- CropMesh
##     |-- AimVolume      <- on the interaction-only physics layer
##     `-- SoilTileInteractable
##
## ## The prompt is the real state machine
##
## A farming action has four verbs and no single correct prompt: a bare tile can
## be tilled, a tilled tile can be planted or watered, and a ripe one can be
## harvested. [method get_prompt] derives the verb from the tile's state rather
## than storing a string, which is why the same component works for all of them
## and why the prompt can never disagree with what pressing the key will do.

## The tile this component acts on. Assigned by [SoilTile] in `_ready`, and
## settable directly so a test can pair a tile and a component without a parent.
@export var tile_path: NodePath

var _tile: SoilTile = null


func _ready() -> void:
	super()
	if not tile_path.is_empty():
		_set_tile(get_node_or_null(tile_path) as SoilTile)
	# Normally found by walking *up*, not down. The grid nests this component
	# under an `AimVolume` body so the volume can carry the collider and this
	# carries the behaviour, which puts the tile two levels up rather than one.
	if _tile == null:
		_set_tile(_find_ancestor_tile(self))
	_refresh()


func set_tile(value: SoilTile) -> void:
	_set_tile(value)
	_refresh()


func get_tile() -> SoilTile:
	return _tile


## The middle of the aim volume, not the tile's origin.
##
## A tile's origin is on the soil surface, so aiming there points the camera at
## the ground and the ray hits the terrain instead of the volume. Overridden for
## exactly that reason; see [method Interactable.get_aim_point].
##
## Read from the actual collision shape rather than assumed, so the point stays
## inside the volume if [member FarmGrid.aim_height] is ever retuned.
func get_aim_point() -> Vector3:
	if _tile == null:
		return super()
	var volume := get_parent() as Node3D
	if volume == null:
		return _tile.global_position + Vector3(0.0, 0.2, 0.0)
	var shape := volume.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape != null and shape.shape is BoxShape3D:
		return volume.global_position + Vector3(0.0, ((shape.shape as BoxShape3D).size.y) * 0.5, 0.0)
	return volume.global_position + Vector3(0.0, 0.2, 0.0)


func _set_tile(value: SoilTile) -> void:
	if _tile == value:
		return
	if _tile != null and is_instance_valid(_tile):
		_tile.tilled_changed.disconnect(_refresh)
		_tile.watered_changed.disconnect(_refresh)
		_tile.planted.disconnect(_refresh)
	_tile = value
	if _tile != null:
		_tile.tilled_changed.connect(_refresh)
		_tile.watered_changed.connect(_refresh)
		_tile.planted.connect(_refresh)


## Re-derives availability and the prompt from the tile.
##
## Called on every tile state change rather than every frame: there is nothing
## here to poll, and polling hundreds of tiles every frame for a prompt string is
## the kind of cost that is invisible until the farm plot gets big.
func _refresh() -> void:
	one_shot = false
	enabled = _tile != null
	if _tile != null:
		# Soil is meant to be walked between, not walked on, so the reach is the
		# normal interaction distance rather than something larger.
		max_distance = 2.6
	availability_changed.emit()


func is_available(_actor: Node) -> bool:
	if _tile == null:
		return false
	return enabled


## Whether [method interact] would do something. Every tilled tile is available
## in some form — there is no tile state that cannot be acted on — so this is the
## availability gate plus nothing else. The actual per-verb conditions live in
## [method interact], which reports *why* it refused.
func can_interact(actor: Node) -> bool:
	return is_available(actor)


## Performs the action the prompt names.
##
## Failure is published as a distinct event from success, and the verb is carried
## in the payload, so the HUD can say "that needs tilling first" without this
## component knowing anything about HUD. Swallowing a refusal here would be the
## single most annoying bug in a farming game: the player presses the key and
## nothing happens and nothing says why.
func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false

	var verb := _resolve_verb()
	match verb:
		Verb.TILL:
			if _tile.till():
				interacted.emit(actor)
				return true
		Verb.PLANT:
			# Planting is delegated to [FarmService], because which seed is
			# planted comes from the player's hotbar and that is not this
			# component's business. Falling through to a refusal here would be a
			# dead key.
			return _delegate_plant(actor, verb)
		Verb.WATER:
			if _tile.water():
				interacted.emit(actor)
				return true
		Verb.HARVEST:
			return _delegate_harvest(actor, verb)
		Verb.NONE:
			pass

	EventBus.farming_failed.emit(tile_index_of(), verb_name(verb), "nothing_to_do")
	return false


## The action this tile wants, derived from its state.
##
## Order matters. A ripe crop beats everything, because the player's intent on a
## ripe tile is always to harvest it. Untilled soil can only be tilled. Tilled,
## planted soil is already growing, so watering is the only thing left to do with
## it. Tilled bare soil can be planted or watered, and planting wins because it
## is what the player is standing there for.
func _resolve_verb() -> Verb:
	if _tile == null:
		return Verb.NONE
	if _tile.is_ripe():
		return Verb.HARVEST
	if not _tile.is_tilled:
		return Verb.TILL
	if not _tile.crop_id.is_empty():
		return Verb.WATER
	return Verb.PLANT


enum Verb { NONE, TILL, PLANT, WATER, HARVEST }


static func verb_name(verb: Verb) -> StringName:
	match verb:
		Verb.TILL:
			return &"till"
		Verb.PLANT:
			return &"plant"
		Verb.WATER:
			return &"water"
		Verb.HARVEST:
			return &"harvest"
	return &"none"


## "Till the soil", "Harvest parsnip", "Water the crop".
##
## Reads the crop's display name rather than its id, so the prompt says
## "Harvest parsnip" and not "Harvest parsnip" only by coincidence of the id.
func get_prompt(_actor: Node) -> String:
	if _tile == null:
		return "Nothing here"
	match _resolve_verb():
		Verb.TILL:
			return "Till the soil"
		Verb.PLANT:
			return "Plant a seed"
		Verb.WATER:
			return "Water the soil"
		Verb.HARVEST:
			var data := CropRegistry.get_crop(_tile.crop_id)
			if data != null:
				return "Harvest %s" % data.display_name
			return "Harvest"
	return "Nothing here"


## The action name for the current tile, for a HUD readout or a test.
func get_current_verb() -> StringName:
	return verb_name(_resolve_verb())


## Which tile, for an event payload when this component has no tile.
func tile_index_of() -> Vector2i:
	return _tile.tile_index if _tile != null else Vector2i(-1, -1)


## Tilling and watering are entirely local, so this component does them itself.
## Planting and harvesting need the player's inventory and the seed the hotbar
## is holding, so they go out through the [FarmService] that the boot sequence
## publishes.
##
## The service is found the same way [ClockHUD] finds the clock — by name, from
## the tree root — because an autoload is not a global identifier inside a
## `--script` run, and a typed reference to it would make this file pull the
## service into a tool's compile and reintroduce that trap.
func _delegate_plant(actor: Node, verb: Verb) -> bool:
	var service := _find_service()
	if service == null:
		EventBus.farming_failed.emit(tile_index_of(), verb_name(verb), "no_farm_service")
		return false
	# `call` rather than `service.plant(...)`. See [method _find_service] for why
	# this component is not typed against [FarmService].
	if bool(service.call("plant", _tile, actor)):
		interacted.emit(actor)
		return true
	return false


func _delegate_harvest(actor: Node, verb: Verb) -> bool:
	var service := _find_service()
	if service == null:
		EventBus.farming_failed.emit(tile_index_of(), verb_name(verb), "no_farm_service")
		return false
	if bool(service.call("harvest", _tile, actor)):
		interacted.emit(actor)
		return true
	return false


## The [FarmService], found by name from the tree root.
##
## Typed as a bare [Node] and called dynamically, deliberately. Naming
## `FarmService` here would close a `class_name` loop:
##
##     FarmGrid -> SoilTileInteractable -> FarmService -> FarmGrid
##
## GDScript resolves a cycle by compiling against a partial class, and the
## resulting errors point at innocent bystanders (a `get_stack` "not found" three
## files away) rather than at the real cycle. So this edge stays untyped: the
## farm service owns the inventory rules, and this component only needs to know
## that *something* on the root can plant and harvest.
##
## Found by name rather than by reference because the grid is generated deep
## inside the world scene, and threading a service reference into it would make
## the world depend on the player's bag.
static func _find_service() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search_for_service(scene_root)


static func _search_for_service(node: Node) -> Node:
	if node.get_script() != null and node.has_method("plant") and node.has_method("harvest"):
		return node
	for child: Node in node.get_children():
		var found := _search_for_service(child)
		if found != null:
			return found
	return null


## Nearest [SoilTile] at or above [param from].
##
## Walks up rather than searching the whole subtree: a tile's own descendants are
## meshes, and one of *its sibling* tiles is not this component's business. Going
## upwards is the only direction where "is this mine?" has a definite answer.
static func _find_ancestor_tile(from: Node) -> SoilTile:
	var node := from
	while node != null:
		if node is SoilTile:
			return node
		node = node.get_parent()
	return null