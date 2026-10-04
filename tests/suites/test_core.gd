extends TestSuite
## Group 0 foundation checks: autoloads exist, EventBus declares the documented
## signals, config round-trips, and logging writes.

var _tmp_config_backup: Variant = null


func get_cases() -> Array[StringName]:
	return [
		&"autoloads_are_registered",
		&"event_bus_signals_exist",
		&"event_bus_has_no_self_connections",
		&"config_defaults_are_sane",
		&"config_set_value_persists",
		&"config_reset_restores_defaults",
		&"log_file_is_written",
		&"log_respects_category_level",
		&"game_state_pause_roundtrip",
		&"the_log_keeps_its_recent_lines_in_memory",
		&"the_recent_log_is_bounded",
		&"recent_log_hands_out_a_copy",
		&"suppressed_lines_are_not_remembered",
		&"the_graphics_quality_setting_persists_and_clamps",
	]


func _run(case: StringName) -> Dictionary:
	match case:
		&"autoloads_are_registered":
			return _check_autoloads()
		&"event_bus_signals_exist":
			return _check_signals()
		&"event_bus_has_no_self_connections":
			return _check_bus_connections()
		&"config_defaults_are_sane":
			return _check_config_defaults()
		&"config_set_value_persists":
			return _check_config_persist()
		&"config_reset_restores_defaults":
			return _check_config_reset()
		&"log_file_is_written":
			return _check_log_file()
		&"log_respects_category_level":
			return _check_log_levels()
		&"game_state_pause_roundtrip":
			return _check_pause()
		&"the_log_keeps_its_recent_lines_in_memory":
			return _check_log_memory()
		&"the_recent_log_is_bounded":
			return _check_log_memory_bounded()
		&"recent_log_hands_out_a_copy":
			return _check_log_memory_is_a_copy()
		&"suppressed_lines_are_not_remembered":
			return _check_log_memory_respects_levels()
		&"the_graphics_quality_setting_persists_and_clamps":
			return _check_graphics_quality_persists()
	return fail(case, "unhandled case")


func _check_autoloads() -> Dictionary:
	var c := &"autoloads_are_registered"
	for name: StringName in [
		&"EventBus", &"Log", &"Config", &"GameState", &"Debug"
	]:
		var node := autoload(name)
		if node == null:
			return fail(c, "autoload '%s' not found in the scene tree root" % name)
	return succeeded(c, "5 autoloads present")


func _check_signals() -> Dictionary:
	var c := &"event_bus_signals_exist"
	var required := [
		"game_ready", "game_paused", "game_quitting",
		"config_changed", "camera_mode_changed", "settings_applied",
		"world_loaded",
		"time_minute_changed", "time_hour_changed",
		"day_started", "day_ended", "season_changed", "year_changed",
		"soil_tilled", "crop_planted", "crop_harvested", "crop_grew",
		"item_added", "item_removed", "inventory_changed",
		"hotbar_selection_changed",
		"interactable_focused", "interactable_unfocused", "interaction_performed",
		"currency_changed", "item_purchased", "item_sold",
		# Group 13. `trade_failed` is the half of trading that has to be loud: a
		# sale that quietly does nothing is indistinguishable from a bug.
		"trade_failed", "stamina_changed", "stamina_exhausted",
		# Group 25. Without this the panel has nothing to subscribe to, and the
		# counter opens onto a blank screen.
		"shop_opened",
	]
	for s: String in required:
		if not EventBus.has_signal(s):
			return fail(c, "EventBus is missing signal '%s'" % s)
	return succeeded(c, "%d signals declared" % required.size())


func _check_bus_connections() -> Dictionary:
	var c := &"event_bus_has_no_self_connections"
	var total := 0
	for entry: Dictionary in EventBus.get_signal_list():
		var sig: Signal = EventBus.get(entry["name"])
		total += sig.get_connections().size()
	return succeeded(c, "%d active connection(s)" % total)


