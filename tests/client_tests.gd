## The REST client against tests/fake_jellyfin.py, over real HTTP. Needs a running fake server;
## tests/run_net_tests.py starts one, sets XENU_JF_URL and XENU_JF_SETTINGS (a scratch file, so the
## player's real settings are never touched) and runs this:
##
##   python3 tests/run_net_tests.py
extends SceneTree

const Api = preload("res://mods/xenu.jellyfin/scripts/jf_api.gd")
const Client = preload("res://mods/xenu.jellyfin/scripts/jf_client.gd")
const Config = preload("res://mods/xenu.jellyfin/scripts/jf_config.gd")
const Subs = preload("res://mods/xenu.jellyfin/scripts/jf_subtitles.gd")

const EXPECTED_CASES := 33

var _cases := 0
var _failed := 0
var _c: Node = null


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[jf-net] FAIL ", what)


func _eq(a: Variant, b: Variant, what: String) -> void:
	_cases += 1
	if a != b:
		_failed += 1
		print("[jf-net] FAIL ", what, ": got ", a, " want ", b)


## Run `starter(box)` and wait until it sets box.done (or `seconds` pass). Returns the box.
func _until(starter: Callable, seconds: float = 8.0) -> Dictionary:
	var box := {"done": false}
	starter.call(box)
	var t := Time.get_ticks_msec()
	while not box["done"] and float(Time.get_ticks_msec() - t) / 1000.0 < seconds:
		await process_frame
	return box


