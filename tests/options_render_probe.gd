## Renders the TAB menu page with sample states to PNGs (windowed):
##   OUT=dir godot --path RetroXR --resolution 560x620 --position 20,20 res://mods/xenu.jellyfin/tests/options_render_probe.tscn
extends Node

const Ui = preload("res://mods/xenu.jellyfin/scripts/decoder_options_2d.gd")


func _ready() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 5:
		await get_tree().process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp"
	var img := _vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("[probe] wrote %s (%dx%d)" % [name, img.get_width(), img.get_height()])


var _vp: SubViewport = null


func _run() -> void:
	# Its own viewport: the game's loading overlay sits over the main window.
	_vp = SubViewport.new()
	_vp.size = Vector2i(560, 620)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var ui: Control = Ui.new()
	_vp.add_child(ui)
	await get_tree().process_frame
	var base := {"server": "192.168.1.10:8096", "method": "password", "link": "need_login", "status": "Fake Jellyfin found. Sign in from the menu (TAB)",
		"ok": false, "users": [{"Name": "alice"}, {"Name": "bob"}], "user_name": "", "pref_audio": "ita", "pref_sub": "",
		"powered": true, "now": {"playing": false, "text": "nothing", "browsing": "RECENTLY ADDED"}}
	ui.populate(base)
	await _shot("menu_password")
	var q: Dictionary = base.duplicate(true)
	q["method"] = "quick"
	q["link"] = "quick_code"
	q["status"] = "Quick Connect code: 123456 -- approve it on a signed-in device (Settings > Quick Connect)"
	ui.populate(q)
	await _shot("menu_quick")
	var r: Dictionary = base.duplicate(true)
	r["link"] = "ready"
	r["ok"] = true
	r["status"] = "Connected as alice"
	r["user_name"] = "alice"
	r["now"] = {"playing": true, "text": "Re:Zero, season 2, episode 3 'Re:Union', at 12:34 of 24:10", "audio": "Japanese - AAC - Stereo",
		"subtitles": "English - SDH", "line": "Emilia: Why would you say that?", "words_from": "English - SDH"}
	ui.populate(r)
	await _shot("menu_playing")
	get_tree().quit(0)
