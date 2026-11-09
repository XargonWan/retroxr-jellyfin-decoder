## The Teletext / Televideo navigation model: numbered pages, a cursor, Fastext colours, three
## digit page entry, and the 40 x 24 text it renders. Pure data in, lines out -- the view that
## draws them (teletext_view.gd) and the decoder that feeds them are separate, so every rule here
## is testable without a scene.
##
## A rendered line is an Array of segments [text, fg, bg]; the colours are teletext's eight, as
## indices. A line is always exactly COLS characters wide.
extends RefCounted

const COLS := 40
const ROWS := 24
const BODY_ROWS := 20
const BODY_FIRST := 2

const BLACK := 0
const RED := 1
const GREEN := 2
const YELLOW := 3
const BLUE := 4
const MAGENTA := 5
const CYAN := 6
const WHITE := 7

const PAGE_INDEX := 100
const PAGE_LATEST := 101
const PAGE_NEXT := 102
const PAGE_CONTINUE := 103
const PAGE_SEARCH := 104
const PAGE_LIBRARY_BASE := 110
const PAGE_DYNAMIC_BASE := 200
const PAGE_DYNAMIC_LAST := 699
## Italian Televideo's subtitle page; audio gets the next one.
const PAGE_SUBTITLES := 777
const PAGE_AUDIO := 778

## Fastext: red, green, yellow, cyan.
## The on-screen keyboard: nine keys a row (a 3-column cell and a gap), then a row of the special keys.
const OSK_ROWS := ["ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ-", "123456789"]
const SEARCH_MAX := 32

const FASTEXT_LABELS := ["LATEST", "NEXT UP", "LIBRARIES", "BACK"]
const FASTEXT_COLORS := [RED, GREEN, YELLOW, CYAN]

var views: Dictionary = {}       # int page -> {title, rows, state: "ok"|"loading"|"error", error}
var page: int = PAGE_INDEX
var cursor: int = 0
var history: Array = []          # of {page, cursor}
var status: Dictionary = {}      # {} or {title, lines: [String | [String, color]]}
var overlay: Dictionary = {}     # {} or {kind: "audio"|"subs", title, rows, cursor, current}
var digits: String = ""
var flash: String = ""
var _next_dynamic: int = PAGE_DYNAMIC_BASE
var _libraries: Array = []
## The search box's text, and the key the on-screen keyboard's cursor is on (column, row). The text stays while you
## look at the results and come back, so a search can be refined; CLEAR empties it.
var search_text: String = ""
var osk_col: int = 0
var osk_row: int = 0
static var _osk_cache: Array = []


func _init() -> void:
	reset()


func reset() -> void:
	views.clear()
	history.clear()
	status = {}
	overlay = {}
	digits = ""
	flash = ""
	cursor = 0
	page = PAGE_INDEX
	_next_dynamic = PAGE_DYNAMIC_BASE
	_libraries = []
	search_text = ""
	osk_col = 0
	osk_row = 0
	set_view(PAGE_LATEST, "RECENTLY ADDED", [])
	set_view(PAGE_NEXT, "WHAT'S NEXT", [])
	set_view(PAGE_CONTINUE, "CONTINUE WATCHING", [])
	set_view(PAGE_SEARCH, "SEARCH", [])
	_rebuild_index()


## Libraries get pages 110, 111, ... in the order the server lists them.
func set_libraries(rows: Array) -> void:
	for p in views.keys().duplicate():
		if p >= PAGE_LIBRARY_BASE and p < PAGE_DYNAMIC_BASE:
			views.erase(p)
	_libraries = []
	var i := 0
	for r in rows:
		var p := PAGE_LIBRARY_BASE + i
		if p >= PAGE_DYNAMIC_BASE:
			break
		var row: Dictionary = (r as Dictionary).duplicate()
		row["kind"] = "library"
		row["page"] = p
		_libraries.append(row)
		set_view(p, str(row.get("title", "?")).to_upper(), [], "empty")
		i += 1
	_rebuild_index()


func _rebuild_index() -> void:
	var rows: Array = [
		{"kind": "page", "title": "Recently added", "detail": str(PAGE_LATEST), "page": PAGE_LATEST},
		{"kind": "page", "title": "What's next", "detail": str(PAGE_NEXT), "page": PAGE_NEXT},
		{"kind": "page", "title": "Continue watching", "detail": str(PAGE_CONTINUE), "page": PAGE_CONTINUE},
		{"kind": "page", "title": "Search", "detail": str(PAGE_SEARCH), "page": PAGE_SEARCH},
	]
	for l in _libraries:
		var r: Dictionary = (l as Dictionary).duplicate()
		r["detail"] = str(r["page"])
		rows.append(r)
	set_view(PAGE_INDEX, "JELLYFIN", rows)


