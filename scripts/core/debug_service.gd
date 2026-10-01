extends Node
## Autoload: `Debug`
##
## Lightweight in-game debug utilities. Toggles UI overlay and exposes
## performance counters for later profiling.
##
## The overlay is visible only if `Config.settings.show_debug_overlay` is true.

var _overlay: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	EventBus.config_changed.connect(_on_config_changed)


func _build_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DebugOverlay"
	canvas.layer = 999
	canvas.visible = Config.settings.show_debug_overlay
	add_child(canvas)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_overlay)

	var vbox := VBoxContainer.new()
	vbox.name = "Vbox"
	vbox.anchor_right = 0.0
	vbox.anchor_bottom = 0.0
	vbox.offset_left = 12.0
	vbox.offset_top = 12.0
	_overlay.add_child(vbox)

	var fps_label := Label.new()
	fps_label.name = "FpsLabel"
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	fps_label.add_theme_constant_override("shadow_offset_x", 1)
	fps_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(fps_label)

	var mem_label := Label.new()
	mem_label.name = "MemLabel"
	vbox.add_child(mem_label)

	_update_labels(fps_label, mem_label)
	var timer := Timer.new()
	timer.name = "UpdateTimer"
	timer.autostart = true
	timer.wait_time = 0.25
	timer.timeout.connect(func(): _update_labels(fps_label, mem_label))
	_overlay.add_child(timer)


func _update_labels(fps_label: Label, mem_label: Label) -> void:
	var fps := Engine.get_frames_per_second()
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	fps_label.text = "FPS: %d" % fps
	mem_label.text = "MEM: %.1f MB" % mem


func _on_config_changed(section: StringName) -> void:
	if _overlay == null or _overlay.get_parent() == null:
		return
	_overlay.get_parent().visible = Config.settings.show_debug_overlay


func toggle() -> void:
	Config.settings.show_debug_overlay = not Config.settings.show_debug_overlay
	Config.set_value(&"gameplay", "show_debug_overlay", Config.settings.show_debug_overlay)