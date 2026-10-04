class_name GraphicsQuality
extends Node
## Owns what the game's lighting actually switches on, and at what setting.
##
## ## Why this is a script and not values in the scene
##
## The alternative is an [Environment] with a good-looking set of properties saved into
## `world.tscn`, which is what the project had: a sky, a sun, and nothing else. Every one
## of those values is then correct for exactly one machine. The interesting decision a
## player makes is not "do you want ambient occlusion" but "how much am I willing to pay
## per frame", so the settings have to be reachable from a menu and applied live — and a
## value baked into a scene file cannot be, without regenerating the scene under the
## player's feet.
##
## ## Why the tiers are a table
##
## A chain of `if quality >= HIGH` branches is where a setting gets added to two tiers
## and forgotten in the third. One dictionary per tier, applied key by key, means a new
## effect is one line in one place and "off" is a value like any other.
##
## ## Why it lives next to the sun rather than in `main.gd`
##
## It has to know which nodes it is configuring, and the alternative is `main.gd`
## reaching into the world scene to find them by path. It re-applies on
## [signal EventBus.settings_applied], which is the signal everything else that has a
## setting already listens to.

enum Tier { LOW = 0, MEDIUM = 1, HIGH = 2 }

@export var environment_path: NodePath = ^"../Environment"
@export var sun_path: NodePath = ^"../Sun"

## Every environment/sun property this class is allowed to write, per tier.
##
## Read as: for tier N, set each key to that value. Anything absent from a tier's entry
## is left exactly as the scene or the day/night cycle had it — deliberately, because
## `ambient_light_energy` belongs to [DayNightCycle] and writing it here would fight it
## every frame.
const TIERS := {
	Tier.LOW: {
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": 1.0,
		"ssao_enabled": false,
		"glow_enabled": false,
		"fog_enabled": false,
		"adjustment_enabled": true,
		"adjustment_saturation": 1.02,
		"shadow_enabled": true,
		"directional_shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL,
		"directional_shadow_max_distance": 45.0,
		"directional_shadow_blend_splits": false,
		"shadow_bias": 0.06,
		"msaa": Viewport.MSAA_DISABLED,
	},
	Tier.MEDIUM: {
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": 1.0,
		"ssao_enabled": true,
		"ssao_radius": 1.4,
		"ssao_intensity": 2.4,
		"ssao_power": 1.6,
		"glow_enabled": false,
		"fog_enabled": true,
		"fog_light_color": Color(0.72, 0.79, 0.88),
		"fog_density": 0.006,
		"fog_sky_affect": 0.25,
		"adjustment_enabled": true,
		"adjustment_saturation": 1.05,
		"shadow_enabled": true,
		"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"directional_shadow_max_distance": 70.0,
		"directional_shadow_blend_splits": true,
		"shadow_bias": 0.04,
		"msaa": Viewport.MSAA_2X,
	},
	Tier.HIGH: {
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": 1.0,
		"ssao_enabled": true,
		"ssao_radius": 1.6,
		"ssao_intensity": 2.8,
		"ssao_power": 1.5,
		# Bloom, at a strength you notice in a still and not in motion. `glow_bloom`
		# rather than `glow_strength`: the plain version lifts the whole frame
		# towards white, which on a bright daylight palette reads as a washed-out
		# screenshot rather than as light.
		"glow_enabled": true,
		"glow_bloom": 0.06,
		"glow_hdr_threshold": 1.1,
		"glow_blend_mode": Environment.GLOW_BLEND_MODE_SOFTLIGHT,
		"fog_enabled": true,
		"fog_light_color": Color(0.72, 0.79, 0.88),
		"fog_density": 0.006,
		"fog_sky_affect": 0.25,
		"adjustment_enabled": true,
		"adjustment_saturation": 1.06,
		"adjustment_contrast": 1.02,
		"shadow_enabled": true,
		"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"directional_shadow_max_distance": 90.0,
		"directional_shadow_blend_splits": true,
		"shadow_bias": 0.03,
		"msaa": Viewport.MSAA_4X,
	},
}

## Human names, for a settings row.
const TIER_NAMES := ["Low", "Medium", "High"]

var _environment: Environment = null
var _sun: DirectionalLight3D = null
## Property names per target, read once from each node rather than guessed per key.
var _environment_keys: Dictionary = {}
var _sun_keys: Dictionary = {}


func _ready() -> void:
	_resolve()
	EventBus.settings_applied.connect(apply)
	apply()


func _resolve() -> void:
	var world_environment := get_node_or_null(environment_path) as WorldEnvironment
	_environment = world_environment.environment if world_environment != null else null
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	# Read the real property lists rather than testing `get(key) != null`. A property
	# whose current value happens to be null — a null texture, a null override — would
	# be mistaken for one that does not exist, and the setting would be silently dropped
	# on the one machine where it was already unset.
	_environment_keys = _property_names(_environment)
	_sun_keys = _property_names(_sun)


func _property_names(target: Object) -> Dictionary:
	var names := {}
	if target == null:
		return names
	for property: Dictionary in target.get_property_list():
		names[String(property["name"])] = true
	return names


## Reads the configured tier. Clamped, because the same reason the config service clamps
## applies here: an out-of-range value must not mean "high" by accident.
func current_tier() -> Tier:
	return clampi(int(Config.settings.graphics_quality), 0, 2) as Tier


## Applies the configured tier to the environment, the sun and the viewport.
##
## Writes with `set()` and counts, rather than assigning named properties, because the
## keys span two different classes — an [Environment] property and a
## [DirectionalLight3D] property — and the alternative is a branch per key deciding
## which of two objects to poke. Anything in the table that no node recognises is
## reported instead of swallowed: a typo in a graphics table is otherwise invisible,
## since a property that does not exist is not an error, it is nothing.
func apply() -> void:
	if _environment == null and _sun == null:
		_resolve()
	var settings: Dictionary = TIERS.get(current_tier(), TIERS[Tier.MEDIUM])
	var unknown: Array[String] = []
	for key: String in settings:
		if _environment_keys.has(key):
			_environment.set(key, settings[key])
		elif _sun_keys.has(key):
			_sun.set(key, settings[key])
		elif key == "msaa":
			var viewport := get_viewport()
			if viewport != null:
				viewport.msaa_3d = int(settings[key])
		else:
			unknown.append(key)
	if not unknown.is_empty():
		Log.warn("GraphicsQuality", "no node has %s" % ", ".join(unknown))


## What a tier is worth, for a settings row or a bug report.
static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, 2)]


## True when the world has something this class can configure.
##
## A headless test that builds no world has no [Environment], and every apply() is then
## a no-op. The tests that care assert on the environment directly rather than through
## this, but the ones that only want "apply did not throw" want to know it was honest.
func is_configured() -> bool:
	return _environment != null