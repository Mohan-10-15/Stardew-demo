class_name InputActions
extends RefCounted
## Central registry of InputMap action names.
##
## Nothing else in the codebase should hard-code `&"move_forward"`-style
## literals. Reference these constants instead so a rename happens in one
## place and typos become compile-time-visible.

const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"

const JUMP := &"jump"
const SPRINT := &"sprint"
const CROUCH := &"crouch"

## Camera-look axes. Deliberately separate from the movement actions so an
## analog stick can drive the camera without also steering the character.
const LOOK_LEFT := &"look_left"
const LOOK_RIGHT := &"look_right"
const LOOK_UP := &"look_up"
const LOOK_DOWN := &"look_down"

const INTERACT := &"interact"
const INVENTORY := &"inventory"
const JOURNAL := &"journal"

const TOGGLE_CAMERA_MODE := &"toggle_camera_mode"
const PAUSE := &"pause"

## Shows the in-game log panel. A developer-facing action, deliberately bound to a key
## nobody plays with and deliberately *not* routed through the pause menu: a log you
## have to unpause, navigate a menu and close again to read is a log nobody reads.
const TOGGLE_LOG_PANEL := &"toggle_log_panel"

const HOTBAR_1 := &"hotbar_1"
const HOTBAR_2 := &"hotbar_2"
const HOTBAR_3 := &"hotbar_3"
const HOTBAR_4 := &"hotbar_4"
const HOTBAR_5 := &"hotbar_5"
const HOTBAR_6 := &"hotbar_6"
const HOTBAR_7 := &"hotbar_7"
const HOTBAR_8 := &"hotbar_8"
const HOTBAR_9 := &"hotbar_9"
const HOTBAR_SLOT_NEXT := &"hotbar_next"
const HOTBAR_SLOT_PREV := &"hotbar_prev"

const ZOOM_IN := &"zoom_in"
const ZOOM_OUT := &"zoom_out"


static func movement_actions() -> Array[StringName]:
	return [MOVE_FORWARD, MOVE_BACK, MOVE_LEFT, MOVE_RIGHT]


static func look_actions() -> Array[StringName]:
	return [LOOK_LEFT, LOOK_RIGHT, LOOK_UP, LOOK_DOWN]


static func hotbar_actions() -> Array[StringName]:
	return [
		HOTBAR_1, HOTBAR_2, HOTBAR_3, HOTBAR_4, HOTBAR_5,
		HOTBAR_6, HOTBAR_7, HOTBAR_8, HOTBAR_9,
	]