## Dresses the game's own TV remote with the Jellyfin logo (a child of the remote's scene: the remote is the base game's
## script, untouched). Runs before the remote dresses its keys, so the model's levels are pinned first.
extends Node

const Livery = preload("res://mods/xenu.jellyfin/scripts/decoder_livery.gd")


func _ready() -> void:
	var model := get_parent().get_node_or_null("Model") as ApplianceModel
	if model == null:
		push_warning("[Jellyfin] the remote has no Model node: no logo")
		return
	Livery.dress_remote(model)
