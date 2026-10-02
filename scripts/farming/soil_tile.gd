class_name SoilTile
extends Node3D
## One square of the farm plot, and the only thing that knows what a tile *is*.
##
## State plus presentation. Every rule about when a tile may be tilled, planted,
## watered or harvested is a method here, so the interaction component, the tests
## and a future save file all agree without duplicating the logic.
##
## The tile holds a crop *id* and a growth day count, never a crop definition.
## What a crop means — days to ripen, whether it regrows, what it sells for —
## comes from [CropData] via [CropRegistry]. That split is what lets a crop be
## retuned by editing a `.tres` instead of editing every tile in the world, and
## it is why a save file can name a crop without embedding a resource reference.

## Published when a tile enters or leaves the tilled state, including when it is
## reset by the end of the day.
signal tilled_changed(is_tilled: bool)
signal watered_changed(is_watered: bool)
signal planted(crop_id: StringName)
signal harvested(crop_id: StringName, yield_amount: int)
## Published after *anything* that could change what this tile can be asked to do.
##
## One signal rather than a listener per field, because "what can I do here?" is a
## single question with a single answer and the previous arrangement got that
## answer wrong twice over: a listener per field missed a harvest and missed
## overnight growth, so a ripe crop still prompted "Water the soil" the next
## morning and a picked tomato still offered itself for picking again.
signal state_changed

## Grid coordinates within the owning [FarmGrid]. Stable across sessions, so it
## is what a save file stores and what the farming signals on [EventBus] carry.
@export var tile_index: Vector2i = Vector2i.ZERO

## True once the tile has been dug over. Untilled soil cannot be planted.
var is_tilled: bool = false
## True if it rained or the player watered today. Cleared at day start.
var is_watered: bool = false
## Empty when nothing is growing here.
var crop_id: StringName = &""
## Days this crop has been in the ground, compared against
## [member CropData.days_to_grow].
var growth_days: int = 0

## Deterministic generator for yields, so a farm simulated twice produces the
## same crops. Owned per tile so two tiles never draw from the same stream.
var _rng := RandomNumberGenerator.new()

var _soil_mesh: MeshInstance3D
## Procedural stand-in plant, used only for crops that ship no CC0 model.
var _crop_mesh: MeshInstance3D
## The real CC0 plant model, instantiated when the crop has art. Kept separate
## from [_crop_mesh] rather than sharing one node because the two are shaped
## differently: the model is a whole imported scene whose root carries the
## importer's own scale, and the placeholder is a single mesh scaled directly.
var _crop_model: Node3D
## Path of the model currently parented under this tile, so a repaint that lands on
## the same growth stage does not free and rebuild 200 meshes for nothing.
var _model_path: String = ""
var _tile_size: float = 2.0


## Creates the soil plate and the plant.
##
## Built in code rather than authored as a `.tscn` because there are hundreds of
## these and the mesh sizes follow [param size] — a scene would either be fixed
## at one tile size or need a scene per size. See `docs/DECISIONS.md` D2 for why
## scenes are generated rather than hand-placed; this is the same principle
## applied one level down, where the repeated object is the mesh.
func build_visuals(size: float) -> void:
	_tile_size = maxf(size, 0.05)
	# Seeded from the tile index so two tiles never draw from the same yield
	# stream and a farm replays identically. Done here rather than in `_init`
	# because `tile_index` is assigned after construction by the grid.
	_rng.seed = hash("%s:%d,%d" % [name, tile_index.x, tile_index.y])

	var plate := BoxMesh.new()
	# Slightly thinner than a tile so adjacent plates show a seam instead of
	# z-fighting on their shared edge. A 1mm gap at 2m tiles is invisible from
	# standing height but makes the grid legible when looking down at it.
	plate.size = Vector3(_tile_size - 0.02, 0.06, _tile_size - 0.02)
	var soil := MeshInstance3D.new()
	soil.name = "SoilMesh"
	soil.mesh = plate
	soil.material_override = _make_material(_soil_dry_color())
	soil.position = Vector3(0, 0.03, 0)
	add_child(soil)
	_soil_mesh = soil

	# The procedural plant is now a *fallback*, drawn only for crops that ship no
	# CC0 model. It is kept because content added without art should still be
	# visible and still show progress, and it costs one cylinder per tile.
	#
	# A stalk rather than a billboard: it reads at any angle in first and third
	# person and needs no material setup for transparency.
	var plant := CylinderMesh.new()
	plant.top_radius = _tile_size * 0.16
	plant.bottom_radius = _tile_size * 0.20
	plant.height = _tile_size * 0.55
	plant.radial_segments = 6
	var crop := MeshInstance3D.new()
	crop.name = "CropMesh"
	crop.mesh = plant
	crop.material_override = _make_material(Color(0.5, 0.7, 0.35))
	crop.position = Vector3(0, _tile_size * 0.30, 0)
	crop.visible = false
	add_child(crop)
	_crop_mesh = crop

	refresh_visual()


