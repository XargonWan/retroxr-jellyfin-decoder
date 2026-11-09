## DecoderOptionsPanel -- the decoder's floating menu (point at it and press the left thumbstick; Tab on a
## desktop). Built on demand as the decoder's child, the way the Synth's pod builds its own.
##
## The server, the method, the user and the password live HERE, on the object. The panel only moves
## values between the 2D page and the decoder; what the decoder says is its own (status_text, the
## users, now_playing).
extends FloatingObjectPanel3D

const PANEL_SCENE := preload("res://mods/xenu.jellyfin/scenes/decoder_options_panel.tscn")
const Config := preload("res://mods/xenu.jellyfin/scripts/jf_config.gd")
const NODE_NAME := "DecoderOptionsPanel"
## How far above the box's origin the menu hangs. The base class's own anchor (straight up, then lifted clear
## of the box's top) is right for a thing that stands on a table: the first version hung it BESIDE the box at
## chest height above the ORIGIN, which for a box on a table is two metres up and a metre to the side, out of
## view of anyone standing at it (the Synth's pod can do that: its origin is on the floor).
const FLOAT_HEIGHT := 0.32

var _decoder: Node3D = null
var _users: Array = []
var _timer := 0.0

@onready var _viewport_node: XRToolsViewport2DIn3D = $DecoderOptionsViewport


static func toggle_for(decoder: Node3D, camera: Node3D) -> void:
	if not is_instance_valid(decoder):
		return
	var panel := decoder.get_node_or_null(NODE_NAME)
	if panel == null:
		panel = PANEL_SCENE.instantiate()
		panel.name = NODE_NAME
		decoder.add_child(panel)
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(decoder, camera)


func show_for(decoder: Node3D, camera: Node3D) -> void:
	_decoder = decoder
	_camera = camera
	global_position = _anchor()   # the base class's: over the box, lifted clear of it (and kept clear each frame)
	visible = true
	_ensure_ui_connected()
	_populate()
	if _users.is_empty():
		_decoder.call("load_users")


func _get_ui() -> Control:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if vp == null or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as Control


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := _get_ui()
	if ui == null:
		call_deferred("_ensure_ui_connected")
		return
	ui.close_requested.connect(hide_panel)
	ui.server_submitted.connect(func(text: String) -> void: _decoder.call("ui_set_server", text))
	ui.method_changed.connect(func(m: String) -> void:
		Config.set_value("method", m)
		_refresh())
	ui.quick_connect_pressed.connect(func() -> void: _decoder.call("ui_quick_connect"))
	ui.sign_in_pressed.connect(func(user: String, password: String) -> void:
		_decoder.call("ui_sign_in", user, password))
	ui.sign_out_pressed.connect(func() -> void: _decoder.call("ui_sign_out"))
	ui.prefs_changed.connect(func(audio: String, sub: String) -> void:
		Config.set_value("pref_audio_lang", audio.strip_edges().to_lower())
		Config.set_value("pref_sub_lang", sub.strip_edges().to_lower()))
	ui.power_pressed.connect(func() -> void: _decoder.call("_on_power_pressed"))
	ui.users_requested.connect(func() -> void: _decoder.call("load_users"))
	ui.skips_changed.connect(func(b: int, f: int) -> void: _decoder.call("set_skips", b, f))
	ui.vhs_changed.connect(func(on: bool) -> void: _decoder.call("set_vhs_effect", on))
	_decoder.status_changed.connect(_refresh)
	_decoder.users_loaded.connect(func(users: Array) -> void:
		_users = users
		_refresh())
	_decoder.now_playing_changed.connect(func(_i: Dictionary) -> void: _refresh())
	_ui_connected = true


func _populate() -> void:
	if _get_ui() == null:
		call_deferred("_populate")
		return
	_refresh()


func _refresh() -> void:
	var ui := _get_ui()
	if ui == null or not is_instance_valid(_decoder):
		return
	var s: Dictionary = Config.load_all()
	ui.populate({
		"server": str(s.get("server", "")),
		"method": str(s.get("method", "quick")),
		"link": str(_decoder.get("link")),
		"status": str(_decoder.call("status_text")),
		"ok": bool(_decoder.call("status_ok")),
		"users": _users,
		"user_name": str(_decoder.get("user_name")),
		"pref_audio": str(s.get("pref_audio_lang", "")),
		"pref_sub": str(s.get("pref_sub_lang", "")),
		"powered": bool(_decoder.call("is_powered_on")),
		"vhs": bool(_decoder.get("vhs_effect")),
		"skip_back": int(_decoder.get("skip_back_s")),
		"skip_forward": int(_decoder.get("skip_forward_s")),
		"now": _decoder.call("now_playing"),
	})


func _while_shown(delta: float) -> void:
	# The position of what is playing moves; the menu keeps up once a second.
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_refresh()


func _target_node() -> Node3D:
	return _decoder


func _float_height() -> float:
	return FLOAT_HEIGHT
