extends CanvasLayer
## Minimal gameplay HUD: a crosshair plus an interaction prompt.
##
## Deliberately tiny. Inventory, clock, dialogue and quests arrive in the UI
## group; this only covers what the player needs to aim and interact.

@onready var _crosshair: Control = get_node_or_null(^"Crosshair")
@onready var _prompt: Label = get_node_or_null(^"PromptContainer/PromptLabel")
@onready var _hold_bar: ProgressBar = get_node_or_null(^"PromptContainer/HoldBar")

var _probe: InteractionProbe = null


func _ready() -> void:
	if _crosshair != null:
		_crosshair.visible = true
	_set_prompt_visible(false)

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
	_probe.focus_changed.connect(_on_focus_changed)
	_probe.interacted.connect(_on_interacted)


func _process(_delta: float) -> void:
	if _probe == null:
		_attach_probe()
		if _probe == null:
			return
	_update_hold_bar()


## Late-binds to the probe, retrying until one exists.
##
## Cheap insurance rather than a bug fix: one tree scan per frame until the
## probe shows up, then this stops being called at all.
func _attach_probe() -> void:
	var found := _find_probe(get_tree().get_root())
	if found == null:
		return
	_probe = found
	_probe.focus_changed.connect(_on_focus_changed)
	_probe.interacted.connect(_on_interacted)
	# A target may already be under the crosshair by the time we bind, in which
	# case `focus_changed` will not fire again and the prompt stays hidden.
	_on_focus_changed(_probe.get_focus())


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
	if _prompt == null or _probe == null:
		return
	if target == null:
		_set_prompt_visible(false)
		return

	var actor := _probe.get_actor()
	var key := _probe.get_action_label()
	var verb := target.get_prompt(actor)
	# A timed interaction says so, otherwise the player holds and wonders.
	var suffix := " (hold)" if target.hold_seconds > 0.0 else ""
	_prompt.text = "[%s] %s%s" % [key, verb, suffix]
	_prompt.visible = true


func _on_interacted(_target: Interactable, _actor: Node) -> void:
	if _hold_bar != null:
		_hold_bar.value = 0.0