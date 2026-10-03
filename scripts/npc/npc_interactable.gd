extends Interactable
class_name NpcInteractable
## Makes one villager talkable and giftable by aiming at them and pressing interact.
##
## A component like every other interactable: the player does not learn that villagers
## exist, and a villager does not learn what the interact key is. Same layout as
## [ResourceNodeInteractable], with the aim volume between body and component because
## the component has to be a sibling of the collider the ray actually hits:
##
##     Npc
##     |-- CollisionShape3D<- on the NPC layer, what you walk into
##     |-- Model
##     `-- AimVolume        <- on the interaction-only layer, what the ray finds
##         |-- CollisionShape3D
##         `-- Interactable
##
## ## The prompt is the rule check
##
## [method get_prompt] and [method interact] both ask [NpcManager], via
## [method _preview], what would happen and then render or perform exactly that. One
## source of truth means the prompt cannot promise a gift the press then refuses,
## which is the failure this whole class exists to make impossible.
##
## ## One key, two meanings
##
## There is no separate "give gift" button. Holding a giftable item makes interact
## *give* it, and holding anything else — or nothing — makes interact *talk*. The
## prompt always says which, so the key is never a mystery: "Give the wild berry" or
## "Talk to Mira". One context key is what the controller already has, and a second
## one would mean teaching the player a modifier nobody asked for. The cost is that
## you cannot greet someone while holding a parsnip, which is why talk and gift are
## separate signals rather than one "interacted" event.

## The villager this component acts on. Bound by [NpcManager] before it enters the
## tree, and settable directly so a test can pair a villager and a component without
## building a whole cast.
var _npc: Npc = null

## Group [NpcManager] registers under, and this component searches for.
##
## Duplicated as a literal rather than shared, for the reason spelled out at length in
## [method SoilTileInteractable._find_service]: the constant would have to live on one
## of the two classes, and naming the other to reach it closes the `class_name` cycle
## that `NpcManager -> Npc -> NpcInteractable -> NpcManager` is. `_find_manager` and
## that function fail loudly if the two ever drift.
const SERVICE_GROUP := &"npc_service"

## How close the player has to stand. Further than the farm's 2.6 and the same as a
## tree's 3.0: a villager is a person-sized thing and standing inside one to talk to
## them is not a thing anyone should have to do.
const REACH := 3.0


func _ready() -> void:
	super()
	if _npc == null:
		_npc = _find_ancestor_npc(self)
	set_meta(&"npc_interactable", true)
	_refresh()


## Pairs this component with [param value].
func bind(value: Npc) -> void:
	_npc = value
	_refresh()


func get_npc_ref() -> Npc:
	return _npc


func npc_id_of() -> StringName:
	return _npc.data.id if _npc != null and _npc.data != null else &""


## The middle of the villager's body, not their feet.
##
## A villager's origin is on the ground, so aiming there points the camera at the dirt
## and the ray finds the terrain instead of the person. See
## [method Interactable.get_aim_point].
func get_aim_point() -> Vector3:
	if _npc == null:
		return super()
	return _npc.global_position + Vector3(0.0, _npc.aim_height() * 0.5, 0.0)


func _refresh() -> void:
	one_shot = false
	enabled = _npc != null
	max_distance = REACH
	availability_changed.emit()


## A villager is always available, even one who has had today's gifts.
##
## Not available in the sense of "this will do something" — [method interact] refuses
## a spent villager with a reason. Available in the sense of "keep showing me this",
## because the refusal *is* the information: a prompt that vanishes the moment the
## weekly budget runs out leaves the player holding a key with nothing happening and
## nothing said.
func is_available(_actor: Node) -> bool:
	if _npc == null:
		return false
	return enabled


func can_interact(actor: Node) -> bool:
	return is_available(actor)


