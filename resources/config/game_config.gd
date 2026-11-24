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
@export var ambient_volume: float = 0.8
@export var ui_volume: float = 0.9
@export var muted: bool = false

@export_group("Gameplay")
@export var camera_switch_key_action: StringName = &"toggle_camera_mode"
@export var show_debug_overlay: bool = false

@export_group("Accessibility")
## Multiplier applied to every label and button font size. 1.0 is the shipped
## size; 1.25 makes text legible on a high-DPI display without clipping rows.
@export_range(0.75, 1.5, 0.05) var ui_scale: float = 1.0
## Adds a text marker beside status colours so colour is never the only channel.
@export var colour_assist: bool = false
## Runtime key overrides: action name -> physical keycode. These are applied to
## the InputMap on boot by RebindService, so a rebind survives save and reload.
@export var bindings: Dictionary = {}
## First-day hints; skippable forever from Settings.
@export var tutorial_enabled: bool = true
## Block texture pack: hollowbrook_detailed (default) or pixel16.
@export var voxel_texture_pack: String = "hollowbrook_detailed"

@export_group("Graphics")
## 0 low, 1 medium, 2 high. An int rather than a bool because the interesting decision
## a player makes is "how much am I willing to pay", and low/high with nothing between
## forces someone with a middling machine to pick a side and then live with it.
##
## Read by [code]scripts/world/graphics_quality.gd[/code], which owns what each tier
## actually turns on. Nothing else may read it: a second place that decides what "high"
## means is a second place to forget to update.
@export_enum("Low", "Medium", "High") var graphics_quality: int = 2


func duplicate_config() -> GameConfig:
	return duplicate(true) as GameConfig