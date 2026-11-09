## DecoderOptions2D -- the decoder's menu page: the server, how to sign in, who, and what is on.
## Loaded into DecoderOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
##
## Emits (the panel turns them into calls on the decoder):
##   server_submitted(text)   -- the address was committed (Enter, the button, or focus left it)
##   method_changed(method)   -- "quick" | "password"
##   quick_connect_pressed    -- "Get a code"
##   sign_in_pressed(user, password)
##   sign_out_pressed
##   prefs_changed(audio_lang, sub_lang)
##   power_pressed
##   users_requested          -- "Reload users"
##   vhs_changed(on)          -- the VHS look on the film
##   skips_changed(back, fwd) -- how many seconds the skip keys jump
##   close_requested
##
## The PASSWORD is a LineEdit with `secret = true`; it is read into sign_in_pressed and cleared, and never
## stored anywhere.
extends Control

signal close_requested
signal server_submitted(text: String)
signal method_changed(method: String)
signal quick_connect_pressed
signal sign_in_pressed(user: String, password: String)
signal sign_out_pressed
signal prefs_changed(audio_lang: String, sub_lang: String)
signal power_pressed
signal users_requested
signal vhs_changed(on: bool)
signal skips_changed(back: int, forward: int)

const COLOR_BG := Color(0.06, 0.08, 0.14, 0.96)
const COLOR_ROW := Color(0.65, 0.70, 0.85)
const COLOR_OK := Color(0.45, 1.0, 0.65)
const COLOR_WARN := Color(1.0, 0.80, 0.35)
const COLOR_DIM := Color(0.55, 0.58, 0.70)

var _scroll: ScrollContainer = null
var _status: Label = null
var _server_edit: LineEdit = null
var _method_quick: Button = null
var _method_pass: Button = null
var _quick_box: VBoxContainer = null
var _pass_box: VBoxContainer = null
var _signed_box: VBoxContainer = null
var _users_host: HBoxContainer = null
var _users: VRDropdown = null
var _user_choice := ""
var _pass_edit: LineEdit = null
var _name_edit: LineEdit = null
var _audio_edit: LineEdit = null
var _sub_edit: LineEdit = null
var _power: Button = null
var _vhs_check: CheckButton = null
var _skip_back_edit: LineEdit = null
var _skip_fwd_edit: LineEdit = null
var _now: Label = null
var _line: Label = null
var _signed_label: Label = null
var _last_users_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