func _call_api(fn: Callable) -> Dictionary:
	return await _until(func(box: Dictionary) -> void:
		fn.call(func(ok: bool, data: Variant, code: int) -> void:
			box["ok"] = ok
			box["data"] = data
			box["code"] = code
			box["done"] = true))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var url := OS.get_environment("XENU_JF_URL")
	if url.is_empty():
		print("[jf-net] FAIL XENU_JF_URL is not set (run tests/run_net_tests.py)")
		quit(1)
		return
	_c = Client.new()
	root.add_child(_c)
	_c.configure(url)

	# open endpoints
	var r := await _call_api(_c.ping)
	_check(r.get("ok", false) and r["data"].get("ServerName") == "Fake Jellyfin", "ping answers with the server's name")
	r = await _call_api(_c.public_users)
	_check(r.get("ok", false) and (r["data"] as Array).size() == 2, "public users: two, loaded dynamically")
	_eq(r["data"][0]["Name"], "alice", "first public user")
	# a request needing a token, without one
	r = await _call_api(_c.views)
	_check(not r.get("ok", true), "views without a token is refused")

	# password sign-in: wrong, then right
	var fail_msg := {"m": ""}
	_c.sign_in_failed.connect(func(m: String) -> void: fail_msg["m"] = m)
	var ok_user := {}
	_c.signed_in.connect(func(u: Dictionary) -> void: ok_user.assign(u))
	_c.user_id = "u1"
	_c.sign_in_password("alice", "wrong")
	await _wait_for(func() -> bool: return fail_msg["m"] != "")
	_eq(fail_msg["m"], "wrong user or password", "a wrong password says so")
	_check(_c.token.is_empty(), "no token after a failed sign-in")
	_c.sign_in_password("alice", "secret")
	await _wait_for(func() -> bool: return not ok_user.is_empty())
	_eq(ok_user.get("Name"), "alice", "password sign-in")
	_eq(_c.token, "tok-pw", "the token is held")
	_eq(_c.user_id, "u1", "and the user id")

	# content
	r = await _call_api(_c.latest)
	var rows := Api.item_rows(r["data"])
	_eq(rows.size(), 3, "latest: bare array of three")
	_eq(rows[0]["series"], "Re:Zero", "latest: an episode knows its series")
	_eq(Api.latest_rows(r["data"]).size(), 2, "latest: the season's two episodes are one row, plus the movie")
	r = await _call_api(_c.next_up)
	_eq(Api.item_rows(r["data"]).size(), 1, "next up: one")
	r = await _call_api(_c.views)
	var libs := Api.library_rows(r["data"])
	_eq(libs.size(), 2, "views: music is left out")
	r = await _call_api(func(cb: Callable) -> void: _c.children("lib-movies", cb))
	_eq(Api.item_rows(r["data"]).size(), 3, "a library's items")
	r = await _call_api(func(cb: Callable) -> void: _c.children("lib-shows", cb))
	var series := Api.item_rows(r["data"])
	_eq(series[0]["kind"], "folder", "a series opens")
	r = await _call_api(func(cb: Callable) -> void: _c.seasons("series1", cb))
	_eq(Api.item_rows(r["data"])[0]["kind"], "folder", "a season opens")
	r = await _call_api(func(cb: Callable) -> void: _c.episodes("series1", "season2", cb))
	var eps := Api.item_rows(r["data"])
	_eq(eps.size(), 3, "three episodes")
	_eq(eps[2]["episode"], 3, "episode number")

	# tracks and the second (companion) track's words
	r = await _call_api(func(cb: Callable) -> void: _c.item("ep3", cb))
	var tr := Api.parse_tracks(r["data"])
	_eq(tr["audio"].size(), 2, "item: two audio tracks")
	_eq(tr["subs"].size(), 3, "item: three subtitle tracks")
	var pick := Api.pick_companion_track(tr["subs"], "eng")
	_eq(tr["subs"][pick]["label"], "English - SDH", "the companion track is the hearing-impaired one")
	var sub: Dictionary = tr["subs"][pick]
	r = await _call_api(func(cb: Callable) -> void:
		_c.get_text(Api.path_subtitle("ep3", "ms1", int(sub["index"])), cb))
	_check(r.get("ok", false), "the subtitle file is fetched")
	var cues: RefCounted = Subs.parse(str(r["data"]))
	_check(cues.line_at(9.0).contains("Emilia: Why would you say that?"), "and read at a given second")
	_eq(cues.recent(9.0, 2).size(), 2, "recent lines")

	# a stale token: refused and the client says so
	var refused := {"n": 0}
	_c.auth_failed.connect(func() -> void: refused["n"] += 1)
	_c.token = "stale"
	r = await _call_api(_c.views)
	_check(not r.get("ok", true) and r["code"] == 401, "a stale token is refused")
	_eq(refused["n"], 1, "and auth_failed fires once")

	# quick connect
	_c.token = ""
	_c.user_id = ""
	ok_user.clear()
	var code_seen := {"c": ""}
	_c.quick_connect_code.connect(func(c: String) -> void: code_seen["c"] = c)
	_c.sign_in_quick_connect()
	await _wait_for(func() -> bool: return code_seen["c"] != "")
	_eq(code_seen["c"], "123456", "quick connect shows its code")
	await _wait_for(func() -> bool: return not ok_user.is_empty(), 12.0)
	_eq(ok_user.get("Name"), "alice", "quick connect signs in once approved")
	_eq(_c.token, "tok-qc", "with the token it was given")

	# the settings file never gets a password
	Config.set_value("server", url)
	Config.set_value("access_token", _c.token)
	var written := FileAccess.get_file_as_string(OS.get_environment("XENU_JF_SETTINGS"))
	_check(not written.contains("secret") and not written.contains("Pw"), "no password in the settings file")
	_check(written.contains("tok-qc"), "the token is kept")
	Config.forget_login()
	_check(not FileAccess.get_file_as_string(OS.get_environment("XENU_JF_SETTINGS")).contains("tok-qc"), "signing out forgets the token")

	_finish()


func _wait_for(cond: Callable, seconds: float = 8.0) -> void:
	var t := Time.get_ticks_msec()
	while not cond.call() and float(Time.get_ticks_msec() - t) / 1000.0 < seconds:
		await process_frame


func _finish() -> void:
	print("[jf-net] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-net] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		quit(1)
		return
	quit(1 if _failed > 0 else 0)
