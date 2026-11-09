## The cloned remote against a decoder: what its keys do, that the TV keys reach the set the decoder is
## cabled to, and the keyboard's digits and F-keys. Run through run_net_tests.py (it points the mod's
## settings at a scratch file, so a test never touches the player's real server):
##
##   python3 tests/run_net_tests.py --scene tests/remote_tests.tscn
extends Node

const EXPECTED_CASES := 41

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
	var r: Node = rscene.instantiate()
	add_child(r)
	r.freeze = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check(r.is_in_group("spawned"), "the remote is a spawned object")
	_check(r._is_decoder(d), "the remote knows a decoder")
	_check(not r._is_decoder(r), "and a remote is not one")

	# the handset wears the Jellyfin logo (sized, face up, top towards the tip), RETRO XR printed over
	var logo := r.find_child("JellyfinLogo", true, false) as Node3D
	_check(logo != null, "the remote has the Jellyfin logo")
	if logo != null:
		_check(absf(logo.global_transform.basis.x.length() - 0.038) < 0.001, "it is 38 mm wide (not a metre: the turn kept its scale)")
		_check(logo.global_transform.basis.z.normalized().dot(Vector3.UP) > 0.99, "it faces up")
		_check(logo.global_transform.basis.y.normalized().dot(-r.global_transform.basis.z) > 0.99, "its top is towards the tip")
	r._target = d
	var ids := {}
	for spec: Dictionary in r._layout_for_target():
		ids[str(spec["id"])] = true
	for need in ["back", "menu", "up", "down", "left", "right", "ok", "playpause", "stop", "rew", "ff", "audio", "subtitle",
			"red", "green", "yellow", "cyan", "digit0", "digit9"]:
		_check(ids.has(need), "the decoder's layout has %s" % need)
	var rows := 0
	for spec: Dictionary in r._layout_for_target():
		rows = maxi(rows, int(spec["row"]) + 1)
	_check(rows <= 11, "the decoder's grid is at most 11 rows tall (it ran off a small window at 13)")
	_check(ids.has("digit5") and ids.has("digit6") and ids.has("digit1"), "all ten digits are there")
	r._nrows = rows
	var win_view := Vector2(1275, 722)
	var fit: float = r.desktop_menu_scale(rows, 70.0, false, win_view)
	_check(fit < 1.0 and fit > 0.35, "the grid shrinks to fit a 1275 x 722 window")
	_check(r.desktop_menu_scale(5, 70.0, true, Vector2(1920, 1080)) == 1.0, "and a short one is left alone")
	_eq(r.cell_for_key("KeyEject"), "back", "the handset's EJECT is BACK on the decoder")
	_eq(r.cell_for_key("KeyOk"), "ok", "OK is OK")

	# the keys do what the cells do
	d.handle_key("menu")
	_eq(d._pages.page, 100, "(decoder on the index)")
	r.press_key("KeyDown")
	_eq(d._pages.cursor, 1, "the handset's DOWN moves the cursor on the TV pages")
	_check(not r._cell_enabled("audio"), "AUDIO is greyed while nothing plays")

	# the set's own keys go to the set the decoder is cabled to
	_eq(r.press_key("KeyVolUp"), "", "VOL+ with no TV cabled does nothing (and says so)")
	var tvs: PackedScene = load("res://Scenes/Objects/tv.tscn")
	if tvs != null:
		var tv: Node = tvs.instantiate()
		add_child(tv)
		await get_tree().process_frame
		d.connected_tv = tv
		r._target = d   # a remote that is not held drops its target every frame
		_eq(r.press_key("KeyVolUp"), "vol_up", "VOL+ reaches the TV the decoder is cabled to")
		_check(r._target == d or r._target == tv, "(target restored after the redirect)")
	else:
		_check(false, "the classic TV scene did not load")
		_check(false, "(skipped)")

	# keyboard, held on a desktop and aimed at the decoder
	r._target = d
	r._desktop_held = true
	var press := func(code: Key) -> void:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.pressed = true
		r._unhandled_input(e)
	press.call(KEY_F2)
	_eq(d._pages.page, 102, "F2 is the green key: what's next")
	press.call(KEY_1)
	press.call(KEY_0)
	press.call(KEY_1)
	_eq(d._pages.page, 101, "typing 1 0 1 goes to page 101")

	print("[jf-remote] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-remote] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