## Digs the tile over. Idempotent: tilling tilled soil changes nothing and
## publishes nothing, which is what keeps `soil_tilled` meaningful as a success
## event rather than a per-frame chatter.
func till() -> bool:
	if is_tilled:
		return false
	is_tilled = true
	tilled_changed.emit(true)
	refresh_visual()
	EventBus.soil_tilled.emit(tile_index)
	state_changed.emit()
	return true


## Waters the tile. Only tilled soil holds water — watering grass is refused
## rather than silently buffered, so the player learns the rule from the failure
## instead of wondering why the watering can did nothing later.
func water() -> bool:
	if not is_tilled:
		return false
	if is_watered:
		return false
	is_watered = true
	watered_changed.emit(true)
	refresh_visual()
	state_changed.emit()
	return true


## Puts a seed in the ground.
##
## Fails on untilled soil, on a tile that already has a crop, and on an id the
## registry does not know. An unknown id is a content bug, and planting one would
## leave a tile permanently occupied by a plant that can never be harvested and
## never appear — the worst possible failure, because nothing would look wrong.
func plant(id: StringName) -> bool:
	if not is_tilled:
		return false
	if not crop_id.is_empty():
		return false
	if id.is_empty() or CropRegistry.get_crop(id) == null:
		return false
	crop_id = id
	growth_days = 0
	# A new crop gets its own stream so a regrowing tomato does not replay the
	# same sequence forever.
	_rng.seed = hash("%s:%s:%d" % [str(tile_index), String(id), growth_days])
	refresh_visual()
	planted.emit(id)
	EventBus.crop_planted.emit(tile_index, id)
	state_changed.emit()
	return true


## Whether the crop here has finished growing.
func is_ripe() -> bool:
	if crop_id.is_empty():
		return false
	var data := CropRegistry.get_crop(crop_id)
	if data == null:
		return false
	return growth_days >= data.days_to_grow


## How far along the plant is, 0..1. Drives the sprout's scale so a field shows
## progress at a glance without needing a tooltip on every tile.
func growth_fraction() -> float:
	if crop_id.is_empty():
		return 0.0
	var data := CropRegistry.get_crop(crop_id)
	if data == null or data.days_to_grow <= 0:
		return 0.0
	return clampf(float(growth_days) / float(data.days_to_grow), 0.0, 1.0)


## What [method harvest] would take, if it were allowed to.
##
## Lets a caller check the yield against its storage *before* committing. That
## order matters: the amount is rolled from a seeded RNG and the regrower's clock
## is rewound inside `harvest`, and neither is undone by re-planting afterwards.
##
## Rolls from the same generator over the same state, so the amount it reports is
## the amount `harvest` will produce — not an estimate that could disagree.
func preview_harvest() -> Dictionary:
	var data := CropRegistry.get_crop(crop_id)
	if data == null:
		return {"ok": false, "reason": "empty", "crop_id": crop_id, "amount": 0}
	if not is_ripe():
		return {"ok": false, "reason": "not_ripe", "crop_id": crop_id, "amount": 0}
	return {"ok": true, "reason": "", "crop_id": data.id, "amount": data.roll_yield(_rng)}


