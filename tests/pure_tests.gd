## Pure-logic tests: URLs, headers, parsing (jf_api) and the teletext navigation model (jf_pages).
## Touches no node and no extension, so it runs anywhere Godot does:
##
##   godot --headless --path RetroXR --script res://mods/xenu.jellyfin/tests/pure_tests.gd
##
## EXPECTED_CASES guards against a script error that stops the run early and still prints
## "0 failed".
extends SceneTree

const Api = preload("res://mods/xenu.jellyfin/scripts/jf_api.gd")
const Pages = preload("res://mods/xenu.jellyfin/scripts/jf_pages.gd")
const LogoMesh = preload("res://mods/xenu.jellyfin/scripts/logo_mesh.gd")
const Subs = preload("res://mods/xenu.jellyfin/scripts/jf_subtitles.gd")

const EXPECTED_CASES := 178

var _cases := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	_cases += 1
	if not ok:
		_failed += 1
		print("[jf-test] FAIL ", what)


func _eq(a: Variant, b: Variant, what: String) -> void:
	_cases += 1
	if a != b:
		_failed += 1
		print("[jf-test] FAIL ", what, ": got ", a, " want ", b)


func _init() -> void:
	_api()
	_tracks()
	_pages_nav()
	_pages_render()
	_subtitles()
	_now_playing()
	_latest()
	_reports()
	_osk()
	_lan()
	_logo()
	print("[jf-test] %d cases, %d failed" % [_cases, _failed])
	if _cases != EXPECTED_CASES:
		print("[jf-test] FAIL expected %d cases, ran %d (a script error stopped the run?)" % [EXPECTED_CASES, _cases])
		quit(1)
		return
	quit(1 if _failed > 0 else 0)


func _api() -> void:
	_eq(Api.normalize_server(" 192.168.1.5:8096/ "), "http://192.168.1.5:8096", "server: scheme + slash")
	_eq(Api.normalize_server("https://jf.example.org/sub//"), "https://jf.example.org/sub", "server: keeps path")
	_eq(Api.normalize_server("   "), "", "server: empty")
	var h := Api.auth_header("dev1")
	_check(h.begins_with("Authorization: MediaBrowser "), "header prefix")
	_check(h.contains('DeviceId="dev1"') and not h.contains("Token"), "header has no token before sign-in")
	_check(Api.auth_header("dev1", "abc").contains('Token="abc"'), "header carries the token")
	var u := Api.stream_url("http://s:8096", "ID1", "tok", "MS1")
	_eq(u, "http://s:8096/Videos/ID1/stream?static=true&MediaSourceId=MS1&api_key=tok", "stream url")
	_eq(Api.stream_url("http://s", "I", "t"), "http://s/Videos/I/stream?static=true&api_key=t", "stream url, no source id")
	var hls := Api.hls_url("http://s", "I", "t", "M", 2, 5, 600000000)
	_check(hls.contains("AudioStreamIndex=2") and hls.contains("SubtitleStreamIndex=5"), "hls tracks")
	_check(hls.contains("StartTimeTicks=600000000"), "hls resume position")
	_check(not Api.hls_url("http://s", "I", "t").contains("StreamIndex"), "hls: no track forced")
	_eq(Api.redact("http://s/x?api_key=SECRET&a=1"), "http://s/x?api_key=***&a=1", "redact token")
	_check(Api.path_latest("U").begins_with("/Users/U/Items/Latest?"), "latest path")
	_check(Api.path_next_up("U").contains("userId=U"), "next up path")
	_check(Api.path_children("U", "P").contains("ParentId=P"), "children path")
	_eq(Api.path_qc_poll("a b"), "/QuickConnect/Connect?secret=a%20b", "secret is url-encoded")

	var ep := {"Id": "e1", "Name": "Pilot", "Type": "Episode", "SeriesName": "Show",
			"ParentIndexNumber": 1, "IndexNumber": 3, "RunTimeTicks": 27000000000}
	var r := Api.item_row(ep)
	_eq(r["kind"], "play", "episode plays")
	_eq(r["detail"], "S1E3", "episode detail")
	_eq(r["title"], "Show - Pilot", "episode title carries the series")
	var mv := Api.item_row({"Id": "m", "Name": "Film", "Type": "Movie", "ProductionYear": 1999})
	_eq(mv["detail"], "1999", "movie year")
	_eq(Api.item_row({"Id": "s", "Name": "Show", "Type": "Series"})["kind"], "folder", "series opens")
	_eq(Api.item_row({"Id": "b", "Name": "Box", "Type": "BoxSet", "IsFolder": true})["kind"], "folder", "boxset opens")
	_eq(Api.item_row({"Id": "x", "Name": "?", "Type": "Weird"})["kind"], "other", "unknown type")
	_eq(Api.items_of([{"a": 1}]).size(), 1, "bare array response")
	_eq(Api.items_of({"Items": [{}, {}]}).size(), 2, "wrapped response")
	_eq(Api.items_of("garbage").size(), 0, "garbage response")
	var libs := Api.library_rows({"Items": [
		{"Id": "1", "Name": "Movies", "CollectionType": "movies"},
		{"Id": "2", "Name": "Music", "CollectionType": "music"},
		{"Id": "3", "Name": "Shows", "CollectionType": "tvshows"}]})
	_eq(libs.size(), 2, "libraries: music is left out")
	_eq(libs[1]["title"], "Shows", "libraries keep server order")
	_eq(Api.runtime_text(63 * 600000000), "1h03m", "runtime hours")
	_eq(Api.runtime_text(42 * 600000000), "42m", "runtime minutes")


