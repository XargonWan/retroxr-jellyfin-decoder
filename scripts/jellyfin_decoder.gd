## JellyfinDecoder -- a VCR-like box that signs in to a Jellyfin server and shows its libraries on
## the TV as a Teletext / Televideo service, then plays what is picked.
##
## It is a MediaTransport (power, the A/V cable graph, the spatial audio at the set's speakers) on
## the VCR's own scene: the model, the keys, the three phono sockets and the pointer box are the
## VCR's, minus the tape slot. Everything the player sees on the TV in MENU mode is a SubViewport of
## text (teletext_view.gd); in PLAY mode it is the film.
##
## WHAT IT SAYS ABOUT ITSELF. now_playing() answers what is on, as a dictionary: the title, and for
## a series the series, season and episode; the position; and -- while a companion that reads (the
## Synth) is in the room -- the line just said and the few before it, from a second subtitle track
## (a hearing-impaired one by preference) fetched from the server and held here. It is asked, never
## broadcast: nothing is written into the world as text. The TAB menu shows it too.
##
## THE COMPANION. A node in the group "companion_viewer" says someone in the room follows the
## dialogue by reading. The decoder then loads a text track for it (jf_api.pick_companion_track) WITHOUT
## touching what the screen shows: the player's own subtitle choice is the player's.
##
## Local only: no net_get_state, so a netplay peer sees the box and not what it plays.
extends MediaTransport

const Api = preload("res://mods/xenu.jellyfin/scripts/jf_api.gd")
const Config = preload("res://mods/xenu.jellyfin/scripts/jf_config.gd")
const Client = preload("res://mods/xenu.jellyfin/scripts/jf_client.gd")
const Pages = preload("res://mods/xenu.jellyfin/scripts/jf_pages.gd")
const Subs = preload("res://mods/xenu.jellyfin/scripts/jf_subtitles.gd")
const PlayerBase = preload("res://mods/xenu.jellyfin/scripts/jf_player.gd")
const VlcEngine = preload("res://mods/xenu.jellyfin/scripts/jf_vlc_player.gd")
const TeletextView = preload("res://mods/xenu.jellyfin/scripts/teletext_view.gd")
const Keys = preload("res://mods/xenu.jellyfin/scripts/decoder_keys.gd")
## The VHS look is the DECK's (the TV owns the tube: scanlines, mask, glass): a deck hands the set a stage and the
## set runs it, as the VCR does. This is the VCR's own shader and its default values.
const VHS_SHADER := preload("res://Shaders/vcr_effect.gdshader")
const RemoteCells = preload("res://mods/xenu.jellyfin/scripts/decoder_remote.gd")
const Livery = preload("res://mods/xenu.jellyfin/scripts/decoder_livery.gd")
const OptionsPanel = preload("res://mods/xenu.jellyfin/scripts/decoder_options_panel.gd")

signal status_changed
## Who can sign in, once the server has been asked (Array of {Id, Name}).
signal users_loaded(users: Array)
## What is on changed (started, stopped, paused, a new episode): not every second.
signal now_playing_changed(info: Dictionary)

enum Mode { MENU, PLAY }

const COMPANION_GROUP := "companion_viewer"
## Jellyfin's own web client skips 30 s forward and 10 s back by default (both are settings there); so does this one,
## and the menu changes them. They are what the box's SKIP keys, the cross's left / right and REW / FF do.
const SKIP_BACK_DEFAULT := 10
const SKIP_FORWARD_DEFAULT := 30
## A client says where it is every so often: Jellyfin's own ones, every ten seconds or so.
const PROGRESS_SECONDS := 10.0
## No new picture for this long and the stream is swapped for a transcoded one that starts where it was; for this long
## and it is given up. (Seconds. The first reading of the user's log: a resumed film froze two seconds in.)
const STALL_LOG_SECONDS := 3.0
const STALL_RECOVER_SECONDS := 6.0
## libVLC's cache for a stream: small on the local network, larger over the internet.
const CACHE_LAN_MS := 1500
const CACHE_REMOTE_MS := 5000
const RANGE_PROBE_BYTES := 262144
## Direct play that shows no picture for this long is tried again as a transcoded stream.
const NO_PICTURE_SECONDS := 12.0
const STALL_SECONDS := 15.0
const OPEN_TIMEOUT_SECONDS := 25.0

## What other mods read (the Synth takes `display_name` as the machine's name).
var display_name := "Jellyfin Decoder"
## A short title while something plays, "" otherwise (the Synth reads it as "what is in it").
var game_label := ""
var mode: int = Mode.MENU
## "idle" | "need_server" | "checking" | "need_login" | "quick_code" | "signing_in" | "ready" | "error"
var link := "idle"
var link_text := "Not connected"
var server_name := ""
var user_name := ""
var is_playing := false
## The VHS look on the film (the pages stay clean: a teletext page is meant to be read). The TAB menu's switch.
var vhs_effect := true
var _vhs_params := {
	"effect_amount": 1.0, "aberration": 0.0025, "scanline_strength": 0.22, "noise_strength": 0.10,
	"wobble_strength": 0.0016, "tracking_strength": 0.02, "tracking_noise": 1.0, "tracking_speed": 0.18,
	"desaturation": 0.15, "brightness": 1.12, "roll_amount": 0.008, "roll_speed": 0.5,
	"banded_noise_opacity": 0.15, "noise_speed": 8.0, "vhs_contrast": 1.12, "pixelate": true,
}

var _client: Node = null
var _pages: RefCounted = null
var _view: Node = null
var _player: PlayerBase = null
var _power_on := true
var _led_on_mat: StandardMaterial3D = null
var _led_off_mat: StandardMaterial3D = null
var _vfd: VfdDisplay = null
var _vfd_state: Dictionary = {}
var _vfd_key := ""
var _model: ApplianceModel = null

var _row: Dictionary = {}
var _siblings: Array = []
var _media_source := ""
var _tracks: Dictionary = {"audio": [], "subs": []}
var _audio_ordinal := 0
var _sub_ordinal := -1
var _user_picked_subs := false
var _tracks_applied := false
var _using_hls := false
var _tried_hls := false
var _pending_url := ""
var _pending_start := 0.0
var skip_back_s := SKIP_BACK_DEFAULT
var skip_forward_s := SKIP_FORWARD_DEFAULT
## Seconds into the item where the stream being played begins (a transcoded stream is opened AT a position).
var _pos_offset := 0.0
## Where to pick up a half-watched item (from Continue watching), once the player knows its length; -1 = none.
var _resume_s := -1.0
var _play_session := ""
var _reporting := false
var _progress_clock := 0.0
## Whether the server honours a Range request ("unknown" until the probe answers): a seek on a direct stream needs it.
var _range_state := "unknown"
var _stall_logged := false
var _stall_msec := 0
var _buffering_pct := 100.0
var _since_open := 0.0
var _since_frame := 0.0
var _last_frames := 0
var _have_picture := false
var _qc_code := ""

var _companion: RefCounted = null
var _companion_label := ""
var _companion_state := ""   # "" | "loading" | "done"
var _companion_timer := 0.0
var _clock_timer := 0.0
var _last_info_key := ""
var _warned_unavailable := false


## The game's TV remote drives anything in the group "remote_target" that answers remote_layout / remote_activate
## (RemoteTarget.join does exactly this add_to_group; the literal keeps the box loadable on a build that has no such class).
func _init() -> void:
	add_to_group(&"remote_target")


func remote_layout() -> Array:
	return RemoteCells.layout()


func remote_activate(id: String) -> void:
	RemoteCells.activate(self, id)