## Removes a crop and reports what came up.
##
## Returns a dictionary rather than a bool because the caller has to distinguish
## "harvested one parsnip" from "too early" from "that tile is not mine". The
## `ok` key is the answer to "did anything happen"; `reason` is for the player.
## An empty result is the caller's cue to publish `farming_failed`, never to stay
## silent — see [method FarmService.harvest] for the split.
##
## The caller is expected to have settled storage first — see
## [method preview_harvest]. This method publishes a *success* (`harvested` and
## `crop_harvested`), so anything that fails after it runs cannot be unsaid.
func harvest() -> Dictionary:
	if crop_id.is_empty():
		return {"ok": false, "reason": "empty", "crop_id": &"", "amount": 0}

	var data := CropRegistry.get_crop(crop_id)
	if data == null:
		# A save written by a build that had this crop, loaded by one that does
		# not. Clearing the tile is better than leaving it permanently
		# unharvestable, and the reason says so rather than blaming the player.
		var lost := crop_id
		_set_crop(&"")
		refresh_visual()
		state_changed.emit()
		return {"ok": false, "reason": "unknown_crop", "crop_id": lost, "amount": 0}

	if not is_ripe():
		return {"ok": false, "reason": "not_ripe", "crop_id": crop_id, "amount": 0}

	var amount := data.roll_yield(_rng)
	# A regrowing crop stays in the ground and restarts its clock. A one-shot
	# crop leaves bare tilled soil, ready to be replanted.
	#
	# The regrower's clock starts at `days_to_grow - regrow_days` rather than
	# zero, so it takes exactly `regrow_days` more days to ripen again instead of
	# another full season. Setting it to zero is the obvious version and is wrong
	# by `days_to_grow` days for every regrowing crop.
	if data.regrows:
		growth_days = maxi(data.days_to_grow - data.regrow_days, 0)
		# The visual must follow the new clock. Without this the sprout stays at
		# full ripe scale until the next `grow_one_day`, so a picked tomato looks
		# harvestable for another day and the player presses E on a tile that
		# refuses.
		refresh_visual()
	else:
		_set_crop(&"")

	harvested.emit(data.id, amount)
	EventBus.crop_harvested.emit(tile_index, data.id, amount)
	# The two harvest paths above take the tile in different directions — cleared
	# for a one-shot crop, clock rewound for a regrower — and the prompt has to
	# change in both cases. Emitted last so a listener sees the settled state.
	state_changed.emit()
	return {"ok": true, "reason": "", "crop_id": data.id, "amount": amount}


## Advances this crop one day. Returns true only on the day it ripens, which is
## what makes `crop_grew` fire once rather than every day for the rest of the
## season.
func grow_one_day() -> bool:
	if crop_id.is_empty():
		return false
	var data := CropRegistry.get_crop(crop_id)
	if data == null:
		return false
	growth_days += 1
	var ripened := growth_days >= data.days_to_grow
	refresh_visual()
	# Unconditional, not only on the ripening frame. A crop that ripens and is
	# *not* harvested tonight has to start offering "Harvest" the next morning,
	# and nothing else announces that.
	state_changed.emit()
	if ripened:
		EventBus.crop_grew.emit(tile_index)
	return ripened


## Midnight. Watering does not carry over; growth does.
##
## Called once per day for every tile by [FarmService]. It is a method on the
## tile rather than logic inside the service because the service walks the grid,
## it does not decide what a tile does.
##
## ## A crop only grows if it was watered
##
## The flag is read *before* it is cleared. Clearing first and then growing
## unconditionally is the obvious version and it makes watering pointless: the
## crop grows at the same rate whether or not anyone carried a can around. The
## read-then-clear order is what makes "did I remember to water this" a
## question with consequences.
func on_new_day() -> void:
	var was_watered := is_watered
	if is_watered:
		is_watered = false
		watered_changed.emit(false)
	if was_watered:
		grow_one_day()
	refresh_visual()
	# The dry night also emits: nothing else fired when a watered tile went dry,
	# and a plant holding moisture is not the same state as one that never had
	# any.
	state_changed.emit()


## Wipes the tile back to grass. Used by a new game and by any future
## "clear the plot" action.
func reset() -> void:
	is_tilled = false
	is_watered = false
	growth_days = 0
	_set_crop(&"")
	tilled_changed.emit(false)
	watered_changed.emit(false)
	refresh_visual()
	state_changed.emit()


## Edge length of this tile in metres.
##
## [FarmGrid] builds the tiles and owns the size, so it is the grid's number to
## answer with. A tile that has not been built yet reports the default rather
## than zero, because a zero here silently divides by zero in every reach check.
func tile_extent() -> float:
	return _tile_size