func set_view(p: int, title: String, rows: Array, state: String = "ok") -> void:
	views[p] = {"title": title, "rows": rows, "state": state, "error": ""}
	if p == page:
		cursor = clampi(cursor, 0, maxi(rows.size() - 1, 0))


func set_loading(p: int, title: String = "") -> void:
	var v: Dictionary = views.get(p, {"title": title, "rows": []})
	v["state"] = "loading"
	if not title.is_empty():
		v["title"] = title
	views[p] = v


func set_error(p: int, message: String) -> void:
	var v: Dictionary = views.get(p, {"title": "", "rows": []})
	v["state"] = "error"
	v["error"] = message
	views[p] = v


func new_dynamic_page(title: String) -> int:
	var p := _next_dynamic
	_next_dynamic += 1
	if _next_dynamic > PAGE_DYNAMIC_LAST:
		_next_dynamic = PAGE_DYNAMIC_BASE
	set_loading(p, title.to_upper())
	views[p]["rows"] = []
	return p


func current() -> Dictionary:
	return views.get(page, {"title": "", "rows": [], "state": "ok", "error": ""})


func _rows() -> Array:
	return overlay.get("rows", []) if not overlay.is_empty() else current().get("rows", [])


func _cursor_ref() -> int:
	return int(overlay.get("cursor", 0)) if not overlay.is_empty() else cursor


# --- navigation ---------------------------------------------------------------------------------

## Go to a page. False (and a message on the status row) when there is no such page.
func goto(p: int, push: bool = true) -> bool:
	digits = ""
	if not views.has(p):
		flash = "NO PAGE %03d" % p
		return false
	flash = ""
	if push and p != page:
		history.append({"page": page, "cursor": cursor})
	page = p
	cursor = 0
	overlay = {}
	if p == PAGE_SEARCH:
		osk_col = 0
		osk_row = 0
	return true


func back() -> bool:
	digits = ""
	flash = ""
	if not overlay.is_empty():
		overlay = {}
		return true
	if not status.is_empty():
		return false
	if history.is_empty():
		if page == PAGE_INDEX:
			return false
		page = PAGE_INDEX
		cursor = 0
		return true
	var h: Dictionary = history.pop_back()
	page = int(h["page"])
	cursor = int(h["cursor"])
	return true


func move(delta: int) -> void:
	if osk_active():
		osk_move(0, delta)
		return
	var n := _rows().size()
	if n == 0:
		return
	if overlay.is_empty():
		cursor = clampi(cursor + delta, 0, n - 1)
	else:
		overlay["cursor"] = clampi(int(overlay["cursor"]) + delta, 0, n - 1)


func page_step(dir: int) -> void:
	if osk_active():
		osk_move(dir, 0)
		return
	move(dir * BODY_ROWS)


func subpage() -> int:
	return _cursor_ref() / BODY_ROWS


func subpage_count() -> int:
	return maxi(1, int(ceil(float(_rows().size()) / BODY_ROWS)))


## A digit key. Three of them make a page number.
## Returns {} while typing or after a plain jump, {action: "open_overlay", kind} for 777 / 778
## (the decoder owns the tracks, so it opens those).
func digit(d: int) -> Dictionary:
	if d < 0 or d > 9:
		return {}
	flash = ""
	if osk_active():
		osk_type(str(d))     # on the keyboard a digit is a digit, not the start of a page number
		return {}
	digits += str(d)
	if digits.length() < 3:
		return {}
	var p := int(digits)
	digits = ""
	var kind := overlay_page_for(p)
	if kind != "":
		return {"action": "open_overlay", "kind": kind}
	goto(p)
	return {}


## "audio" / "subs" when `p` is one of the two track pages, else "".
static func overlay_page_for(p: int) -> String:
	if p == PAGE_SUBTITLES:
		return "subs"
	if p == PAGE_AUDIO:
		return "audio"
	return ""


## The coloured key `i` (0 red, 1 green, 2 yellow, 3 cyan).
func fastext(i: int) -> void:
	match i:
		0:
			goto(PAGE_LATEST)
		1:
			goto(PAGE_NEXT)
		2:
			goto(PAGE_INDEX)
		3:
			back()