## The stick scrolls the page (the spawn menu controller asks for this).
func scroll_active(pixels: float) -> void:
	if _scroll != null:
		_scroll.scroll_vertical += int(pixels)


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)
	MenuStyle.close_button(MenuStyle.title_row(outer, "Jellyfin Decoder"), func() -> void: close_requested.emit())
	outer.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	_scroll.add_child(root)

	_status = Label.new()
	_status.text = "Not connected"
	_status.add_theme_font_size_override("font_size", 18)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	# Server
	_server_edit = _field_row(root, "Server", "192.168.1.10:8096")
	_server_edit.text_submitted.connect(func(t: String) -> void: server_submitted.emit(t))
	_server_edit.focus_exited.connect(func() -> void: server_submitted.emit(_server_edit.text))
	var connect_btn := Button.new()
	connect_btn.text = "Save and connect"
	connect_btn.custom_minimum_size = Vector2(0, 40)
	connect_btn.pressed.connect(func() -> void: server_submitted.emit(_server_edit.text))
	root.add_child(connect_btn)

	# Method
	var method_row := HBoxContainer.new()
	method_row.add_theme_constant_override("separation", 8)
	root.add_child(method_row)
	_method_quick = _method_button(method_row, "Quick Connect", "quick")
	_method_pass = _method_button(method_row, "User + password", "password")

	# Quick Connect
	_quick_box = VBoxContainer.new()
	_quick_box.add_theme_constant_override("separation", 6)
	root.add_child(_quick_box)
	var hint := Label.new()
	hint.text = "You get a code. Type it on a device that is already signed in (Settings > Quick Connect)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", COLOR_DIM)
	_quick_box.add_child(hint)
	var get_code := Button.new()
	get_code.text = "Get a code"
	get_code.custom_minimum_size = Vector2(0, 44)
	get_code.pressed.connect(func() -> void: quick_connect_pressed.emit())
	_quick_box.add_child(get_code)

	# User + password
	_pass_box = VBoxContainer.new()
	_pass_box.add_theme_constant_override("separation", 6)
	root.add_child(_pass_box)
	_users_host = HBoxContainer.new()
	_users_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pass_box.add_child(_users_host)
	var reload := Button.new()
	reload.text = "Reload users from the server"
	reload.custom_minimum_size = Vector2(0, 34)
	reload.pressed.connect(func() -> void: users_requested.emit())
	_pass_box.add_child(reload)
	# A server can hide its users (Dashboard > Users): then the name is typed here instead.
	_name_edit = _field_row(_pass_box, "User name", "the account's name")
	_name_edit.get_parent().visible = false
	_pass_edit = _field_row(_pass_box, "Password", "")
	_pass_edit.secret = true
	var sign_in := Button.new()
	sign_in.text = "Sign in"
	sign_in.custom_minimum_size = Vector2(0, 44)
	sign_in.pressed.connect(func() -> void:
		var pw := _pass_edit.text
		_pass_edit.text = ""
		sign_in_pressed.emit(_name_edit.text.strip_edges() if _name_edit.get_parent().visible else _user_choice, pw))
	_pass_box.add_child(sign_in)

	# Signed in
	_signed_box = VBoxContainer.new()
	_signed_box.add_theme_constant_override("separation", 6)
	root.add_child(_signed_box)
	_signed_label = Label.new()
	_signed_label.add_theme_font_size_override("font_size", 18)
	_signed_label.add_theme_color_override("font_color", COLOR_OK)
	_signed_box.add_child(_signed_label)
	var out := Button.new()
	out.text = "Sign out"
	out.custom_minimum_size = Vector2(0, 40)
	out.pressed.connect(func() -> void: sign_out_pressed.emit())
	_signed_box.add_child(out)

	root.add_child(HSeparator.new())

	# Now playing: what the box would tell a viewer who asks. Shown here; never broadcast.
	var now_title := Label.new()
	now_title.text = "Now playing"
	now_title.add_theme_font_size_override("font_size", 20)
	root.add_child(now_title)
	_now = Label.new()
	_now.text = "nothing"
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now.add_theme_font_size_override("font_size", 17)
	root.add_child(_now)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_size_override("font_size", 16)
	_line.add_theme_color_override("font_color", COLOR_DIM)
	root.add_child(_line)

	root.add_child(HSeparator.new())

	# Preferences
	var prefs := Label.new()
	prefs.text = "Languages (3 letters, e.g. ita, eng, jpn)"
	prefs.add_theme_font_size_override("font_size", 16)
	prefs.add_theme_color_override("font_color", COLOR_ROW)
	root.add_child(prefs)
	_audio_edit = _field_row(root, "Audio", "ita")
	_sub_edit = _field_row(root, "Subtitles", "none")
	for e in [_audio_edit, _sub_edit]:
		(e as LineEdit).text_submitted.connect(func(_t: String) -> void: _emit_prefs())
		(e as LineEdit).focus_exited.connect(_emit_prefs)

	# How far the skip keys jump (Jellyfin's own web client: 30 s forward, 10 s back).
	var skips := Label.new()
	skips.text = "Skip lengths (seconds)"
	skips.add_theme_font_size_override("font_size", 16)
	skips.add_theme_color_override("font_color", COLOR_ROW)
	root.add_child(skips)
	_skip_back_edit = _field_row(root, "Back", "10")
	_skip_fwd_edit = _field_row(root, "Forward", "30")
	for e in [_skip_back_edit, _skip_fwd_edit]:
		(e as LineEdit).text_submitted.connect(func(_t: String) -> void: _emit_skips())
		(e as LineEdit).focus_exited.connect(_emit_skips)

	# The VHS look is the deck's (the TV's own tube stage is the TV's): scanlines, tracking noise, a little wobble.
	_vhs_check = CheckButton.new()
	_vhs_check.text = "VHS look on the film"
	_vhs_check.button_pressed = true
	_vhs_check.toggled.connect(func(on: bool) -> void: vhs_changed.emit(on))
	root.add_child(_vhs_check)

	_power = Button.new()
	_power.text = "Switch off"
	_power.custom_minimum_size = Vector2(0, 40)
	_power.pressed.connect(func() -> void: power_pressed.emit())
	root.add_child(_power)