func _tracks() -> void:
	var item := {"MediaSources": [{"MediaStreams": [
		{"Type": "Video", "Index": 0, "Codec": "h264"},
		{"Type": "Audio", "Index": 1, "Language": "eng", "Codec": "aac", "IsDefault": true},
		{"Type": "Audio", "Index": 2, "Language": "ita", "Codec": "ac3", "DisplayTitle": "Italian - AC3 - 5.1"},
		{"Type": "Subtitle", "Index": 3, "Language": "ita", "Codec": "subrip"},
		{"Type": "Subtitle", "Index": 4, "Codec": "ass"}]}]}
	var t := Api.parse_tracks(item)
	_eq(t["audio"].size(), 2, "two audio tracks")
	_eq(t["subs"].size(), 2, "two subtitle tracks")
	_eq(t["audio"][1]["ordinal"], 1, "audio ordinal is the position among audio")
	_eq(t["audio"][1]["index"], 2, "audio keeps Jellyfin's stream index")
	_eq(t["subs"][0]["ordinal"], 0, "subtitle ordinal restarts at 0")
	_eq(t["audio"][1]["label"], "Italian - AC3 - 5.1", "label from DisplayTitle")
	_eq(t["subs"][1]["label"], "UND ASS", "label falls back to language + codec")
	_eq(Api.pick_track(t["audio"], "ita"), 1, "preferred language wins")
	_eq(Api.pick_track(t["audio"], "fra"), 0, "falls back to the default track")
	_eq(Api.pick_track(t["subs"], ""), -1, "no preference, no default: none")
	_eq(Api.parse_tracks({})["audio"].size(), 0, "no streams")


func _fresh() -> RefCounted:
	var p := Pages.new()
	p.set_libraries([{"id": "L1", "title": "Movies"}, {"id": "L2", "title": "Shows"}])
	return p


