class_name CutscenePlayer
extends Resource
## An authored cutscene: an id and an ordered list of steps.
##
## Data only. The director owns playback, the lock and restoration, so a
## cutscene can be interrupted at any step without this resource knowing.

@export var id: StringName = &""
@export var events: Array[CutsceneEvent] = []
@export var title: String = ""


func is_valid() -> bool:
	if id.is_empty() or events.is_empty():
		return false
	for event: CutsceneEvent in events:
		if event == null or not event.is_valid():
			return false
	return true
