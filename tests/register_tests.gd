## The mod registers through the game's own ModApi: both objects exist, are offered on the SPAWN menu, and
## their scenes are the ones that load. Run through run_net_tests.py (a scratch settings file):
##   python3 tests/run_net_tests.py --scene tests/register_tests.tscn
extends Node

const EXPECTED_CASES := 14

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[jf-reg] FAIL ", what)


func _ready() -> void:
	_run.call_deferred()


## Whether this game's SPAWN menu has an Electronics tab (read through the script, as the mod does).
func _game_has_electronics() -> bool:
	var tabs: Variant = (load("res://Scripts/Data/systems/spawn_catalog.gd") as GDScript).get_script_constant_map().get("SPAWN_TABS", {})
	return tabs is Dictionary and (tabs as Dictionary).has("electronics")


func _run() -> void:
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://mods/xenu.jellyfin/mod.json"))
	_check(json is Dictionary, "mod.json parses")
	var manifest := ModManifest.parse(json as Dictionary)
	_check(manifest != null and manifest.id == "xenu.jellyfin", "the manifest is valid and named xenu.jellyfin")
	_check(manifest.claims.is_empty(), "it claims no shipped file")
	var script := load(manifest.entry) as GDScript
	_check(script != null, "the entry script loads")
	var api := ModApi.new(manifest, ModHooks.new(get_tree()))
	(script.new() as RetroMod).register(api)
	for type in ["xenu.jellyfin:decoder", "xenu.jellyfin:remote"]:
		_check(ScenePersistence.is_mod_object(type), "%s is a registered object" % type)
		var scene_path := ScenePersistence.mod_object_scene(type)
		_check(load(scene_path) is PackedScene, "%s's scene loads" % type)
	var labels := []
	for item: Dictionary in SpawnCatalog.mod_spawnables():
		labels.append(item["label"])
	_check("Jellyfin Decoder" in labels and "Jellyfin Decoder Remote" in labels, "both are on the SPAWN menu")
	# On the Electronics tab of a game that has one; on the only list (Objects) of an older one.
	var has_tab := _game_has_electronics()
	var tab_rows: Array = SpawnCatalog.tab_rows("electronics") if has_tab else SpawnCatalog.objects()
	var tokens := []
	for row in tab_rows:
		tokens.append(str(row[1]))
	var tab_name := "Electronics" if has_tab else "Objects"
	_check("mod:xenu.jellyfin:decoder" in tokens, "the %s tab spawns the decoder as mod:xenu.jellyfin:decoder" % tab_name)
	_check("mod:xenu.jellyfin:remote" in tokens, "the %s tab spawns the remote" % tab_name)
	_check(script.call("game_has_tab", "electronics") == has_tab, "the mod's own look at the game's tabs agrees (%s)" % has_tab)
	_check((script.call("menu_for", "X") as Dictionary).has("tab") == has_tab, "the tab is named only when the game has it")
	if has_tab:
		var on_objects := []
		for row in SpawnCatalog.objects():
			on_objects.append(str(row[1]))
		_check(not ("mod:xenu.jellyfin:decoder" in on_objects), "the decoder is on Electronics alone, not on Objects too")
	else:
		_check(true, "an older game has no tabs: nothing to be on twice")
	print("[jf-reg] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-reg] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
