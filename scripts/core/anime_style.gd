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
		for child: Node in node.get_children():
			stack.append(child)
