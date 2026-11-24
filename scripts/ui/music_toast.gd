extends CanvasLayer
## W6.6: a brief "Now playing" toast, off when the setting says off.

@onready var _label: Label = get_node_or_null(^"Panel/Text") as Label

var _left: float = 0.0


func _ready() -> void:
	layer = 17
	process_mode = Node.PROCESS_MODE_ALWAYS
	var director := MusicDirector.find(get_tree().root)
	if director != null and not director.now_playing.is_connected(_on_now_playing):
		director.now_playing.connect(_on_now_playing)
	visible = false


func _on_now_playing(title: String) -> void:
	if not Config.settings.now_playing_toast or _label == null:
		return
	_label.text = "Now playing — " + title
	_left = 3.0
	visible = true


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
