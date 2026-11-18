extends Sprite3D
## A floating ! or ? over a villager with work for the player.
##
## The quest tracker shows what the player accepted; this shows what is on offer
## before they walk over. It is a pure listener: all answers come from
## [QuestService] through the group, and the marker owns no quest state of its
## own. The two glyphs are drawn in code so no font or texture asset is needed.

const QUEST_SERVICE_GROUP := &"quest_service"

## The marks a player can see, drawn as 32x32 alpha textures.
var _mark_offer: ImageTexture = null
var _mark_ready: ImageTexture = null
var _npc_id: StringName = &""


func bind(npc_id: StringName) -> void:
	_npc_id = npc_id
	_mark_offer = _draw_bang()
	_mark_ready = _draw_question()
	# A sprite with no texture until it has an answer is an invisible marker,
	# which is exactly what a villager with nothing to say should show.
	texture = null
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	centered = true
	# `_ready` may have run before the id was bound; this is the first moment
	# the marker can answer anything, so ask now.
	_refresh()


func _ready() -> void:
	var bus := _bus()
	if bus != null:
		bus.quest_accepted.connect(_refresh)
		bus.quest_turned_in.connect(_refresh)
		bus.quest_progress_changed.connect(_on_progress)
		bus.quest_accepted_failed.connect(_refresh)
		bus.quest_turned_in_failed.connect(_refresh)
		bus.quest_service_ready.connect(_on_service_ready)
	_refresh()


func _on_service_ready() -> void:
	_refresh()


func _exit_tree() -> void:
	var bus := _bus()
	if bus == null:
		return
	if bus.quest_accepted.is_connected(_refresh):
		bus.quest_accepted.disconnect(_refresh)
	if bus.quest_turned_in.is_connected(_refresh):
		bus.quest_turned_in.disconnect(_refresh)
	if bus.quest_progress_changed.is_connected(_on_progress):
		bus.quest_progress_changed.disconnect(_on_progress)
	if bus.quest_accepted_failed.is_connected(_refresh):
		bus.quest_accepted_failed.disconnect(_refresh)
	if bus.quest_turned_in_failed.is_connected(_refresh):
		bus.quest_turned_in_failed.disconnect(_refresh)
	if bus.quest_service_ready.is_connected(_on_service_ready):
		bus.quest_service_ready.disconnect(_on_service_ready)


func _refresh(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	var service := _find_service()
	if service == null or _npc_id.is_empty():
		texture = null
		visible = false
		return
	var ready_id: StringName = service.call("ready_to_turn_in_from", _npc_id)
	var offered_id: StringName = service.call("next_offer_from", _npc_id)
	if not ready_id.is_empty():
		texture = _mark_ready
	elif not offered_id.is_empty():
		texture = _mark_offer
	else:
		texture = null
	visible = texture != null


func _on_progress(_quest_id: StringName, _current: int, _required: int) -> void:
	_refresh()


func _bus() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(^"EventBus")


func _find_service() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return _search((loop as SceneTree).root)


func _search(node: Node) -> Node:
	if node == null:
		return null
	if node.is_in_group(QUEST_SERVICE_GROUP):
		return node
	for child: Node in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


# --- The two glyphs, drawn pixel by pixel -------------------------------------

const GOLD := Color(1.0, 0.84, 0.22, 1.0)
const INK := Color(0.10, 0.08, 0.06, 1.0)
const SIZE := 32


static func _blank() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


static func _box(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y: int in range(maxi(0, y0), mini(SIZE, y1)):
		for x: int in range(maxi(0, x0), mini(SIZE, x1)):
			image.set_pixel(x, y, color)


static func _draw_bang() -> ImageTexture:
	var image := _blank()
	_box(image, 13, 4, 19, 21, INK)
	_box(image, 11, 4, 21, 8, INK)
	_box(image, 13, 6, 17, 19, GOLD)
	_box(image, 13, 23, 19, 29, INK)
	_box(image, 14, 24, 18, 28, GOLD)
	return ImageTexture.create_from_image(image)


static func _draw_question() -> ImageTexture:
	var image := _blank()
	# A blocky arc plus a stem: reads as '?' at marker size without a font.
	_box(image, 10, 5, 22, 9, INK)
	_box(image, 8, 8, 13, 15, INK)
	_box(image, 19, 8, 24, 15, INK)
	_box(image, 18, 13, 22, 19, INK)
	_box(image, 14, 17, 19, 21, INK)
	_box(image, 14, 18, 18, 20, GOLD)
	_box(image, 13, 23, 19, 29, INK)
	_box(image, 14, 24, 18, 28, GOLD)
	_box(image, 10, 6, 22, 8, GOLD)
	_box(image, 9, 9, 12, 14, GOLD)
	_box(image, 20, 9, 23, 14, GOLD)
	return ImageTexture.create_from_image(image)
