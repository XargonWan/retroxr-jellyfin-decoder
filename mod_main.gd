## Jellyfin Decoder -- a RetroXR mod.
##
## A VCR-like box that signs in to a Jellyfin server and shows its libraries on the TV as a
## Teletext / Televideo service. The logic (scripts/jf_*.gd) is pure and tested;
## jellyfin_decoder.gd is the object, teletext_view.gd what it shows on the TV.
##
## The type strings are written into save slots; they are permanent once anyone has used them.
extends RetroMod

const DECODER_TYPE := "xenu.jellyfin:decoder"
const REMOTE_TYPE := "xenu.jellyfin:remote"


func register(api: ModApi) -> void:
	api.log_line("registering")
	api.register_object(DECODER_TYPE, "res://mods/xenu.jellyfin/scenes/jellyfin_decoder.tscn",
		{"label": "Jellyfin Decoder"})
	# The handset for it: a clone of the TV remote that also drives the decoder (see jellyfin_remote.gd).
	api.register_object(REMOTE_TYPE, "res://mods/xenu.jellyfin/scenes/jellyfin_remote.tscn",
		{"label": "Jellyfin Decoder Remote"})
