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


## Where the box goes on the SPAWN menu: the Electronics tab of a RetroXR that has one (the "tab" of a prop's menu,
## RetroXR 3b75d782 and later). An older RetroXR has one list only, so the key is left out and the props land
## on its Objects tab; and a RetroXR that has tabs but not this one would REFUSE the registration, hence the look
## first (SpawnCatalog is read through its script: naming a constant it lacks would not even parse there).
const WANTED_TAB := "electronics"


static func game_has_tab(tab: String) -> bool:
	for row: Dictionary in ProjectSettings.get_global_class_list():
		if str(row.get("class", "")) == "SpawnCatalog":
			var script := load(str(row.get("path", ""))) as GDScript
			if script == null:
				return false
			var tabs: Variant = script.get_script_constant_map().get("SPAWN_TABS", {})
			return tabs is Dictionary and (tabs as Dictionary).has(tab)
	return false


## The menu spec of a prop: its label, and the tab when this game has it.
static func menu_for(label: String) -> Dictionary:
	var menu := {"label": label}
	if game_has_tab(WANTED_TAB):
		menu["tab"] = WANTED_TAB
	return menu


func register(api: ModApi) -> void:
	api.log_line("registering")
	api.register_object(DECODER_TYPE, "res://mods/xenu.jellyfin/scenes/jellyfin_decoder.tscn",
		menu_for("Jellyfin Decoder"))
	# The handset for it: the game's own TV remote, dressed with the logo (it drives the decoder through RemoteTarget) (see remote_livery.gd and decoder_remote.gd).
	api.register_object(REMOTE_TYPE, "res://mods/xenu.jellyfin/scenes/jellyfin_remote.tscn",
		menu_for("Jellyfin Decoder Remote"))