func remote_cell_enabled(id: String) -> bool:
	return RemoteCells.cell_enabled(self, id)


func remote_cell_face(id: String) -> Dictionary:
	return RemoteCells.cell_face(self, id)


func remote_cell_faces(id: String) -> Array:
	return RemoteCells.cell_faces(id)


func remote_key_cell(cell: String) -> String:
	return RemoteCells.key_cell(cell)


func _ready() -> void:
	super._ready()
	# The VCR scene's group is what the VCR's own users look for (the remote, the cable code ask it for
	# VCRPlayer methods); this is not one.
	if is_in_group("vcr_player"):
		remove_from_group("vcr_player")
	add_to_group("spawned")
	add_to_group("jellyfin_decoder")
	_float_lock = FloatLock.attach(self, ignore_gravity)
	_model = get_node_or_null("Model") as ApplianceModel
	for gone: String in ["TapeSlot", "VCROptionsPanel", "VCRClock"]:
		var n := get_node_or_null(gone)
		if n != null:
			n.queue_free()
	TransportGlyphs.label_buttons(self, {
		"PlayButton": "play", "StopButton": "stop", "RewindButton": "prev", "FastForwardButton": "next",
	}, TransportGlyphs.DECK_SIZE)
	_dress()
	# The keys on the box: the cross and OK, then skip back, play, skip forward, stop (and POWER).
	for pair: Array in [["UpButton", "up", "UP"], ["DownButton", "down", "DOWN"], ["LeftButton", "left", "LEFT"],
			["RightButton", "right", "RIGHT"], ["OkButton", "ok", "OK"], ["RewindButton", "skip_back", "SKIP BACK"],
			["PlayButton", "playpause", "PLAY"], ["FastForwardButton", "skip_forward", "SKIP FORWARD"], ["StopButton", "stop", "STOP"]]:
		var id: String = pair[1]
		var what: String = pair[2]
		(get_node(pair[0]) as VRButton).button_pressed.connect(func() -> void: _on_key(id, what))
	(get_node("PowerButton") as VRButton).button_pressed.connect(_on_power_pressed)
	var label := get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.text = "JELLYFIN"

	_client = Client.new()
	_client.name = "JellyfinClient"
	add_child(_client)
	_client.signed_in.connect(_on_signed_in)
	_client.sign_in_failed.connect(_on_sign_in_failed)
	_client.quick_connect_code.connect(_on_quick_connect_code)
	_client.auth_failed.connect(_on_auth_failed)

	_pages = Pages.new()
	_view = TeletextView.new()
	_view.name = "Teletext"
	_view.pages = _pages
	add_child(_view)

	var cfg := Config.load_all()
	vhs_effect = bool(cfg.get("vhs_effect", true))
	skip_back_s = clampi(int(cfg.get("skip_back_s", SKIP_BACK_DEFAULT)), 1, 600)
	skip_forward_s = clampi(int(cfg.get("skip_forward_s", SKIP_FORWARD_DEFAULT)), 1, 600)
	_player = VlcEngine.new()
	_player.finished.connect(_on_finished)
	_player.failed.connect(_on_player_failed)
	_player.buffering.connect(_on_buffering)
	_player.stopped.connect(_on_player_stopped)
	_setup_audio()
	_show_status()
	call_deferred("_maybe_connect")


## The model's keys, sockets and display, as the VCR dresses them (DeckFace). A model-less scene
## keeps the grey box, with a warning.
func _dress() -> void:
	if _model == null:
		push_warning("[Jellyfin] %s: no Model node; drawn as the old box" % name)
		return
	# The transport row keeps the model's own caps (printed icons): REW is skip back, FF skip forward. EJECT, PAUSE and
	# REC have no job here: their keys come off. The directional cross and OK are built beside them (decoder_keys.gd).
	for pair: Array in [["PlayButton", "ButtonPlay"], ["StopButton", "ButtonStop"],
			["RewindButton", "ButtonRewind"], ["FastForwardButton", "ButtonFastForward"], ["PowerButton", "ButtonPower"]]:
		DeckFace.adopt_front_key(_model, get_node(pair[0]) as VRButton, pair[1])
	for gone: String in ["EjectButton", "PauseButton", "RecordButton"]:
		var n := get_node_or_null(gone)
		if n != null:
			n.queue_free()
	for part: String in ["ButtonEject", "ButtonPause", "ButtonRecord"]:
		_model.hide_part(part)
	Keys.build_cross(self, get_node("PlayButton") as VRButton)
	for port: String in ["VideoOut", "AudioLOut", "AudioROut"]:
		DeckFace.seat_port(_model, get_node(port) as Node3D, port)
	_model.hide_part("Display")
	# Not a VCR: no cassette bay, the Jellyfin logo where RETRO XR was.
	Livery.dress(_model)
	# A long LED display on the front strip (three quarters of it; the logo has the first), in the VCR's style.
	_vfd = VfdDisplay.new()
	_vfd.name = "Vfd"
	_vfd.size_m = Livery.display_size()
	_vfd.painter = _paint_vfd
	_vfd.glow = 1.25   # no smoked window in front of it now
	_vfd.transform = _model.transform * Transform3D(Basis.IDENTITY, Livery.display_center())
	add_child(_vfd)
	_led_on_mat = StandardMaterial3D.new()
	_led_on_mat.albedo_color = Color(0.05, 0.25, 0.08)
	_led_on_mat.emission_enabled = true
	_led_on_mat.emission = Color(0.25, 1.0, 0.35)
	_led_on_mat.emission_energy_multiplier = 2.5
	_led_off_mat = StandardMaterial3D.new()
	_led_off_mat.albedo_color = Color(0.04, 0.12, 0.05)
	_led_off_mat.roughness = 0.25
	_light_led()
	_model.fit_shapes([get_node_or_null("CollisionShape3D") as CollisionShape3D,
		get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D])
	print("[Jellyfin] %s: dressed with the RETRO XR model" % name)


func _front_panel() -> bool:
	return true


func _log_tag() -> String:
	return "Jellyfin"


# --- power --------------------------------------------------------------------------------------

## What other mods ask a machine (the Synth: "is it switched on?").
func is_powered_on() -> bool:
	return _power_on and mains_live()


func _on_power_pressed() -> void:
	if not _mains_gate("POWER"):
		return
	_set_power(not _power_on)


func _set_power(on: bool) -> void:
	_power_on = on
	print("[Jellyfin] %s: %s" % [name, "on" if on else "standby"])
	if not on:
		_stop_playback("power off")
	else:
		_maybe_connect()
	_light_led()
	_vfd_key = ""
	_show_status()
	status_changed.emit()


func _light_led() -> void:
	if _model == null:
		return
	var lit := is_powered_on()
	for led in _model.parts("PowerLed"):
		(led as MeshInstance3D).material_override = _led_on_mat if lit else _led_off_mat


func _on_mains_redraw() -> void:
	_light_led()
	_vfd_key = ""
	if not mains_live():
		_stop_playback("lost its power")
	else:
		_maybe_connect()
	_show_status()


# --- the link to the server ---------------------------------------------------------------------

func _set_link(state: String, text: String) -> void:
	link = state
	link_text = text
	print("[Jellyfin] %s: link %s -- %s" % [name, state, text])
	_show_status()
	status_changed.emit()


func status_text() -> String:
	return link_text


func status_ok() -> bool:
	return link == "ready"


## Connect if there is a server and the box is on. Safe to call again: it starts over.
func _maybe_connect() -> void:
	if not is_powered_on() or link in ["checking", "quick_code", "signing_in"]:
		return
	var s := Config.load_all()
	if str(s.get("server", "")).is_empty():
		_set_link("need_server", "No server address yet: open the menu (TAB) and enter it")
		return
	if link == "ready":
		return
	connect_now()