func _pages_nav() -> void:
	var p := _fresh()
	_eq(p.page, 100, "starts on the index")
	_eq(p.current()["rows"].size(), 6, "index: four sections (incl. Search) + two libraries")
	_check(not p.goto(999), "unknown page refused")
	_eq(p.flash, "NO PAGE 999", "refusal says so")
	_eq(p.page, 100, "page unchanged after a refusal")
	_check(p.goto(101), "goto latest")
	_check(p.back() and p.page == 100, "back returns to the index")
	_check(not p.back(), "nothing to go back to on the index")
	# digits
	p.digit(1)
	p.digit(0)
	_eq(p.digits, "10", "digits accumulate")
	p.digit(2)
	_eq(p.page, 102, "three digits jump")
	_eq(p.digits, "", "digit buffer cleared")
	_eq(p.digit(7).size() + p.digit(7).size(), 0, "two digits do nothing yet")
	_eq(p.digit(7)["action"], "open_overlay", "777 asks for the subtitle overlay")
	_eq(Pages.overlay_page_for(778), "audio", "778 is audio")
	# fastext
	p.goto(100)
	p.fastext(0)
	_eq(p.page, 101, "red = latest")
	p.fastext(1)
	_eq(p.page, 102, "green = next up")
	p.fastext(2)
	_eq(p.page, 100, "yellow = libraries")
	# select
	p.cursor = 0
	p.select()
	_eq(p.page, 101, "a page row opens its page")
	p.goto(100)
	p.move(4)
	var act: Dictionary = p.select()
	_eq(act["action"], "load_library", "a library asks to be loaded")
	_eq(p.page, 110, "and its page opens (loading)")
	_eq(p.current()["state"], "loading", "page is loading")
	p.set_view(110, "MOVIES", [{"kind": "play", "id": "m1", "title": "Film", "detail": "1999"}])
	_eq(p.select()["action"], "play", "a playable row plays")
	p.back()
	_eq(p.cursor, 4, "back restores the cursor on the library row")
	_eq(p.select().size(), 0, "a loaded library opens without a new request")
	# folder
	var np: int = p.new_dynamic_page("Show")
	_check(np >= Pages.PAGE_DYNAMIC_BASE, "dynamic pages start at 200")
	p.set_view(np, "SHOW", [{"kind": "folder", "id": "se", "title": "Season 1"}])
	p.goto(np)
	var fa: Dictionary = p.select()
	_eq(fa["action"], "open_folder", "a folder asks to be opened")
	_check(int(fa["page"]) != np, "into a new page")


func _pages_render() -> void:
	var p := _fresh()
	var lines: Array = p.render("Sun 08 Nov 12:34")
	_eq(lines.size(), 24, "24 lines")
	var wide := true
	for l in lines:
		if Pages.line_text(l).length() != 40:
			wide = false
	_check(wide, "every line is exactly 40 characters")
	_eq(lines[1].size(), 2, "the title bar is blue to the last column (no padding cell)")
	_check(Pages.line_text(lines[0]).begins_with(" P100 "), "header shows the page number")
	_check(Pages.line_text(lines[0]).contains("12:34"), "header shows the clock")
	_check(Pages.line_text(lines[BODY()]).begins_with("> "), "cursor on the first row")
	_check(Pages.line_text(lines[23]).contains("LATEST") and Pages.line_text(lines[23]).contains("BACK"), "fastext labels")
	p.digit(1)
	_check(Pages.line_text(p.render()[0]).contains("P1__"), "typed digits show in the header")
	# a long list pages and scrolls with the cursor
	var rows: Array = []
	for i in 45:
		rows.append({"kind": "play", "id": str(i), "title": "Item %d" % i, "detail": ""})
	p.set_view(101, "LATEST", rows)
	p.goto(101)
	_eq(p.subpage_count(), 3, "45 rows = 3 sub-pages")
	p.page_step(1)
	_eq(p.subpage(), 1, "page down moves a sub-page")
	var lines2: Array = p.render()
	_check(Pages.line_text(lines2[BODY()]).contains("Item 20"), "second sub-page starts at row 20")
	_check(Pages.line_text(lines2[1]).contains("2/3"), "title bar shows 2/3")
	# overlay
	p.open_overlay("audio", "AUDIO", [{"kind": "other", "title": "English", "detail": "AAC", "ordinal": 0},
			{"kind": "other", "title": "Italian", "detail": "AC3", "ordinal": 1}], 1)
	_eq(p.overlay["cursor"], 1, "overlay starts on the current track")
	_check(Pages.line_text(p.render()[0]).contains("P778"), "overlay shows page 778")
	_check(Pages.line_text(p.render()[BODY() + 1]).contains("*AC3"), "current track is marked")
	p.move(-1)
	var ch: Dictionary = p.select()
	_eq(ch["ordinal"], 0, "choosing returns the track ordinal")
	_check(p.overlay.is_empty(), "overlay closes after a choice")
	p.set_status("QUICK CONNECT", ["ENTER THIS CODE", ["123456", Pages.YELLOW]])
	_check(Pages.line_text(p.render()[2]).contains("ENTER THIS CODE"), "status page body")
	_eq(p.render()[3][0][1], Pages.YELLOW, "status line keeps its colour")


