class_name StoryRegistry
extends RefCounted
## Loads the authored chapters from one directory, sorted into play order.
## Static and content-only, like [QuestRegistry], so a content test can read it
## without booting the game.

const DIRECTORY := "res://resources/story/chapters/"

static var _chapters: Array[StoryChapter] = []
static var _loaded: bool = false


static func all() -> Array[StoryChapter]:
	ensure_loaded()
	var out: Array[StoryChapter] = []
	for item: Resource in _chapters:
		if item is StoryChapter:
			out.append(item)
	return out


static func chapter_for(id: StringName) -> StoryChapter:
	for chapter: StoryChapter in all():
		if chapter.id == id:
			return chapter
	return null


static func first() -> StoryChapter:
	var chapters := all()
	return chapters[0] if not chapters.is_empty() else null


static func last() -> StoryChapter:
	var chapters := all()
	return chapters[chapters.size() - 1] if not chapters.is_empty() else null


static func duplicate_ids() -> Array[StringName]:
	var seen: Dictionary = {}
	var bad: Array[StringName] = []
	for chapter: StoryChapter in all():
		if seen.has(chapter.id) and not bad.has(chapter.id):
			bad.append(chapter.id)
		seen[chapter.id] = true
	return bad


static func clear_cache() -> void:
	_chapters.clear()
	_loaded = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			var chapter := ResourceLoader.load("%s%s" % [DIRECTORY, entry]) as StoryChapter
			if chapter != null and chapter.is_valid():
				_chapters.append(chapter)
			else:
				RuntimeLog.warn("StoryRegistry", "%s is not a valid chapter" % entry)
		entry = dir.get_next()
	dir.list_dir_end()
	_chapters.sort_custom(func(a: StoryChapter, b: StoryChapter) -> bool:
		return String(a.id) < String(b.id)
	)
