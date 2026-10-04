extends CanvasLayer
## Minimal gameplay HUD: a crosshair plus an interaction prompt.
##
## Deliberately tiny. Inventory, clock, dialogue and quests arrive in the UI
## group; this only covers what the player needs to aim and interact.
##
## ## The prompt is re-rendered, not cached
##
## The obvious version of this node renders the prompt once, when focus changes. That is
## wrong the moment the prompt depends on state the player can change without moving the
## crosshair, and all four of these were found by [code]tools/playtest_npc.gd[/code] rather
## than by reading the code:
##
## - Give Mira a berry, and the label still promises "Give the Wild Berry" while the press
##   now says hello. She is full for the day; the prompt did not know.
## - Switch from a berry to the axe without looking away, and the label still offers a gift
##   the player is no longer holding.
## - Empty a stack in the bag and the label still names an item that is gone.
##
## So the prompt is rebuilt on the probe's focus and interaction signals *and* on the
## [signal EventBus.hotbar_selection_changed], [signal EventBus.inventory_changed] and
## [signal EventBus.npc_friendship_changed] signals. One label, a handful of cheap string
## builds, and the promise on screen is the promise the key will keep.

@onready var _crosshair: Control = get_node_or_null(^"Crosshair")
@onready var _prompt: Label = get_node_or_null(^"PromptContainer/PromptLabel")
@onready var _hold_bar: ProgressBar = get_node_or_null(^"PromptContainer/HoldBar")
@onready var _notice: Label = get_node_or_null(^"PromptContainer/NoticeLabel")

## How long a notice stays up. Long enough to read one line, short enough that a
## second event does not land on top of a forgotten first one.
const NOTICE_SECONDS := 3.0

var _probe: InteractionProbe = null
var _watching_state := false
var _notice_left := 0.0


func _ready() -> void:
	if _crosshair != null:
		_crosshair.visible = true
	_set_prompt_visible(false)
	_set_notice("")
	# Connected here rather than in `_watch_state`, which is about the *prompt*'s
	# dependencies: a tool breaking does not change what any key will do, it changes
	# what the player needs to be told.
	EventBus.tool_broken.connect(_on_tool_broken)

	_probe = _find_probe(get_tree().get_root())
	if _probe == null:
		# `main.gd` spawns the player before the HUD, and `add_child` runs
		# `_ready` synchronously, so in the normal boot order the probe is
		# already here. Any other order (a HUD opened before a player, a
		# cutscene that spawns one later) should still end up bound rather
		# than leaving the prompt permanently dead, so `_process` keeps
		# retrying.
		Log.info("InteractionHUD", "No InteractionProbe in the tree; retrying each frame")
		return
	_bind_probe()


func _process(delta: float) -> void:
	# Ahead of the probe search, deliberately. The two are unrelated, and putting the
	# countdown behind `if _probe == null: return` means a notice never expires in any
	# tree without a player — which is also why it looked fine in the game and failed in
	# the test that actually looked.
	_tick_notice(delta)
	if _probe == null:
		_attach_probe()
		if _probe == null:
			return
	_update_hold_bar()


## Late-binds to the probe, retrying until one exists.
##
## Cheap insurance rather than a bug fix: one tree scan per frame until the probe
## shows up, then this stops being called at all.
func _attach_probe() -> void:
	var found := _find_probe(get_tree().get_root())
	if found == null:
		return
	_probe = found
	_bind_probe()
	# A target may already be under the crosshair by the time we bind, in which
	# case `focus_changed` will not fire again and the prompt stays hidden.
	_on_focus_changed(_probe.get_focus())


## Every input to the prompt, in one place, so the two ways of binding cannot drift.
func _bind_probe() -> void:
	_probe.focus_changed.connect(_on_focus_changed)
	_probe.interacted.connect(_on_interacted)
	_watch_state(true)