func _emit_skips() -> void:
	skips_changed.emit(int(_skip_back_edit.text) if _skip_back_edit.text.is_valid_int() else 10,
		int(_skip_fwd_edit.text) if _skip_fwd_edit.text.is_valid_int() else 30)


func _emit_prefs() -> void:
	prefs_changed.emit(_audio_edit.text, _sub_edit.text)


func _method_button(row: Container, text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(func() -> void: method_changed.emit(method))
	row.add_child(b)
	return b


func _field_row(parent: Container, caption: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_ROW)
	lbl.custom_minimum_size = Vector2(100, 0)
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 38)
	edit.add_theme_font_size_override("font_size", 18)
	row.add_child(edit)
	return edit


## Fill the page from the decoder's state. Safe to call as often as it likes: a field being typed in
## is left alone, and the user list is rebuilt only when the list changed.
func populate(s: Dictionary) -> void:
	if _status == null:
		return
	_status.text = str(s["status"])
	_status.add_theme_color_override("font_color", COLOR_OK if bool(s["ok"]) else COLOR_WARN)
	if not _server_edit.has_focus():
		_server_edit.text = str(s["server"])
	var link := str(s["link"])
	var signed := link == "ready"
	var method := str(s["method"])
	_method_quick.button_pressed = method == "quick"
	_method_pass.button_pressed = method == "password"
	var can_sign_in := link in ["need_login", "quick_code", "signing_in"]
	_method_quick.get_parent().visible = not signed and can_sign_in
	_quick_box.visible = not signed and method == "quick" and can_sign_in
	_pass_box.visible = not signed and method == "password" and can_sign_in
	_signed_box.visible = signed
	_signed_label.text = "Signed in as %s" % str(s["user_name"])
	if _pass_box.visible:
		_set_users(s["users"] as Array)
	if not _audio_edit.has_focus():
		_audio_edit.text = str(s["pref_audio"])
	if not _sub_edit.has_focus():
		_sub_edit.text = str(s["pref_sub"])
	_power.text = "Switch off" if bool(s["powered"]) else "Switch on"
	_vhs_check.set_pressed_no_signal(bool(s.get("vhs", true)))
	if not _skip_back_edit.has_focus():
		_skip_back_edit.text = str(int(s.get("skip_back", 10)))
	if not _skip_fwd_edit.has_focus():
		_skip_fwd_edit.text = str(int(s.get("skip_forward", 30)))
	var now: Dictionary = s["now"]
	_now.text = str(now.get("text", "nothing"))
	if bool(now.get("playing", false)):
		var extra: PackedStringArray = []
		extra.append("Audio: %s" % str(now.get("audio", "?")))
		extra.append("Subtitles: %s" % str(now.get("subtitles", "?")))
		if now.has("line"):
			extra.append("Words (%s): %s" % [str(now.get("words_from", "")), str(now["line"]).replace("\n", " / ")])
		_line.text = "\n".join(extra)
	else:
		_line.text = ""
		if str(now.get("browsing", "")) != "":
			_line.text = "Browsing: %s" % str(now["browsing"])


func _set_users(users: Array) -> void:
	var key := str(users.hash())
	if key == _last_users_key and _users != null:
		return
	_last_users_key = key
	var opts: Array = []
	for u in users:
		opts.append([str((u as Dictionary).get("Name", "?")), str((u as Dictionary).get("Name", ""))])
	if _users == null:
		_users = VRDropdown.create("User", opts, _user_choice)
		_users.item_selected.connect(func(id: Variant) -> void: _user_choice = str(id))
		_users_host.add_child(_users)
	if opts.is_empty():
		_users.set_options([["(none listed)", ""]], "")
		_user_choice = ""
		_name_edit.get_parent().visible = true
		return
	_name_edit.get_parent().visible = false
	var keep := _user_choice
	var found := false
	for o in opts:
		if o[1] == keep:
			found = true
	_user_choice = keep if found else str(opts[0][1])
	_users.set_options(opts, _user_choice)
