## The mod registers through the game's own ModApi: both objects exist, are offered on the SPAWN menu, and
## their scenes are the ones that load. Run through run_net_tests.py (a scratch settings file):
##   python3 tests/run_net_tests.py --scene tests/register_tests.tscn
extends Node

const EXPECTED_CASES := 10

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[jf-reg] FAIL ", what)


func _ready() -> void:
	_run.call_deferred()


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
	var tokens := []
	for row in SpawnCatalog.objects():
		tokens.append(str(row[1]))
	_check("mod:xenu.jellyfin:decoder" in tokens, "the Objects tab spawns the decoder as mod:xenu.jellyfin:decoder")
	print("[jf-reg] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-reg] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
