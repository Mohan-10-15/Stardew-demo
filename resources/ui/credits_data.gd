class_name CreditsData
extends Resource
## The shipped credits screen, written by tools/generate_credits_data.gd.
## Every CC0 / CC-BY asset in ASSET_LICENSES.md must appear here.

@export var title: String = "Credits"
@export var entries: Array[CreditEntry] = []
