extends Node
## Autoload: `Log`
##
## Logging / debugging system. Thin wrapper over `print` and `push_warning`
## that adds timestamps, severity tags, categories and per-category level
## filtering.
##
## Usage from anywhere:
##     Log.info("PlayerController", "Loaded %d items" % n)
##     Log.warn("Farming", "Tile %s already planted" % tile)

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, OFF = 4 }

const LEVEL_NAMES := ["DEBUG", "INFO ", "WARN ", "ERROR", "OFF  "]

## Emitted for every line that passes the filters, as `{time, level, category, message}`.
##
## The in-game panel ([code]scripts/ui/log_panel.gd[/code]) listens to this rather than
## polling the file: the file is flushed on every line and lives outside the game, so
## reading it back is both slow and impossible to see while playing.
signal line_logged(entry: Dictionary)

## Lines kept in memory for the panel. Bounded because this is a log, not a journal —
## an hour of play at four lines a frame would otherwise be an unbounded array behind a
## UI. Oldest goes first.
const MEMORY_LINES := 400

## Categories whose output is suppressed at the given level.
var _category_levels: Dictionary = {}
var _global_level: Level = Level.DEBUG
var _log_to_file: bool = true
var _file: FileAccess = null
var _file_path: String = ""
var _recent: Array[Dictionary] = []


func _ready() -> void:
	# Keep the log readable on the first frame even if _ready order matters.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_file_logging(true, "hollowbrook.log")


func set_global_level(level: Level) -> void:
	_global_level = level
	_write_file("Global log level set to %s" % LEVEL_NAMES[level])


func set_category_level(category: String, level: Level) -> void:
	_category_levels[category.to_lower()] = level


func set_file_logging(enabled: bool, file_name: String = "game.log") -> void:
	_log_to_file = enabled
	if not enabled:
		_close_file()
		return
	_file_path = "user://" + file_name
	# WRITE_READ creates the file when missing; READ_WRITE does not.
	_file = FileAccess.open(_file_path, FileAccess.WRITE_READ)
	if _file == null:
		push_warning("Log: could not open %s for writing" % _file_path)
		_log_to_file = false
		return
	_file.seek_end()
	_write_file("--- log opened ---")


func log_file_path() -> String:
	return _file_path


func debug(category: String, message: String) -> void:
	_emit(Level.DEBUG, category, message)


func info(category: String, message: String) -> void:
	_emit(Level.INFO, category, message)


func warn(category: String, message: String) -> void:
	_emit(Level.WARN, category, message)


func error(category: String, message: String) -> void:
	_emit(Level.ERROR, category, message)


## Emits without routing through push_error/push_warning. Used by the test
## suite, where deliberately-bad input would otherwise pollute CI output.
func quiet(category: String, message: String, level: Level = Level.ERROR) -> void:
	if _is_enabled(category, level):
		_remember(level, category, message)
		_write_file("%s [%s] %s" % [LEVEL_NAMES[level], category, message])


## The most recent lines, oldest first, for the in-game panel.
##
## Returns a copy of the array but the same dictionaries, so a caller that sorts or
## filters them cannot corrupt the log's own history. A copy of the *array* is what
## makes `recent().clear()` harmless, which is the mistake a caller will otherwise make.
func recent(count: int = -1) -> Array[Dictionary]:
	if count < 0 or count >= _recent.size():
		return _recent.duplicate()
	return _recent.slice(_recent.size() - count)


func _remember(level: Level, category: String, message: String) -> void:
	_recent.append({
		"time": _timestamp(),
		"level": int(level),
		"category": category,
		"message": message,
	})
	while _recent.size() > MEMORY_LINES:
		_recent.pop_front()
	line_logged.emit(_recent[_recent.size() - 1])


func _emit(level: Level, category: String, message: String) -> void:
	if not _is_enabled(category, level):
		return
	match level:
		Level.WARN:
			push_warning("%s [%s] %s" % [LEVEL_NAMES[level], category, message])
		Level.ERROR:
			push_error("%s [%s] %s" % [LEVEL_NAMES[level], category, message])
		_:
			print("[%s] %s" % [category, message])
	_remember(level, category, message)
	_write_file("%s [%s] %s" % [LEVEL_NAMES[level], category, message])


func _is_enabled(category: String, level: Level) -> bool:
	var cat := category.to_lower()
	if _category_levels.has(cat):
		return level >= int(_category_levels[cat])
	return level >= _global_level


func _timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]


func _write_file(line: String) -> void:
	if _file == null:
		return
	_file.store_line(line)
	_file.flush()


func _close_file() -> void:
	if _file != null:
		_file = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_close_file()