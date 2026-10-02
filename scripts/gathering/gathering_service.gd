class_name GatheringService
extends Node
## Every rule about chopping, mining and foraging, in one place.
##
## The node holds its own state and its own artwork. The component holds the prompt
## and the press. Everything in between — what is in the player's hands, whether they
## can afford the swing, what comes out, where it lands — belongs here, because that
## is the only part that touches both the player's bag and the world.
##
## ## One check, asked twice
##
## [method status_for] answers "what would happen" and [method gather] answers "make
## it happen", and they are the same question. The prompt calls the first and the
## interact key calls the second, so a prompt can never promise a swing that is then
## refused, and a refusal can never be phrased differently from the prompt that
## invited the player to try it. Nothing here is duplicated for the HUD's benefit.
##
## ## Refusals are events, not silence
##
## Every refusal publishes [signal EventBus.gathering_failed] with a reason, and no
## two reasons sound or read alike. A keypress that does nothing and says nothing is
## the single most reported bug in a game with a tool belt, and it is always the same
## cause: the code had a `return false` with nothing on the other side of it.

## Group this node registers under, so [ResourceNodeInteractable] can find it.
##
## Duplicated as a literal in that component because a shared constant would need one
## of the two classes to name the other.
const SERVICE_GROUP := &"gathering_service"

## Emitted for every press, worked or not.
##
## Carries the verb and the node rather than a success flag, so audio can play a
## thunk for a swing that landed *and* the same thunk for one that was refused by a
## depleted stump — the thud is the same, the crack of a breaking trunk is not.
signal tool_used(action: StringName, node_id: StringName)

## How close the actor must stand. Matches
## [constant ResourceNodeInteractable.REACH]; the service re-checks it because a
## prompt is not a promise about distance — the player can walk backwards between
## reading it and pressing the key.
@export_range(1.0, 6.0, 0.1) var reach: float = 3.0

## How high a felled drop spawns above the ground, so a log does not start inside a
## collider and get ejected.
@export var drop_height: float = 0.65
## How far a drop is thrown sideways from the node that produced it. Enough to spread
## a stack of wood out instead of leaving it as one perfectly stacked column.
@export_range(0.0, 3.0, 0.1) var drop_spread: float = 0.45

## Seed for the drop scatter.
##
## Fixed rather than [method RandomNumberGenerator.randomize], because the
## amount each pile holds is already deterministic — [method ResourceNode.take_yield]
## rolls from a generator seeded to the node's identity — and having the *position*
## be random on top of that makes "fell the same wood in the same place" true of the
## numbers and false of the world. Two builds from the same seed lay the same logs in
## the same spots, which is what makes a bug report reproducible and a save's layout
## believable.
const DROP_SCATTER_SEED := 0x5EED

var _drops: Node3D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(SERVICE_GROUP)
	_rng.seed = DROP_SCATTER_SEED
	_drops = Node3D.new()
	_drops.name = "Drops"
	add_child(_drops)
	Log.info("Gathering", "Ready")


## What would happen if [param actor] pressed the key on [param node] right now.
##
## Returns `{ok, reason, verb, prompt}`:
## - `ok` — whether the press would work.
## - `reason` — empty when `ok`, otherwise the machine-readable refusal for
##   [signal EventBus.gathering_failed].
## - `verb` — `chop`, `mine` or `forage`. Reported even on a refusal, because "you
##   need an axe" is only useful if the audio knows it was a chop attempt.
## - `prompt` — the line to put in front of the player.
##
## Side-effect free. The HUD calls this every frame and it must not spend anything.
func status_for(node: ResourceNode, actor: Node) -> Dictionary:
	var none := {
		"ok": false, "reason": &"no_target", "verb": &"none", "prompt": "Nothing here",
	}
	if node == null or node.data == null:
		return none
	var verb := node.data.verb()
	var noun := node.data.describe()
	if node.depleted:
		var wait := node.progress_text()
		return {
			"ok": false,
			"reason": &"respawning",
			"verb": verb,
			"prompt": "%s — %s" % [noun, wait],
		}

	var state := _state()
	if state == null or state.hotbar == null:
		return {
			"ok": false, "reason": &"no_player_state", "verb": verb,
			"prompt": "%s the %s" % [node.data.describe_action(), noun],
		}

	var held_action := state.hotbar.get_selected_tool_action()
	var tier := state.hotbar.get_selected_tool_tier()
	var needed := node.data.tool_action

	if not needed.is_empty():
		# Tool in hand, and it is the wrong one, is a different complaint from no
		# tool at all: a player holding a hoe at a tree needs to be told to swap, and
		# a player with nothing needs to be told to go find one.
		if held_action.is_empty():
			return {
				"ok": false, "reason": &"no_tool", "verb": verb,
				"prompt": "You need a %s" % _tool_noun(needed),
			}
		if held_action != needed:
			return {
				"ok": false, "reason": &"wrong_tool", "verb": verb,
				"prompt": "%s the %s" % [node.data.describe_action(), noun],
			}
		if not node.data.accepts_tier(tier):
			return {
				"ok": false, "reason": &"needs_better_tool", "verb": verb,
				"prompt": "The %s is too hard for that tool" % noun,
			}

	# Distance before stamina. Both are refusals and neither costs anything, so the
	# order is about the *message*: a player who is too far away and too tired should
	# be told to walk over, because that is the thing still standing between them and
	# the swing. It also means walking away from a node can never leave them short of
	# stamina for a swing they were not close enough to land.
	if not _in_reach(actor, node):
		return {
			"ok": false, "reason": &"out_of_reach", "verb": verb,
			"prompt": "Move closer to the %s" % noun,
		}

	if not node.data.tool_action.is_empty():
		var cost := _held_stamina_cost(state)
		if cost > 0 and not _can_spend(state, cost):
			return {
				"ok": false, "reason": &"exhausted", "verb": verb,
				"prompt": "Too tired to %s" % _verb_word(verb),
			}

	return {
		"ok": true, "reason": &"", "verb": verb,
		"prompt": "%s the %s (%d left)" % [
			node.data.describe_action(), noun, node.hits_left(tier),
		],
	}


