class_name MusicCue
extends Resource
## A selectable score plus the rules the MusicDirector obeys. Data, not code.

@export var id: StringName = &""
@export var display_name: String = ""
@export var score: MusicScore = null
## Higher wins. cutscene > boss > combat > festival > location > title.
@export_range(0, 100, 1) var priority: int = 10
@export_range(5.0, 600.0, 1.0) var min_play_seconds: float = 25.0
@export_range(0.0, 300.0, 1.0) var rest_seconds: float = 45.0
@export_range(0.1, 5.0, 0.1) var fade_seconds: float = 1.5
@export var tags: Array[StringName] = []


func is_valid() -> bool:
	return not id.is_empty() and score != null and score.is_valid()
