class_name ResourceFiles
extends RefCounted
## Lists content files in a directory in both source and exported builds.
##
## In the editor a definition is `foo.tres`. The exporter rewrites it to
## `foo.res` plus a `foo.tres.remap` redirect, so a registry that filters only
## `.tres` sees an empty directory in a shipped build — the shop counter goes
## inert and the whole content graph disappears. One helper fixes every
## registry without a per-file special case.

static func is_resource(entry: String) -> bool:
	return entry.ends_with(".tres") or entry.ends_with(".res") \
		or entry.ends_with(".tres.remap") or entry.ends_with(".res.remap")


## Builds a path ResourceLoader can follow (the .tres path resolves through its
## .remap redirect in an exported build).
static func path_for(dir_path: String, entry: String) -> String:
	var name := entry
	if name.ends_with(".remap"):
		name = name.trim_suffix(".remap")
	return dir_path.path_join(name)
