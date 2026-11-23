class_name CollectionData
extends Resource
## A data-driven set of things the valley remembers. Six of these call the
## six Embers home; the last tier of each yields one Ember.

@export var id: StringName = &""
@export var display_name: String = ""
@export var ember: StringName = &""
## "item" ids are recorded from item events; "npc" ids from friendship events.
@export_enum("item", "npc") var kind: String = "item"
@export var entries: Array[StringName] = []
@export var tiers: Array[CollectionTier] = []


func is_valid() -> bool:
	if id.is_empty() or display_name.is_empty() or ember.is_empty() \
			or entries.size() < 6 or tiers.size() != 3:
		return false
	for tier: CollectionTier in tiers:
		if tier == null or not tier.is_valid():
			return false
	return true