## OK on the cursor row. Returns what the decoder must do:
## {} (handled here), {action: "load_library", id, page}, {action: "open_folder", row, page},
## {action: "play", row}, {action: "choose_track", kind, ordinal (-1 = none)}.
func select() -> Dictionary:
	if osk_active():
		return osk_press()
	if not overlay.is_empty():
		var orows: Array = overlay["rows"]
		var oi := int(overlay["cursor"])
		var okind := str(overlay["kind"])
		var ordinal: int = int((orows[oi] as Dictionary).get("ordinal", -1)) if oi < orows.size() else -1
		overlay = {}
		return {"action": "choose_track", "kind": okind, "ordinal": ordinal}
	var rows: Array = current().get("rows", [])
	if cursor < 0 or cursor >= rows.size():
		return {}
	var row: Dictionary = rows[cursor]
	match str(row.get("kind", "")):
		"page":
			goto(int(row["page"]))
			return {}
		"library":
			var p := int(row["page"])
			var v: Dictionary = views.get(p, {})
			goto(p)
			if str(v.get("state", "empty")) == "ok":
				return {}
			set_loading(p)
			return {"action": "load_library", "id": str(row.get("id", "")), "page": p}
		"folder":
			var np := new_dynamic_page(str(row.get("title", "")))
			goto(np)
			return {"action": "open_folder", "row": row, "page": np}
		"play":
			return {"action": "play", "row": row}
	return {}


# --- the on-screen keyboard ---------------------------------------------------------------------------------------

## Whether the keyboard is what is on the screen (the search page, nothing laid over it).
func osk_active() -> bool:
	return page == PAGE_SEARCH and overlay.is_empty() and status.is_empty()


## The keys: rows of {label, kind: char | space | del | clear | go, ch, x, w} (x, w in teletext columns).
static func osk_layout() -> Array:
	if not _osk_cache.is_empty():
		return _osk_cache
	var rows: Array = []
	for r: String in OSK_ROWS:
		var row: Array = []
		var x0 := (COLS - (r.length() * 4 - 1)) / 2
		for i in r.length():
			row.append({"label": r.substr(i, 1), "kind": "char", "ch": r.substr(i, 1), "x": x0 + i * 4, "w": 3})
		rows.append(row)
	var specs: Array = [["0", "char", "0", 3], ["SPACE", "space", " ", 7], ["DEL", "del", "", 5],
		["CLEAR", "clear", "", 7], ["SEARCH", "go", "", 8]]
	var total := 4
	for sp: Array in specs:
		total += int(sp[3])
	var x := (COLS - total) / 2
	var last: Array = []
	for sp: Array in specs:
		last.append({"label": sp[0], "kind": sp[1], "ch": sp[2], "x": x, "w": sp[3]})
		x += int(sp[3]) + 1
	rows.append(last)
	_osk_cache = rows
	return rows


## Where a character's key is (column, row), or (-1, -1).
static func osk_locate(ch: String) -> Vector2i:
	var rows := osk_layout()
	for r in rows.size():
		for c in (rows[r] as Array).size():
			if str(rows[r][c]["kind"]) == "char" and str(rows[r][c]["ch"]) == ch.to_upper():
				return Vector2i(c, r)
	return Vector2i(-1, -1)


## Move the cursor a key sideways (dx) or a row up / down (dy, +1 = down). Up and down land on the key nearest, along
## the screen, to the one left (the last row has five wide keys under nine narrow ones).
func osk_move(dx: int, dy: int) -> void:
	var rows := osk_layout()
	flash = ""
	if dy != 0:
		var cur: Dictionary = rows[osk_row][osk_col]
		var cx := float(cur["x"]) + float(cur["w"]) * 0.5
		var nr := clampi(osk_row + dy, 0, rows.size() - 1)
		if nr != osk_row:
			var best := 0
			var best_d := INF
			for c in (rows[nr] as Array).size():
				var k: Dictionary = rows[nr][c]
				var d := absf(float(k["x"]) + float(k["w"]) * 0.5 - cx)
				if d < best_d:
					best_d = d
					best = c
			osk_row = nr
			osk_col = best
	if dx != 0:
		osk_col = clampi(osk_col + dx, 0, (rows[osk_row] as Array).size() - 1)