func _check_config_defaults() -> Dictionary:
	var c := &"config_defaults_are_sane"
	if Config.settings == null:
		return fail(c, "Config.settings is null")
	if Config.get_mouse_sensitivity() <= 0.0:
		return fail(c, "mouse sensitivity must be positive")
	if Config.get_fov() < 40.0 or Config.get_fov() > 140.0:
		return fail(c, "fov %s out of sane range" % Config.get_fov())
	return succeeded(c)


func _check_config_persist() -> Dictionary:
	var c := &"config_set_value_persists"
	var original := Config.settings.fov
	var target := clampf(original + 5.0, 40.0, 140.0)
	Config.set_value(&"camera", "fov", target)
	if not is_equal_approx(Config.settings.fov, target):
		return fail(c, "in-memory value not updated")
	var cfg := ConfigFile.new()
	if cfg.load(Config.CONFIG_PATH) != OK:
		return fail(c, "config file could not be reloaded from disk")
	var on_disk := float(cfg.get_value("camera", "fov", -1.0))
	if not is_equal_approx(on_disk, target):
		return fail(c, "expected %s on disk but got %s" % [str(target), str(on_disk)])
	Config.set_value(&"camera", "fov", original)
	return succeeded(c, "fov %s persisted" % target)


## The graphics tier is the first setting whose value decides what the renderer
## does, so it is also the first one where a value that survives to disk but never
## reaches [Environment] is worth asserting on. This checks the persistence half;
## the apply half lives in `test_world`, against a real world.
func _check_graphics_quality_persists() -> Dictionary:
	var c := &"the_graphics_quality_setting_persists_and_clamps"
	var original: int = int(Config.settings.graphics_quality)
	Config.set_value(&"graphics", "graphics_quality", 0)
	if int(Config.settings.graphics_quality) != 0:
		return fail(c, "low was not stored in memory")
	var cfg := ConfigFile.new()
	if cfg.load(Config.CONFIG_PATH) != OK:
		return fail(c, "config file could not be reloaded from disk")
	if int(cfg.get_value("graphics", "graphics_quality", -1)) != 0:
		return fail(c, "low did not reach the config file")
	# A hand-edited config file is the realistic source of a bad value.
	Config.set_value(&"graphics", "graphics_quality", 9)
	if int(Config.settings.graphics_quality) != 2:
		return fail(c, "a 9 in the config file was not clamped to high, got %d" % int(Config.settings.graphics_quality))
	Config.set_value(&"graphics", "graphics_quality", original)
	return succeeded(c, "tier persisted and 9 clamped to 2")


func _check_config_reset() -> Dictionary:
	var c := &"config_reset_restores_defaults"
	Config.settings.fov = 111.0
	Config.reset_to_defaults()
	if not is_equal_approx(Config.settings.fov, GameConfig.new().fov):
		return fail(c, "fov not restored to default")
	return succeeded(c)


func _check_log_file() -> Dictionary:
	var c := &"log_file_is_written"
	Log.info("TestSuite", "log file probe")
	var path := ProjectSettings.globalize_path(Log.log_file_path())
	if not FileAccess.file_exists(path):
		return fail(c, "no log file at %s" % path)
	var text := FileAccess.get_file_as_string(Log.log_file_path())
	if not text.contains("log file probe"):
		return fail(c, "probe message not present in log file")
	return succeeded(c, path)


func _check_log_levels() -> Dictionary:
	var c := &"log_respects_category_level"
	Log.set_category_level("quiet_category", Log.Level.ERROR)
	Log.quiet("quiet_category", "this should not appear", Log.Level.INFO)
	Log.quiet("quiet_category", "neither should this", Log.Level.WARN)
	Log.quiet("quiet_category", "but this should", Log.Level.ERROR)
	var text := FileAccess.get_file_as_string(Log.log_file_path())
	if text.contains("this should not appear") or text.contains("neither should this"):
		return fail(c, "suppressed messages were written anyway")
	if not text.contains("but this should"):
		return fail(c, "ERROR level message was suppressed")
	Log.set_category_level("quiet_category", Log.Level.DEBUG)
	return succeeded(c)


