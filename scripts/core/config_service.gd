extends Node
## Autoload: `Config`
##
## Configuration system. Loads/saves `user://config.cfg`, exposes a typed
## [GameConfig] and applies engine-facing settings (window, vsync).
##
## Signals every change on `EventBus.config_changed` so UI and gameplay code
## never need to poll.

const CONFIG_PATH := "user://config.cfg"

var settings: GameConfig


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = GameConfig.new()
	load_config()
	apply_settings()
	Log.info("Config", "Loaded configuration from %s" % CONFIG_PATH)


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		Log.info("Config", "No config file found, using defaults")
		settings = GameConfig.new()
		return
	settings = GameConfig.new()
	settings.fullscreen = bool(cfg.get_value("display", "fullscreen", settings.fullscreen))
	settings.window_width = int(cfg.get_value("display", "window_width", settings.window_width))
	settings.window_height = int(cfg.get_value("display", "window_height", settings.window_height))
	settings.vsync_enabled = bool(cfg.get_value("display", "vsync_enabled", settings.vsync_enabled))
	settings.default_camera_mode = int(cfg.get_value("camera", "default_camera_mode", settings.default_camera_mode))
	settings.mouse_sensitivity = float(cfg.get_value("camera", "mouse_sensitivity", settings.mouse_sensitivity))
	settings.invert_y = bool(cfg.get_value("camera", "invert_y", settings.invert_y))
	settings.fov = float(cfg.get_value("camera", "fov", settings.fov))
	settings.master_volume = float(cfg.get_value("audio", "master_volume", settings.master_volume))
	settings.music_volume = float(cfg.get_value("audio", "music_volume", settings.music_volume))
	settings.sfx_volume = float(cfg.get_value("audio", "sfx_volume", settings.sfx_volume))
	settings.camera_switch_key_action = StringName(cfg.get_value("gameplay", "camera_switch_key_action", String(settings.camera_switch_key_action)))
	settings.show_debug_overlay = bool(cfg.get_value("gameplay", "show_debug_overlay", settings.show_debug_overlay))


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", settings.fullscreen)
	cfg.set_value("display", "window_width", settings.window_width)
	cfg.set_value("display", "window_height", settings.window_height)
	cfg.set_value("display", "vsync_enabled", settings.vsync_enabled)
	cfg.set_value("camera", "default_camera_mode", settings.default_camera_mode)
	cfg.set_value("camera", "mouse_sensitivity", settings.mouse_sensitivity)
	cfg.set_value("camera", "invert_y", settings.invert_y)
	cfg.set_value("camera", "fov", settings.fov)
	cfg.set_value("audio", "master_volume", settings.master_volume)
	cfg.set_value("audio", "music_volume", settings.music_volume)
	cfg.set_value("audio", "sfx_volume", settings.sfx_volume)
	cfg.set_value("gameplay", "camera_switch_key_action", String(settings.camera_switch_key_action))
	cfg.set_value("gameplay", "show_debug_overlay", settings.show_debug_overlay)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		Log.error("Config", "Failed to save config: %d" % err)
	else:
		Log.info("Config", "Saved configuration")


func apply_settings() -> void:
	var window := get_window()
	if window == null:
		return
	var mode: Window.Mode = (
		Window.MODE_FULLSCREEN if settings.fullscreen else Window.MODE_WINDOWED
	)
	window.mode = mode
	if not settings.fullscreen:
		window.size = Vector2i(settings.window_width, settings.window_height)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings.vsync_enabled else DisplayServer.VSYNC_DISABLED
	)
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(settings.master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus, settings.master_volume <= 0.001)


func set_value(section: StringName, key: String, value: Variant) -> void:
	match section:
		&"display":
			match key:
				"fullscreen":
					settings.fullscreen = value
				"window_width":
					settings.window_width = value
				"window_height":
					settings.window_height = value
				"vsync_enabled":
					settings.vsync_enabled = value
		&"camera":
			match key:
				"default_camera_mode":
					settings.default_camera_mode = value
				"mouse_sensitivity":
					settings.mouse_sensitivity = value
				"invert_y":
					settings.invert_y = value
				"fov":
					settings.fov = value
		&"audio":
			match key:
				"master_volume":
					settings.master_volume = value
				"music_volume":
					settings.music_volume = value
				"sfx_volume":
					settings.sfx_volume = value
		&"gameplay":
			match key:
				"camera_switch_key_action":
					settings.camera_switch_key_action = StringName(value)
				"show_debug_overlay":
					settings.show_debug_overlay = value
		_:
			Log.warn("Config", "Unknown config section '%s'" % section)
			return
	save_config()
	apply_settings()
	EventBus.config_changed.emit(section)
	EventBus.settings_applied.emit()


## Convenience accessors so gameplay code does not reach into `.settings`.
func get_fov() -> float:
	return settings.fov


func get_mouse_sensitivity() -> float:
	return settings.mouse_sensitivity


func invert_vertical() -> bool:
	return settings.invert_y


func reset_to_defaults() -> void:
	settings = GameConfig.new()
	save_config()
	apply_settings()
	EventBus.config_changed.emit(&"all")
	EventBus.settings_applied.emit()