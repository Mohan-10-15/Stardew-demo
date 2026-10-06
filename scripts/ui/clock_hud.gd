extends CanvasLayer
## The clock readout: date and time in the corner of the screen.
##
## Reads the clock through [TimeService] rather than subscribing to every
## individual `EventBus` signal. The date changes on `day_started`, but the hour
## and minute change on signals that fire far more often; subscribing to all
## three and reassembling a date from partial updates is the bug-prone version.
## One `get_display_text()` call per redraw is both simpler and cheaper than
## reconstructing `Year 1 Spring 4` from three unrelated integers.
##
## Repaints on [signal EventBus.time_minute_changed] rather than every frame.
## A label that re-renders 60 times a second to show the same string wastes
## layout work for nothing.

const REPAINT_INTERVAL_MINUTES := 1

@onready var _date_label: Label = get_node_or_null(^"Panel/Column/DateLabel")
@onready var _time_label: Label = get_node_or_null(^"Panel/Column/TimeLabel")
@onready var _weather_label: Label = get_node_or_null(^"Panel/Column/WeatherLabel")

var _service: TimeService = null
## Cached so the readout is stable within a minute rather than flickering
## between a painted and an unpainted state every time the clock ticks.
var _last_text := ""


func _ready() -> void:
	layer = 5
	# Below the interaction HUD's layer 10, so a prompt always draws on top of
	# the clock rather than the other way round.
	_service = TimeService.find(get_tree().get_root())
	if _service == null:
		Log.warn("ClockHUD", "No TimeService in the tree; clock readout disabled")
		return
	EventBus.time_minute_changed.connect(_on_minute_changed)
	# Repaint once immediately: the service publishes its starting state during
	# `_ready`, which may have been before this node existed.
	_refresh()


func _on_minute_changed(_minute_of_day: int) -> void:
	_refresh()


func _refresh() -> void:
	if _service == null:
		return
	var text := _service.get_display_text()
	if text == _last_text:
		return
	_last_text = text
	if _date_label != null:
		_date_label.text = _service.time.describe_date()
	if _time_label != null:
		_time_label.text = _service.time.describe_time()
	if _weather_label != null:
		var weather := _service.get_weather()
		_weather_label.text = WorldTime.weather_name(weather)
		# Storms read worse than a plain white label, so they get their own
		# colour. This is not decoration for its own sake: at a glance the
		# player needs to know whether to carry a hoe back before it rains.
		match weather:
			WorldTime.Weather.RAIN:
				_weather_label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
			WorldTime.Weather.STORM:
				_weather_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.50))
			WorldTime.Weather.SNOW:
				_weather_label.add_theme_color_override("font_color", Color(0.88, 0.93, 0.98))
			_:
				_weather_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.88))
