## What the decoder tells the game's TV remote (RemoteTarget, docs/modding.md "Something the TV remote drives"): the
## cells of the floating grid, which work right now, the face a state key wears, and what pressing one does.
##
## The decoder joins the group `remote_target` in its own _init and answers remote_layout / remote_activate (and the optional
## ones) by calling these. The handset's physical keys press the cell with their printed id, so the ids are the handset's
## where they mean the same thing (power, vol_up, ok, playpause, rew, ff, prev, next, audio, subtitle ...); a cell of our own
## (back, digit0..9, red, audio_list ...) is reached through the grid, and EJECT is routed to `back` by remote_key_cell.
##
## The SET's keys (power, source, volume, mute) are cells here too and are forwarded to the TV the decoder is cabled to
## (connected_tv): the remote is aimed at the box, and the box is what has the cable.
extends RefCounted

const TV_CELLS := ["power", "source", "vol_down", "mute", "vol_up"]
## The tints a state key may use (RemoteTarget.TINT_ON / TINT_ALERT: written out so the mod does not need the class).
const TINT_ON := Color(0.30, 1.0, 0.42)
const TINT_ALERT := Color(1.0, 0.35, 0.35)


static func layout() -> Array:
	var cells: Array = [
		# the set's own keys, forwarded to the TV the decoder is cabled to
		{"id": "power", "glyph": "power", "col": 0.0, "row": 0, "span": 1.5},
		{"id": "source", "glyph": "source", "col": 1.5, "row": 0, "span": 1.5},
		{"id": "vol_down", "glyph": "vol_down", "col": 0, "row": 1},
		{"id": "mute", "glyph": "mute", "col": 1, "row": 1},
		{"id": "vol_up", "glyph": "vol_up", "col": 2, "row": 1},
		# the decoder's pages and transport
		{"id": "back", "glyph": "eject", "col": 0.0, "row": 2, "span": 1.5},
		{"id": "menu", "glyph": "menu", "col": 1.5, "row": 2, "span": 1.5},
		{"id": "up", "glyph": "up", "col": 1, "row": 3},
		{"id": "left", "glyph": "left", "col": 0, "row": 4},
		{"id": "ok", "glyph": "ok", "col": 1, "row": 4},
		{"id": "right", "glyph": "right", "col": 2, "row": 4},
		{"id": "down", "glyph": "down", "col": 1, "row": 5},
		{"id": "prev", "glyph": "prev", "col": 0, "row": 6},
		{"id": "playpause", "glyph": "play", "col": 1, "row": 6},
		{"id": "next", "glyph": "next", "col": 2, "row": 6},
		{"id": "rew", "glyph": "rew", "col": 0, "row": 7},
		{"id": "stop", "glyph": "stop", "col": 1, "row": 7},
		{"id": "ff", "glyph": "ff", "col": 2, "row": 7},
		{"id": "audio", "glyph": "audio", "col": 0.0, "row": 8, "span": 1.5},
		{"id": "subtitle", "glyph": "subtitle", "col": 1.5, "row": 8, "span": 1.5},
		{"id": "audio_list", "text": "AUDIO LIST", "col": 0.0, "row": 9, "span": 1.5},
		{"id": "subtitle_list", "text": "SUB LIST", "col": 1.5, "row": 9, "span": 1.5},
		# the four Fastext colours and the digits (not keys on the handset's model): cells of the grid
		{"id": "red", "text": "R", "col": 0.0, "row": 10, "span": 0.75},
		{"id": "green", "text": "G", "col": 0.75, "row": 10, "span": 0.75},
		{"id": "yellow", "text": "Y", "col": 1.5, "row": 10, "span": 0.75},
		{"id": "cyan", "text": "C", "col": 2.25, "row": 10, "span": 0.75},
	]
	# Digits in two rows of five (1-5, 6-0), a fifth of the width each.
	for d in 10:
		cells.append({"id": "digit%d" % ((d + 1) % 10), "text": str((d + 1) % 10),
			"col": float(d % 5) * 0.6, "row": 11 + d / 5, "span": 0.6})
	return cells


static func tv_of(decoder: Node) -> Node:
	var tv: Variant = decoder.get("connected_tv")
	return tv as Node if tv is Node and is_instance_valid(tv) else null


## Nothing works on a box that is off; the set's keys need a set; the track and seek keys need something playing.
static func cell_enabled(decoder: Node, id: String) -> bool:
	if id in TV_CELLS:
		return tv_of(decoder) != null
	if not bool(decoder.call("is_powered_on")):
		return false
	if id in ["audio", "subtitle", "audio_list", "subtitle_list", "rew", "ff", "stop"]:
		return int(decoder.get("mode")) == 1
	return true


## State keys: PLAY shows PAUSE while it plays; the set's POWER is lit while it is on and MUTE alarmed while it is muted.
static func cell_face(decoder: Node, id: String) -> Dictionary:
	match id:
		"playpause":
			var playing := bool(decoder.get("is_playing")) and not bool(decoder.call("is_paused"))
			return {"glyph": "pause" if playing else "play"}
		"power":
			var tv := tv_of(decoder)
			return {"tint": TINT_ON} if tv != null and tv.has_method("is_on") and bool(tv.call("is_on")) else {}
		"mute":
			var tv2 := tv_of(decoder)
			return {"tint": TINT_ALERT} if tv2 != null and tv2.has_method("is_muted") and bool(tv2.call("is_muted")) else {}
	return {}


static func cell_faces(id: String) -> Array:
	if id == "playpause":
		return [{"glyph": "play"}, {"glyph": "pause"}]
	return []


## The handset's EJECT is BACK on the decoder.
static func key_cell(cell: String) -> String:
	return "back" if cell == "eject" else cell


## What pressing a cell does: the set's keys go to the TV (the same functions its own bezel and the remote call), the rest is
## the decoder's own key path, which is what a hand on the box uses.
static func activate(decoder: Node, id: String) -> void:
	print("[Jellyfin] %s: remote pressed %s" % [decoder.name, id])
	if id in TV_CELLS:
		var tv := tv_of(decoder)
		if tv == null:
			print("[Jellyfin] %s: %s pressed on the remote, but the decoder is not cabled to a TV" % [decoder.name, id])
			return
		match id:
			"power": tv.call("remote_power_toggle")
			"source": tv.call("remote_source_cycle")
			"vol_up": tv.call("remote_volume_up")
			"vol_down": tv.call("remote_volume_down")
			"mute": tv.call("remote_mute_toggle")
		return
	decoder.call("handle_key", id)