## What the player would do right now, as `{"action", "text", "ok", "reason",
## "reaction"}`.
##
## The single decision point. The prompt renders [code]text[/code] and
## [method interact] performs [code]action[/code], so the two can never disagree —
## and a test can assert on the decision without a tree, a camera or a keypress.
func preview(actor: Node) -> Dictionary:
	if _npc == null:
		return _decision(&"none", "Nothing here", false, &"no_npc")
	if _npc.data == null:
		return _decision(&"none", "Nobody here", false, &"nothing_to_say")
	var manager := _find_manager()
	if manager == null:
		return _decision(&"none", _npc.describe(), false, &"no_npc_service")
	var state := PlayerStateService.find()
	if state == null:
		return _decision(&"none", _npc.describe(), false, &"no_player_state")

	var held: Dictionary = state.call("held_item_id", actor)
	var item_id := StringName(str(held.get("id", &"")))
	var item: ItemDefinition = held.get("item") as ItemDefinition
	var gift: Dictionary = _npc.gift_preview(item)

	# Talking is always allowed, so it is the fallback whenever a gift would not be.
	# A refused gift must not refuse the whole key: the player is holding a rake and
	# wants to say hello, and "not_giftable" should mean "talk instead", not "nothing
	# happens".
	if bool(gift.get("ok", false)):
		var item_name: String = String(held.get("display_name", item_id))
		return _decision(&"gift", "Give the %s" % item_name, true, &"", item_id,
			StringName(gift.get("reaction", &"")))

	if item_id.is_empty():
		return _decision(&"talk", "Talk to %s" % _npc.data.display_name, true, &"", &"",
			StringName(gift.get("reaction", &"")))

	# Holding something that will not be given. Talk is still on the table, and the
	# prompt says so, but the refusal is carried along so a caller that cares can say
	# *why* the gift is not happening rather than silently downgrading.
	var reaction := StringName(gift.get("reaction", &""))
	var reason := StringName(gift.get("reason", &"not_giftable"))
	return _decision(&"talk", "Talk to %s" % _npc.data.display_name, true, &"", item_id,
		reaction, reason)


## "Give the wild berry" or "Talk to Mira".
func get_prompt(actor: Node) -> String:
	return String(preview(actor).get("text", ""))


## Talks, or gives a gift.
##
## Returns false only when the interaction itself was refused — no villager, no
## manager, no player state. A refused *gift* still returns true, because the press
## did what the prompt said it would: said hello.
func interact(actor: Node) -> bool:
	var decision := preview(actor)
	var npc_id := npc_id_of()
	if StringName(decision.get("action", &"")) == &"none":
		EventBus.npc_talk_failed.emit(npc_id, StringName(decision.get("reason", &"no_npc")))
		return false

	var manager := _find_manager()
	if manager == null:
		EventBus.npc_talk_failed.emit(npc_id, &"no_npc_service")
		return false

	# `call`, not `manager.talk(...)`. Naming the manager here would close a cycle:
	# the manager knows about [Npc], and this component would then know about the
	# manager. Same bargain as [ResourceNodeInteractable.interact].
	if StringName(decision.get("action", &"")) == &"gift":
		var item_id := StringName(decision.get("item_id", &""))
		var ok := bool(manager.call("give_gift", _npc, item_id, actor))
		if ok:
			# Hold still for the exchange rather than pacing out of the conversation.
			_npc.attending = true
			interacted.emit(actor)
		return ok

	var ok := bool(manager.call("talk", _npc, actor))
	if ok:
		interacted.emit(actor)
	return ok


func _decision(action: StringName, text: String, ok: bool, reason: StringName,
		item_id: StringName = &"", reaction: StringName = &"",
		downgrade_reason: StringName = &"") -> Dictionary:
	return {
		"action": action, "text": text, "ok": ok, "reason": reason,
		"item_id": item_id, "reaction": reaction, "downgrade_reason": downgrade_reason,
	}


## The [NpcManager], found by group from the tree root.
##
## Typed as a bare [Node] and called dynamically, for the reason spelled out at length
## in [method SoilTileInteractable._find_service]: naming the manager here makes
## `NpcManager -> Npc -> NpcInteractable -> NpcManager`, and GDScript reports that as
## errors in unrelated files.
static func _find_manager() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var scene_root := (loop as SceneTree).root
	if scene_root == null:
		return null
	return _search_by_group(scene_root, SERVICE_GROUP)


## Depth-first search for the first node in [param group].
##
## A group rather than a name or a singleton, because the manager is *found* rather than
## reached: a test can drop a second cast anywhere in the tree and both keep working.
static func _search_by_group(node: Node, group: StringName) -> Node:
	if node.is_in_group(group):
		return node
	for child: Node in node.get_children():
		var found := _search_by_group(child, group)
		if found != null:
			return found
	return null


static func _find_ancestor_npc(from: Node) -> Npc:
	var node := from
	while node != null:
		if node is Npc:
			return node as Npc
		node = node.get_parent()
	return null