func BODY() -> int:
	return Pages.BODY_FIRST


const VTT := "WEBVTT\n\n1\n00:00:01.000 --> 00:00:03.000 align:start\n<i>Hello</i> there.\n\n00:00:02.500 --> 00:00:05.000\n[door slams]\n\n00:01:00,000 --> 00:01:02,500\n{\\an8}Later line\nsecond row\n"


func _subtitles() -> void:
	var c: RefCounted = Subs.parse(VTT)
	_eq(c.cues.size(), 3, "vtt: three cues")
	_eq(c.line_at(0.5), "", "nothing before the first cue")
	_eq(c.line_at(1.5), "Hello there.", "markup is stripped")
	_eq(c.line_at(2.7), "Hello there.\n[door slams]", "two overlapping cues are both shown")
	_eq(c.line_at(4.0), "[door slams]", "the first has ended")
	_eq(c.line_at(61.0), "Later line second row", "srt-style comma, ass tag, two rows joined")
	_eq(c.line_at(30.0), "", "silence between cues")
	_eq(c.recent(61.0, 3, 120.0).size(), 3, "recent: three lines back")
	_eq(c.recent(61.0, 3, 10.0), ["Later line second row"], "recent: window cuts older lines")
	_eq(c.recent(2.7, 1)[0], "[door slams]", "recent: n=1 is the latest started")
	var srt: RefCounted = Subs.parse("1\r\n00:00:01,000 --> 00:00:02,000\r\nHi\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nBye\r\n")
	_eq(srt.cues.size(), 2, "srt with CRLF")
	_check(Subs.parse("not a subtitle file at all").is_empty(), "garbage is an empty track")
	_check(Subs.parse("").is_empty(), "empty is an empty track")


func _now_playing() -> void:
	var ep := Api.item_row({"Id": "e", "Name": "Return to Zero", "Type": "Episode", "SeriesName": "Re:Zero",
			"ParentIndexNumber": 2, "IndexNumber": 3})
	_eq(ep["series"], "Re:Zero", "row keeps the series")
	_eq(ep["season"], 2, "row keeps the season")
	var d := Api.now_playing_of(ep, 754.0, 1450.0, false)
	_eq(d["kind"], "episode", "now playing: episode")
	_eq(d["text"], "Re:Zero, season 2, episode 3 'Return to Zero', at 12:34 of 24:10", "now playing text, series")
	var mv := Api.now_playing_of(Api.item_row({"Id": "m", "Name": "Film", "Type": "Movie", "ProductionYear": 1999}), 3723.0, -1.0, true)
	_eq(mv["text"], "Film (1999), at 1:02:03, paused", "now playing text, movie")
	_eq(Api.now_playing_text({"playing": false}), "nothing", "now playing: nothing")
	# companion subtitle choice
	var subs := [
		{"lang": "eng", "default": true, "forced": false, "sdh": false},
		{"lang": "eng", "default": false, "forced": false, "sdh": true},
		{"lang": "jpn", "default": false, "forced": true, "sdh": false}]
	_eq(Api.pick_companion_track(subs, "eng"), 1, "an SDH track in the language wins")
	_eq(Api.pick_companion_track(subs, "ita"), 1, "any SDH track beats a plain one")
	_eq(Api.pick_companion_track([subs[0], subs[2]], "eng"), 0, "no SDH: the language's plain track")
	_eq(Api.pick_companion_track([subs[2]], "eng"), -1, "a forced-only track is no help")
	_check(Api.is_sdh_label("English (SDH)") and Api.is_sdh_label("Italiano - Non udenti"), "sdh from the name")
	_check(not Api.is_sdh_label("English - SubRip"), "plain name is not sdh")
	_eq(Api.parse_tracks({"MediaStreams": [{"Type": "Subtitle", "Index": 2, "Language": "eng", "IsHearingImpaired": true}]})["subs"][0]["sdh"], true, "the server's own flag")


