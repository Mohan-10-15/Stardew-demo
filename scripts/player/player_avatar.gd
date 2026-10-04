class_name PlayerAvatar
extends Node3D
## Draws the player's body from a [PlayerAvatarData] definition, the way [Npc] draws a
## villager's.
##
## ## Why it is built here and not baked into `player.tscn`
##
## The obvious version bakes the imported model into the generated scene, and it was
## tried: the generator instantiates the model, scales it, grounds it and tints it, and
## the saved scene has a transform on `Model` and nothing else. No tint.
##
## The reason is [member Node.owner]. Packing writes the transforms of a node's *owned*
## children; an instanced model is saved as a reference to the FBX with a transform
## override, and everything set on its children — including the per-surface
## `material_override` that [method ModelArt.apply_tint] installs — is discarded, because
## those children belong to the FBX scene and not to this one. The generator printed the
## tint it had applied, the scene loaded clean, and the player rendered as an untinted
## [Rogue.fbx]: exactly the same body as [code]fen[/code], in the same colours, which is
## the one thing the tint exists to prevent.
##
## Building at runtime keeps the tint, and has the side benefit the tint cache was written
## for: the player's Rogue and fen's Rogue share one imported scene and one pair of
## duplicated materials, rather than each carrying a private copy baked into a text file.
##
## ## Ordering
##
## The rig hides the body in first person, and it discovers the meshes to hide by walking
## the player. So the body has to exist before [method CameraRig._discover_body_meshes]
## runs, which it does not have to *rely* on: [method _register_with_rig] below hands the
## meshes over explicitly, and [method CameraRig.register_body_mesh] applies the current
## visibility on the spot. Registering before the rig's own `_ready` is harmless, because
## the rig re-applies visibility when it initialises.

const DEFAULT_DEFINITION := "res://resources/player/player_avatar.tres"

## The [PlayerAvatarData] to draw. Overridable so a test can hand this component a
## definition of its own rather than mutating the shipped one.
@export var definition_path: String = DEFAULT_DEFINITION

## Set once the body exists, whether or not it drew.
var built: bool = false

var _definition: PlayerAvatarData = null
var _model: Node3D = null
var _box: AABB = AABB()


func _ready() -> void:
	build()


## Draws the body. Returns whether it drew, and says why in the log when it did not.
##
## Public and idempotent, because the player is instantiated by a generator and then
## sometimes re-equipped mid-game, and a second body appearing inside the first is worse
## than a missing one.
func build() -> bool:
	if _model != null:
		return true
	_definition = load(definition_path) as PlayerAvatarData
	if _definition == null:
		Log.error("PlayerAvatar", "no avatar definition at %s" % definition_path)
		return false
	if not _definition.is_valid():
		Log.error("PlayerAvatar", "%s is not a drawable avatar" % definition_path)
		return false

	# `body_aabb` before `instantiate`, because the ground offset is measured in the
	# model's own units and has to be scaled by however much the body was resized.
	#
	# `body_aabb` and not `natural_aabb`: this file is a character, and a character in this
	# pack is a body *plus its whole armoury* under one imported root. Measured whole, the
	# box is 4.1m wide, the offset comes out 0.7m wrong, and the avatar stands buried to
	# the ankles in the floor.
	_box = ModelArt.body_aabb(_definition.model)
	_model = ModelArt.instantiate_standing(_definition.model, _definition.target_height)
	if _model == null:
		Log.error("PlayerAvatar", "cannot instantiate %s" % _definition.model)
		return false
	var weapons := ModelArt.strip_attachments(_model)
	_model.name = "Body"
	# Standing on this node's origin. The imported root sits at the character's hips, so
	# without this the feet are a metre below the player's origin: the camera is a metre
	# too low in first person and the body is buried to the waist in third.
	_model.position.y = -_box.position.y * _model.scale.y
	add_child(_model)
	if not ModelArt.is_white(_definition.model_tint):
		ModelArt.apply_tint(_model, _definition.model_tint)

	built = true
	_register_with_rig()
	Log.info("PlayerAvatar", "%s at %.2fm, tint %s%s" % [
		_definition.model.get_file(), _definition.target_height, _definition.model_tint,
		"" if weapons == 0 else ", dropped %d held props" % weapons,
	])
	return true


## The definition this avatar was built from, or null before [method build].
func get_definition() -> PlayerAvatarData:
	return _definition


## The model node, or null before [method build]. Tests and the playtest read the real
## geometry through here rather than trusting the definition to match what drew.
func get_model() -> Node3D:
	return _model


## This body's measured bounds in world units, in [member Node3D] local space.
##
## Measured by walking the built model rather than read from [member
## PlayerAvatarData.target_height], because the definition says how tall it was *asked*
## to be and this says how tall it ended up. Those differ whenever the importer's
## conversion and the requested height disagree, and only one of the two is what a player
## sees.
func measured_bounds() -> AABB:
	if _model == null:
		return AABB()
	# Spelled out rather than `_box * _model_xform()`. The operator form was returning a
	# box whose lowest corner sat 0.163m below the floor on a body that was standing on it,
	# with the scale applied correctly and only the translation landing in the wrong place
	# — an AABB is a value type with no room to be wrong *partly*, so reading this as
	# "scale the corners, then move them" is both the shorter comment and the arithmetic
	# that can be checked against the two numbers printed beside it.
	var moved := _box.position * _model.scale + _model.position
	return AABB(moved, _box.size * _model.scale)


## Hands every mesh to the camera rig so it can hide the body in first person.
##
## Best-effort by design: the player exists in tests without a rig, and a body that drew
## is not a failure because nothing wanted to hide it.
func _register_with_rig() -> void:
	var rig := get_node_or_null(^"../CameraRig") as CameraRig
	if rig == null or _model == null:
		return
	for mesh: MeshInstance3D in _meshes(_model):
		rig.register_body_mesh(mesh)


static func _meshes(from: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if from == null:
		return out
	if from is MeshInstance3D:
		out.append(from as MeshInstance3D)
	for child: Node in from.get_children():
		out.append_array(_meshes(child))
	return out