func connect_now() -> void:
	var s := Config.load_all()
	_client.configure(str(s.get("server", "")), str(s.get("access_token", "")), str(s.get("user_id", "")))
	if _client.base.is_empty():
		_set_link("need_server", "No server address yet: open the menu (TAB) and enter it")
		return
	_set_link("checking", "Contacting %s ..." % _client.base)
	_client.ping(func(ok: bool, data: Variant, _code: int) -> void:
		if not ok:
			_set_link("error", "Cannot reach %s" % _client.base)
			return
		server_name = str((data as Dictionary).get("ServerName", "")) if data is Dictionary else ""
		load_users()
		if _client.has_login():
			_verify_login()
		else:
			_set_link("need_login", "%s found. Sign in from the menu (TAB)" % (server_name if server_name != "" else "Server")))


func _verify_login() -> void:
	user_name = str(Config.load_all().get("user_name", ""))
	_client.views(func(ok: bool, data: Variant, _code: int) -> void:
		if not ok:
			Config.forget_login()
			_client.token = ""
			_client.user_id = ""
			_set_link("need_login", "Sign in again from the menu (TAB)")
			return
		_set_link("ready", "Connected%s" % ((" as " + user_name) if user_name != "" else ""))
		_fill_libraries(data)
		_load_home(false))


func load_users() -> void:
	_client.public_users(func(ok: bool, data: Variant, _code: int) -> void:
		users_loaded.emit(data as Array if ok and data is Array else []))


## The menu's "Save and connect".
func ui_set_server(text: String) -> void:
	Config.set_value("server", Api.normalize_server(text))
	_client.cancel_quick_connect()
	_client.token = ""
	_set_link("idle", "Not connected")
	connect_now()


func ui_quick_connect() -> void:
	if link not in ["need_login", "ready", "error", "quick_code"]:
		return
	_set_link("quick_code", "Asking for a Quick Connect code ...")
	_client.sign_in_quick_connect()


func ui_sign_in(username: String, password: String) -> void:
	if username.strip_edges().is_empty():
		_set_link("need_login", "Choose a user first")
		return
	_set_link("signing_in", "Signing in as %s ..." % username)
	_client.sign_in_password(username, password)


func ui_sign_out() -> void:
	_stop_playback("signed out")
	_client.cancel_quick_connect()
	Config.forget_login()
	_client.token = ""
	_client.user_id = ""
	user_name = ""
	_pages.reset()
	_set_link("need_login", "Signed out. Sign in from the menu (TAB)")


func _on_quick_connect_code(code: String) -> void:
	_qc_code = code
	_set_link("quick_code", "Quick Connect code: %s -- approve it on a signed-in device (Settings > Quick Connect)" % code)


func _on_signed_in(user: Dictionary) -> void:
	user_name = str(user.get("Name", ""))
	Config.set_value("access_token", _client.token)
	Config.set_value("user_id", _client.user_id)
	Config.set_value("user_name", user_name)
	_qc_code = ""
	_set_link("ready", "Connected as %s" % user_name)
	_client.views(func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			_fill_libraries(data)
		_load_home(false))


func _on_sign_in_failed(message: String) -> void:
	_qc_code = ""
	_set_link("need_login", "Sign-in failed: %s" % message)


func _on_auth_failed() -> void:
	_stop_playback("the server refused the token")
	Config.forget_login()
	_set_link("need_login", "The server refused the login. Sign in again from the menu (TAB)")


# --- the pages ----------------------------------------------------------------------------------

func _fill_libraries(views_data: Variant) -> void:
	_pages.set_libraries(Api.library_rows(views_data))
	_redraw()


func _load_home(_unused: bool) -> void:
	_pages.set_loading(Pages.PAGE_LATEST)
	_pages.set_loading(Pages.PAGE_NEXT)
	_pages.set_loading(Pages.PAGE_CONTINUE)
	_client.resume(func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			_pages.set_view(Pages.PAGE_CONTINUE, "CONTINUE WATCHING", Api.resume_rows(data))
		else:
			_pages.set_error(Pages.PAGE_CONTINUE, "CANNOT LOAD THE LIST")
		_redraw())
	_client.latest(func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			_pages.set_view(Pages.PAGE_LATEST, "RECENTLY ADDED", Api.latest_rows(data))
		else:
			_pages.set_error(Pages.PAGE_LATEST, "CANNOT LOAD THE LIST")
		_redraw())
	_client.next_up(func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			_pages.set_view(Pages.PAGE_NEXT, "WHAT'S NEXT", Api.item_rows(data))
		else:
			_pages.set_error(Pages.PAGE_NEXT, "CANNOT LOAD THE LIST")
		_redraw())
	_show_status()


## A status page stands in front of everything until the box is connected and signed in.
func _show_status() -> void:
	if mode == Mode.PLAY:
		return
	if not is_powered_on():
		_pages.set_status("STANDBY", [["", 7], ["SWITCHED OFF", 3]])
	elif link == "ready":
		_pages.clear_status()
	elif link == "quick_code" and _qc_code != "":
		_pages.set_status("QUICK CONNECT", [
			["", 7], ["ENTER THIS CODE ON A DEVICE", 7], ["SIGNED IN TO YOUR SERVER:", 7], ["", 7],
			[_qc_code, 3], ["", 7], ["SETTINGS > QUICK CONNECT", 6]])
	else:
		_pages.set_status("JELLYFIN", [["", 7], [link_text.to_upper(), 6 if link in ["checking", "signing_in", "quick_code"] else (1 if link == "error" else 3)],
			["", 7], ["OPEN THE MENU (TAB) TO SET UP", 7] if link in ["need_server", "need_login"] else ["", 7]])
	_redraw()


func _redraw() -> void:
	if _view != null:
		_view.refresh()
	_vfd_key = ""


# --- keys ---------------------------------------------------------------------------------------

func _on_key(id: String, what: String) -> void:
	if not _mains_gate(what):
		return
	if not _power_on:
		return
	handle_key(id)


## The one entry for every key: the box's own buttons and the remote. Ids: up down left right ok
## menu back prev next playpause pause stop rew ff audio subtitle audio_list subtitle_list
## red green yellow cyan, and digit0 .. digit9.
func handle_key(id: String) -> void:
	if not is_powered_on():
		return
	if id.begins_with("digit"):
		var act: Dictionary = _pages.digit(int(id.substr(5)))
		if act.get("action") == "open_overlay":
			_open_track_overlay(str(act["kind"]))
		_redraw()
		return
	var overlay_open: bool = not _pages.overlay.is_empty()
	if mode == Mode.PLAY and not overlay_open:
		_play_key(id)
		return
	match id:
		"up":
			_pages.move(-1)
		"down":
			_pages.move(1)
		"left", "prev", "skip_back":
			_pages.page_step(-1)
		"right", "next", "skip_forward":
			_pages.page_step(1)
		"ok", "playpause":
			_handle_action(_pages.select())
		"menu":
			if overlay_open:
				_pages.close_overlay()
			else:
				_pages.goto(Pages.PAGE_INDEX)
		"back", "stop":
			if not _pages.back() and mode == Mode.PLAY:
				_pages.close_overlay()
		"red":
			_pages.fastext(0)
		"green":
			_pages.fastext(1)
		"yellow":
			_pages.fastext(2)
		"cyan":
			_pages.fastext(3)
		"audio", "audio_list":
			if mode == Mode.PLAY:
				_open_track_overlay("audio")
		"subtitle", "subtitle_list":
			if mode == Mode.PLAY:
				_open_track_overlay("subs")
	if mode == Mode.PLAY:
		_sync_backdrop()
	_redraw()


