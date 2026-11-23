class_name NpcAnimator
extends RefCounted
## W4.4: maps schedule activity strings to the rig's 76 embedded clips.
## Pure mapping + a thin player wrapper, so a test can assert coverage without
## instantiating a world. The old procedural bone posing stays as fallback.

const DEFAULT_CLIP := &"Idle"

## Every activity string in resources/npc/schedules/*.tres must map to a clip
## that exists in the KayKit rigs (probe_rig.gd lists the 76 names).
const ACTIVITY_CLIPS: Dictionary = {
	&"idle": &"Idle",
	&"standing": &"Unarmed_Idle",
	&"talk": &"Interact",
	&"talking": &"Interact",
	&"walk": &"Walking_A",
	&"walking": &"Walking_A",
	&"errand": &"Walking_B",
	&"work": &"Use_Item",
	&"working": &"Use_Item",
	&"hoe": &"Use_Item",
	&"water": &"Use_Item",
	&"hammer": &"Use_Item",
	&"sweep": &"Use_Item",
	&"fish": &"Use_Item",
	&"fishing": &"Use_Item",
	&"sit": &"Sit_Chair_Idle",
	&"sitting": &"Sit_Chair_Idle",
	&"sleep": &"Lie_Idle",
	&"sleeping": &"Lie_Idle",
	&"pick up": &"PickUp",
	&"cheer": &"Cheer",
	&"dance": &"Cheer",
	&"eat": &"Use_Item",
	&"drink": &"Use_Item",
	&"wave": &"Interact",
	&"read": &"Unarmed_Idle",
	&"guard": &"Blocking",
}


static func clip_for(activity: StringName) -> StringName:
	var key := String(activity).to_lower().strip_edges()
	if ACTIVITY_CLIPS.has(StringName(key)):
		return ACTIVITY_CLIPS[StringName(key)]
	# Schedule activities are prose ("balancing the books", "at the festival").
	# Match a known verb inside the prose so new authored lines still animate.
	for verb: StringName in ACTIVITY_CLIPS:
		if key.contains(String(verb)) and String(verb).length() >= 4:
			return ACTIVITY_CLIPS[verb]
	return DEFAULT_CLIP


static func find_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child: Node in root.get_children():
		var found := find_player(child)
		if found != null:
			return found
	return null


## Plays the clip for [param activity] if the rig has it. Returns false when
## the rig or clip is absent, which is the signal to fall back to bone posing.
static func play(root: Node, activity: StringName) -> bool:
	var player := find_player(root)
	if player == null:
		return false
	var clip := clip_for(activity)
	if not player.has_animation(clip):
		return false
	player.play(clip)
	return true
