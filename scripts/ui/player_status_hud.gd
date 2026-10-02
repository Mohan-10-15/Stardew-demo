extends CanvasLayer
## The player's vital readouts: gold and stamina.
##
## ## Why this exists
##
## Every number in the game — what a seed packet costs, how long a hoe lasts,
## whether a crop is ready — is invisible until something draws it. Gold and
## stamina were the two worst omissions: both are spent constantly, both silently
## refuse when they run out, and a player watching a hoe refuse with no
## explanation has no way to tell a rules refusal from a bug. The stamina bar is
## not decoration; it is the difference between "the tool is broken" and "you are
## tired".
##
## Reads state through [PlayerStateService] rather than subscribing to every
## inventory event. The bag changes on almost every swing, and rebuilding nine slot
## labels on each one is work done to produce the same nine strings.
##
## Repaints only when a displayed value actually changes, and only on the signals
## that can change one. A HUD that re-lays-out 60 times a second to render an
## identical string is a HUD that costs frames for nothing.

@onready var _gold_label: Label = get_node_or_null(^"Panel/Column/GoldLabel")
@onready var _stamina_label: Label = get_node_or_null(^"Panel/Column/StaminaLabel")
@onready var _stamina_bar: ProgressBar = get_node_or_null(
	^"Panel/Column/StaminaRow/StaminaBar"
)

var _state: PlayerStateService = null
## Last strings and values written, so a repaint only touches a label whose text
## actually differs. `null` forces the first paint.
var _last_gold := ""
var _last_stamina_text := ""
var _last_stamina_max := -1


func _ready() -> void:
	# Below the interaction HUD (layer 10) so a prompt always draws over this.
	layer = 6
	_state = _find_state(get_tree().get_root())
	if _state == null:
		Log.warn("PlayerStatusHUD", "No PlayerStateService; gold and stamina hidden")
		return
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.stamina_changed.connect(_on_stamina_changed)
	# The service publishes its starting state during `_ready`, which may have been
	# before this node existed, so paint once immediately as well.
	_refresh()


func _on_currency_changed(_amount: int) -> void:
	_refresh()


func _on_stamina_changed(_current: int, _maximum: int) -> void:
	_refresh()


## Re-locates the state service if the one we cached is gone.
##
## `_state` is a hard reference held across the life of the HUD, and the HUD
## outlives the scene that spawned it whenever the world is rebuilt. Freed nodes
## stay referenced from GDScript, so `if _state == null` does **not** catch a
## freed instance — it passes, and the next line reads a property off a dead
## object. That is how one suite freeing its rig turned into eight unrelated
## failures in the suites that ran after it.
##
## `PlayerStateService.find()` walks the tree, so re-resolving is cheap and it is
## the only way the HUD survives a scene change it did not initiate.
func _live_state() -> PlayerStateService:
	if _state != null and is_instance_valid(_state):
		return _state
	_state = _find_state(get_tree().get_root())
	return _state


func _refresh() -> void:
	var state := _live_state()
	if state == null:
		return
	var wallet: Wallet = state.wallet
	if wallet != null and _gold_label != null:
		var text := "%dg" % wallet.gold
		if text != _last_gold:
			_last_gold = text
			_gold_label.text = text

	var pool: Stamina = state.stamina
	if pool == null:
		return
	if _stamina_bar != null and (_last_stamina_max != pool.maximum
			or _stamina_bar.max_value != pool.maximum):
		# Only rebuild the bar when the ceiling moves. Assigning `max_value` clears
		# the value, so this cannot run on every repaint or the bar would flicker.
		_last_stamina_max = pool.maximum
		_stamina_bar.max_value = pool.maximum
		_stamina_bar.min_value = 0
	if _stamina_bar != null:
		_stamina_bar.value = pool.current
	if _stamina_label != null:
		var text := "%d/%d" % [pool.current, pool.maximum]
		if text != _last_stamina_text:
			_last_stamina_text = text
			_stamina_label.text = text
		# Red when spent. A player needs to see *why* the hoe stopped working, and
		# the number alone reads as a bug report rather than a rule.
		_stamina_label.add_theme_color_override(
			"font_color",
			Color(0.90, 0.45, 0.42) if pool.is_exhausted() else Color(0.98, 0.96, 0.88)
		)


func _find_state(start: Node) -> PlayerStateService:
	if start == null:
		return null
	if start is PlayerStateService:
		return start
	for child: Node in start.get_children():
		var found := _find_state(child)
		if found != null:
			return found
	return null