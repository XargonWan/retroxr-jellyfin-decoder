## The text of a subtitle track, for whoever wants to know what was JUST SAID (the Synth, the menu's
## "now playing"). Parses WebVTT and SRT into cues and answers "what is on screen at time t".
##
## This is read from the server's own subtitle stream and is independent of the picture: the
## player draws the viewer's chosen track on the screen, this holds a second track's words (a
## hearing-impaired one by preference) without changing what is drawn. Pure: no node, no network.
extends RefCounted

## Cues, sorted by start: {start, end, text} in seconds.
var cues: Array = []


## Parse a whole WebVTT or SRT file. Garbage in, empty out (never an error: a bad track is just
## a track with no words).
static func parse(raw: String) -> RefCounted:
	var out: RefCounted = load("res://mods/xenu.jellyfin/scripts/jf_subtitles.gd").new()
	var text := raw.replace("\r\n", "\n").replace("\r", "\n")
	if text.begins_with("﻿"):
		text = text.substr(1)
	for block in text.split("\n\n", false):
		var lines := block.split("\n", false)
		var at := -1
		for i in lines.size():
			if lines[i].contains("-->"):
				at = i
				break
		if at < 0:
			continue
		var parts := lines[at].split("-->")
		var start := _seconds(parts[0])
		var end := _seconds(parts[1].strip_edges().split(" ")[0])
		if start < 0.0 or end < start:
			continue
		var words: PackedStringArray = []
		for j in range(at + 1, lines.size()):
			var l := _clean(lines[j])
			if not l.is_empty():
				words.append(l)
		if words.is_empty():
			continue
		out.cues.append({"start": start, "end": end, "text": " ".join(words)})
	out.cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["start"] < b["start"])
	return out


## "00:01:02,500" / "01:02.500" / "1:02:03.5" -> seconds, or -1.
static func _seconds(raw: String) -> float:
	var s := raw.strip_edges().replace(",", ".")
	var parts := s.split(":")
	if parts.size() < 2 or parts.size() > 3:
		return -1.0
	var total := 0.0
	for p in parts:
		if not p.strip_edges().is_valid_float():
			return -1.0
		total = total * 60.0 + float(p)
	return total


## Take the markup out: <i>, <font ...>, ASS overrides {\an8}, and the &entities a VTT may carry.
static func _clean(line: String) -> String:
	var rx := RegEx.new()
	rx.compile("<[^>]*>|\\{[^}]*\\}")
	var t := rx.sub(line, "", true)
	t = t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ").replace("\\N", " ")
	return t.strip_edges()


func is_empty() -> bool:
	return cues.is_empty()


## The cue on screen at `t`, or "". Two overlapping cues (a second speaker) are both returned,
## joined by a line break.
func line_at(t: float) -> String:
	var shown: PackedStringArray = []
	var i := _last_started(t)
	# Walk back a little: a long cue may have started before a shorter, later one.
	var j := i
	while j >= 0 and j > i - 6:
		var c: Dictionary = cues[j]
		if t >= float(c["start"]) and t < float(c["end"]):
			shown.insert(0, str(c["text"]))
		j -= 1
	return "\n".join(shown)


## Up to `n` lines that STARTED within `window` seconds before `t` (oldest first), the one on
## screen included: what was said lately, for a viewer who looked away for a moment.
func recent(t: float, n: int = 3, window: float = 30.0) -> Array:
	var out: Array = []
	var i := _last_started(t)
	while i >= 0 and out.size() < n:
		var c: Dictionary = cues[i]
		if t - float(c["start"]) > window:
			break
		out.insert(0, str(c["text"]))
		i -= 1
	return out


## Index of the last cue starting at or before `t`, or -1.
func _last_started(t: float) -> int:
	var lo := 0
	var hi := cues.size() - 1
	var best := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(cues[mid]["start"]) <= t:
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return best
