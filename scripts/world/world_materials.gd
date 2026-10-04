class_name WorldMaterials
extends RefCounted
## The valley's surfaces: one named [StandardMaterial3D] per material class, built
## once and shared.
##
## ## Why a library and not a colour at each call site
##
## The world used to call `material(COL_WOOD, 0.9)` at fifteen call sites, which is
## fifteen chances to spell the same surface slightly differently, and nowhere to hang
## a texture. Naming the classes means `world_builder.gd` asks for "wood", and anything
## that wants to know what wood looks like — the avatar, a future building upgrade, the
## test suite — asks the same question and gets the same answer.
##
## ## The detail texture is one, shared, and multiplied
##
## A tiled noise texture assigned to `albedo_texture` *multiplies* `albedo_color`, so a
## near-white noise map turns a flat colour into a surface with variation on it without
## moving the hue the palette picked. One [NoiseTexture2D] is generated for the whole
## world and tiled differently per class via `uv1_scale`, rather than one per material:
## nine simultaneous 256x256 generations at world build is nine times the cost for a
## difference nobody can see.
##
## The range is 0.86-1.0 rather than 0.0-1.0 on purpose. A full-range noise map over a
## surface reads as camouflage; a 14% dip reads as a surface.
##
## ## Instances are shared on purpose
##
## `material_override` on forty identical fence posts pointing at one resource lets the
## renderer batch them. Forty separate [StandardMaterial3D]s with identical properties
## defeats that, so [method get] caches.

const DETAIL_SIZE := 256

## Surface classes. The value is `[albedo, roughness, metallic, specular, uv_tiles]`.
## `uv_tiles` is in texture repeats per *world metre*, converted per material below by
## the scale each surface's UVs are authored in.
const SURFACES := {
	&"grass": [Color(0.36, 0.62, 0.31), 0.95, 0.0, 0.15, 0.35],
	&"dirt": [Color(0.45, 0.33, 0.22), 0.95, 0.0, 0.15, 0.55],
	&"path": [Color(0.62, 0.55, 0.42), 0.90, 0.0, 0.18, 0.70],
	&"water": [Color(0.24, 0.48, 0.66, 0.75), 0.08, 0.0, 0.55, 0.22],
	&"wood": [Color(0.38, 0.26, 0.16), 0.90, 0.0, 0.20, 1.20],
	&"rock": [Color(0.52, 0.52, 0.55), 0.85, 0.0, 0.25, 0.80],
	&"wall": [Color(0.78, 0.72, 0.62), 0.90, 0.0, 0.18, 0.65],
	&"roof": [Color(0.62, 0.31, 0.28), 0.85, 0.0, 0.22, 0.90],
	&"fence": [Color(0.52, 0.38, 0.24), 0.90, 0.0, 0.20, 1.20],
	&"door": [Color(0.32, 0.22, 0.15), 0.88, 0.0, 0.22, 1.60],
	&"glass": [Color(0.55, 0.72, 0.85, 0.62), 0.18, 0.0, 0.85, 1.00],
	&"metal": [Color(0.58, 0.58, 0.62), 0.42, 0.85, 0.60, 1.40],
}

## Every class name, for tests that assert the library is complete.
static func surface_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for key: StringName in SURFACES:
		names.append(key)
	names.sort()
	return names

static var _cache: Dictionary = {}
static var _detail: NoiseTexture2D = null


## The shared near-white tiling noise, generated once.
##
## `seamless = true` because the visible artefact of a non-tiling map is a grid of
## repeating blobs, and on a ground plane 40m across with `uv1_scale` above 1 it is the
## first thing you see.
static func detail_texture() -> NoiseTexture2D:
	if _detail == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.035
		noise.fractal_octaves = 3
		noise.fractal_gain = 0.45
		# The whole point is that the reader never consciously sees the pattern, so
		# the features are large and soft rather than fine and busy.
		var texture := NoiseTexture2D.new()
		texture.width = DETAIL_SIZE
		texture.height = DETAIL_SIZE
		texture.seamless = true
		texture.noise = noise
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.86, 0.86, 0.86))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		texture.color_ramp = ramp
		_detail = texture
	return _detail


## The named material for [param surface], or null if the name is not a surface.
##
## Null rather than a fallback material: a typo in a surface name should fail a test
## loudly, not hand back wood where the author meant glass.
static func surface(surface_name: StringName) -> StandardMaterial3D:
	if not SURFACES.has(surface_name):
		return null
	if _cache.has(surface_name):
		return _cache[surface_name]
	var spec: Array = SURFACES[surface_name]
	var m := _make(spec[0], spec[1], spec[2], spec[3], spec[4])
	if surface_name == &"water":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Water is the one surface where a visible highlight is the point. `0.55`
		# specular against wood's `0.20` is what separates "a blue pane" from "water"
		# before any ripple texture exists.
		m.emission_enabled = true
		m.emission = Color(0.10, 0.20, 0.28)
		m.emission_energy_multiplier = 0.35
	elif surface_name == &"glass":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[surface_name] = m
	return m


## A material for a colour that is not one of the named classes.
##
## The examine props carry their own colour per [Resource] definition, so they cannot
## come from the table. They still get the shared detail texture, otherwise every
## hand-picked prop is the one flat surface in a world that is not.
static func for_color(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var key := "&by_colour_%s_%.2f" % [color.to_html(false), roughness]
	if _cache.has(key):
		return _cache[key]
	var m := _make(color, roughness, 0.0, 0.2, 1.0)
	_cache[key] = m
	return m


static func _make(
	color: Color, roughness: float, metallic: float, specular: float, uv_tiles: float
) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = detail_texture()
	# `uv1_scale` is the tiling. Every primitive in this world is either a
	# [PlaneMesh] or a [BoxMesh], whose UVs are 0..1 per face, so the scale is
	# "repeats per face" rather than per metre — which is why a 2m fence post and a
	# 40m ground get numbers two orders of magnitude apart.
	m.uv1_scale = Vector3(uv_tiles, uv_tiles, uv_tiles)
	m.roughness = roughness
	m.metallic = metallic
	# Godot 4 renamed SpatialMaterial.specular to this.
	m.metallic_specular = specular
	# The detail map is a multiply on top of the albedo, so the surface must also be
	# allowed to take vertex colour: the ground's biome tint arrives that way.
	m.vertex_color_use_as_albedo = true
	return m


## Forgets the cache. Tests only — the world is built once per boot and re-reading the
## table is not a thing anything should do mid-frame.
static func reset_cache() -> void:
	_cache.clear()
	_detail = null