func _play_key(id: String) -> void:
	match id:
		"ok", "playpause":
			toggle_pause()
		"pause":
			set_paused(true)
		"stop", "back":
			_stop_playback("stop")
		"menu":
			_open_track_overlay("subs")
		"rew", "left", "skip_back":
			seek_by(-float(skip_back_s))
		"ff", "right", "skip_forward":
			seek_by(float(skip_forward_s))
		"prev":
			_step_episode(-1)
		"next":
			_step_episode(1)
		"audio":
			cycle_audio()
		"subtitle":
			cycle_subtitle()
		"audio_list":
			_open_track_overlay("audio")
		"subtitle_list":
			_open_track_overlay("subs")
		_:
			pass


# --- actions from the pages ---------------------------------------------------------------------

func _handle_action(act: Dictionary) -> void:
	match str(act.get("action", "")):
		"load_library":
			var page := int(act["page"])
			_client.children(str(act["id"]), func(ok: bool, data: Variant, _c: int) -> void:
				if ok:
					_pages.set_view(page, str(_pages.views.get(page, {}).get("title", "")), Api.item_rows(data))
				else:
					_pages.set_error(page, "CANNOT LOAD THE LIBRARY")
				_redraw())
		"open_folder":
			_open_folder(act["row"] as Dictionary, int(act["page"]))
		"play":
			var rows: Array = _pages.current().get("rows", [])
			var playable: Array = []
			for r in rows:
				if (r as Dictionary).get("kind") == "play":
					playable.append(r)
			play_row(act["row"] as Dictionary, playable)
		"choose_track":
			_choose_track(str(act["kind"]), int(act["ordinal"]))
		"search":
			_search(str(act["text"]))
	_redraw()


## SEARCH on the keyboard: the results are a page of their own (BACK returns to the keyboard, its text kept, to refine).
func _search(text: String) -> void:
	var page: int = _pages.new_dynamic_page("SEARCH: " + text)
	_pages.goto(page)
	print("[Jellyfin] %s: searching for '%s'" % [name, text])
	_client.search(text, func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			_pages.set_view(page, "SEARCH: " + text.to_upper(), Api.item_rows(data))
			_pages.views[page]["empty"] = "NO RESULTS FOR %s" % text.to_upper()
		else:
			_pages.set_error(page, "THE SEARCH FAILED")
		_redraw())


func _open_folder(row: Dictionary, page: int) -> void:
	var done := func(ok: bool, data: Variant, _c: int) -> void:
		if ok:
			_pages.set_view(page, str(row.get("title", "")).to_upper(), Api.item_rows(data))
		else:
			_pages.set_error(page, "CANNOT LOAD THIS")
		_redraw()
	match str(row.get("type", "")):
		"Series":
			_client.seasons(str(row["id"]), done)
		"Season":
			# A grouped "new episodes" row may have no season id (an old server): then it is the series' episodes.
			_client.episodes(str(row.get("series_id", "")), str(row.get("id", "")), done)
		_:
			_client.children(str(row["id"]), done)


# --- playback -----------------------------------------------------------------------------------

## Start an item. `siblings` are the playable rows beside it (previous / next episode).
func play_row(row: Dictionary, siblings: Array = []) -> void:
	if not is_powered_on() or not _player.is_available():
		if not _player.is_available() and not _warned_unavailable:
			_warned_unavailable = true
			push_warning("[Jellyfin] no video engine: cannot play")
		_pages.set_status("NO VIDEO ENGINE", [["", 7], ["THE VIDEO PLAYER IS NOT AVAILABLE", 1]])
		_redraw()
		return
	_stop_playback("another item", false)
	_row = row
	_siblings = siblings
	_play_session = _new_session_id()
	_pos_offset = 0.0
	_resume_s = float(int(row.get("resume_ticks", 0))) / 10000000.0 if bool(row.get("resume", false)) else -1.0
	if _resume_s < 1.0:
		_resume_s = -1.0
	_pages.set_status("LOADING", [["", 7], [str(row.get("title", "")).to_upper(), 7], ["", 7], ["PLEASE WAIT", 6]])
	_redraw()
	_client.item(str(row["id"]), func(ok: bool, data: Variant, _c: int) -> void:
		if not ok or not (data is Dictionary):
			_pages.set_status("CANNOT PLAY", [["", 7], [str(row.get("title", "")).to_upper(), 7], ["THE SERVER DID NOT ANSWER", 1]])
			_row = {}
			_redraw()
			return
		var sources: Array = (data as Dictionary).get("MediaSources", [])
		_media_source = str((sources[0] as Dictionary).get("Id", "")) if not sources.is_empty() else ""
		_tracks = Api.parse_tracks(data)
		_audio_ordinal = 0
		_sub_ordinal = -1
		_user_picked_subs = false
		_companion = null
		_companion_label = ""
		_companion_state = ""
		_using_hls = false
		_tried_hls = false
		var url := Api.stream_url(_client.base, str(row["id"]), _client.token, _media_source, _play_session)
		_probe_range(url)
		_open_stream(url))


func _open_stream(url: String, start_s: float = 0.0) -> void:
	_pending_url = ""
	if not _player.is_ready():
		_pending_url = url
		_pending_start = start_s
		return
	_player.stop()
	_pos_offset = start_s
	_have_picture = false
	_tracks_applied = false
	_since_open = 0.0
	_since_frame = 0.0
	_last_frames = 0
	_stall_logged = false
	var cache := CACHE_LAN_MS if Api.is_lan_url(url) else CACHE_REMOTE_MS
	if not _player.open(url, PackedStringArray(["network-caching=%d" % cache])):
		_playback_failed("the player refused the address")
		return
	_player.play()
	mode = Mode.PLAY
	is_playing = true
	_paused = false
	game_label = _short_title()
	_pages.clear_status()
	_apply_volume()
	_progress_clock = 0.0
	if not _reporting:
		_report("start")
	_announce(true)


func _playback_failed(why: String) -> void:
	print("[Jellyfin] %s: playback failed -- %s" % [name, why])
	var title := str(_row.get("title", "")).to_upper()
	_stop_playback("failed", false)
	_pages.set_status("CANNOT PLAY", [["", 7], [title, 7], ["", 7], [why.to_upper(), 1]])
	_redraw()


func _stop_playback(why: String, announce: bool = true) -> void:
	if not is_playing and mode == Mode.MENU:
		return
	print("[Jellyfin] %s: stopped (%s)" % [name, why])
	# Say where it stopped, as every client does: the server keeps the place (Continue watching) and the watched mark.
	if _reporting:
		_report_stopped(_position_s())
	if _player != null:
		_player.stop()
	if _emitter:
		_emitter.flush()
	is_playing = false
	_paused = false
	mode = Mode.MENU
	game_label = ""
	_row = {}
	_companion = null
	_companion_label = ""
	_companion_state = ""
	_pending_url = ""
	_pos_offset = 0.0
	_resume_s = -1.0
	if _view != null:
		_view.set_backdrop(null)
	_pages.close_overlay()
	if announce:
		_announce(true)
	_show_status()


func toggle_pause() -> void:
	set_paused(not _paused)


func set_paused(on: bool) -> void:
	if not is_playing or on == _paused:
		return
	_paused = on
	_since_frame = 0.0
	_player.set_paused(on)
	_osd("PAUSE" if on else "PLAY", on)
	_report("progress", "Pause" if on else "Unpause")
	_announce(true)


