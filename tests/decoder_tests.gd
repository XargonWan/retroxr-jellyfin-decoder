## The decoder object, in the real game, against tests/fake_jellyfin.py: sign in both ways, walk the pages
## with the remote's key ids down to an episode, play it (a small video made by run_net_tests.py with two
## audio and three subtitle tracks), change tracks, and ask what is on -- with a "reading companion" in
## the room, as the Synth is.
##
##   python3 tests/run_net_tests.py --scene tests/decoder_tests.tscn
extends Node

const Api = preload("res://mods/xenu.jellyfin/scripts/jf_api.gd")
const Pages = preload("res://mods/xenu.jellyfin/scripts/jf_pages.gd")
const LogoMesh = preload("res://mods/xenu.jellyfin/scripts/logo_mesh.gd")
const Livery = preload("res://mods/xenu.jellyfin/scripts/decoder_livery.gd")

const EXPECTED_CASES := 156

var _cases := 0
var _failed := 0
var _d: Node = null


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[jf-obj] FAIL ", what)


func _eq(a: Variant, b: Variant, what: String) -> void:
	_cases += 1
	if a != b:
		_failed += 1
		print("[jf-obj] FAIL ", what, ": got ", a, " want ", b)


func _wait_for(cond: Callable, seconds: float = 10.0) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call() and float(Time.get_ticks_msec() - t) / 1000.0 < seconds:
		await get_tree().process_frame
	return cond.call()


## What the client told the fake server about playback (its test hook).
func _fetch_reports() -> Array:
	var box := {"done": false, "list": []}
	_d._client.get_text("/_test/reports", func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			var parsed: Variant = JSON.parse_string(str(data))
			if parsed is Array:
				box["list"] = parsed
		box["done"] = true)
	await _wait_for(func() -> bool: return box["done"], 5.0)
	return box["list"]


## The first report of `kind` (and `event`, "" = any) about `item`, as its body, or {}.
func _find_report(reports: Array, kind: String, item: String, event: String = "") -> Dictionary:
	for r: Dictionary in reports:
		var b: Dictionary = r["body"]
		if r["kind"] == kind and str(b.get("ItemId", "")) == item and (event == "" or str(b.get("EventName", "")) == event):
			return b
	return {}


## Press a key of the box (its own VRButton), as a hand would.
func _box_key(id: String) -> void:
	var names := {"up": "UpButton", "down": "DownButton", "left": "LeftButton", "right": "RightButton", "ok": "OkButton", "stop": "StopButton"}
	_d.get_node(names[id]).button_pressed.emit()


## Move the on-screen keyboard's cursor to (col, row) with the box's cross, then press OK.
func _press_key_at(at: Vector2i) -> void:
	for i in 40:
		var pg = _d._pages
		if pg.osk_col == at.x and pg.osk_row == at.y:
			break
		if pg.osk_row < at.y:
			_box_key("down")
		elif pg.osk_row > at.y:
			_box_key("up")
		elif pg.osk_col < at.x:
			_box_key("right")
		else:
			_box_key("left")
	_box_key("ok")


func _type_text(text: String) -> void:
	for ch in text:
		_press_key_at(Pages.osk_locate(ch))


