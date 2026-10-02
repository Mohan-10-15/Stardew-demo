class_name ResourceDrop
extends RigidBody3D
## One pile of something lying on the ground, waiting to be walked over.
##
## A physical object rather than an immediate inventory change, because "the log fell
## over there and I have to walk over and pick it up" is the whole reason a tree is
## worth chopping in a game with a walk button.
##
## ## Why a rigid body on its own physics layer
##
## [constant PhysicsLayers.RESOURCE] exists for exactly this. On
## [constant PhysicsLayers.WORLD] a drop would shove the player around as it settled,
## which reads as a bug and gets reported as one. Here it is solid against the
## ground — so it lands, rests, and does not sink through the world — and invisible
## to the player's own collider — so walking over it feels like nothing at all.
##
## ## Why it polls instead of connecting
##
## [signal body_entered] does not fire for a body that is *already* overlapping when
## the area is created, and a drop spawned by felling a tree is very often created
## inside the player. Connecting only would lose exactly the pickup the player is
## standing in the middle of, which is the one they notice. [method _physics_process]
## polls instead, and stops entirely once collected.

## Emitted when the player is close enough to take it. Carries the drop rather than
## the item, because the service owns the inventory and needs to ask the drop what it
## still has.
signal pickup_requested(drop: ResourceDrop)

## What this pile is.
@export var item_id: StringName = &""
## How many units. Taken as a whole or not at all: a drop that gave "the rest of it"
## would need a partial-pickup rule, and a bag with no room should leave the whole
## pile on the ground where the player can see it.
@export var amount: int = 1

var _area: Area3D = null
var _collected: bool = false
var _mesh: MeshInstance3D = null


func _ready() -> void:
	collision_layer = PhysicsLayers.RESOURCE
	# Ground only. Two logs knocking each other around in a heap that never settles
	# is a worse artefact than logs that sink gently through one another.
	collision_mask = PhysicsLayers.RESOURCE_MASK
	linear_damp = 0.6
	angular_damp = 1.0
	continuous_cd = true
	_build_body()
	_build_pickup_area()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.14
	shape.shape = sphere
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.13
	sphere_mesh.height = 0.26
	sphere_mesh.radial_segments = 8
	sphere_mesh.rings = 4
	_mesh.mesh = sphere_mesh
	# A tinted ball, not the item's icon. An icon is a flat texture and these are
	# lit 3D spheres; the swatch colour is the cheapest thing that still says "that is
	# the copper".
	var material := StandardMaterial3D.new()
	material.albedo_color = _swatch_colour()
	material.roughness = 0.7
	_mesh.material_override = material
	add_child(_mesh)


func _swatch_colour() -> Color:
	var definition := ItemRegistry.get_item(item_id)
	if definition == null:
		return Color(0.6, 0.5, 0.4)
	return definition.icon_color


## The overlap test, deliberately without a layer or mask of its own.
##
## The area watches for the player only. If it also watched for the world it would
## report every piece of terrain the drop was resting against, and the "am I touching
## something" question would need a second answer nobody asked.
func _build_pickup_area() -> void:
	_area = Area3D.new()
	_area.name = "PickupArea"
	_area.collision_layer = 0
	_area.collision_mask = PhysicsLayers.PLAYER
	_area.monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.85
	shape.shape = sphere
	shape.position = Vector3(0.0, 0.1, 0.0)
	_area.add_child(shape)
	add_child(_area)


func _physics_process(_delta: float) -> void:
	if _collected or _area == null or not is_inside_tree():
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is PlayerController:
			pickup_requested.emit(self)
			return


## Marks this drop as taken and takes it out of the world.
##
## Called by [GatheringService] once the item is actually in the bag. Removing the
## drop *before* the inventory accepted it is how wood evaporates; removing it after
## is how it duplicates.
func collect() -> void:
	if _collected:
		return
	_collected = true
	set_physics_process(false)
	queue_free()


func is_collected() -> bool:
	return _collected


func to_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"amount": amount,
		"position": global_position,
	}


## "3 Wood", for a debug line or a notification.
func describe() -> String:
	var label := ItemRegistry.display_name_of(item_id)
	return label if amount == 1 else "%d %s" % [amount, label]