func seek_by(delta: float) -> void:
	if not is_playing:
		return
	var length := _length_s()
	var to := _position_s() + delta
	if length > 0.0:
		to = clampf(to, 0.0, maxf(length - 1.0, 0.0))
	to = maxf(to, 0.0)
	_resume_s = -1.0
	_since_frame = 0.0
	if _using_hls or _range_state == "no":
		# A transcoded stream has no past before where it began, and a server that ignores Range cannot seek a direct one:
		# ask for a stream that starts there.
		_using_hls = true
		_tried_hls = true
		var a: int = int(_tracks["audio"][_audio_ordinal]["index"]) if _audio_ordinal < (_tracks["audio"] as Array).size() else -1
		var sub: int = int(_tracks["subs"][_sub_ordinal]["index"]) if _sub_ordinal >= 0 and _sub_ordinal < (_tracks["subs"] as Array).size() else -1
		_open_stream(_hls_url(a, sub, to), to)
	else:
		_player.seek_s(to - _pos_offset)
	_osd(("%s%d S" % ["+" if delta > 0 else "-", int(absf(delta))]), false)
	_report("progress", "TimeUpdate")


func _step_episode(dir: int) -> void:
	var i := -1
	for k in _siblings.size():
		if (_siblings[k] as Dictionary).get("id") == _row.get("id"):
			i = k
	var j := i + dir
	if i < 0 or j < 0 or j >= _siblings.size():
		_osd("NO MORE", false)
		return
	play_row(_siblings[j] as Dictionary, _siblings)


func _on_finished() -> void:
	if not is_playing:
		return
	print("[Jellyfin] %s: finished %s" % [name, str(_row.get("title", ""))])
	if _reporting:
		_report_stopped(_length_s())   # played to its end: the server marks it watched
	var i := -1
	for k in _siblings.size():
		if (_siblings[k] as Dictionary).get("id") == _row.get("id"):
			i = k
	if str(_row.get("type", "")) == "Episode" and i >= 0 and i + 1 < _siblings.size():
		play_row(_siblings[i + 1] as Dictionary, _siblings)
		return
	_stop_playback("finished")


## Replace the direct stream with a transcoded one that starts at `start_s` (once per item).
func _switch_to_hls(start_s: float, why: String) -> void:
	_tried_hls = true
	_using_hls = true
	_resume_s = -1.0
	var a: int = int(_tracks["audio"][_audio_ordinal]["index"]) if _audio_ordinal < (_tracks["audio"] as Array).size() else -1
	var sub: int = int(_tracks["subs"][_sub_ordinal]["index"]) if _sub_ordinal >= 0 and _sub_ordinal < (_tracks["subs"] as Array).size() else -1
	print("[Jellyfin] %s: switching to a transcoded stream at %s (%s)" % [name, Api.clock_text(start_s), why])
	_open_stream(_hls_url(a, sub, start_s), start_s)


## Ask the server for the first bytes with a Range header, as a client checks before it seeks: 206 = it honours ranges;
## 200 with the whole body coming = it ignores them (a seek on the direct stream then cannot work). Logged with the
## speed it answered at, which is what tells a slow server from a slow client.
func _probe_range(url: String) -> void:
	_range_state = "unknown"
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 10.0
	http.body_size_limit = RANGE_PROBE_BYTES + 4096
	add_child(http)
	var t0 := Time.get_ticks_msec()
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		var secs := maxf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.001)
		var kb := body.size() / 1024
		if code == 206:
			_range_state = "ok"
			print("[Jellyfin] stream check: Range honoured, %d KB in %.2f s (%.1f Mbit/s)" % [kb, secs, float(body.size()) * 8.0 / secs / 1000000.0])
		elif code == 200 and (result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED or body.size() > RANGE_PROBE_BYTES):
			_range_state = "no"
			print("[Jellyfin] stream check: the server IGNORES Range (answered 200 with the whole file coming): seeking a direct stream will not work")
		else:
			# Not conclusive (a small file, an error): do not penalise the stream for it.
			_range_state = "ok"
			print("[Jellyfin] stream check: HTTP %d, result %d, %d KB in %.2f s" % [code, result, kb, secs]))
	var err := http.request(url, PackedStringArray(["Range: bytes=0-%d" % (RANGE_PROBE_BYTES - 1)]))
	if err != OK:
		http.queue_free()
		_range_state = "ok"


func _on_buffering(percent: float) -> void:
	# libVLC reports many times a second: only the interesting changes are logged.
	if is_playing and (percent < 100.0 and (_buffering_pct >= 100.0 or absf(percent - _buffering_pct) >= 25.0)):
		print("[Jellyfin] %s: the player is buffering (%.0f%%) at %s" % [name, percent, Api.clock_text(_position_s())])
	elif is_playing and percent >= 100.0 and _buffering_pct < 100.0:
		print("[Jellyfin] %s: buffered" % name)
	_buffering_pct = percent


func _on_player_stopped() -> void:
	# libVLC says "stopped" after our own stop() too; only an unexpected one is news.
	if is_playing and _have_picture:
		print("[Jellyfin] %s: the player reports STOPPED at %s with the film still on (stream ended or dropped)" % [name, Api.clock_text(_position_s())])


func _on_player_failed(message: String) -> void:
	if is_playing and not _have_picture:
		_try_transcode_or_fail(message)


## Direct play showed nothing: ask the server to transcode instead, once.
func _try_transcode_or_fail(why: String) -> void:
	if _tried_hls or _row.is_empty():
		_playback_failed(why)
		return
	_tried_hls = true
	_using_hls = true
	print("[Jellyfin] %s: direct play gave no picture (%s); asking for a transcoded stream" % [name, why])
	var start := maxf(_resume_s, 0.0)
	_resume_s = -1.0
	_open_stream(_hls_url(-1, -1, start), start)


func _hls_url(audio_index: int, sub_index: int, start_s: float) -> String:
	return Api.hls_url(_client.base, str(_row.get("id", "")), _client.token, _media_source,
		audio_index, sub_index, int(start_s * 10000000.0), _play_session)


# --- tracks -------------------------------------------------------------------------------------

func _apply_preferred_tracks() -> void:
	_tracks_applied = true
	var cfg := Config.load_all()
	var a_tracks: Array = _player.audio_tracks()
	var want_a := Api.pick_track(_tracks["audio"], str(cfg.get("pref_audio_lang", "")))
	if want_a >= 0 and want_a < a_tracks.size():
		_audio_ordinal = want_a
		_player.set_audio_track(int(a_tracks[want_a]["id"]))
	var pref_sub := str(cfg.get("pref_sub_lang", ""))
	if not pref_sub.is_empty():
		var want_s := Api.pick_track(_tracks["subs"], pref_sub)
		var s_tracks: Array = _player.subtitle_tracks()
		if want_s >= 0 and want_s < s_tracks.size():
			_sub_ordinal = want_s
			_player.set_subtitle(int(s_tracks[want_s]["id"]))


func _track_name(kind: String, ordinal: int) -> String:
	if ordinal < 0:
		return "OFF"
	var list: Array = _tracks["audio"] if kind == "audio" else _tracks["subs"]
	if ordinal < list.size():
		return str(list[ordinal]["label"])
	return "TRACK %d" % (ordinal + 1)


func cycle_audio() -> void:
	var n: int = (_tracks["audio"] as Array).size()
	if n <= 1:
		_osd("AUDIO: ONLY ONE TRACK", false)
		return
	_choose_track("audio", (_audio_ordinal + 1) % n)


func cycle_subtitle() -> void:
	var n: int = (_tracks["subs"] as Array).size()
	if n == 0:
		_osd("SUBTITLES: NONE", false)
		return
	var next := _sub_ordinal + 1
	_choose_track("subs", next if next < n else -1)