func _press_special(kind: String) -> void:
	var row: Array = Pages.osk_layout()[4]
	for c in row.size():
		if row[c]["kind"] == kind:
			_press_key_at(Vector2i(c, 4))


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var url := OS.get_environment("XENU_JF_URL")
	var scene: PackedScene = load("res://mods/xenu.jellyfin/scenes/jellyfin_decoder.tscn")
	_check(scene != null, "the decoder scene loads")
	if scene == null or url.is_empty():
		print("[jf-obj] FAIL no scene or no XENU_JF_URL")
		get_tree().quit(1)
		return
	_d = scene.instantiate()
	add_child(_d)
	_d.ignore_gravity = true
	_d.freeze = true
	await get_tree().process_frame
	await get_tree().process_frame

	# what it is
	_check(_d.is_in_group("spawned"), "it is a spawned object (saved with the room)")
	_check(not _d.is_in_group("vcr_player"), "and not a VCR to the code that looks for VCRs")
	_check(AvSourceContract.missing_in_script(_d.get_script()).is_empty(), "it answers the A/V source contract")
	_check(_d.get_node_or_null("TapeSlot") == null or _d.get_node("TapeSlot").is_queued_for_deletion(), "no tape slot")
	_check(_d.get_node_or_null("VideoOut") != null and _d.get_node_or_null("AudioLOut") != null, "it keeps the three phono sockets")
	_check(_d.link in ["checking", "need_login"], "with a server configured it goes looking for it at once")
	# the front: no cassette bay, the logo a quarter of the strip and a long display the other three quarters
	var model: Node = _d.get_node("Model")
	_check(not _d._model.part("Door").visible and not _d._model.part("CassetteHolder").visible, "the cassette door and holder are hidden")
	_check(model.find_child("BayPlate", true, false) != null, "a faceplate closes the cassette opening")
	_check(model.find_child("JellyfinLogo", true, false) != null, "the Jellyfin logo is on the front")
	# the logo reads whatever the light: unshaded, a true white, and the brand's own gradient
	var logo_mat := LogoMesh.material()
	_check(logo_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "the logo is unshaded (a white wordmark did not read as white in a dim room)")
	_eq(LogoMesh.mesh().get_surface_count(), 2, "the icon and the lettering are two surfaces")
	_check(LogoMesh.material(true).albedo_color.r > LogoMesh.material(false).albedo_color.r, "the lettering is driven brighter than the icon (Filmic would grey a plain white)")
	var cols: Array = LogoMesh.data()["colors"]
	var has_white := false
	var has_purple := false
	var has_blue := false
	for i in range(0, cols.size(), 3):
		if cols[i] > 0.99 and cols[i + 1] > 0.99 and cols[i + 2] > 0.99:
			has_white = true
		if absf(cols[i] - 0.667) < 0.02 and absf(cols[i + 1] - 0.361) < 0.02 and absf(cols[i + 2] - 0.765) < 0.02:
			has_purple = true
		if cols[i] < 0.02 and absf(cols[i + 1] - 0.643) < 0.02 and absf(cols[i + 2] - 0.863) < 0.02:
			has_blue = true
	_check(has_white and has_purple and has_blue, "with white lettering and the gradient's ends, #AA5CC3 and #00A4DC")
	_check(model.find_child("BlankPlate", true, false) != null, "the slots of the removed keys are closed")
	var strip := Livery.strip_width()
	var dsz := Livery.display_size()
	_check(absf(Livery.display_x0() - (Livery.STRIP_X0 + strip * Livery.LOGO_CELL) - Livery.DISPLAY_MARGIN) < 1e-6, "the display starts after the logo's quarter")
	_check(Livery.display_x1() + Livery.DISPLAY_MARGIN <= Livery.cross_center().x - Livery.cross_width() * 0.5 + 1e-6, "and ends before the cross (it gave up its right end)")
	_check(Livery.logo_center().x < Livery.display_center().x - dsz.x * 0.5, "and the logo is BEFORE it")
	_check(Livery.LOGO_WIDTH < strip * Livery.LOGO_CELL and Livery.LOGO_WIDTH > strip * Livery.LOGO_CELL * 0.7, "the logo fills most of its quarter")
	_check(dsz.x > 0.126 * 1.4, "the display is still much longer than the VCR's 126 mm")
	_check(_d._vfd.size_m.is_equal_approx(dsz), "the LED display is that size")
	_check(_d._model.switch_distance > 1000.0, "the close model level is drawn at every distance (the far ones have the bay baked in)")
	_eq(_d._vfd_lines().size(), 2, "the display has two lines")
	_check(_d.get_video_stage(null).is_empty(), "browsing the pages is not given the VHS look (a page is meant to be read)")
	_check(_d._vfd_offset("MOVIE", 68, 5) == 0.0, "a short title stands still")
	_check(_d._vfd_offset("X".repeat(90), 68, 5) > 0.0, "a title too long for the display steps along")
	_eq(_d.now_playing()["playing"], false, "nothing is playing")
	_eq(_d.now_playing()["text"], "nothing", "and it says nothing")

	# the picture it gives the set
	_d._feed_video = true
	_check(_d.get_video_texture() != null, "while browsing it gives the set the teletext picture")
	var users := []
	_d.users_loaded.connect(func(u: Array) -> void: users.assign(u))

	# sign in: wrong then right
	_d.ui_set_server(url)
	_check(await _wait_for(func() -> bool: return _d.link == "need_login"), "a reachable server asks for a sign-in")
	_check(await _wait_for(func() -> bool: return users.size() == 2), "the users are loaded from the server")
	_d.ui_sign_in("alice", "wrong")
	_check(await _wait_for(func() -> bool: return _d.link_text.begins_with("Sign-in failed")), "a wrong password is refused")
	_d.ui_sign_in("alice", "secret")
	_check(await _wait_for(func() -> bool: return _d.link == "ready"), "the right one signs in")
	_eq(_d.user_name, "alice", "as alice")
	_check(await _wait_for(func() -> bool: return (_d._pages.views[Pages.PAGE_LATEST]["rows"] as Array).size() == 2), "recently added is filled")
	var latest: Array = _d._pages.views[Pages.PAGE_LATEST]["rows"]
	_eq(latest[0]["detail"], "+2 EP", "recently added: the season is one row saying episodes were added")
	_eq(latest[0]["kind"], "folder", "and it opens to the season")
	_eq((_d._pages.views[Pages.PAGE_NEXT]["rows"] as Array).size(), 1, "what's next is filled")
	_eq((_d._pages.views[Pages.PAGE_INDEX]["rows"] as Array).size(), 6, "the index lists four sections (incl. Continue watching and Search) and two libraries")
	_check(_d._pages.status.is_empty(), "the status page is gone once connected")

	# the keys on the box: the cross, OK, skip back, play, skip forward, stop -- and not eject, pause or rec
	for kn in ["UpButton", "DownButton", "LeftButton", "RightButton", "OkButton", "RewindButton", "PlayButton", "FastForwardButton", "StopButton"]:
		_check(_d.get_node_or_null(kn) is VRButton, "the box has its %s" % kn)
	for gone in ["EjectButton", "PauseButton", "RecordButton"]:
		_check(_d.get_node_or_null(gone) == null or _d.get_node(gone).is_queued_for_deletion(), "and no %s" % gone)
	var up: Node3D = _d.get_node("UpButton")
	var down: Node3D = _d.get_node("DownButton")
	var left: Node3D = _d.get_node("LeftButton")
	var right: Node3D = _d.get_node("RightButton")
	var okb: Node3D = _d.get_node("OkButton")
	_check(up.position.y > okb.position.y and okb.position.y > down.position.y and is_equal_approx(up.position.x, down.position.x), "the cross: up over OK over down, in one column")
	_check(left.position.x < okb.position.x and okb.position.x < right.position.x and is_equal_approx(left.position.y, right.position.y), "and left, OK, right in one row")
	var half_key := Livery.CROSS_CAP * 0.5
	var strip_lo: float = Livery.STRIP_Y - Livery.STRIP_HEIGHT * 0.5
	var strip_hi: float = Livery.STRIP_Y + Livery.STRIP_HEIGHT * 0.5
	_check(down.position.y - half_key.y >= strip_lo and up.position.y + half_key.y <= strip_hi, "the cross fits the strip's height (it does not spill off the panel)")
	_check(right.position.x + half_key.x <= Livery.STRIP_X1 and left.position.x - half_key.x >= Livery.display_x1(), "and sits at its right end, after the display")
	_check(is_equal_approx((_d.get_node("OkButton/ButtonMesh") as MeshInstance3D).mesh.get_aabb().size.x, 0.016), "its keys are as big as the model's own (16 mm)")
	_check((_d.get_node("OkButton/ButtonMesh") as MeshInstance3D).mesh is BoxMesh and _d.get_node("OkButton/ButtonMesh/Glyph") != null, "its keys are capped and printed")
	_eq(_d._pages.page, 100, "(on the index)")
	_d.get_node("DownButton").button_pressed.emit()
	_eq(_d._pages.cursor, 1, "the box's DOWN moves the cursor down")
	_d.get_node("UpButton").button_pressed.emit()
	_eq(_d._pages.cursor, 0, "UP moves it back")
	_d.get_node("OkButton").button_pressed.emit()
	_eq(_d._pages.page, 101, "OK opens the page under the cursor")
	_d.get_node("StopButton").button_pressed.emit()
	_eq(_d._pages.page, 100, "STOP goes back (nothing plays)")
	# walk to an episode with the remote's key ids: Anime > Re:Zero > Season 2 > episode 3
	_d.handle_key("menu")
	for i in 5:
		_d.handle_key("down")
	_d.handle_key("ok")
	_eq(_d._pages.page, 111, "the second library opens its page")
	_check(await _wait_for(func() -> bool: return (_d._pages.current()["rows"] as Array).size() == 1), "its items load")
	_d.handle_key("ok")
	_check(await _wait_for(func() -> bool: return (_d._pages.current()["rows"] as Array).size() == 1 and _d._pages.current()["rows"][0]["type"] == "Season"), "a series opens to its seasons")
	_d.handle_key("ok")
	_check(await _wait_for(func() -> bool: return (_d._pages.current()["rows"] as Array).size() == 3), "a season opens to its episodes")
	_d.handle_key("down")
	_d.handle_key("down")

	# a reader in the room, as the Synth is
	var reader := Node3D.new()
	reader.add_to_group("companion_viewer")
	reader.set_meta("companion_lang", "eng")
	add_child(reader)
	var changes := []
	_d.now_playing_changed.connect(func(i: Dictionary) -> void: changes.append(i))
	_d.handle_key("ok")
	_check(await _wait_for(func() -> bool: return _d.mode == 1 and _d.is_playing, 15.0), "OK on an episode starts it")
	var np: Dictionary = _d.now_playing()
	_eq(np["kind"], "episode", "it knows it is an episode")
	_eq(np["series"], "Re:Zero", "and which series")
	_eq(np["season"], 2, "which season")
	_eq(np["episode"], 3, "which episode")
	_eq(np["title"], "Re:Union", "and its title")
	_check(str(np["text"]).begins_with("Re:Zero, season 2, episode 3 'Re:Union', at "), "and says it in words")
	_check(not changes.is_empty(), "the start was announced to whoever listens")
	_eq(_d.game_label, "Re:Zero S2E3", "a short label for other mods")
	var words: PackedStringArray = _d._vfd_lines()
	_eq(words[0], "RE:ZERO", "the display says the series")
	_eq(words[1], "S2 E3  RE:UNION", "and the season, episode and title")
	_check(await _wait_for(func() -> bool: return _d._companion != null, 12.0), "the reader's text track is fetched (the server's SDH one)")
	_eq(_d._companion_label, "English - SDH", "it is the hearing-impaired track")
	np = _d.now_playing()
	_check(np.has("recent") and np.has("line"), "the line just said is available to the reader")
	_eq(np["words_from"], "English - SDH", "and says where it comes from")
	_check(str(_d._companion.line_at(9.0)).contains("Emilia"), "the track holds the dialogue by time")
	_check(_d.get_node_or_null("DecoderOptionsPanel") == null, "no menu opened by itself")
	# the contract other mods (the Synth) read: what now_playing() carries and what the box calls itself
	for k in ["playing", "kind", "title", "series", "season", "episode", "paused", "position_s", "length_s", "text", "line", "recent"]:
		if not np.has(k):
			_check(false, "now_playing() carries %s" % k)
	_check(_d.has_method("companion_kind") and _d.companion_kind() == "Jellyfin decoder", "the box names itself for other mods")
	_check(str(np["text"]) != "" and np["position_s"] is float, "text and a numeric position")
	_check(_d.is_powered_on(), "and says it is switched on")

	# the picture while playing
	_check(await _wait_for(func() -> bool: return _d._have_picture, 15.0), "a first picture arrives")
	_check(_d.get_video_texture() != _d._view.texture(), "the set gets the film now, not the teletext")

	# the VHS look is the deck's: the film gets the stage, the pages and the chooser do not
	var stage: Dictionary = _d.get_video_stage(null)
	_check(stage.has("shader") and stage["shader"] != null and stage["params"].has("scanline_strength"), "the film goes through the VHS stage (the deck's, with its own scanlines)")
	_d.set_vhs_effect(false)
	_check(_d.get_video_stage(null).is_empty(), "switched off, the film gets the set's tube alone")
	_d.set_vhs_effect(true)
	_d.handle_key("subtitle_list")
	_check(_d.get_video_stage(null).is_empty(), "and under a chooser (the pages' picture) it is not applied")
	_d.handle_key("menu")
	_check(not _d.get_video_stage(null).is_empty(), "closing the chooser brings it back")

	# the SKIP keys jump seconds, as the clients' do (Jellyfin's web client: 30 s forward, 10 s back; settable here)
	_eq(_d.skip_forward_s, 30, "skip forward is 30 s by default, as in Jellyfin's web client")
	_eq(_d.skip_back_s, 10, "and skip back 10 s")
	_d.set_skips(3, 4)
	var p0: float = _d._position_s()
	_d.get_node("FastForwardButton").button_pressed.emit()
	_check(await _wait_for(func() -> bool: return _d._position_s() > p0 + 3.0, 6.0), "SKIP FORWARD on the box jumps ahead by the set length")
	var p1: float = _d._position_s()
	_d.get_node("RewindButton").button_pressed.emit()
	_check(await _wait_for(func() -> bool: return _d._position_s() < p1 - 1.0, 6.0), "SKIP BACK jumps back")
	_d.handle_key("ff")
	_check(await _wait_for(func() -> bool: return _d._position_s() > p1 + 1.0, 6.0), "and the remote's FF does the same length")
	_d.set_skips(10, 30)
	_d.set_paused(true)
	_d.set_paused(false)

	# tracks from the remote
	_d.cycle_audio()
	_eq(_d._audio_ordinal, 1, "AUDIO moves to the next audio track")
	_d.cycle_subtitle()
	_eq(_d._sub_ordinal, 0, "SUBTITLE turns the first one on")
	_d.cycle_subtitle()
	_d.cycle_subtitle()
	_d.cycle_subtitle()
	_eq(_d._sub_ordinal, -1, "and round to off again")
	_d.handle_key("subtitle_list")
	_check(not _d._pages.overlay.is_empty() and (_d._pages.overlay["rows"] as Array).size() == 4, "the subtitle chooser lists Off and three tracks")
	_d.handle_key("down")
	_d.handle_key("down")
	_d.handle_key("ok")
	_eq(_d._sub_ordinal, 1, "choosing from the chooser switches to it")
	_d.handle_key("digit7")
	_d.handle_key("digit7")
	_d.handle_key("digit8")
	_eq(_d._pages.overlay.get("kind", ""), "audio", "typing 778 opens the audio chooser, as on Televideo")
	_d.handle_key("menu")

	# stopping
	_d.get_node("StopButton").button_pressed.emit()
	_eq(_d.mode, 0, "STOP on the box goes back to the pages")
	_eq(_d.now_playing()["playing"], false, "and nothing is playing")
	_eq(_d.game_label, "", "the label is cleared")

	# the TAB menu: open it, see it filled, close it
	_d.toggle_options_ui(null)
	for i in 6:
		await get_tree().process_frame
	var panel := _d.get_node_or_null("DecoderOptionsPanel")
	_check(panel != null, "TAB builds the menu panel as the decoder's child")
	_check(panel != null and panel.visible, "and shows it")
	var ui: Control = panel._get_ui() if panel != null else null
	_check(ui != null, "its 2D page is loaded")
	_check(ui != null and ui.get("_status") != null and str(ui._status.text) != "", "the page shows the decoder's status")
	# Over the box, not off to the side or above the head (the first build hung it 2 m up from a box on a table).
	_check(panel != null and panel.global_position.distance_to(_d.global_position) < 1.0
			and panel.global_position.y >= _d.global_position.y, "the menu hangs over the decoder, within a metre of it")
	_d.toggle_options_ui(null)
	_check(panel != null and not panel.visible, "TAB again hides it")

	# Search: a keyboard on the TV, worked with the box's own cross and OK; the results are a page of their own
	_d.handle_key("menu")
	_eq(str((_d._pages.views[Pages.PAGE_INDEX]["rows"] as Array)[3]["title"]), "Search", "Search is on the main page")
	for dg in [1, 0, 4]:
		_d.handle_key("digit%d" % dg)
	_eq(_d._pages.page, 104, "typing 104 opens the search page")
	_check(_d._pages.osk_active(), "it is the on-screen keyboard")
	_type_text("ZEROX")
	_eq(_d._pages.search_text, "ZEROX", "the box's cross and OK type on it")
	_press_special("del")
	_eq(_d._pages.search_text, "ZERO", "DEL rubs out the last letter")
	_eq(_d._vfd_lines()[1], "SEARCH: ZERO_", "and the LED display shows what is typed")
	_check(Pages.line_text(_d._view.current_lines()[5]).contains("ZERO"), "so does the teletext page")
	_press_special("go")
	_check(await _wait_for(func() -> bool: return _d._pages.page >= 200 and (_d._pages.current()["rows"] as Array).size() == 1), "SEARCH lists what the server found")
	_eq(_d._pages.current()["rows"][0]["type"], "Series", "a series, which opens to its seasons")
	_check(str(_d._pages.current()["title"]).begins_with("SEARCH: ZERO"), "under a title that says what was asked")
	_box_key("stop")
	_eq(_d._pages.page, 104, "STOP goes back to the keyboard")
	_eq(_d._pages.search_text, "ZERO", "with its text kept, to refine")
	_press_special("clear")
	_eq(_d._pages.search_text, "", "CLEAR empties it")
	_type_text("QQQ")
	_press_special("go")
	_check(await _wait_for(func() -> bool: return _d._pages.page >= 200 and str(_d._pages.current().get("empty", "")).begins_with("NO RESULTS")), "a search that finds nothing says so")
	_box_key("stop")
	_box_key("stop")
	_eq(_d._pages.page, 100, "(back on the index)")

	# what the box told the server, as every client does
	await get_tree().create_timer(0.8).timeout
	var reports := await _fetch_reports()
	var started := _find_report(reports, "start", "ep3")
	_check(not started.is_empty(), "it reported the start of playback")
	_check(str(started.get("MediaSourceId", "")) == "ms1" and str(started.get("PlayMethod", "")) == "DirectPlay" and str(started.get("PlaySessionId", "")) != "", "with the source, how it plays and a session")
	_eq(int(started.get("AudioStreamIndex", -1)), 1, "and the audio track it plays")
	_check(not _find_report(reports, "progress", "ep3", "Pause").is_empty() and bool(_find_report(reports, "progress", "ep3", "Pause").get("IsPaused", false)), "it reported the pause")
	_check(not _find_report(reports, "progress", "ep3", "Unpause").is_empty(), "and the resume")
	_check(not _find_report(reports, "progress", "ep3", "AudioTrackChange").is_empty(), "a change of audio track")
	_check(not _find_report(reports, "progress", "ep3", "SubtitleTrackChange").is_empty(), "and of subtitles")
	_check(not _find_report(reports, "progress", "ep3", "TimeUpdate").is_empty(), "and its position as it jumped")
	var stopped := _find_report(reports, "stopped", "ep3")
	_check(not stopped.is_empty() and int(stopped.get("PositionTicks", 0)) > 0, "it reported where it stopped (a position, in ticks)")
	_eq(stopped.get("PlaySessionId", "x"), started.get("PlaySessionId", "y"), "in the same session it started")

	# Continue watching: listed on the index, and playing from it picks up where it was left
	_d.handle_key("menu")
	_check(str((_d._pages.views[Pages.PAGE_INDEX]["rows"] as Array)[2]["title"]) == "Continue watching", "Continue watching is on the main page")
	for dg in [1, 0, 3]:
		_d.handle_key("digit%d" % dg)
	_eq(_d._pages.page, 103, "typing 103 opens it")
	_check(await _wait_for(func() -> bool: return (_d._pages.current()["rows"] as Array).size() == 2), "the half-watched items are listed")
	var crow: Dictionary = _d._pages.current()["rows"][0]
	_check(str(crow["detail"]).begins_with("S2E1 ") and str(crow["detail"]).ends_with("%") and bool(crow.get("resume", false)), "each says how far it is")
	_d.handle_key("ok")
	_check(await _wait_for(func() -> bool: return _d.mode == 1 and _d.is_playing and _d._have_picture, 15.0), "OK plays it")
	_check(await _wait_for(func() -> bool: return _d._resume_s < 0.0, 10.0), "it picks up where it was left")
	_check(await _wait_for(func() -> bool: return _d._position_s() >= 4.0, 8.0), "the player is at the place it was left (5 s)")
	await get_tree().create_timer(0.6).timeout
	_eq(_d._range_state, "ok", "the Range probe found that the server honours ranges")
	# a stream that stalls is swapped for a transcoded one that starts where it was
	_d._have_picture = true
	_d._since_frame = 7.0
	_d._last_frames = 1 << 30
	var stalled_at: float = _d._position_s()
	_d._tick_play(0.016)
	_check(_d._using_hls and _d._tried_hls, "a stream that stalls for 6 s is swapped for a transcoded one")
	_check(absf(_d._pos_offset - stalled_at) < 1.5, "which starts where it was")
	_check(await _wait_for(func() -> bool: return _d._have_picture, 15.0), "and gets a picture")
	var started1 := _find_report(await _fetch_reports(), "start", "ep1")
	_eq(int(started1.get("PositionTicks", -1)), 50000000, "and the start is reported at that place, not at 0")
	_d.get_node("StopButton").button_pressed.emit()
	_eq(_d.mode, 0, "(stopped again)")

	# secrets
	var written := FileAccess.get_file_as_string(OS.get_environment("XENU_JF_SETTINGS"))
	_check(not written.contains("secret") and written.contains("tok-pw"), "the token is kept and the password never written")
	_d.ui_sign_out()
	_eq(_d.link, "need_login", "signing out asks for a sign-in again")
	_d._set_power(false)
	_eq(_d.is_powered_on(), false, "switched off")
	_check(_d.get_video_texture() == null, "an off box gives no picture")
	_eq(_d._vfd_lines()[0], "", "and a dark display")

	print("[jf-obj] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-obj] FAIL expected %d cases, ran %d" % [EXPECTED_CASES, _cases])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
