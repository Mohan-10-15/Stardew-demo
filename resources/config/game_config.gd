class_name GameConfig
extends Resource
## Typed schema for the game's persisted configuration.
##
## This is the *shape* of the configuration. Actual values live in
## [ConfigService], which reads/writes `user://config.cfg` and keeps an
## instance of this resource in memory.

@export_group("Display")
@export var fullscreen: bool = false
@export var window_width: int = 1280
@export var window_height: int = 720
@export var vsync_enabled: bool = true

@export_group("Camera")
@export_enum("First Person", "Third Person") var default_camera_mode: int = 0
@export var mouse_sensitivity: float = 0.0035
@export var invert_y: bool = false
@export var fov: float = 78.0

@export_group("Audio")
@export var master_volume: float = 1.0
@export var music_volume: float = 0.8
@export var sfx_volume: float = 1.0

@export_group("Gameplay")
@export var camera_switch_key_action: StringName = &"toggle_camera_mode"
@export var show_debug_overlay: bool = false


func duplicate_config() -> GameConfig:
	return duplicate(true) as GameConfig