## Switch to track `ordinal` of `kind` ("audio" / "subs"; -1 = subtitles off) and say so on the set.
func _choose_track(kind: String, ordinal: int) -> void:
	if not is_playing:
		return
	if kind == "audio":
		if _using_hls:
			_audio_ordinal = ordinal
			_reload_hls()
		else:
			var tr: Array = _player.audio_tracks()
			if ordinal >= tr.size():
				return
			_audio_ordinal = ordinal
			_player.set_audio_track(int(tr[ordinal]["id"]))
		_osd("AUDIO: " + _track_name("audio", ordinal), false)
	else:
		_user_picked_subs = true
		if _using_hls:
			_sub_ordinal = ordinal
			_reload_hls()
		else:
			var st: Array = _player.subtitle_tracks()
			if ordinal < 0:
				_player.set_subtitle(-1)
			elif ordinal < st.size():
				_player.set_subtitle(int(st[ordinal]["id"]))
			else:
				return
			_sub_ordinal = ordinal
		_osd("SUBTITLES: " + _track_name("subs", ordinal), false)
	_report("progress", "AudioTrackChange" if kind == "audio" else "SubtitleTrackChange")
	print("[Jellyfin] %s: %s track -> %s" % [name, kind, _track_name(kind, ordinal)])
	_sync_backdrop()
	_announce(true)
	_redraw()


## A transcoded stream chooses its tracks on the server: ask for the new pair from here.
func _reload_hls() -> void:
	var a: int = int(_tracks["audio"][_audio_ordinal]["index"]) if _audio_ordinal < (_tracks["audio"] as Array).size() else -1
	var s: int = int(_tracks["subs"][_sub_ordinal]["index"]) if _sub_ordinal >= 0 and _sub_ordinal < (_tracks["subs"] as Array).size() else -1
	var pos := _position_s()
	_open_stream(_hls_url(a, s, pos), pos)


func _open_track_overlay(kind: String) -> void:
	if mode != Mode.PLAY:
		return
	var rows: Array = []
	var list: Array = _tracks["audio"] if kind == "audio" else _tracks["subs"]
	if kind == "subs":
		rows.append({"kind": "other", "title": "Off", "detail": "", "ordinal": -1})
	for t in list:
		rows.append({"kind": "other", "title": str(t["label"]), "detail": str(t["codec"]).to_upper(),
			"ordinal": int(t["ordinal"])})
	if rows.is_empty():
		_osd("NO %s TRACKS" % ("AUDIO" if kind == "audio" else "SUBTITLE"), false)
		return
	_pages.open_overlay(kind, "AUDIO" if kind == "audio" else "SUBTITLES", rows,
		_audio_ordinal if kind == "audio" else _sub_ordinal)
	_sync_backdrop()
	_redraw()


## The chooser is laid over the film: give the teletext view the picture to sit on.
func _sync_backdrop() -> void:
	if _view == null:
		return
	if mode == Mode.PLAY and not _pages.overlay.is_empty() and _have_picture:
		_view.set_backdrop(_player.texture())
	else:
		_view.set_backdrop(null)


# --- where it is, and telling the server -------------------------------------------------------------------------

## Seconds into the ITEM (the player's own clock starts at 0 whenever a transcoded stream is opened at a position).
func _position_s() -> float:
	return _pos_offset + (_player.position_s() if _player != null else 0.0)


## The item's length in seconds: the server's runtime, else the player's, else -1.
func _length_s() -> float:
	var ticks := int(_row.get("ticks", 0))
	if ticks > 0:
		return float(ticks) / 10000000.0
	var l := _player.length_s() if _player != null else -1.0
	return l + _pos_offset if l > 0.0 else -1.0


func _new_session_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _report_body(event: String, position_s: float) -> Dictionary:
	var a: int = int(_tracks["audio"][_audio_ordinal]["index"]) if _audio_ordinal < (_tracks["audio"] as Array).size() else -1
	var sub: int = int(_tracks["subs"][_sub_ordinal]["index"]) if _sub_ordinal >= 0 and _sub_ordinal < (_tracks["subs"] as Array).size() else -1
	return Api.playback_body(str(_row.get("id", "")), _media_source, position_s, _paused, a, sub,
		"Transcode" if _using_hls else "DirectPlay", _play_session, event)


## "start" once per item, "progress" (with what changed) now and then, "stopped" at the end -- as every Jellyfin client.
func _report(kind: String, event: String = "") -> void:
	if _row.is_empty() or _client == null or not _client.has_login():
		return
	if kind == "start":
		_reporting = true
	elif not _reporting:
		return
	var pos := _position_s()
	if kind == "start" and _resume_s > pos:
		pos = _resume_s    # told where it picks up, not 0
	_client.report(kind, _report_body(event, pos))


func _report_stopped(position_s: float) -> void:
	if not _reporting or _row.is_empty() or _client == null or not _client.has_login():
		_reporting = false
		return
	_reporting = false
	_client.report("stopped", _report_body("", position_s))
	print("[Jellyfin] %s: reported stopped at %s" % [name, Api.clock_text(position_s)])


## The menu's SKIP lengths (seconds).
func set_skips(back: int, forward: int) -> void:
	skip_back_s = clampi(back, 1, 600)
	skip_forward_s = clampi(forward, 1, 600)
	Config.set_value("skip_back_s", skip_back_s)
	Config.set_value("skip_forward_s", skip_forward_s)
	print("[Jellyfin] %s: skip %d s back, %d s forward" % [name, skip_back_s, skip_forward_s])
	status_changed.emit()


# --- what is on (asked for, never broadcast) ----------------------------------------------------

func _short_title() -> String:
	var d := Api.now_playing_of(_row, 0.0, -1.0, false)
	if str(d["kind"]) == "episode" and str(d["series"]) != "":
		return "%s S%dE%d" % [d["series"], maxi(int(d["season"]), 0), maxi(int(d["episode"]), 0)]
	return str(d["title"])


## What is being watched, right now: {playing, kind, title, series, season, episode, year,
## position_s, length_s, paused, text, audio, subtitles} and -- when someone reading along is in
## the room and the server gave a text track -- {line, recent, words_from}. {playing: false, ...}
## while browsing. ONLY returned: nothing is announced into the world.
func now_playing() -> Dictionary:
	if mode != Mode.PLAY or _row.is_empty():
		var v: Dictionary = _pages.current()
		return {"playing": false, "text": "nothing", "browsing": str(v.get("title", "")),
			"powered": is_powered_on(), "connected": link == "ready"}
	var pos := _position_s()
	var d := Api.now_playing_of(_row, pos, _length_s(), _paused)
	d["audio"] = _track_name("audio", _audio_ordinal)
	d["subtitles"] = _track_name("subs", _sub_ordinal)
	if _companion != null and not _companion.is_empty():
		d["line"] = _companion.line_at(pos)
		d["recent"] = _companion.recent(pos, 3, 30.0)
		d["words_from"] = _companion_label
	return d


## How other mods should name this machine.
func companion_kind() -> String:
	return "Jellyfin decoder"


## Emit now_playing_changed when what is on really changed (not for a moving position).
func _announce(force: bool) -> void:
	var d := now_playing()
	# What is on, not WHERE in it: the position moves every second and is not news.
	var key := "%s|%s|%s|%s|%s|%s|%s" % [d.get("title", ""), d.get("series", ""), d.get("season", ""), d.get("episode", ""),
		d.get("paused", false), d.get("audio", ""), d.get("subtitles", "")]
	if not force and key == _last_info_key:
		return
	_last_info_key = key
	print("[Jellyfin] %s: now playing: %s" % [name, str(d.get("text", ""))])
	now_playing_changed.emit(d)