## Works [param node], if the player can.
##
## Returns whether anything was actually done. Every `false` has published
## [signal EventBus.gathering_failed] and [signal tool_used] first, so no caller has
## to decide whether a refusal deserves a sound — the answer is always yes.
##
## The order is deliberate: everything is *checked* before anything is *paid*.
## Charging stamina and then discovering the node refused the tier would take the
## player's stamina for a swing that never happened, which is the same class of bug
## as a shop selling into a full bag.
func gather(node: ResourceNode, actor: Node) -> bool:
	if node == null:
		tool_used.emit(&"none", &"")
		EventBus.gathering_failed.emit(&"", &"none", &"no_target")
		return false

	var status := status_for(node, actor)
	var verb := StringName(status.get("verb", &"none"))
	var node_id := node.data.id if node.data != null else &""
	if not bool(status.get("ok", false)):
		tool_used.emit(verb, node_id)
		EventBus.gathering_failed.emit(node_id, verb, StringName(status.get("reason", &"no_target")))
		return false

	var state := _state()
	var tier := state.hotbar.get_selected_tool_tier() if state != null and state.hotbar != null else 0

	# Paid for only now, when the swing is known to be affordable and legal.
	var charged := _charge_stamina(state, verb)

	var result := node.hit(tier)
	if not bool(result.get("applied", false)):
		# The node refused between the check and the hit — a respawn landing mid-press,
		# or a second press in the same frame. Give the stamina back rather than
		# charging for a swing that did not land.
		_refund_stamina(state, charged)
		tool_used.emit(verb, node_id)
		EventBus.gathering_failed.emit(node_id, verb, &"nothing_to_do")
		return false

	if not node.data.tool_action.is_empty() and state != null:
		# Only a tool wears down. Forage is picked with hands, and a berry bush does
		# not sharpen the player's teeth.
		state.spend_tool_durability(verb)

	if bool(result.get("broke", false)):
		_spawn_drops(node)

	tool_used.emit(verb, node_id)
	return true


## The drops currently lying around.
func get_drops() -> Array[ResourceDrop]:
	var out: Array[ResourceDrop] = []
	if _drops == null:
		return out
	for child: Node in _drops.get_children():
		if child is ResourceDrop:
			out.append(child as ResourceDrop)
	return out


func drop_count() -> int:
	return get_drops().size()


## Takes one pile into the bag, if the bag will take it.
##
## All or nothing, matching [method Inventory.add]: a player told a rock gave "3
## Stone" and given two is a bug report waiting to happen. A full bag leaves the pile
## on the ground and says so, so the wood is visibly still there rather than having
## quietly vanished.
func collect_drop(drop: ResourceDrop) -> bool:
	if drop == null or drop.is_collected():
		return false
	var state := _state()
	if state == null or state.inventory == null:
		EventBus.gathering_failed.emit(drop.item_id, &"pickup", &"no_player_state")
		return false
	var added := state.inventory.add(drop.item_id, drop.amount)
	if added <= 0:
		EventBus.gathering_failed.emit(drop.item_id, &"pickup", &"bag_full")
		Log.info("Gathering", "no room for %s" % drop.describe())
		return false
	drop.collect()
	EventBus.resource_collected.emit(drop.item_id, added)
	return true


