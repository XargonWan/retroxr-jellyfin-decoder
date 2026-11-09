## A server that IGNORES Range requests (tests/fake_jellyfin.py --no-range): a seek on the direct stream cannot work, so
## resuming a half-watched film must go through a transcoded stream that starts at the place it was left, and say so
## to the server (PlayMethod Transcode, the place in ticks).
##
##   python3 tests/run_net_tests.py --scene tests/resume_tests.tscn --no-range
extends Node

const Pages = preload("res://mods/xenu.jellyfin/scripts/jf_pages.gd")

const EXPECTED_CASES := 10

var _cases := 0
var _failed := 0
var _d: Node = null


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[jf-resume] FAIL ", what)


func _eq(a: Variant, b: Variant, what: String) -> void:
	_cases += 1
	if a != b:
		_failed += 1
		print("[jf-resume] FAIL ", what, ": got ", a, " want ", b)


func _wait_for(cond: Callable, seconds: float = 12.0) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call() and float(Time.get_ticks_msec() - t) / 1000.0 < seconds:
		await get_tree().process_frame
	return cond.call()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_d = (load("res://mods/xenu.jellyfin/scenes/jellyfin_decoder.tscn") as PackedScene).instantiate()
	add_child(_d)
	_d.ignore_gravity = true
	_d.freeze = true
	_check(await _wait_for(func() -> bool: return _d.link == "need_login"), "the decoder finds the server")
	_d.ui_sign_in("alice", "secret")
	_check(await _wait_for(func() -> bool: return _d.link == "ready"), "and signs in")
	_d.handle_key("menu")
	for dg in [1, 0, 3]:
		_d.handle_key("digit%d" % dg)
	_check(await _wait_for(func() -> bool: return (_d._pages.current()["rows"] as Array).size() == 2), "Continue watching lists the half-watched items")
	_d.handle_key("ok")
	_check(await _wait_for(func() -> bool: return _d.mode == 1 and _d.is_playing), "OK plays the first")
	_check(await _wait_for(func() -> bool: return _d._range_state != "unknown", 8.0), "the Range probe answers")
	_eq(_d._range_state, "no", "and finds the server ignores Range")
	_check(await _wait_for(func() -> bool: return _d._using_hls, 15.0), "so resuming goes through a transcoded stream")
	_check(await _wait_for(func() -> bool: return _d._have_picture and _d._position_s() >= 5.0, 15.0), "that starts at the place it was left (5 s), with a picture")
	_eq(_d._pos_offset, 5.0, "(the stream's own clock starts at 5 s)")
	_d.seek_by(1.0)
	await get_tree().create_timer(1.0).timeout
	var box := {"done": false, "list": []}
	_d._client.get_text("/_test/reports", func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			var parsed: Variant = JSON.parse_string(str(data))
			if parsed is Array:
				box["list"] = parsed
		box["done"] = true)
	await _wait_for(func() -> bool: return box["done"], 5.0)
	var transcoded := false
	for r: Dictionary in box["list"]:
		var b: Dictionary = r["body"]
		if r["kind"] == "progress" and str(b.get("PlayMethod", "")) == "Transcode" and int(b.get("PositionTicks", 0)) >= 50000000:
			transcoded = true
	_check(transcoded, "and the server is told it is a transcode, at or after the place it was left")
	print("[jf-resume] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-resume] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
