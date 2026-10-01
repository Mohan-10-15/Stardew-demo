class_name DayNightCycle
extends Node
## Drives the sun and sky from the clock, so the valley actually looks like the
## time it is.
##
## Subscribes to [EventBus] rather than holding a reference to [TimeService].
## That is the whole point of the hub: lighting, schedules, shop hours and crop
## growth all need the time of day, and none of them should need to know who owns
## the clock. If this ever grows a `TimeService` field the architecture has been
## quietly undone.
##
## The gradient is keyed on *absolute minutes from the 6:00 AM day start*, so
## 0:00 AM reads as deep night rather than as dawn. Keying on the display hour
## would put the darkest point at 12 AM and the brightest at 6 AM twice, once on
## each side of the night.

## Absolute minute of each key point. One simulation tick is 10 in-game minutes,
## so these are deliberately all multiples of 10.
const KEY_MINUTES: Array[int] = [
	0,      # 6:00 AM, first light
	180,    # 9:00 AM
	540,    # 3:00 PM, peak
	900,    # 9:00 PM, dusk
	1080,   # midnight
	1200,   # 2:00 AM, collapse
]

## Sun energy at each key point. Interpolated linearly, so light ramps rather
## than snapping between states.
const KEY_ENERGY: Array[float] = [0.55, 1.05, 1.20, 0.85, 0.30, 0.16]

## Ambient multiplier at each key point. Night is dimmer than the sun alone
## implies, because a night lit only by a moon-blue directional reads as a
## floodlit room at 2 AM.
const KEY_AMBIENT: Array[float] = [0.75, 1.00, 1.00, 0.85, 0.45, 0.35]

## Sun colour at each key point. Warm at dawn and dusk, blue at night.
const KEY_COLOR: Array[Color] = [
	Color(1.00, 0.82, 0.66),
	Color(1.00, 0.95, 0.86),
	Color(1.00, 0.98, 0.93),
	Color(1.00, 0.74, 0.52),
	Color(0.62, 0.68, 0.92),
	Color(0.55, 0.62, 0.90),
]

## Sun elevation in degrees at each key point. Negative is below the horizon.
const KEY_ELEVATION: Array[float] = [4.0, 38.0, 46.0, 12.0, -18.0, -26.0]

## Ambient energy at midday, before the night multiplier is applied.
const MIDDAY_AMBIENT_ENERGY := 0.85

const SKY_TOP_DAY := Color(0.30, 0.53, 0.78)
const SKY_HORIZON_DAY := Color(0.72, 0.82, 0.88)
const SKY_TOP_NIGHT := Color(0.04, 0.06, 0.14)
const SKY_HORIZON_NIGHT := Color(0.10, 0.12, 0.22)

## The sun keeps a constant azimuth; only elevation and colour animate. A real sky
## would sweep the azimuth too, but that moves every shadow in the valley and is
## an ambience decision for the world group, not the clock's.
const SUN_AZIMUTH_DEGREES := -38.0

@export var sun_path: NodePath = ^"../Sun"
@export var environment_path: NodePath = ^"../Environment"
## When false the cycle stops writing to the lights, so a cutscene or a test can
## pin the lighting without disconnecting anything.
@export var enabled: bool = true

var _sun: DirectionalLight3D = null
var _sky_material: ProceduralSkyMaterial = null
var _environment: Environment = null


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var world_environment := get_node_or_null(environment_path) as WorldEnvironment
	if world_environment != null:
		_environment = world_environment.environment
		if _environment != null and _environment.sky != null:
			_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial

	if _sun == null:
		Log.warn("DayNight", "No sun at %s; lighting cycle disabled" % sun_path)
		return

	EventBus.time_minute_changed.connect(_on_minute_changed)
	# Apply immediately so the light is right before the first tick arrives,
	# rather than a frame of the default midday key.
	apply_minute_of_day(Clock.DAY_START_HOUR * Clock.MINUTES_PER_HOUR)
	Log.info("DayNight", "Lighting cycle active (sky=%s)" % [_sky_material != null])


## The `EventBus` signal carries a wall-clock minute-of-day in `0..1439`, which is
## not what the gradient is keyed on. This is the single conversion point between
## the two scales.
func _on_minute_changed(minute_of_day: int) -> void:
	apply_minute_of_day(minute_of_day)


## Public so tests and the dev console can drive the cycle without waiting on real
## seconds.
func apply_minute_of_day(minute_of_day: int) -> void:
	if not enabled or _sun == null:
		return
	var wrapped := posmod(minute_of_day, 24 * Clock.MINUTES_PER_HOUR)
	var absolute := Clock.to_absolute_minutes(
		wrapped / Clock.MINUTES_PER_HOUR, wrapped % Clock.MINUTES_PER_HOUR
	)
	_apply(absolute)


## The last absolute minute, `2:00 AM`, where the player collapses. Between here
## and 6:00 AM they are asleep, so the light holds at its darkest rather than
## interpolating through a sunrise nobody sees.
func _is_asleep_window(absolute: int) -> bool:
	return absolute >= Clock.PASS_OUT_ABSOLUTE


func _apply(absolute: int) -> void:
	if _is_asleep_window(absolute):
		_write_lighting(KEY_ENERGY.size() - 1, 1.0)
		return

	for i: int in range(KEY_MINUTES.size() - 1):
		var from := KEY_MINUTES[i]
		var to := KEY_MINUTES[i + 1]
		if absolute < from or absolute > to:
			continue
		var span := to - from
		var t := 0.0 if span <= 0.0 else float(absolute - from) / float(span)
		_write_lighting(i, t)
		return
	_write_lighting(0, 0.0)


## Blends key `index` toward key `index + 1` by `t` and writes the result to the
## sun and the sky.
func _write_lighting(index: int, t: float) -> void:
	var next := mini(index + 1, KEY_ENERGY.size() - 1)
	var energy := lerpf(KEY_ENERGY[index], KEY_ENERGY[next], t)
	var ambient := lerpf(KEY_AMBIENT[index], KEY_AMBIENT[next], t)
	var color := KEY_COLOR[index].lerp(KEY_COLOR[next], t)
	var elevation := lerpf(KEY_ELEVATION[index], KEY_ELEVATION[next], t)

	_sun.light_energy = energy
	_sun.light_color = color
	_sun.rotation_degrees = Vector3(elevation, SUN_AZIMUTH_DEGREES, 0.0)

	# `ambient` is 1.0 at midday and falls off at night, so the darkness factor
	# is `1 - ambient`; lerping the sky towards night by that same amount keeps
	# the sky and the ambient light dimming together instead of drifting apart.
	var nightness := clampf(1.0 - ambient, 0.0, 1.0)
	if _sky_material != null:
		_sky_material.sky_top_color = SKY_TOP_DAY.lerp(SKY_TOP_NIGHT, nightness)
		_sky_material.sky_horizon_color = SKY_HORIZON_DAY.lerp(SKY_HORIZON_NIGHT, nightness)
	if _environment != null:
		_environment.ambient_light_energy = MIDDAY_AMBIENT_ENERGY * ambient


## The sun's current elevation, in degrees. Negative means the sun is below the
## horizon. Exposed so a test can assert the cycle is not stuck at one key.
func get_sun_elevation() -> float:
	return _sun.rotation_degrees.x if _sun != null else 0.0


func get_sun_energy() -> float:
	return _sun.light_energy if _sun != null else 0.0