func _update_hold_bar() -> void:
	if _hold_bar == null:
		return
	var target := _probe.get_focus() if _probe != null else null
	if target == null or target.hold_seconds <= 0.0:
		_hold_bar.visible = false
		return
	_hold_bar.visible = true
	_hold_bar.value = clampf(_probe.get_hold_progress() * 100.0, 0.0, 100.0)


func _set_prompt_visible(value: bool) -> void:
	if _prompt != null:
		_prompt.visible = value
	if _hold_bar != null:
		_hold_bar.visible = false


func _find_probe(start: Node) -> InteractionProbe:
	if start == null:
		return null
	if start is InteractionProbe:
		return start
	for child: Node in start.get_children():
		var found := _find_probe(child)
		if found != null:
			return found
	return null


func _on_focus_changed(target: Interactable) -> void:
	# Tell the crosshair, not just the label. It draws a bare dot when nothing is
	# focused and grows arms when something is, and that was the only difference
	# between "aiming at a note" and "aiming at thin air" — except nothing ever
	# called `set_focused`, so the player got a 3px dot in every direction and no
	# way to tell whether the crosshair had resolved a target.
	if _crosshair != null and _crosshair.has_method(&"set_focused"):
		_crosshair.call(&"set_focused", target != null)
	_refresh_prompt()


func _on_interacted(_target: Interactable, _actor: Node) -> void:
	if _hold_bar != null:
		_hold_bar.value = 0.0
	# The interaction may have changed the very state the prompt is made of: a gift
	# spends the villager's day, a purchase empties a slot. Rebuild rather than assume.
	_refresh_prompt()


## Rebuilds the prompt label from whatever is under the crosshair *right now*.
func _refresh_prompt() -> void:
	if _prompt == null or _probe == null:
		return
	var target := _probe.get_focus()
	if target == null:
		_set_prompt_visible(false)
		return

	var actor := _probe.get_actor()
	var key := _probe.get_action_label()
	var verb := target.get_prompt(actor)
	# A timed interaction says so, otherwise the player holds and wonders.
	var suffix := " (hold)" if target.hold_seconds > 0.0 else ""
	# And why the interesting option is missing, when the target can say. Kept off the
	# prompt proper so the verb stays scannable.
	var note := target.get_prompt_note(actor)
	var tail := " — %s" % note if not note.is_empty() else ""
	_prompt.text = "[%s] %s%s%s" % [key, verb, suffix, tail]
	_prompt.visible = true


## Connects the three bus signals the prompt depends on, once.
func _watch_state(value: bool) -> void:
	if value == _watching_state:
		return
	_watching_state = value
	if value:
		EventBus.hotbar_selection_changed.connect(_refresh_prompt)
		EventBus.inventory_changed.connect(_refresh_prompt)
		EventBus.npc_friendship_changed.connect(_on_friendship_changed)
	else:
		EventBus.hotbar_selection_changed.disconnect(_refresh_prompt)
		EventBus.inventory_changed.disconnect(_refresh_prompt)
		EventBus.npc_friendship_changed.disconnect(_on_friendship_changed)


## A villager's standing moved, so whether they can take a present may have moved with it.
func _on_friendship_changed(_npc_id: StringName, _hearts: int, _tier_name: String) -> void:
	_refresh_prompt()


## The held tool wore out and is gone from the bag.
##
## [signal EventBus.tool_broken] had no subscriber anywhere in the project: the stack was
## removed, the held slot went empty, and the player was left swinging at the soil with
## nothing in hand and no reason given. A tool that disappears without a word is
## indistinguishable from a bug, and the empty hand it leaves behind is the part that
## actually costs the player — the tool has to be bought again.
func _on_tool_broken(item_id: StringName) -> void:
	_set_notice("Your %s broke." % ItemRegistry.display_name_of(item_id))


func _set_notice(text: String) -> void:
	_notice_left = 0.0
	if _notice == null:
		return
	_notice.text = text
	_notice.visible = not text.is_empty()


func _tick_notice(delta: float) -> void:
	if _notice == null or not _notice.visible:
		return
	_notice_left += delta
	if _notice_left >= NOTICE_SECONDS:
		_set_notice("")