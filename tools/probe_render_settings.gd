extends SceneTree
## What the live renderer is actually feeding the ground. Written after a
## pixel sample showed the grass reading R144 G166 B175 (blue-grey) instead of
## green, which no albedo change could explain.

const WORLD := "res://scenes/world/world.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe_mat := StandardMaterial3D.new()
	var keys: Array[String] = []
	for prop: Dictionary in probe_mat.get_property_list():
		var key := String(prop["name"])
		if key.contains("diffuse") or key.contains("toon") or key.contains("rim") \
				or key.contains("shading") or key.contains("specular") \
				or key.contains("grow") or key.contains("cull") or key.contains("outline"):
			keys.append(key)
	keys.sort()
	print("MATERIAL keys: %s" % str(keys))
	for value: int in [0, 1, 2, 3, 4]:
		probe_mat.set("diffuse_mode", value)
		print("  diffuse_mode %d -> %s" % [value, str(probe_mat.get("diffuse_mode"))])
	probe_mat.set("specular_mode", 0)
	print("  specular_mode 0 -> %s" % str(probe_mat.get("specular_mode")))
	print("AMBIENT_SOURCE enum: COLOR=%d SKY=%d" % [
		Environment.AMBIENT_SOURCE_COLOR,
		Environment.AMBIENT_SOURCE_SKY,
	])
	var packed := load(WORLD) as PackedScene
	var world := packed.instantiate() as Node3D
	root.add_child(world)
	await process_frame
	var we := _find(world, "Environment") as WorldEnvironment
	var env: Environment = we.environment if we != null else null
	if env != null:
		print("env ambient_source=%d color=%s energy=%.3f" % [
			env.ambient_light_source, str(env.ambient_light_color),
			env.ambient_light_energy,
		])
		print("env fog=%s mode=%d density=%.4f depth=%.2f..%.2f curve=%.2f color=%s" % [
			str(env.fog_enabled), env.fog_mode, env.fog_density,
			env.fog_depth_begin, env.fog_depth_end, env.fog_depth_curve,
			str(env.fog_light_color),
		])
		print("env adjust=%s sat=%.3f tonemap=%d exposure=%.3f" % [
			str(env.adjustment_enabled), env.adjustment_saturation,
			env.tonemap_mode, env.tonemap_exposure,
		])
	var sun := _find(world, "Sun") as DirectionalLight3D
	if sun != null:
		print("sun energy=%.3f color=%s shadow=%s rot=%s" % [
			sun.light_energy, str(sun.light_color), str(sun.shadow_enabled),
			str(sun.rotation_degrees),
		])
	var ground := _find(world, "GroundMesh") as MeshInstance3D
	if ground != null:
		var mat := ground.material_override as StandardMaterial3D
		if mat != null:
			print("ground albedo=%s texture=%s vertex_color=%s rough=%.2f" % [
				str(mat.albedo_color), str(mat.albedo_texture != null),
				str(mat.vertex_color_use_as_albedo), mat.roughness,
			])
	quit(0)


func _find(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null