## Half the tile's width. What a tool swing should compare against when the
## player is standing *on* the tile, so reaching from the near edge counts.
func tile_half_extent() -> float:
	return _tile_size * 0.5


func has_crop() -> bool:
	return not crop_id.is_empty()


## Serialises the tile.
##
## The crop is stored as a string, never as a resource reference: a save that
## embedded a [CropData] would capture whatever that instance's fields happened
## to be at save time, and re-tuning the crop would silently rewrite history.
func to_dict() -> Dictionary:
	return {
		"index": [tile_index.x, tile_index.y],
		"tilled": is_tilled,
		"watered": is_watered,
		"crop_id": String(crop_id),
		"growth_days": growth_days,
	}


## Restores a bare tile from [method to_dict], without building meshes.
##
## Returns a tile that carries data only; [method FarmGrid.from_dict] copies that
## data onto the live tile it already has, because instantiating a second tile for
## a slot that is already occupied would give the farm two things in one place.
## Clamped field by field rather than rejecting the payload, for the same reason
## [method WorldTime.from_dict] does it: one corrupt int should cost one tile, not
## the whole farm.
static func from_dict(data: Dictionary) -> SoilTile:
	var tile := SoilTile.new()
	var raw_index: Variant = data.get("index", [0, 0])
	if raw_index is Array and (raw_index as Array).size() >= 2:
		var pair: Array = raw_index
		tile.tile_index = Vector2i(int(pair[0]), int(pair[1]))

	tile.is_tilled = bool(data.get("tilled", false))
	# Watered-but-untilled is impossible; the water flag follows the tilled flag.
	tile.is_watered = bool(data.get("watered", false)) and tile.is_tilled

	var id := StringName(str(data.get("crop_id", "")))
	# A crop standing on untilled soil is corrupt. Dropping the crop keeps the
	# tile usable instead of leaving it occupied by something unharvestable.
	if tile.is_tilled and not id.is_empty() and CropRegistry.get_crop(id) != null:
		tile.crop_id = id
		var crop := CropRegistry.get_crop(id)
		# Growth can never exceed the crop's own requirement: a larger number
		# would read back as instantly ripe, which is a quiet reward for editing
		# a save file.
		tile.growth_days = clampi(int(data.get("growth_days", 0)), 0, crop.days_to_grow)
	else:
		tile.crop_id = &""
		tile.growth_days = 0
	return tile


## Rebuilds every mesh from the tile's own data.
##
## Presentation is derived, never stored alongside the data, so a tile can never
## end up showing untilled soil while `is_tilled` is true — a class of bug that is
## invisible until a player saves mid-drag and reloads.
func refresh_visual() -> void:
	if _soil_mesh != null:
		var mat := _make_material(_soil_color())
		mat.roughness = 0.7 if is_watered else 1.0
		_soil_mesh.material_override = mat
	if crop_id.is_empty():
		_set_model_path("")
		if _crop_mesh != null:
			_crop_mesh.visible = false
		return
	var data := CropRegistry.get_crop(crop_id)
	if data == null:
		# Unknown crop: draw nothing rather than a wrong-coloured plant. The
		# warning belongs at load time, in the registry, not every repaint.
		_set_model_path("")
		if _crop_mesh != null:
			_crop_mesh.visible = false
		return

	var planted_fraction := growth_fraction()
	var stage := data.stage_model(planted_fraction)
	if not stage.is_empty():
		_set_model_path(stage)
		if _crop_model != null:
			_fit_model(data, stage, planted_fraction)
			_crop_model.visible = true
			if _crop_mesh != null:
				_crop_mesh.visible = false
			return
		# The model path is real content but would not load — a moved or corrupted
		# FBX. Fall through to the procedural stalk so the crop is still visible
		# rather than the tile looking empty.

	# No art for this crop, or its art failed to load: the procedural stalk, tinted
	# by growth. Its scaling is deliberately unchanged from before the model swap
	# so any crop added without art looks exactly as it did.
	_set_model_path("")
	if _crop_mesh == null:
		return
	_crop_mesh.visible = true
	# Blends sprout to ripe colour so growth is legible from a standing height.
	var tint := data.sprout_color.lerp(data.ripe_color, planted_fraction)
	_crop_mesh.material_override = _make_material(tint)
	var scale_v := lerpf(data.sprout_scale, 1.0, planted_fraction)
	# Ripeness gets a small extra lift so a harvestable field is obvious without
	# reading a single label.
	if is_ripe():
		scale_v *= 1.12
	_crop_mesh.scale = Vector3.ONE * scale_v


