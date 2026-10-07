class_name DialogueChoice
extends Resource
## One reply the player can pick, and what saying it does.
##
## Replies are content like everything else: the text the player reads, the line
## the reply leads to, and the consequences of making it — all in the `.tres`,
## none of it in code. A dialogue system where the branching lives in `match`
## statements is a system where adding a reply means recompiling the game.
##
## A reply with no [member next] ends the conversation after its effects apply,
## which is how "Maybe later." closes a story beat without the tree needing an
## explicit end node.

## What the player reads on the button. Never empty — [method DialogueTree.is_valid]
## refuses a nameless reply, because a blank button in a choice row is a trap the
## player walks into by clicking it.
@export var text: String = ""

## The entry id this reply leads to, or [code]&""[/code] to end the conversation.
##
## Not validated against the tree from here: a choice is a fragment, and only the
## [DialogueTree] that contains it can know which ids exist. That check lives in
## [method DialogueTree.is_valid], so a dangling reply fails the content test by
## name rather than at the moment the player clicks it.
@export var next: StringName = &""

## Hearts granted when this reply is taken. Whole hearts, through the same
## [Friendship] the gift system uses, so a meaningful conversation moves the
## relationship by the same measure a present does. Never negative: a reply the
## player chose freely costing friendship with no warning would be a trap, and
## [method DialogueTree.is_valid] refuses it.
@export var hearts: int = 0

## Story flags raised by taking this reply. Cross-conversation memory: a flag set
## here can gate a line in this villager's tree or any other's, which is how
## "I told Bram about the river" gets to matter later.
@export var set_flags: Array[StringName] = []


## Whether this reply leads somewhere rather than ending the conversation.
func has_next() -> bool:
	return not next.is_empty()


## One-line summary for a validation message.
func describe() -> String:
	return "choice '%s' -> %s" % [text, next if has_next() else "(end)"]