func _latest() -> void:
	var ep := func(n: int, season: int, season_id: String, series: String, series_id: String) -> Dictionary:
		return {"Id": "e%s%d" % [season_id, n], "Name": "Ep %d" % n, "Type": "Episode", "SeriesName": series, "SeriesId": series_id,
				"SeasonId": season_id, "SeasonName": "Season %d" % season, "ParentIndexNumber": season, "IndexNumber": n}
	var data := [
		ep.call(3, 2, "s2", "Re:Zero", "rz"),
		{"Id": "m1", "Name": "Paprika", "Type": "Movie", "ProductionYear": 2006},
		ep.call(2, 2, "s2", "Re:Zero", "rz"),
		ep.call(9, 1, "s1", "Bebop", "bb"),
		ep.call(1, 2, "s2", "Re:Zero", "rz"),
		ep.call(8, 1, "s1", "Bebop", "bb")]
	var rows := Api.latest_rows(data)
	_eq(rows.size(), 3, "latest: three episodes of one season are ONE row (movie and other series stay)")
	_eq(rows[0]["title"], "Re:Zero - Season 2", "the group is named series - season")
	_eq(rows[0]["detail"], "+3 EP", "and says how many episodes were added")
	_eq(rows[0]["kind"], "folder", "it opens (the season), it does not play")
	_eq(rows[0]["type"], "Season", "as a season")
	_eq(rows[1]["title"], "Paprika", "a movie keeps its own row, in server order")
	_eq(rows[2]["detail"], "+2 EP", "another series' season is its own group")
	_eq(rows[0]["id"], "s2", "the row carries the season id to open")
	_eq(Api.latest_rows({"Items": [ep.call(1, 1, "s1", "X", "x")]})[0]["detail"], "+1 EP", "a single new episode is still 'episodes were added'")


func _reports() -> void:
	var b := Api.playback_body("ep3", "ms1", 754.3, false, 2, -1, "DirectPlay", "sess", "")
	_eq(b["PositionTicks"], 7543000000, "a report carries the position in ticks (100 ns)")
	_eq(b["PlayMethod"], "DirectPlay", "and how it plays")
	_check(b["PlaySessionId"] == "sess" and b["ItemId"] == "ep3" and b["MediaSourceId"] == "ms1", "and which item, source and session")
	_check(b["AudioStreamIndex"] == 2 and not b.has("SubtitleStreamIndex") and not b.has("EventName"), "stream indices and event only when there is one")
	var ps := Api.playback_body("x", "m", 1.0, true, -1, 5, "Transcode", "s", "Pause")
	_check(ps["IsPaused"] == true and ps["EventName"] == "Pause" and ps["SubtitleStreamIndex"] == 5, "a pause report says so")
	_eq(Api.path_report("start"), "/Sessions/Playing", "start goes to /Sessions/Playing")
	_eq(Api.path_report("progress"), "/Sessions/Playing/Progress", "progress to .../Progress")
	_eq(Api.path_report("stopped"), "/Sessions/Playing/Stopped", "stopped to .../Stopped")
	_check(Api.path_resume("U").begins_with("/Users/U/Items/Resume?"), "the resume list's path")
	_check(Api.stream_url("http://s", "I", "t", "M", "sess").contains("PlaySessionId=sess"), "the stream url carries the play session")
	var rows := Api.resume_rows({"Items": [
		{"Id": "e1", "Name": "Re:Birth", "Type": "Episode", "SeriesName": "Re:Zero", "ParentIndexNumber": 2, "IndexNumber": 1,
			"RunTimeTicks": 14400000000, "UserData": {"PlaybackPositionTicks": 6000000000}},
		{"Id": "m1", "Name": "Film", "Type": "Movie", "RunTimeTicks": 36000000000, "UserData": {"PlaybackPositionTicks": 3600000000}}]})
	_eq(rows[0]["detail"], "S2E1 41%", "continue watching: season, episode and how far")
	_eq(rows[1]["detail"], "10%", "a movie says how far")
	_check(rows[0]["resume"] == true and rows[0]["resume_ticks"] == 6000000000, "and remembers where it was left")


