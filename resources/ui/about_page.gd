class_name AboutPage
extends Resource
## One page of "what is this game?" shown from the title screen and Help.
## Data, not code: the copy is written by tools/generate_about_data.gd and
## checked by a test for length, BBCode balance and screen fit.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var body: String = ""
@export var icon: String = ""
@export var order: int = 0


func is_valid() -> bool:
	return not id.is_empty() and not title.is_empty() \
		and not body.strip_edges().is_empty() and body.length() <= 600 \
		and _bbcode_balanced()


func _bbcode_balanced() -> bool:
	var stack: Array[String] = []
	var i := 0
	while i < body.length():
		if body[i] == "[" and i + 1 < body.length() and body[i + 1] != "/":
			var end := body.find("]", i)
			if end < 0:
				return false
			stack.append(body.substr(i + 1, end - i - 1))
			i = end + 1
			continue
		if body[i] == "[" and i + 1 < body.length() and body[i + 1] == "/":
			var end := body.find("]", i)
			if end < 0 or stack.is_empty():
				return false
			var tag := body.substr(i + 2, end - i - 2)
			if stack.pop_back() != tag:
				return false
			i = end + 1
			continue
		i += 1
	return stack.is_empty()
