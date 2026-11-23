class_name CharacterProfile
extends Resource
## Per-character anime styling. Data, so twelve villagers are twelve rows
## rather than twelve `if id ==` branches in the NPC script (content is data).

@export var id: StringName = &""
@export var display_name: String = ""
@export var model: String = ""
@export_range(1.4, 2.2, 0.05) var target_height: float = 1.8
## 0=slim, 1=average, 2=broad, 3=short, 4=tall — applied to bone scales.
@export_range(0, 4, 1) var build: int = 1
@export_range(1.0, 1.45, 0.01) var head_scale: float = 1.15
@export var hair_style: StringName = &"short"
@export var hair_color: Color = Color(0.2, 0.16, 0.12)
@export var eye_color: Color = Color(0.35, 0.55, 0.72)
@export var skin_tone: Color = Color(0.96, 0.82, 0.72)
@export var palette: Array[Color] = []
@export var accessory: StringName = &""
@export var spring_hair: bool = false
@export_range(0.6, 1.6, 0.05) var voice_pitch: float = 1.0
@export var portrait_framing: float = 0.42


func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() \
		and not model.is_empty() and palette.size() >= 3


## Stable signature used by the test that proves all twelve are distinct.
func signature() -> String:
	return "%s|%s|%s|%s|%s" % [
		model, hair_style, eye_color.to_html(false),
		"/".join(palette.map(func(c: Color) -> String: return c.to_html(false))),
		str(build),
	]
