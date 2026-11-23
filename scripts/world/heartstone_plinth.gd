extends Interactable
## The empty plinth in the village square. It shows the live Ember count and
## starts The Mending only when all six are home. A closed plinth never
## silently does nothing: it publishes its state so the HUD can say why.

@export var needed: int = 6

var _state: HeartstoneState = null


func _ready() -> void:
	super()
	prompt_text = "Examine the Heartstone plinth"
	_state = _find_state(get_tree().get_root())


func get_prompt(actor: Node) -> String:
	if _state == null:
		_state = _find_state(get_tree().get_root())
	if _state != null and _state.can_mend():
		return "Mend the Heartstone"
	return "Examine the Heartstone plinth (%d/%d Embers)" % [
		_state.count() if _state != null else 0, needed,
	]


func interact(actor: Node) -> bool:
	if not super(actor):
		return false
	if _state == null:
		_state = _find_state(get_tree().get_root())
	var count := _state.count() if _state != null else 0
	EventBus.plinth_inspected.emit(count, needed)
	if _state != null and _state.can_mend():
		EventBus.cutscene_requested.emit(&"the_mending")
	return true


static func _find_state(node: Node) -> HeartstoneState:
	if node == null:
		return null
	var main := node.get_node_or_null(^"Main")
	if main != null and main.get("heartstone") != null:
		return main.get("heartstone") as HeartstoneState
	for child: Node in node.get_children():
		var found := _find_state(child)
		if found != null:
			return found
	return null
