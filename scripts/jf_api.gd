## Pure helpers for talking to a Jellyfin server: URLs, the auth header and the parsing of what
## comes back into the plain rows the teletext pages show. No nodes, no network: tests/pure_tests
## drives every function here.
##
## Endpoint paths are Jellyfin's REST API as documented for 10.8+; they are checked against a
## real server by the probe, not by this file.
extends RefCounted

const CLIENT_NAME := "RetroXR"
const DEVICE_NAME := "RetroXR Jellyfin Decoder"
const CLIENT_VERSION := "0.1.0"

## An item kind that has children to open rather than a file to play.
const FOLDER_TYPES := ["Series", "Season", "BoxSet", "Folder", "CollectionFolder", "UserView",
		"Playlist", "MusicAlbum", "MusicArtist"]
const PLAYABLE_TYPES := ["Movie", "Episode", "Video", "MusicVideo", "Audio", "Recording",
		"Program", "Trailer"]


## "192.168.1.5:8096 " -> "http://192.168.1.5:8096". Keeps a sub-path (reverse proxy), drops the
## trailing slash. Empty in, empty out.
static func normalize_server(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	if not (s.begins_with("http://") or s.begins_with("https://")):
		s = "http://" + s
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	return s


## The Authorization header every call carries. `token` empty before sign-in.
static func auth_header(device_id: String, token: String = "") -> String:
	var h := 'Authorization: MediaBrowser Client="%s", Device="%s", DeviceId="%s", Version="%s"' % [
			CLIENT_NAME, DEVICE_NAME, device_id, CLIENT_VERSION]
	if not token.is_empty():
		h += ', Token="%s"' % token
	return h


static func _q(pairs: Array) -> String:
	var parts: PackedStringArray = []
	for p in pairs:
		if p[1] == null or str(p[1]).is_empty():
			continue
		parts.append("%s=%s" % [str(p[0]), str(p[1]).uri_encode()])
	return "&".join(parts)


## Direct play: the file as it is on the server. The token rides in the URL because libVLC
## cannot send a header (VlcPlayer allows only a few media options).
static func stream_url(base: String, item_id: String, token: String, media_source_id: String = "",
		play_session_id: String = "") -> String:
	return "%s/Videos/%s/stream?%s" % [base, item_id, _q([
			["static", "true"], ["MediaSourceId", media_source_id], ["PlaySessionId", play_session_id],
			["api_key", token]])]


## Transcoded HLS, used when direct play fails or a track must be picked by the server.
## Indices are Jellyfin's MediaStream indices; -1 leaves the choice to the server.
static func hls_url(base: String, item_id: String, token: String, media_source_id: String = "",
		audio_index: int = -1, subtitle_index: int = -1, start_ticks: int = 0, play_session_id: String = "") -> String:
	var pairs: Array = [["MediaSourceId", media_source_id], ["PlaySessionId", play_session_id], ["api_key", token],
			["VideoCodec", "h264"], ["AudioCodec", "aac"], ["SegmentContainer", "ts"]]
	if audio_index >= 0:
		pairs.append(["AudioStreamIndex", str(audio_index)])
	if subtitle_index >= 0:
		pairs.append(["SubtitleStreamIndex", str(subtitle_index)])
		pairs.append(["SubtitleMethod", "Encode"])
	if start_ticks > 0:
		pairs.append(["StartTimeTicks", str(start_ticks)])
	return "%s/Videos/%s/master.m3u8?%s" % [base, item_id, _q(pairs)]


## Whether a URL points at this machine or the local network (a bigger network cache is for the others).
static func is_lan_url(url: String) -> bool:
	var rest := url
	if rest.contains("://"):
		rest = rest.substr(rest.find("://") + 3)
	var host := rest.split("/")[0].split(":")[0].to_lower()
	if host == "localhost" or host.begins_with("127.") or host.begins_with("10.") or host.begins_with("192.168.") \
			or host.ends_with(".local") or host.ends_with(".lan"):
		return true
	if host.begins_with("172."):
		var second := host.split(".")[1] if host.split(".").size() > 1 else ""
		return second.is_valid_int() and int(second) >= 16 and int(second) <= 31
	return false


## What the log may show of a URL: the token is replaced.
static func redact(url: String) -> String:
	var rx := RegEx.new()
	rx.compile("(api_key|ApiKey|Token)=[^&\\s\"]+")
	return rx.sub(url, "$1=***", true)


# --- endpoints (paths only, joined onto the base by the client) ---------------------------------

static func path_public_info() -> String:
	return "/System/Info/Public"


static func path_public_users() -> String:
	return "/Users/Public"


static func path_qc_enabled() -> String:
	return "/QuickConnect/Enabled"


static func path_qc_initiate() -> String:
	return "/QuickConnect/Initiate"


static func path_qc_poll(secret: String) -> String:
	return "/QuickConnect/Connect?" + _q([["secret", secret]])


static func path_auth_quick_connect() -> String:
	return "/Users/AuthenticateWithQuickConnect"


static func path_auth_by_name() -> String:
	return "/Users/AuthenticateByName"


static func path_latest(user_id: String, limit: int = 40) -> String:
	return "/Users/%s/Items/Latest?%s" % [user_id, _q([["Limit", limit],
			["GroupItems", "false"], ["Fields", "ProductionYear,MediaSources"], ["EnableImages", "false"]])]


static func path_next_up(user_id: String, limit: int = 40) -> String:
	return "/Shows/NextUp?" + _q([["userId", user_id], ["Limit", limit], ["EnableImages", "false"]])


## What the user left half-watched (Jellyfin's "Continue Watching").
static func path_resume(user_id: String, limit: int = 40) -> String:
	return "/Users/%s/Items/Resume?%s" % [user_id, _q([["Limit", limit], ["MediaTypes", "Video"],
			["Fields", "ProductionYear"], ["EnableImages", "false"]])]


## Where a client says what it is playing, as every Jellyfin client does: start, progress, stopped.
static func path_report(kind: String) -> String:
	match kind:
		"start":
			return "/Sessions/Playing"
		"progress":
			return "/Sessions/Playing/Progress"
		_:
			return "/Sessions/Playing/Stopped"


## Search: movies, series and episodes (the server ranks them; its own order is kept).
static func path_search(user_id: String, term: String, limit: int = 50) -> String:
	return "/Users/%s/Items?%s" % [user_id, _q([["searchTerm", term], ["IncludeItemTypes", "Movie,Series,Episode,BoxSet"],
			["Recursive", "true"], ["Limit", limit], ["Fields", "ProductionYear"], ["EnableImages", "false"]])]


static func path_views(user_id: String) -> String:
	return "/Users/%s/Views" % user_id


static func path_children(user_id: String, parent_id: String, start: int = 0, limit: int = 200) -> String:
	return "/Users/%s/Items?%s" % [user_id, _q([["ParentId", parent_id], ["SortBy", "SortName"],
			["SortOrder", "Ascending"], ["StartIndex", start], ["Limit", limit],
			["Fields", "ProductionYear"], ["EnableImages", "false"]])]


static func path_seasons(user_id: String, series_id: String) -> String:
	return "/Shows/%s/Seasons?%s" % [series_id, _q([["userId", user_id]])]


static func path_episodes(user_id: String, series_id: String, season_id: String = "") -> String:
	return "/Shows/%s/Episodes?%s" % [series_id, _q([["userId", user_id], ["seasonId", season_id],
			["Fields", "ProductionYear"]])]


static func path_item(user_id: String, item_id: String) -> String:
	return "/Users/%s/Items/%s" % [user_id, item_id]


# --- parsing ------------------------------------------------------------------------------------

## A list response is a bare array (Items/Latest) or {"Items": [...]}.
static func items_of(data: Variant) -> Array:
	if data is Array:
		return data
	if data is Dictionary and data.get("Items") is Array:
		return data["Items"]
	return []


## One teletext row for an item. `kind` is "folder" (open it), "play" (start it) or "other".
static func item_row(item: Dictionary) -> Dictionary:
	var type := str(item.get("Type", ""))
	var name := str(item.get("Name", "?"))
	var detail := ""
	var title := name
	if type == "Episode":
		var s: Variant = item.get("ParentIndexNumber")
		var e: Variant = item.get("IndexNumber")
		if s != null and e != null:
			detail = "S%dE%d" % [int(s), int(e)]
		elif e != null:
			detail = "E%d" % int(e)
		var series := str(item.get("SeriesName", ""))
		if not series.is_empty():
			title = "%s - %s" % [series, name]
	elif type == "Season":
		var sn := str(item.get("SeriesName", ""))
		title = name if sn.is_empty() else "%s - %s" % [sn, name]
	elif item.get("ProductionYear") != null:
		detail = str(int(item["ProductionYear"]))
	var kind := "other"
	if type in FOLDER_TYPES or (bool(item.get("IsFolder", false)) and type not in PLAYABLE_TYPES):
		kind = "folder"
	elif type in PLAYABLE_TYPES:
		kind = "play"
	return {"id": str(item.get("Id", "")), "title": title, "detail": detail, "kind": kind,
			"type": type, "series_id": str(item.get("SeriesId", "")),
			"season_id": str(item.get("SeasonId", "")),
			"resume_ticks": int((item.get("UserData", {}) as Dictionary).get("PlaybackPositionTicks", 0)) if item.get("UserData") is Dictionary else 0,
			"ticks": int(item.get("RunTimeTicks", 0)),
			# What the thing IS, apart from how a row prints it: now_playing() and the Synth read these.
			"name": name, "series": str(item.get("SeriesName", "")),
			"season": int(item["ParentIndexNumber"]) if item.get("ParentIndexNumber") != null else -1,
			"episode": int(item["IndexNumber"]) if item.get("IndexNumber") != null else -1,
			"year": int(item["ProductionYear"]) if item.get("ProductionYear") != null else -1}


static func item_rows(data: Variant) -> Array:
	var rows: Array = []
	for it in items_of(data):
		if it is Dictionary:
			rows.append(item_row(it))
	return rows


## The rows of "Recently added". A season that gained episodes is ONE row, "Series - Season N" with
## "+3 EP", that opens the season: not a line per episode. Movies and anything else stay as they are.
## The group stands where its most recent episode was (the server lists newest first). With no season
## id on the episodes (an old server) the group opens the series' episodes instead.
static func latest_rows(data: Variant) -> Array:
	var out: Array = []
	var groups: Dictionary = {}   # "seriesId|season" -> the row in `out`
	for it in items_of(data):
		if not (it is Dictionary):
			continue
		var row := item_row(it)
		if str(row["type"]) != "Episode":
			out.append(row)
			continue
		var key := "%s|%s|%d" % [row["series_id"], row["season_id"], int(row["season"])]
		if groups.has(key):
			var g: Dictionary = groups[key]
			g["new_count"] = int(g["new_count"]) + 1
			g["detail"] = "+%d EP" % int(g["new_count"])
			continue
		var series := str(row["series"])
		var season_name := str((it as Dictionary).get("SeasonName", ""))
		if season_name.is_empty():
			season_name = ("Season %d" % int(row["season"])) if int(row["season"]) >= 0 else "New episodes"
		var g := {"id": str(row["season_id"]), "title": ("%s - %s" % [series, season_name]) if series != "" else season_name,
				"detail": "+1 EP", "kind": "folder", "type": "Season", "series_id": str(row["series_id"]),
				"season_id": str(row["season_id"]), "new_count": 1, "name": season_name, "series": series,
				"season": int(row["season"]), "episode": -1, "year": -1, "ticks": 0}
		groups[key] = g
		out.append(g)
	return out


## The rows of "Continue watching": each remembers where it was left (`resume_ticks`, `resume: true`, so playing it
## picks up there) and says how far in it is ("S2E3 41%").
static func resume_rows(data: Variant) -> Array:
	var rows := item_rows(data)
	for r: Dictionary in rows:
		var pos := int(r.get("resume_ticks", 0))
		var total := int(r.get("ticks", 0))
		if pos <= 0:
			continue
		r["resume"] = true
		var head := ""
		if int(r.get("episode", -1)) >= 0 and int(r.get("season", -1)) >= 0:
			head = "S%dE%d " % [int(r["season"]), int(r["episode"])]
		r["detail"] = "%s%d%%" % [head, clampi(int(100.0 * float(pos) / float(total)) if total > 0 else 0, 0, 99)]
	return rows


## The body of a start / progress / stopped report. `event` names what changed on a progress report ("Pause",
## "Unpause", "TimeUpdate", "AudioTrackChange", "SubtitleTrackChange"); stream indices are Jellyfin's, -1 = none.
static func playback_body(item_id: String, media_source_id: String, position_s: float, paused: bool,
		audio_index: int, subtitle_index: int, play_method: String, play_session_id: String, event: String = "") -> Dictionary:
	var b := {
		"ItemId": item_id, "MediaSourceId": media_source_id,
		"PositionTicks": int(maxf(position_s, 0.0) * 10000000.0),
		"IsPaused": paused, "IsMuted": false, "CanSeek": true, "VolumeLevel": 100,
		"PlayMethod": play_method, "PlaySessionId": play_session_id, "RepeatMode": "RepeatNone",
	}
	if audio_index >= 0:
		b["AudioStreamIndex"] = audio_index
	if subtitle_index >= 0:
		b["SubtitleStreamIndex"] = subtitle_index
	if not event.is_empty():
		b["EventName"] = event
	return b


## Libraries from /Users/{id}/Views: only the ones whose content the decoder can show.
static func library_rows(data: Variant) -> Array:
	var rows: Array = []
	for it in items_of(data):
		if not (it is Dictionary):
			continue
		var ct := str(it.get("CollectionType", ""))
		if ct in ["music", "books", "photos", "livetv", "playlists", "musicvideos"]:
			continue
		rows.append({"id": str(it.get("Id", "")), "title": str(it.get("Name", "?")),
				"detail": ct, "kind": "library", "type": "CollectionFolder"})
	return rows


## Audio and subtitle tracks of an item (the first media source), in the order Jellyfin lists
## them. Each: {index (Jellyfin's), ordinal (position among the same kind), label, lang, codec,
## default}. The ordinal is what maps onto a player's own numbering.
static func parse_tracks(item: Dictionary) -> Dictionary:
	var out := {"audio": [], "subs": []}
	var streams: Array = []
	var sources: Variant = item.get("MediaSources")
	if sources is Array and not (sources as Array).is_empty() and sources[0] is Dictionary:
		streams = (sources[0] as Dictionary).get("MediaStreams", [])
	if streams.is_empty():
		streams = item.get("MediaStreams", [])
	var a := 0
	var s := 0
	for st in streams:
		if not (st is Dictionary):
			continue
		var t := str(st.get("Type", ""))
		if t != "Audio" and t != "Subtitle":
			continue
		var lang := str(st.get("Language", ""))
		var codec := str(st.get("Codec", ""))
		var label := str(st.get("DisplayTitle", ""))
		if label.is_empty():
			label = (lang if not lang.is_empty() else "und").to_upper()
			if not codec.is_empty():
				label += " " + codec.to_upper()
		var rec := {"index": int(st.get("Index", -1)), "label": label, "lang": lang,
				"codec": codec, "default": bool(st.get("IsDefault", false)),
				"forced": bool(st.get("IsForced", false)),
				"sdh": t == "Subtitle" and (bool(st.get("IsHearingImpaired", false)) or is_sdh_label(label)),
				"external": bool(st.get("IsExternal", false))}
		if t == "Audio":
			rec["ordinal"] = a
			a += 1
			out["audio"].append(rec)
		else:
			rec["ordinal"] = s
			s += 1
			out["subs"].append(rec)
	return out


## Whether a track's name says it is for the deaf and hard of hearing: it then also describes
## sounds ("[door slams]") and says who speaks. Servers older than 10.9 have no flag for it, so
## the name is all there is to go on.
static func is_sdh_label(label: String) -> bool:
	var rx := RegEx.new()
	rx.compile("(?i)(\\bsdh\\b|\\bcc\\b|closed caption|hearing|non[- ]?udenti|per sordi|\\bhi\\b)")
	return rx.search(label) != null


## The subtitle track a viewer who READS the dialogue (the Synth) should be given, as a position
## in `subs` (the "subs" array of parse_tracks), or -1. Hearing-impaired first, in the viewer's
## language, then any language; then the language's ordinary track, the default one, the first
## that is not a forced (foreign-parts-only) track.
static func pick_companion_track(subs: Array, preferred_lang: String) -> int:
	var lang := preferred_lang.to_lower()
	var tiers: Array = [
		func(t: Dictionary) -> bool: return bool(t.get("sdh")) and str(t.get("lang", "")).to_lower() == lang and lang != "",
		func(t: Dictionary) -> bool: return bool(t.get("sdh")),
		func(t: Dictionary) -> bool: return not bool(t.get("forced")) and str(t.get("lang", "")).to_lower() == lang and lang != "",
		func(t: Dictionary) -> bool: return not bool(t.get("forced")) and bool(t.get("default")),
		func(t: Dictionary) -> bool: return not bool(t.get("forced")),
	]
	for tier: Callable in tiers:
		for i in subs.size():
			if tier.call(subs[i]):
				return i
	return -1


## Where the text of a subtitle track is read from (WebVTT, parsed by jf_subtitles).
static func path_subtitle(item_id: String, media_source_id: String, stream_index: int) -> String:
	return "/Videos/%s/%s/Subtitles/%d/0/Stream.vtt" % [item_id, media_source_id if media_source_id != "" else item_id, stream_index]


## What is being watched, as a dictionary anything may ask for (decoder.now_playing()). `row` is
## an item_row, `position_s` / `length_s` in seconds (length -1 = unknown).
static func now_playing_of(row: Dictionary, position_s: float, length_s: float, paused: bool) -> Dictionary:
	var is_ep := int(row.get("episode", -1)) >= 0 or str(row.get("type", "")) == "Episode"
	var d := {
		"playing": true, "paused": paused,
		"kind": "episode" if is_ep else "movie",
		"title": str(row.get("name", row.get("title", ""))),
		"series": str(row.get("series", "")) if is_ep else "",
		"season": int(row.get("season", -1)) if is_ep else -1,
		"episode": int(row.get("episode", -1)) if is_ep else -1,
		"year": int(row.get("year", -1)),
		"position_s": maxf(position_s, 0.0), "length_s": length_s,
	}
	d["text"] = now_playing_text(d)
	return d


## "Re:Zero, season 2, episode 3 'Title', at 12:34 of 24:10, paused" / "Film (1999) at 12:34".
static func now_playing_text(d: Dictionary) -> String:
	if not bool(d.get("playing", false)):
		return "nothing"
	var t := ""
	if str(d.get("kind", "")) == "episode":
		t = str(d.get("series", "")) if str(d.get("series", "")) != "" else str(d.get("title", ""))
		if int(d.get("season", -1)) >= 0:
			t += ", season %d" % int(d["season"])
		if int(d.get("episode", -1)) >= 0:
			t += ", episode %d" % int(d["episode"])
		if str(d.get("series", "")) != "" and str(d.get("title", "")) != "":
			t += " '%s'" % str(d["title"])
	else:
		t = str(d.get("title", ""))
		if int(d.get("year", -1)) > 0:
			t += " (%d)" % int(d["year"])
	t += ", at " + clock_text(float(d.get("position_s", 0.0)))
	if float(d.get("length_s", -1.0)) > 0.0:
		t += " of " + clock_text(float(d["length_s"]))
	if bool(d.get("paused", false)):
		t += ", paused"
	return t


## 754.3 -> "12:34"; an hour or more -> "1:02:03".
static func clock_text(seconds: float) -> String:
	var s := int(maxf(seconds, 0.0))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## The preferred track among `tracks` (output of parse_tracks' "audio"/"subs") for a language
## code, or the default one, or -1. Returns the position in the array.
static func pick_track(tracks: Array, preferred_lang: String) -> int:
	if not preferred_lang.is_empty():
		for i in tracks.size():
			if str(tracks[i].get("lang", "")).to_lower() == preferred_lang.to_lower():
				return i
	for i in tracks.size():
		if bool(tracks[i].get("default", false)):
			return i
	return -1


## Ticks (100 ns) -> "1h 42m" / "42m".
static func runtime_text(ticks: int) -> String:
	var minutes := int(ticks / 600000000)
	if minutes <= 0:
		return ""
	if minutes >= 60:
		return "%dh%02dm" % [minutes / 60, minutes % 60]
	return "%dm" % minutes
