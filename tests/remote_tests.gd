## The game's own TV remote against a decoder, through RemoteTarget (the decoder joins the group "remote_target" and
## answers remote_layout / remote_activate): the cells, what the handset's keys press, the set's keys forwarded to the
## TV the decoder is cabled to, and the Jellyfin logo on the handset. Run through run_net_tests.py (a scratch settings
## file, so a test never touches the player's real server):
##
##   python3 tests/run_net_tests.py --scene tests/remote_tests.tscn
extends Node

const RemoteCells = preload("res://mods/xenu.jellyfin/scripts/decoder_remote.gd")

const EXPECTED_CASES := 53

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[jf-remote] FAIL ", what)


func _eq(a: Variant, b: Variant, what: String) -> void:
	_cases += 1
	if a != b:
		_failed += 1
		print("[jf-remote] FAIL ", what, ": got ", a, " want ", b)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var d: Node = (load("res://mods/xenu.jellyfin/scenes/jellyfin_decoder.tscn") as PackedScene).instantiate()
	add_child(d)
	d.ignore_gravity = true
	d.freeze = true
	var rscene: PackedScene = load("res://mods/xenu.jellyfin/scenes/jellyfin_remote.tscn")
	_check(rscene != null, "the remote scene loads")
	var r: TVRemote = rscene.instantiate() as TVRemote
	_check(r != null, "it is the game's own TVRemote (no clone)")
	add_child(r)
	r.freeze = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check(r.is_in_group("spawned"), "the remote is a spawned object")
	_check(r.get_script().resource_path.begins_with("res://Scripts/"), "and its script is the game's, untouched")

	# the logo, in place of RETRO XR
	var logo := r.find_child("JellyfinLogo", true, false) as Node3D
	_check(logo != null, "the handset wears the Jellyfin logo")
	if logo != null:
		_check(absf(logo.global_transform.basis.x.length() - 0.038) < 0.001, "38 mm wide (the turn kept its scale)")
		_check(logo.global_transform.basis.z.normalized().dot(Vector3.UP) > 0.99, "face up")
		_check(logo.global_transform.basis.y.normalized().dot(-r.global_transform.basis.z) > 0.99, "its top towards the tip")

	# the decoder is a target
	_check(d.is_in_group(RemoteTarget.GROUP), "the decoder joined the remote_target group in its _init")
	_check(RemoteTarget.of(d.get_node("PointerArea")) == d, "its pointable body walks up to it")
	var cells := RemoteTarget.layout(d)
	_eq(cells.size(), d.remote_layout().size(), "no cell of its layout is left out (all valid, inside the 3 columns)")
	var ids := {}
	for spec: Dictionary in cells:
		ids[str(spec["id"])] = true
	for need in ["power", "source", "vol_down", "mute", "vol_up", "back", "menu", "up", "down", "left", "right", "ok",
			"playpause", "stop", "rew", "ff", "prev", "next", "audio", "subtitle", "audio_list", "subtitle_list",
			"red", "green", "yellow", "cyan", "digit0", "digit9"]:
		_check(ids.has(need), "the layout has %s" % need)
	_eq(RemoteTarget.key_cell(d, "eject"), "back", "the handset's EJECT is BACK on the decoder")

	# the handset's keys press the cells
	r._target = d
	d.handle_key("menu")
	_eq(d._pages.page, 100, "(decoder on the index)")
	_eq(r.press_key("KeyDown"), "down", "the handset's DOWN is the decoder's down")
	_eq(d._pages.cursor, 1, "and the cursor moved")
	_eq(r.press_key("KeyEject"), "back", "EJECT presses BACK")
	_check(not r._cell_enabled("audio"), "AUDIO is greyed while nothing plays")

	# the set's own keys go to the TV the decoder is cabled to
	r._target = d
	_eq(r.press_key("KeyVolUp"), "", "VOL+ with no TV cabled does nothing")
	var tv: Node = (load("res://Scenes/Objects/tv.tscn") as PackedScene).instantiate()
	add_child(tv)
	await get_tree().process_frame
	d.connected_tv = tv
	r._target = d
	var vol0: float = tv.volume()
	_eq(r.press_key("KeyVolDown"), "vol_down", "VOL- is the set's cell, found by the handset's key")
	var vol1: float = tv.volume()
	_check(vol1 < vol0, "and the TV the decoder is cabled to really got quieter (%.2f -> %.2f)" % [vol0, vol1])
	_eq(r.press_key("KeyVolUp"), "vol_up", "VOL+ likewise")
	_check(tv.volume() > vol1, "and louder again")

	# the grid, as the floating menu builds it, and a state key's face
	r._target = d
	r._rebuild_grid()
	_eq(r._cells.size(), cells.size(), "the grid has every cell of the layout")
	d.is_playing = true
	d._paused = false
	_eq(RemoteCells.cell_face(d, "playpause")["glyph"], "pause", "PLAY shows PAUSE while it plays")
	d._paused = true
	_eq(RemoteCells.cell_face(d, "playpause")["glyph"], "play", "and PLAY when it is paused")

	print("[jf-remote] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-remote] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