func _osk() -> void:
	var p := _fresh()
	p.goto(Pages.PAGE_SEARCH)
	_check(p.osk_active(), "the search page is a keyboard")
	var rows: Array = Pages.osk_layout()
	_eq(rows.size(), 5, "four rows of characters and one of special keys")
	_eq((rows[0] as Array).size(), 9, "nine keys a row")
	_eq(Pages.osk_locate("R"), Vector2i(8, 1), "R is the ninth key of the second row")
	_eq(Pages.osk_locate("0"), Vector2i(0, 4), "0 starts the last row")
	_eq(Pages.osk_locate("!"), Vector2i(-1, -1), "an unknown character has no key")
	_eq([p.osk_col, p.osk_row], [0, 0], "the cursor starts on A")
	# arrows (the pages' own up / down / left / right) move the cursor
	p.move(1)
	_eq([p.osk_col, p.osk_row], [0, 1], "down is a row down")
	p.page_step(1)
	_eq([p.osk_col, p.osk_row], [1, 1], "right is a key right")
	p.page_step(-1)
	p.page_step(-1)
	_eq(p.osk_col, 0, "and the cursor stops at the left end")
	p.move(-1)
	p.move(-1)
	_eq(p.osk_row, 0, "and at the top")
	# typing
	for ch in ["Z", "E", "R", "O"]:
		var at: Vector2i = Pages.osk_locate(ch)
		p.osk_col = at.x
		p.osk_row = at.y
		p.select()
	_eq(p.search_text, "ZERO", "OK on a key types it")
	var del_at := Vector2i(2, 4)
	_eq(Pages.osk_layout()[4][2]["kind"], "del", "(the third special key is DEL)")
	p.osk_col = del_at.x
	p.osk_row = del_at.y
	p.select()
	_eq(p.search_text, "ZER", "DEL rubs out the last letter")
	p.osk_col = 1
	p.osk_row = 4
	p.select()
	_eq(p.search_text, "ZER ", "SPACE adds a space")
	p.select()
	_eq(p.search_text, "ZER ", "but not two")
	p.digit(7)
	_eq(p.search_text, "ZER 7", "a digit key types the digit on the keyboard (it is not a page number)")
	_eq(p.digits, "", "and starts no page number")
	p.osk_col = 3
	p.osk_row = 4
	p.select()
	_eq(p.search_text, "", "CLEAR empties it")
	# SEARCH with nothing typed asks for something; with text it asks the decoder
	p.osk_col = 4
	p.osk_row = 4
	_eq(p.select().size(), 0, "SEARCH with nothing typed does nothing")
	_eq(p.flash, "TYPE SOMETHING FIRST", "and says so")
	p.osk_type("z")
	var act: Dictionary = p.select()
	_check(act.get("action") == "search" and act.get("text") == "Z", "SEARCH with text asks for a search (text upper-cased)")
	for i in 40:
		p.osk_type("A")
	_eq(p.search_text.length(), Pages.SEARCH_MAX, "the text stops at its limit")
	# vertical moves land on the nearest key under the last row's wide keys
	p.osk_col = 8
	p.osk_row = 3
	p.move(1)
	_eq([p.osk_col, p.osk_row], [4, 4], "down from the far right lands on SEARCH, not off the row")
	p.osk_col = 0
	p.osk_row = 4
	p.move(-1)
	_eq([p.osk_col, p.osk_row], [0, 3], "and up from 0 lands on 1")
	# the picture
	var lines: Array = p.render("")
	var wide := true
	for l in lines:
		if Pages.line_text(l).length() != 40:
			wide = false
	_check(wide, "the keyboard page is 24 lines of exactly 40 characters")
	var text_all := ""
	for l in lines:
		text_all += Pages.line_text(l) + "\n"
	_check(text_all.contains("SEARCH") and text_all.contains("DEL") and text_all.contains("CLEAR") and text_all.contains("SPACE"), "it shows the special keys")
	_check(Pages.line_text(lines[5]).contains("AAAAAAAA") and Pages.line_text(lines[5]).contains("_"), "and the typed text with its cursor")
	var cur_bg := -1
	for l in lines:
		for seg in l:
			if int(seg[2]) == Pages.YELLOW and str(seg[0]).strip_edges().length() > 0 and not str(seg[0]).contains("TYPE"):
				cur_bg = int(seg[2])
	_eq(cur_bg, Pages.YELLOW, "the key under the cursor is lit yellow")
	# leaving: BACK cancels (the page before), the text is kept for next time
	var q := _fresh()
	q.goto(Pages.PAGE_SEARCH)
	q.osk_type("x")
	_check(q.back() and q.page == Pages.PAGE_INDEX, "BACK cancels the keyboard")
	_eq(q.search_text, "X", "(the text is kept)")
	q.goto(Pages.PAGE_SEARCH)
	_eq([q.osk_col, q.osk_row], [0, 0], "and coming back puts the cursor on A again")
	# from the index
	var r := _fresh()
	r.cursor = 3
	r.select()
	_eq(r.page, Pages.PAGE_SEARCH, "the Search row of the index opens the keyboard")


