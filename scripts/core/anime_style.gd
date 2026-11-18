class_name AnimeStyle
extends RefCounted
## Cel-shades the CC0 character meshes so the cast reads as bright-shonen anime
## rather than low-poly adventure miniatures.
##
## `diffuse_mode = 3` is Godot 4.5's Toon mode (Burley, Lambert, Lambert Wrap,
## Toon). A low `rim` with a dark tint fakes the inked outline a shader would
## give, without introducing a custom shader the rest of the world does not use.
## The original pack textures and the per-villager tints are kept: this is a
## lighting response change, not a content replacement.

const TOON_DIFFUSE := 3

## Inked outlines via the classic inverted hull: a second copy of each mesh,
## grown along its normals, drawn only on its back faces, in near-black.
const OUTLINE_PREFIX := "Outline_"
const OUTLINE_GROW := 0.012


## Applies the toon look to every mesh under [param root].
##
## Materials already overridden by [ModelArt.apply_tint] are safe to edit — they
## are per-(model,tint) duplicates. A mesh with no override owns its mesh's
## shared material, so it is duplicated first; editing that in place would
## cel-shade every other object using the same surface in the valley.
static func apply_to(root: Node3D) -> void:
	if root == null:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh := node as MeshInstance3D
			var mat := mesh.material_override as StandardMaterial3D
			if mat == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				var source := mesh.mesh.surface_get_material(0)
				if source is StandardMaterial3D:
					mat = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
					mesh.material_override = mat
			if mat != null:
				mat.diffuse_mode = TOON_DIFFUSE
				mat.rim_enabled = true
				mat.rim = 0.42
				mat.rim_tint = 0.0
				mat.metallic_specular = 0.12
				mat.roughness = 0.85
				_add_outline(mesh)
		for child: Node in node.get_children():
			stack.append(child)


## Adds the inked silhouette copy beside [param mesh].
##
## The copy keeps the original `skin`, so a skinned limb keeps following the
## same bones; without it the outline would stay in a T-pose while the body
## walked. The face plane is excluded — its ink is already drawn — and so are
## outlines made by an earlier application, which keeps this idempotent.
static func _add_outline(mesh: MeshInstance3D) -> void:
	if mesh.name == "FacePlane" or mesh.name.begins_with(OUTLINE_PREFIX):
		return
	if mesh.mesh == null or mesh.get_parent() == null:
		return
	if mesh.get_parent().get_node_or_null(OUTLINE_PREFIX + mesh.name) != null:
		return
	var outline := MeshInstance3D.new()
	outline.name = OUTLINE_PREFIX + mesh.name
	outline.mesh = mesh.mesh
	outline.skin = mesh.skin
	outline.transform = mesh.transform
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.035, 0.028, 0.055, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.grow = 1
	mat.grow_amount = OUTLINE_GROW
	outline.material_override = mat
	mesh.get_parent().add_child(outline)
