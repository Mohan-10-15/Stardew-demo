class_name InputDeviceMonitor
extends Node
## Watches raw input events so InputGlyphs knows which family the player is
## holding. `_input` (not `_unhandled_input`) is deliberate: UI panels consume
## unhandled events, and a pad press that only reaches a menu must still swap
## the glyphs.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		# Stick drift must not flip the glyphs away from the keyboard.
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < 0.5:
			return
	InputGlyphs.observe(event)