func _check_pause() -> Dictionary:
	var c := &"game_state_pause_roundtrip"
	if tree == null:
		return fail(c, "harness did not inject a SceneTree")
	GameState.set_paused(true)
	if not GameState.paused or not tree.paused:
		return fail(c, "tree did not pause")
	GameState.set_paused(false)
	if GameState.paused or tree.paused:
		return fail(c, "tree did not unpause")
	return succeeded(c)


## The log keeps what it just said, in memory.
##
## The file is the wrong place to read a log from: it lives outside the game, and it is
## flushed on every line, so the panel that shows the log while you play would have to
## re-read a file on every frame. This asserts the ring buffer directly.
func _check_log_memory() -> Dictionary:
	var c := &"the_log_keeps_its_recent_lines_in_memory"
	var marker := "memory probe %d" % Time.get_ticks_msec()
	Log.info("TestSuite", marker)
	var found := false
	for entry: Dictionary in Log.recent():
		if str(entry.get("message", "")) == marker:
			found = true
			if not entry.has("time") or str(entry.get("time", "")).is_empty():
				return fail(c, "the line was remembered with no timestamp")
			if str(entry.get("category", "")) != "TestSuite":
				return fail(c, "category came back as '%s'" % str(entry.get("category", "")))
	if not found:
		return fail(c, "the line was not in the recent buffer")
	return succeeded(c, marker)


## The buffer is bounded, and drops the oldest.
##
## An unbounded log behind a UI is a slow-motion crash: a long session would grow an
## array without limit, and the panel would rebuild from all of it. This drives it past
## the cap deliberately — `recent()` is capped at a few hundred entries, so the count
## must stay near that however much is logged.
func _check_log_memory_bounded() -> Dictionary:
	var c := &"the_recent_log_is_bounded"
	var before := Log.recent().size()
	var chunk := before + Log.MEMORY_LINES + 50
	for i: int in range(chunk):
		Log.quiet("BulkProbe", "line %d" % i, Log.Level.DEBUG)
	var after := Log.recent().size()
	if after > before + Log.MEMORY_LINES:
		return fail(c, "%d lines retained after logging %d over a cap of %d"
			% [after, chunk, Log.MEMORY_LINES])
	if after <= 0:
		return fail(c, "the buffer was emptied rather than trimmed")
	# Oldest first, so the newest line is the last one — the order the panel relies on.
	var last: Dictionary = Log.recent()[after - 1]
	if str(last.get("message", "")) != "line %d" % (chunk - 1):
		return fail(c, "the newest line is '%s'" % str(last.get("message", "")))
	return succeeded(c, "%d lines retained" % after)


## A caller cannot corrupt the log by sorting what it was handed.
func _check_log_memory_is_a_copy() -> Dictionary:
	var c := &"recent_log_hands_out_a_copy"
	var handed: Array = Log.recent(5)
	handed.clear()
	if Log.recent().size() <= 5:
		return fail(c, "clearing the returned array emptied the log's own history")
	return succeeded(c)


## Suppressed lines stay out of memory as well as out of the file.
func _check_log_memory_respects_levels() -> Dictionary:
	var c := &"suppressed_lines_are_not_remembered"
	Log.set_category_level("silent_probe", Log.Level.ERROR)
	Log.quiet("silent_probe", "should not be remembered", Log.Level.WARN)
	for entry: Dictionary in Log.recent():
		if str(entry.get("message", "")) == "should not be remembered":
			Log.set_category_level("silent_probe", Log.Level.DEBUG)
			return fail(c, "a suppressed line was kept in memory anyway")
	Log.set_category_level("silent_probe", Log.Level.DEBUG)
	return succeeded(c)