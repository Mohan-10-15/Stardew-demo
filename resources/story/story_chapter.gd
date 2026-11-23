class_name StoryChapter
extends Resource
## One chapter of the valley's main story, as data.
##
## A chapter opens when all of its `requires` flags are set. The last one is the
## ending, after which the service keeps running in free play rather than
## stopping the game — the brief requires both the ending and continuation.

@export var id: StringName = &""
@export var title: String = ""
@export var description: String = ""
## Flags that must all be set before this chapter can open.
@export var requires: Array[StringName] = []
## Cutscene requested when the chapter opens, if any.
@export var cutscene_id: StringName = &""
## Gold paid when the chapter opens. A chapter is content, not a code branch.
@export var reward_gold: int = 0
## The final chapter: reaching it publishes `story_ending_reached`.
@export var is_ending: bool = false
## Update 2 story spine. Existing ids are never renamed or renumbered (saves).
@export var act: int = 1
@export var order: int = 0


func is_valid() -> bool:
	return not id.is_empty() and not title.is_empty()