## Removes every drop. For a new game, and for tests.
func clear_drops() -> void:
	for drop: ResourceDrop in get_drops():
		drop.queue_free()


## What one swing of the held item costs.
##
## Read from the held stack, not from the node: the cost belongs to the tool. Zero
## when nothing is held, and zero for anything that does not wear out — which today
## means the hoe and the watering can, whose stamina cost is [member
## ItemDefinition.stamina_cost] rather than durability-gated. See the note on
## [method ItemRegistry.stamina_cost_of].
func _held_stamina_cost(state: PlayerStateService) -> int:
	if state == null or state.hotbar == null:
		return 0
	var stack := state.hotbar.get_selected_stack()
	if stack == null:
		return 0
	return ItemRegistry.stamina_cost_of(stack.id)


func _can_spend(state: PlayerStateService, cost: int) -> bool:
	return state != null and state.stamina != null and state.stamina.can_spend(cost)


## Pays for one swing. Returns the amount charged, or -1 when refused.
##
## Mirrors [method FarmService._charge_stamina] rather than sharing it, because the
## refusal events differ: farming reports against a tile index, gathering reports
## against a node. Two three-line methods with different payloads beats one with a
## payload both callers have to unpack.
func _charge_stamina(state: PlayerStateService, verb: StringName) -> int:
	if state == null or state.stamina == null:
		# A unit test with no player state. Gathering still works; there is just
		# nothing to spend.
		return 0
	var cost := _held_stamina_cost(state)
	if cost <= 0:
		return 0
	if state.stamina.can_spend(cost):
		state.stamina.spend(cost)
		return cost
	EventBus.stamina_exhausted.emit()
	return -1


## Gives back what a swing that never landed was charged.
func _refund_stamina(state: PlayerStateService, amount: int) -> void:
	if state == null or state.stamina == null or amount <= 0:
		return
	state.stamina.restore(amount)


## Puts what a broken node gave out on the ground, one pile per line of its table.
func _spawn_drops(node: ResourceNode) -> void:
	if _drops == null or node == null:
		return
	var entries := node.take_yield()
	for i: int in range(entries.size()):
		var entry: Dictionary = entries[i]
		var item_id := StringName(entry.get("item_id", &""))
		var amount := int(entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		var drop := ResourceDrop.new()
		drop.item_id = item_id
		drop.amount = amount
		drop.name = "drop_%s" % item_id
		_drops.add_child(drop)
		# Scatter deterministically around the base so a stack of logs does not land
		# as one vertical column, and so the same tree always drops in the same
		# pattern.
		var angle := _rng.randf() * TAU
		var spread := _rng.randf_range(0.0, drop_spread)
		drop.position = node.global_position + Vector3(
			cos(angle) * spread,
			drop_height + float(i) * 0.12,
			sin(angle) * spread,
		)
		# A small shove away from the trunk, so the drop rolls clear of the collider
		# that is still about to be switched off.
		drop.linear_velocity = Vector3(cos(angle), 1.4, sin(angle)) * 1.1
		drop.pickup_requested.connect(_on_pickup_requested)
	Log.info("Gathering", "%s dropped %d kinds" % [node.data.id, entries.size()])


func _on_pickup_requested(drop: ResourceDrop) -> void:
	collect_drop(drop)


## Whether [param actor] is close enough to [param node] to work it.
##
## Horizontal distance only. A tree's volume is tall and the player aims at the
## middle of it, so measuring to the origin means a player standing at the trunk is
## "far away" from a node that is three metres over their head.
func _in_reach(actor: Node, node: ResourceNode) -> bool:
	if actor == null or not (actor is Node3D):
		# No actor means a test or a scripted interaction. Refusing here would make
		# every headless test of the rules need a player standing in the right place,
		# so absence of an actor is treated as "reach not in question".
		return true
	var from := (actor as Node3D).global_position
	var to := node.global_position
	var flat := Vector2(from.x - to.x, from.z - to.z).length()
	return flat <= reach


## The player's state, or null in a tree that has none.
func _state() -> PlayerStateService:
	return PlayerStateService.find()


## "an axe" / "a pickaxe", for the "you need one" refusal.
func _tool_noun(action: StringName) -> String:
	match action:
		&"chop":
			return "axe"
		&"mine":
			return "pickaxe"
	return "tool"


## "chop" / "mine" / "forage", as a verb phrase for "too tired to ...".
func _verb_word(verb: StringName) -> String:
	match verb:
		&"chop":
			return "chop"
		&"mine":
			return "mine"
		&"forage":
			return "forage"
	return "work"


## The whole of what is lying on the ground, for the save boundary.
func to_dict() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for drop: ResourceDrop in get_drops():
		out.append(drop.to_dict())
	return out