class_name PlayerAvatarData
extends Resource
## What the player's body is made of.
##
## ## Why this exists when there is exactly one of it
##
## The obvious objection is that a single character does not need a catalogue, and it
## does not need a *system*. It is still a [Resource] rather than two constants in a
## generator for the same reason every other content kind in this project is data: the
## avatar is content, it is authored in the same place as the villagers' content, and it
## is the thing most likely to be swapped. When the KayKit body this started as is
## replaced — and it will be, because all five bodies in the pack are already spoken for
## by [NpcData] villagers — the change is one field here rather than a hunt through a
## generator.
##
## ## Why the body is a duplicate
##
## KayKit's character pack has five bodies. [NpcData] already uses all five across six
## villagers, which the pack's own licence permits and [method ModelArt.apply_tint]
## exists to make cheap: one body, recoloured, is how this project draws a whole cast
## from a handful of models. The player therefore shares a body with a villager and is
## told apart by [member model_tint], which is why the tint below is checked against
## every villager's by a test rather than picked by eye.
##
## Same fields, same names and same units as [NpcData], deliberately. Two definitions of
## "how tall is this character" that disagree by a few centimetres is a bug nobody finds
## until two people stand side by side and one is a head taller.

## The CC0 model this character is drawn from. A path rather than a [PackedScene] so a
## missing file is a content error a test reports, not a silent null in the scene.
@export var model: String = ""

## Multiplied into the model's albedo. Must differ from every villager's tint: the player
## and a villager wearing the same body in the same colours is two of the same person.
@export var model_tint: Color = Color(1, 1, 1, 1)

## Height in metres, feet to crown. Matches [member NpcData.target_height]'s range so the
## two cannot drift apart.
@export_range(0.5, 3.0, 0.05) var target_height: float = 1.75


## Whether this definition can actually be drawn.
##
## Checked rather than assumed, because every way this can be wrong is silent: a missing
## model draws nothing at all, and a non-positive height means "leave it at native size",
## which for a model authored at 100x scale is not a fallback but a bug.
func is_valid() -> bool:
	if model.is_empty():
		return false
	if target_height <= 0.0:
		return false
	return ModelArt.can_load(model)