## Whether somebody who reads the dialogue is in the room (the Synth's body joins the group).
func _companion_wanted() -> Node:
	for n: Node in get_tree().get_nodes_in_group(COMPANION_GROUP):
		if is_instance_valid(n):
			return n
	return null


func _tick_companion(delta: float) -> void:
	_companion_timer += delta
	if _companion_timer < 2.0:
		return
	_companion_timer = 0.0
	if mode != Mode.PLAY or _row.is_empty() or _companion_state != "" or _companion_wanted() == null:
		return
	var who := _companion_wanted()
	var lang := str(who.get_meta("companion_lang", "")) if who != null else ""
	if lang.is_empty():
		lang = str(Config.load_all().get("pref_sub_lang", "eng"))
	var idx := Api.pick_companion_track(_tracks["subs"], lang)
	if idx < 0:
		_companion_state = "done"
		print("[Jellyfin] %s: a reading companion is here, but %s has no subtitle track for it" % [name, str(_row.get("title", ""))])
		return
	var track: Dictionary = _tracks["subs"][idx]
	_companion_state = "loading"
	var item_id := str(_row.get("id", ""))
	_client.get_text(Api.path_subtitle(item_id, _media_source, int(track["index"])),
		func(ok: bool, data: Variant, _c: int) -> void:
			# The item may have changed while it loaded.
			if str(_row.get("id", "")) != item_id:
				return
			_companion_state = "done"
			if not ok:
				print("[Jellyfin] %s: could not fetch the companion's subtitle track" % name)
				return
			_companion = Subs.parse(str(data))
			_companion_label = str(track["label"])
			print("[Jellyfin] %s: reading track for the companion: %s (%d lines)" % [name, _companion_label, _companion.cues.size()]))


# --- frame loop ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null:
		return
	_player.update()
	_pump_audio()
	if _emitter and is_instance_valid(connected_tv):
		_emit_through(connected_tv)
	elif _emitter:
		_emitter.clear_speaker_positions()
		_emitter.clear_emit_position()
		_emitter.clear_emit_direction()
	if _pending_url != "" and _player.is_ready():
		_open_stream(_pending_url, _pending_start)
	if mode == Mode.PLAY:
		_tick_play(delta)
		_tick_companion(delta)
	# A title too long for the display steps along it.
	if _vfd != null and is_powered_on():
		_vfd_scroll += delta
		var step := int(_vfd_scroll / VFD_SCROLL_SECONDS)
		if step != _vfd_step:
			_vfd_step = step
			_update_vfd()
	_clock_timer += delta
	if _clock_timer >= 1.0:
		_clock_timer = 0.0
		if mode == Mode.MENU and _watching_tv() != null:
			_view.refresh()
		_update_vfd()


func _pump_audio() -> void:
	if _emitter == null or _paused or not is_playing:
		return
	var want := _emitter.frames_wanted()
	if want <= 0:
		return
	var frames: PackedVector2Array = _player.read_audio(want)
	if frames.size() > 0:
		_emitter.push_stereo(frames)


func _tick_play(delta: float) -> void:
	var frames := _player.frame_count()
	if frames > _last_frames:
		_last_frames = frames
		if _stall_logged:
			print("[Jellyfin] %s: pictures are coming again after %.1f s" % [name, float(Time.get_ticks_msec() - _stall_msec) / 1000.0])
			_stall_logged = false
		_since_frame = 0.0
		if not _have_picture:
			_have_picture = true
			print("[Jellyfin] %s: first picture of %s" % [name, str(_row.get("title", ""))])
	else:
		_since_frame += delta
	_since_open += delta
	if _have_picture and not _tracks_applied and (_player.audio_tracks().size() > 0 or _since_open > 3.0):
		_apply_preferred_tracks()
	if not _have_picture and _since_open > NO_PICTURE_SECONDS and not _tried_hls:
		_try_transcode_or_fail("no picture after %d s" % int(_since_open))
	elif not _have_picture and _since_open > OPEN_TIMEOUT_SECONDS:
		_playback_failed("no picture after %d s" % int(_since_open))
	elif _have_picture and not _paused:
		if _since_frame > STALL_LOG_SECONDS and not _stall_logged:
			_stall_logged = true
			_stall_msec = Time.get_ticks_msec() - int(_since_frame * 1000.0)
			print("[Jellyfin] %s: no new picture for %.0f s at %s (the player says %.0f%% buffered, direct stream: %s, Range: %s)" % [
				name, _since_frame, Api.clock_text(_position_s()), _buffering_pct, str(not _using_hls), _range_state])
		if _since_frame > STALL_RECOVER_SECONDS and not _tried_hls:
			_switch_to_hls(_position_s(), "the stream stalled for %d s" % int(_since_frame))
		elif _since_frame > STALL_SECONDS:
			_playback_failed("the stream stalled")
	if not _pages.overlay.is_empty():
		_sync_backdrop()
	# Pick up where it was left (Continue watching) as soon as the player knows how long it is.
	if _resume_s > 0.0 and _have_picture and not _using_hls and _player.length_s() > 0.0 \
			and (_range_state != "unknown" or _since_open > 6.0):
		var to := _resume_s
		_resume_s = -1.0
		_osd("RESUMING AT %s" % Api.clock_text(to), false)
		if _range_state == "no":
			# The server ignores Range: a seek on the direct stream cannot work. A transcoded stream that starts there can.
			_switch_to_hls(to, "the server ignores Range requests")
		else:
			_since_frame = 0.0
			_player.seek_s(to)
			print("[Jellyfin] %s: resuming %s at %s" % [name, str(_row.get("title", "")), Api.clock_text(to)])
	if _reporting and _have_picture:
		_progress_clock += delta
		if _progress_clock >= PROGRESS_SECONDS:
			_progress_clock = 0.0
			_report("progress", "TimeUpdate")
	_announce(false)


# --- what the set reads -------------------------------------------------------------------------

func set_audio_volume(volume: float) -> void:
	_volume_linear = clampf(volume, 0.0, 1.0)
	_apply_volume()


func _apply_volume() -> void:
	if _emitter:
		_emitter.set_volume(_volume_linear)


func set_audio_channel_mode(mode_value: int) -> void:
	if _emitter:
		_emitter.set_channel_mode(mode_value)


func get_video_texture() -> Texture2D:
	if not _feed_video or not is_powered_on() or _view == null:
		return null
	if mode == Mode.PLAY and _have_picture and _pages.overlay.is_empty():
		return _player.texture()
	return _view.texture()


## The stage the set runs the picture through. The film gets the VHS look (when it is on); the pages, and the
## film under a chooser (which is the pages' picture), go through the set's tube alone.
func get_video_stage(_tv: Node) -> Dictionary:
	if vhs_effect and mode == Mode.PLAY and _have_picture and _pages.overlay.is_empty():
		return {"shader": VHS_SHADER, "params": _vhs_params}
	return {}


func set_vhs_effect(on: bool) -> void:
	vhs_effect = on
	Config.set_value("vhs_effect", on)
	print("[Jellyfin] %s: VHS look %s" % [name, "on" if on else "off"])
	status_changed.emit()


func _osd(text: String, sticky: bool) -> void:
	var tv := _watching_tv()
	if tv == null:
		return
	if sticky:
		tv.show_osd(text)
	else:
		tv.show_osd_timed(text, 3.0)


# --- display ------------------------------------------------------------------------------------------------------