## Scales the parented model to the crop's art height, ramped by growth.
##
## One place owns model scale: [method CropArt.natural_height] already reports the
## height the model stands at *as imported*, including the FBX importer's
## centimetre conversion, so dividing the wanted height by it gives the exact
## uniform factor — composed with [method CropArt.root_scale] rather than
## replacing it, which is what keeps the unit conversion intact.
##
## Called on every growth repaint, so it only touches `scale` and never rebuilds
## the scene.
func _fit_model(data: CropData, stage: String, planted_fraction: float) -> void:
	var natural := CropArt.natural_height(stage)
	if natural <= 0.0:
		return
	var wanted := _model_height(data) * _growth_scale(planted_fraction)
	if is_ripe():
		# Same ripe lift the placeholder has always had, so a harvestable field is
		# as obvious with models as it was without them.
		wanted *= 1.12
	_crop_model.scale = CropArt.root_scale(stage) * (wanted / natural)
	# Quaternius pivots sit on the ground, so the model only needs lifting clear
	# of the soil plate, which is 0.06 thick and centred at 0.03.
	_crop_model.position = Vector3(0.0, _tile_size * 0.03, 0.0)


## Height in metres the crop's model should stand at, relative to the plot.
##
## Scales with the tile so a larger plot grows proportionally taller crops instead
## of models sized for the 2 m default.
func _model_height(data: CropData) -> float:
	return data.model_height * (_tile_size / 2.0)


## How large a modelled plant should read at [param planted_fraction] growth.
##
## Starts well under half size so a freshly planted tile looks like a seedling,
## and reaches 1.0 exactly at ripeness. Not [member CropData.sprout_scale] — that
## is a multiplier on the procedural cylinder, and reusing it here would make the
## model's size depend on an unrelated field.
func _growth_scale(planted_fraction: float) -> float:
	return lerpf(0.35, 1.0, planted_fraction)


## Parents the model at [param path] under this tile, or clears the current one.
##
## Only rebuilds when the stage actually changes, so the nightly growth pass over
## a field does not reinstantiate every model in the plot.
func _set_model_path(path: String) -> void:
	if path == _model_path and (path.is_empty() or _crop_model != null):
		return
	_model_path = path
	if _crop_model != null:
		remove_child(_crop_model)
		_crop_model.queue_free()
		_crop_model = null
	if path.is_empty():
		return
	var instance := CropArt.instantiate(path)
	if instance == null:
		# Do not record the path, so the next repaint retries rather than treating
		# this as "already has a model".
		_model_path = ""
		return
	instance.name = "CropModel"
	add_child(instance)
	_crop_model = instance


## Scene path of the CC0 model this tile is currently drawing, or `""` when it is
## falling back to the procedural plant.
##
## Public because the node name cannot answer it: every model instance is called
## `CropModel` so the scene tree stays readable, so the *stage* a tile is drawing
## is only knowable from the content it came from.
func current_model_path() -> String:
	return _model_path


func _set_crop(value: StringName) -> void:
	crop_id = value


func _soil_color() -> Color:
	if is_watered:
		return _soil_wet_color()
	return _soil_dry_color() if is_tilled else _soil_grass_color()


## Untilled: darker than the valley grass so the plot reads as bare ground
## waiting to be worked.
func _soil_dry_color() -> Color:
	return Color(0.42, 0.30, 0.19)


## Watered: darker and slightly saturated. The single most important visual
## state in a farming game, since "did I remember to water this" is asked every
## few seconds while planting.
func _soil_wet_color() -> Color:
	return Color(0.27, 0.19, 0.13)


func _soil_grass_color() -> Color:
	return Color(0.45, 0.33, 0.22)


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	# Godot 4 renamed SpatialMaterial.specular; using the old name logs a remap
	# warning per material at load.
	mat.metallic_specular = 0.1
	return mat