## Add a character (a digit from the number keys, or a key pressed).
func osk_type(ch: String) -> void:
	if search_text.length() < SEARCH_MAX:
		search_text += ch.to_upper()


## OK on the key under the cursor. {action: "search", text} only for SEARCH with something typed.
func osk_press() -> Dictionary:
	var k: Dictionary = osk_layout()[osk_row][osk_col]
	flash = ""
	match str(k["kind"]):
		"char":
			osk_type(str(k["ch"]))
		"space":
			if not search_text.is_empty() and not search_text.ends_with(" "):
				osk_type(" ")
		"del":
			search_text = search_text.left(maxi(search_text.length() - 1, 0))
		"clear":
			search_text = ""
		"go":
			if search_text.strip_edges().is_empty():
				flash = "TYPE SOMETHING FIRST"
				return {}
			return {"action": "search", "text": search_text.strip_edges()}
	return {}


func open_overlay(kind: String, title: String, rows: Array, current_ordinal: int) -> void:
	var start := 0
	for i in rows.size():
		if int((rows[i] as Dictionary).get("ordinal", -2)) == current_ordinal:
			start = i
	overlay = {"kind": kind, "title": title, "rows": rows, "cursor": start, "current": current_ordinal}
	digits = ""
	flash = ""


func close_overlay() -> void:
	overlay = {}


func set_status(title: String, lines: Array) -> void:
	status = {"title": title, "lines": lines}


func clear_status() -> void:
	status = {}


# --- rendering ----------------------------------------------------------------------------------

static func _fit(s: String, n: int) -> String:
	if s.length() > n:
		return s.substr(0, n)
	return s + " ".repeat(n - s.length())


static func _center(s: String, n: int) -> String:
	if s.length() >= n:
		return s.substr(0, n)
	var left := (n - s.length()) / 2
	return _fit(" ".repeat(left) + s, n)


static func line_text(line: Array) -> String:
	var t := ""
	for seg in line:
		t += str(seg[0])
	return t


## Pad or cut the last segment so the line is exactly COLS wide.
static func _seal(segs: Array) -> Array:
	var total := 0
	for s in segs:
		total += (s[0] as String).length()
	if total < COLS:
		segs.append([" ".repeat(COLS - total), WHITE, BLACK])
	elif total > COLS:
		var over := total - COLS
		var last: Array = segs[segs.size() - 1]
		last[0] = (last[0] as String).substr(0, maxi((last[0] as String).length() - over, 0))
	return segs


## 24 lines. `clock` is whatever the header should show at the right ("Sun 08 Nov 12:34").
func render(clock: String = "") -> Array:
	var lines: Array = []
	var shown_page := page
	if not overlay.is_empty():
		shown_page = PAGE_SUBTITLES if overlay["kind"] == "subs" else PAGE_AUDIO
	var pn := ("P%03d" % shown_page) if digits.is_empty() else ("P" + _fit(digits, 3).replace(" ", "_"))
	# header
	var clock_w := mini(clock.length(), 22)
	lines.append(_seal([
		[" " + pn + " ", BLACK, WHITE],
		[" " + _fit("JELLYFIN", COLS - pn.length() - 3 - clock_w - 1), YELLOW, BLACK],
		[clock.substr(0, clock_w) + " ", WHITE, BLACK],
	]))
	# title bar
	var title := str(overlay["title"]) if not overlay.is_empty() \
			else (str(status["title"]) if not status.is_empty() else str(current().get("title", "")))
	var tag := ""
	if overlay.is_empty() and status.is_empty() and subpage_count() > 1:
		tag = "%d/%d" % [subpage() + 1, subpage_count()]
	lines.append(_seal([
		[" " + _fit(title.to_upper(), COLS - 2 - tag.length()), WHITE, BLUE],
		[tag + " ", CYAN, BLUE],
	]))
	# body
	lines.append_array(_body())
	# hint / flash
	var hint := flash
	var hint_color := RED
	if hint.is_empty() and not status.is_empty():
		hint = " "
	elif hint.is_empty():
		hint = "UP/DOWN MOVE  OK SELECT  BACK"
		if osk_active():
			hint = "ARROWS MOVE  OK KEY  BACK CANCEL"
		hint_color = CYAN
		if not overlay.is_empty():
			hint = "UP/DOWN MOVE  OK CHOOSE  BACK CLOSE"
	lines.append(_seal([[_fit(hint, COLS), hint_color, BLACK]]))
	# fastext
	var fx: Array = []
	for i in 4:
		fx.append([_fit(" " + FASTEXT_LABELS[i], 10), BLACK, FASTEXT_COLORS[i]])
	lines.append(_seal(fx))
	return lines


