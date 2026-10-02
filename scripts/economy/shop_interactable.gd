class_name ShopInteractable
extends Interactable
## Makes a [Shop] reachable by the interaction probe, and names it in the prompt.
##
## A subclass rather than a configured [Interactable] because the prompt has to
## follow the *content*: it reads the shop's display name, and it has to report a
## counter that has no definition rather than offering a trade that cannot happen.
## Doing either from a `prompt_text` string would mean the author keeps two copies
## of the same name in step.

## The counter this component stands for. Assigned by [method Shop._ready].
var shop: Shop = null

## Emitted after a successful [method interact], for [Shop] to relay.
signal opened(actor: Node)


## Where the crosshair should point to focus this counter.
##
## Overridden because the inherited default puts the aim point 0.9m above the
## counter's origin, which for a stall built by [WorldBuilder] is precisely the
## *top surface* of the counter box. Aiming at the exact top edge of a collider is
## a coin flip: the ray either skims over it or catches the rounded edge, and
## either way the shop intermittently cannot be focused. Aim at the middle of the
## front face instead — comfortably inside the collider, and the part a player
## would actually be looking at.
##
## Offset slightly clear of the face on the +Z side, the direction a shopper
## approaches from, so the ray meets the surface rather than starting inside it.
func get_aim_point() -> Vector3:
	var host := get_parent() as Node3D
	if host == null:
		return super()
	return host.global_position + Vector3(0.0, 0.55, 0.45)


## Opens the counter.
##
## Returns true whenever the counter is reachable, even though no trade happens
## here — opening is the interaction, and the UI that follows owns the buying. A
## false return would make the probe treat it as a refusal and tell the player
## nothing happened, which is the opposite of what pressing E on a shop should do.
func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	opened.emit(actor)
	return true


func get_prompt(_actor: Node) -> String:
	if shop == null or shop.shop == null:
		# Named rather than silent. A shop with no content loaded is a bug, and a
		# prompt that still offered a trade would hide it.
		return "%s (unstaffed)" % prompt_text
	# Concatenated rather than run through a `%` format: a shop display name is
	# content, and content containing a percent sign must not be able to break its
	# own prompt.
	return "%s %s" % [prompt_text, shop.shop.display_name]