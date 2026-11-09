## Where the decoder keeps what it needs between launches: the server, who signed in, and the
## token that sign-in gave. One file for the mod (`user://mods/xenu.jellyfin/settings.json`), never
## the room's save slot: slots are shared, a token is a key to somebody's library.
##
## THE PASSWORD IS NEVER WRITTEN. It lives in the menu's field while it is typed and in the one
## request that signs in; what comes back is a token, and the token is what is kept (the same rule
## as RomM and RetroAchievements here). `forget_login()` throws the token away.
##
## The environment overrides it for the probes (XENU_JF_URL), so a test never touches the player's
## real file.
extends RefCounted

const MOD_ID := "xenu.jellyfin"
const FILE := "user://mods/xenu.jellyfin/settings.json"

## "quick" = Quick Connect, "password" = user + password.
const METHODS := ["quick", "password"]


static func _file() -> String:
	var over := OS.get_environment("XENU_JF_SETTINGS")
	return over if not over.is_empty() else FILE


static func load_all() -> Dictionary:
	var s: Dictionary = JsonStore.read_dict(_file(), MOD_ID)
	var url := OS.get_environment("XENU_JF_URL")
	if not url.is_empty():
		s["server"] = url
	if str(s.get("method", "")) not in METHODS:
		s["method"] = "quick"
	return s


static func save_all(s: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_file().get_base_dir())
	if not JsonStore.write_dict(_file(), s, MOD_ID):
		push_warning("[Jellyfin] could not write %s" % _file())


## Change one key and write the file.
static func set_value(key: String, value: Variant) -> void:
	var s := load_all()
	if value == null or (value is String and (value as String).is_empty()):
		s.erase(key)
	else:
		s[key] = value
	save_all(s)


## A stable random id for this install: the server lists it under the user's devices.
static func device_id() -> String:
	var s := load_all()
	var id := str(s.get("device_id", ""))
	if id.is_empty():
		id = "retroxr-" + Crypto.new().generate_random_bytes(8).hex_encode()
		s["device_id"] = id
		save_all(s)
	return id


## Sign out: the token and who it belonged to go; the server, the method and the language
## preferences stay.
static func forget_login() -> void:
	var s := load_all()
	for k in ["access_token", "user_id", "user_name"]:
		s.erase(k)
	save_all(s)
	print("[Jellyfin] signed out (token forgotten)")


static func signed_in(s: Dictionary) -> bool:
	return not str(s.get("access_token", "")).is_empty() and not str(s.get("user_id", "")).is_empty()