func _body() -> Array:
	var out: Array = []
	if osk_active():
		out = _osk_lines()
	elif not status.is_empty():
		for l in status["lines"]:
			var text := str(l) if l is String else str(l[0])
			var color: int = WHITE if l is String else int(l[1])
			out.append(_seal([[_center(text, COLS), color, BLACK]]))
	elif overlay.is_empty() and str(current().get("state", "ok")) == "loading":
		out.append(_seal([[_center("LOADING...", COLS), CYAN, BLACK]]))
	elif overlay.is_empty() and str(current().get("state", "ok")) == "error":
		out.append(_seal([[_center(str(current().get("error", "ERROR")), COLS), RED, BLACK]]))
	else:
		var rows := _rows()
		if rows.is_empty():
			out.append(_seal([[_center(str(current().get("empty", "(EMPTY)")), COLS), CYAN, BLACK]]))
		else:
			var cur := _cursor_ref()
			var first := (cur / BODY_ROWS) * BODY_ROWS
			for i in range(first, mini(first + BODY_ROWS, rows.size())):
				out.append(_row_line(rows[i], i == cur))
	while out.size() < BODY_ROWS:
		out.append(_seal([[" ".repeat(COLS), WHITE, BLACK]]))
	return out


func _osk_lines() -> Array:
	var out: Array = []
	var blank := func() -> Array: return _seal([[" ".repeat(COLS), WHITE, BLACK]])
	out.append(blank.call())
	out.append(_seal([[_center("TYPE WHAT YOU LOOK FOR", COLS), CYAN, BLACK]]))
	out.append(blank.call())
	var shown := search_text
	if shown.length() > 34:
		shown = shown.substr(shown.length() - 34)
	out.append(_seal([[" ", WHITE, BLACK], [" " + _fit(shown + "_", 36) + " ", WHITE, BLUE]]))
	out.append(blank.call())
	var rows := osk_layout()
	for r in rows.size():
		var segs: Array = []
		var x := 0
		for c in (rows[r] as Array).size():
			var k: Dictionary = rows[r][c]
			if int(k["x"]) > x:
				segs.append([" ".repeat(int(k["x"]) - x), WHITE, BLACK])
			var w := int(k["w"])
			var label := str(k["label"])
			var left := (w - label.length()) / 2
			var cell := _fit(" ".repeat(left) + label, w)
			var fg := WHITE
			var bg := BLUE
			match str(k["kind"]):
				"del":
					bg = RED
				"clear":
					bg = MAGENTA
				"go":
					fg = BLACK
					bg = GREEN
			if r == osk_row and c == osk_col:
				fg = BLACK
				bg = YELLOW
			segs.append([cell, fg, bg])
			x = int(k["x"]) + w
		out.append(_seal(segs))
		out.append(blank.call())
	out.append(_seal([[_center("OK PRESSES THE KEY, DIGITS TYPE DIGITS", COLS), CYAN, BLACK]]))
	out.append(_seal([[_center("DEL RUBS OUT ONE LETTER, CLEAR ALL", COLS), CYAN, BLACK]]))
	out.append(_seal([[_center("SEARCH LOOKS IT UP, BACK CANCELS", COLS), CYAN, BLACK]]))
	return out


func _row_line(r: Dictionary, selected: bool) -> Array:
	var mark := ">" if selected else " "
	var is_current := not overlay.is_empty() and int(r.get("ordinal", -3)) == int(overlay.get("current", -4))
	var detail := str(r.get("detail", ""))
	if is_current:
		detail = "*" + detail
	var dw := mini(detail.length(), 12)
	var tw := COLS - 2 - dw - (1 if dw > 0 else 0)
	var kind := str(r.get("kind", ""))
	var fg := WHITE
	if kind == "folder" or kind == "library" or kind == "page":
		fg = YELLOW if not selected else BLACK
	elif kind == "play":
		fg = WHITE if not selected else BLACK
	else:
		fg = CYAN if not selected else BLACK
	var bg := YELLOW if selected else BLACK
	var text := mark + " " + _fit(str(r.get("title", "?")), tw) + (" " if dw > 0 else "") + _fit(detail, dw)
	return _seal([[text.substr(0, COLS), fg, bg]])
