## Renders the teletext pages to PNGs, windowed (a headless renderer returns blank images):
##   OUT=/some/dir godot --path RetroXR --resolution 320x240 --position 20,20 res://mods/xenu.jellyfin/tests/teletext_render_probe.tscn
extends Node

const Pages = preload("res://mods/xenu.jellyfin/scripts/jf_pages.gd")
const View = preload("res://mods/xenu.jellyfin/scripts/teletext_view.gd")


func _ready() -> void:
	_run.call_deferred()


func _shot(view: Node, name: String) -> void:
	view.refresh()
	for i in 4:
		await get_tree().process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp"
	var img: Image = view.texture().get_image()
	var path := "%s/%s.png" % [out, name]
	img.save_png(path)
	print("[probe] wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _run() -> void:
	var pages: RefCounted = Pages.new()
	var view: Node = View.new()
	view.pages = pages
	add_child(view)
	await get_tree().process_frame
	pages.set_libraries([{"id": "1", "title": "Movies"}, {"id": "2", "title": "Anime"}, {"id": "3", "title": "TV Shows"}])
	await _shot(view, "p100_index")
	var rows: Array = []
	for t in [["Re:Zero - Re:Union", "S2E3"], ["Akira", "1988"], ["Perfect Blue", "1997"], ["Paprika", "2006"], ["Cowboy Bebop - Ballad of Fallen Angels", "S1E5"]]:
		rows.append({"kind": "play", "id": t[0], "title": t[0], "detail": t[1]})
	for i in 24:
		rows.append({"kind": "play", "id": str(i), "title": "Episode number %d of a long season" % i, "detail": "S1E%d" % i})
	pages.set_view(Pages.PAGE_LATEST, "RECENTLY ADDED", rows)
	pages.goto(Pages.PAGE_LATEST)
	pages.move(3)
	await _shot(view, "p101_latest")
	pages.set_status("QUICK CONNECT", [["", 7], ["ENTER THIS CODE ON A DEVICE", 7], ["SIGNED IN TO YOUR SERVER:", 7], ["", 7],
		["123456", 3], ["", 7], ["SETTINGS > QUICK CONNECT", 6]])
	await _shot(view, "quick_connect")
	pages.clear_status()
	pages.open_overlay("subs", "SUBTITLES", [
		{"kind": "other", "title": "Off", "detail": "", "ordinal": -1},
		{"kind": "other", "title": "English - SubRip", "detail": "SUBRIP", "ordinal": 0},
		{"kind": "other", "title": "English - SDH", "detail": "SUBRIP", "ordinal": 1},
		{"kind": "other", "title": "Italiano - SubRip", "detail": "SUBRIP", "ordinal": 2}], 1)
	var img := Image.create(512, 384, false, Image.FORMAT_RGB8)
	for y in 384:
		for x in 512:
			img.set_pixel(x, y, Color(0.2 + 0.6 * x / 512.0, 0.5, 0.3 + 0.5 * y / 384.0))
	view.set_backdrop(ImageTexture.create_from_image(img))
	await _shot(view, "overlay_over_film")
	# the search keyboard
	pages.close_overlay()
	pages.goto(Pages.PAGE_SEARCH)
	for ch in "RE ZERO":
		if ch == " ":
			pages.osk_col = 1
			pages.osk_row = 4
		else:
			var at: Vector2i = Pages.osk_locate(ch)
			pages.osk_col = at.x
			pages.osk_row = at.y
		pages.select()
	var at2: Vector2i = Pages.osk_locate("M")
	pages.osk_col = at2.x
	pages.osk_row = at2.y
	view.set_backdrop(null)
	await _shot(view, "search_osk")
	get_tree().quit(0)