func _lan() -> void:
	_check(Api.is_lan_url("http://192.168.1.10:8096/Videos/x/stream?a=1"), "192.168.x.x is the local network")
	_check(Api.is_lan_url("http://10.0.0.5/x") and Api.is_lan_url("http://localhost:8096/x") and Api.is_lan_url("http://nas.local/x"), "so are 10.x, localhost and .local")
	_check(Api.is_lan_url("https://172.20.1.1/x") and not Api.is_lan_url("https://172.40.1.1/x"), "172.16-31 are, 172.40 is not")
	_check(not Api.is_lan_url("https://video.example.org/Videos/x"), "a name on the internet is not")
	_check(not Api.is_lan_url("https://8.8.8.8:443/x"), "nor a public address")


## Godot draws a face whose vertices run CLOCKWISE seen from the front. The logo's mesh was wound the other way, so the
## front faces were culled and only the inside of the walls showed: thin outlines instead of a filled logo.
func _logo() -> void:
	var d := LogoMesh.data()
	var pos: Array = d["positions"]
	var nor: Array = d["normals"]
	var idx: Array = d["indices"]
	var front := 0
	var wrong := 0
	var walls := 0
	var walls_wrong := 0
	for t in range(0, idx.size(), 3):
		var i0: int = idx[t]
		var i1: int = idx[t + 1]
		var i2: int = idx[t + 2]
		var a := Vector3(pos[i0 * 3], pos[i0 * 3 + 1], pos[i0 * 3 + 2])
		var b := Vector3(pos[i1 * 3], pos[i1 * 3 + 1], pos[i1 * 3 + 2])
		var c := Vector3(pos[i2 * 3], pos[i2 * 3 + 1], pos[i2 * 3 + 2])
		var n := Vector3(nor[i0 * 3], nor[i0 * 3 + 1], nor[i0 * 3 + 2])
		var cross := (b - a).cross(c - a)
		if cross.length() < 1e-8:
			continue
		if n.z > 0.5:
			front += 1
			if cross.dot(n) > 0.0:
				wrong += 1
		else:
			walls += 1
			if cross.dot(n) > 0.0:
				walls_wrong += 1
	_check(front > 1000, "the logo has its front faces")
	_eq(wrong, 0, "every front face is wound clockwise from the front, as Godot wants (else it is culled)")
	_check(walls > 1000, "and its walls")
	_eq(walls_wrong, 0, "every wall faces outwards the same way")
	_check(d.has("word_from") and int(d["word_from"]) > 0 and int(d["word_from"]) < idx.size(), "the icon and the lettering are told apart")
