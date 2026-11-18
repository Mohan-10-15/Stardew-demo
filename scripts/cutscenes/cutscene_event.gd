class_name CutsceneEvent
extends Resource
## One step of a cutscene, as data.
##
## # The full guide lives in `docs/CUTSCENE_GUIDE.md`. This implementation uses
## one Resource with a `kind` and a parameter dictionary rather than one script
## per kind; the vocabulary, skip behaviour and restoration rules are the same,
## and adding a step is still a content edit rather than an `if` in `main.gd`.

enum SkipMode { SKIP_APPLY, SKIP_SKIP, SKIP_REQUIRED }

@export var kind: StringName = &"wait"
@export var params: Dictionary = {}
@export var skip_mode: SkipMode = SkipMode.SKIP_APPLY
## Seconds a `wait` lasts, or a `fade` transition takes.
@export var seconds: float = 1.0
## Text for a `dialogue` step; speaker is in `params`.
@export var text: String = ""


func is_valid() -> bool:
	return not kind.is_empty()