## The panel's layout in pixels (10 per mm): lamps on the left, the title lines, the counter on the right.
const VFD_TEXT_X := 200.0
const VFD_TIME_W := 650.0
const VFD_LINE1 := {"size": 68, "y": 112.0}
const VFD_LINE2 := {"size": 44, "y": 200.0}
const VFD_GAP := 160.0
## A line that does not fit steps along, a few pixels at a time, like the displays of the day.
const VFD_SCROLL_SECONDS := 0.3
const VFD_SCROLL_PX := 26.0

var _vfd_scroll := 0.0
var _vfd_step := 0


func _vfd_area_width() -> float:
	return Livery.display_size().x * 10000.0 - VFD_TEXT_X - VFD_TIME_W


## The two lines the display says: what is playing, or what the box is doing.
func _vfd_lines() -> PackedStringArray:
	if not is_powered_on():
		return PackedStringArray(["", ""])
	var l1 := "JELLYFIN"
	var l2 := ""
	if mode == Mode.PLAY and not _row.is_empty():
		var kind := str(_row.get("type", ""))
		if kind == "Episode" or int(_row.get("episode", -1)) >= 0:
			l1 = str(_row.get("series", "")) if str(_row.get("series", "")) != "" else str(_row.get("name", ""))
			var bits: PackedStringArray = []
			if int(_row.get("season", -1)) >= 0:
				bits.append("S%d" % int(_row["season"]))
			if int(_row.get("episode", -1)) >= 0:
				bits.append("E%d" % int(_row["episode"]))
			var head := " ".join(bits)
			l2 = ("%s  %s" % [head, str(_row.get("name", ""))]).strip_edges() if str(_row.get("series", "")) != "" else head
		else:
			l1 = str(_row.get("name", _row.get("title", "")))
			var year := int(_row.get("year", -1))
			var run := Api.runtime_text(int(_row.get("ticks", 0)))
			l2 = ("%s  %s" % [str(year) if year > 0 else "", run]).strip_edges()
	else:
		match link:
			"ready":
				l2 = "PAGE %03d  %s" % [_pages.page, str(_pages.current().get("title", ""))]
				if _pages.osk_active():
					l2 = "SEARCH: %s_" % _pages.search_text
			"checking":
				l2 = "CONNECTING"
			"need_login":
				l2 = "SIGN IN FROM THE MENU"
			"need_server":
				l2 = "NO SERVER SET"
			"error":
				l2 = "SERVER NOT FOUND"
			"quick_code":
				l2 = "CODE %s" % _qc_code if _qc_code != "" else "ASKING FOR A CODE"
			"signing_in":
				l2 = "SIGNING IN"
	return PackedStringArray([l1.to_upper(), l2.to_upper()])


static func _vfd_width(text: String, size: int) -> float:
	return VfdDisplay.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## How far a line is scrolled (px): none if it fits.
func _vfd_offset(text: String, size: int, step: int) -> float:
	var w := _vfd_width(text, size)
	if w <= _vfd_area_width():
		return 0.0
	return fmod(float(step) * VFD_SCROLL_PX, w + VFD_GAP)


func _update_vfd() -> void:
	if _vfd == null:
		return
	var lines := _vfd_lines()
	var secs := _position_s() if mode == Mode.PLAY else -1.0
	var o1 := _vfd_offset(lines[0], int(VFD_LINE1["size"]), _vfd_step)
	var o2 := _vfd_offset(lines[1], int(VFD_LINE2["size"]), _vfd_step)
	var key := "%d|%d|%d|%d|%d|%s|%s|%d|%d" % [int(is_powered_on()), int(secs) if secs >= 0.0 else -1, int(is_playing),
		int(_paused), int(link == "ready"), lines[0], lines[1], int(o1), int(o2)]
	if key == _vfd_key:
		return
	_vfd_key = key
	_vfd_state = {"secs": secs, "playing": is_playing, "paused": _paused, "linked": link == "ready",
		"l1": lines[0], "l2": lines[1], "o1": o1, "o2": o2}
	_vfd.refresh()


## A line that scrolls is drawn twice (wrapping); what spills over the margins is painted over afterwards.
func _vfd_line(c: Control, text: String, spec: Dictionary, offset: float) -> void:
	if text.is_empty():
		return
	var size := int(spec["size"])
	var y := float(spec["y"])
	VfdDisplay.text(c, text, Vector2(VFD_TEXT_X - offset, y), size, true)
	if offset > 0.0:
		VfdDisplay.text(c, text, Vector2(VFD_TEXT_X - offset + _vfd_width(text, size) + VFD_GAP, y), size, true)


## The VCR's approved style (RetroXR-models' common/applkit/vfd.py), made longer: lamps, then two lines of text, then
## the counter H:MM:SS in seven segments. NET is lit while signed in.
func _paint_vfd(c: Control, sz: Vector2) -> void:
	if not is_powered_on() or _vfd_state.is_empty():
		return
	var st := _vfd_state
	_vfd_line(c, str(st["l1"]), VFD_LINE1, float(st["o1"]))
	_vfd_line(c, str(st["l2"]), VFD_LINE2, float(st["o2"]))
	# Whatever the scrolling text spilled past its window is wiped before the lamps and the counter are drawn.
	c.draw_rect(Rect2(0.0, 0.0, VFD_TEXT_X - 14.0, sz.y), VfdDisplay.BG)
	c.draw_rect(Rect2(sz.x - VFD_TIME_W, 0.0, VFD_TIME_W, sz.y), VfdDisplay.BG)
	var playing: bool = st["playing"] and not st["paused"]
	VfdDisplay.boxed(c, "NET", Rect2(28, 36, 150, 48), 21, st["linked"])
	VfdDisplay.boxed(c, "PLAY", Rect2(28, 98, 150, 48), 19, playing)
	VfdDisplay.boxed(c, "PAUSE", Rect2(28, 160, 150, 48), 19, st["paused"])
	var secs: float = st["secs"]
	var x0 := sz.x - VFD_TIME_W + 20.0
	VfdDisplay.minus(c, Rect2(x0, 46, 64.6, 150), 13.0, false)
	var h := " "
	var mm := "  "
	var ss := "  "
	if secs >= 0.0:
		var t := int(secs)
		@warning_ignore("integer_division")
		h = str((t / 3600) % 10)
		@warning_ignore("integer_division")
		mm = "%02d" % ((t % 3600) / 60)
		ss = "%02d" % (t % 60)
	VfdDisplay.digits(c, h, Vector2(x0 + 80, 46), 68.0, 150.0, 13.0, 84.0)
	VfdDisplay.text(c, "H", Vector2(x0 + 156, 196), 20, secs >= 0.0)
	VfdDisplay.digits(c, mm, Vector2(x0 + 192, 46), 68.0, 150.0, 13.0, 84.0)
	VfdDisplay.text(c, "M", Vector2(x0 + 352, 196), 20, secs >= 0.0)
	VfdDisplay.digits(c, ss, Vector2(x0 + 390, 46), 68.0, 150.0, 13.0, 84.0)
	VfdDisplay.text(c, "S", Vector2(x0 + 550, 196), 20, secs >= 0.0)


# --- menu ---------------------------------------------------------------------------------------

func toggle_options_ui(camera: Node3D) -> void:
	OptionsPanel.toggle_for(self, camera)


func debug_state() -> Array:
	return [["link", link], ["server", _client.base if _client else ""], ["user", user_name],
		["mode", "play" if mode == Mode.PLAY else "menu"], ["page", str(_pages.page)],
		["companion", _companion_label if _companion else ("none (%s)" % _companion_state)]]


func _exit_tree() -> void:
	if _player != null:
		_player.shutdown()
	super._exit_tree()
