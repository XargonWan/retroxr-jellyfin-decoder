## The Jellyfin REST client: one HTTPRequest per call (the RomM client's arrangement), a callback
## per call, and the Quick Connect dance as a small state machine of its own.
##
## Every callback is `func(ok: bool, data: Variant, code: int)`: `data` is the parsed JSON (or the
## raw text for get_text), `code` the HTTP status (0 = never got one). A 401/403 once a token is held
## also emits `auth_failed`, and that is terminal: the decoder signs out rather than retry.
##
## Reachability is logged on its changes only; the token is never logged.
extends Node

const Api = preload("res://mods/xenu.jellyfin/scripts/jf_api.gd")
const Config = preload("res://mods/xenu.jellyfin/scripts/jf_config.gd")

signal auth_failed
signal reachable_changed(reachable: bool)
## Quick Connect: the code to type on an already signed-in device.
signal quick_connect_code(code: String)
## Signed in (either way). `user` is {Id, Name}.
signal signed_in(user: Dictionary)
signal sign_in_failed(message: String)

const TIMEOUT_SECONDS := 20.0
const QC_POLL_SECONDS := 2.0
const QC_GIVE_UP_SECONDS := 300.0

var base: String = ""
var token: String = ""
var user_id: String = ""
var device_id: String = ""
var reachable: bool = true

var _qc_secret := ""
var _qc_timer: Timer = null
var _qc_started_msec := 0
var _qc_busy := false
var _inflight := 0


func _ready() -> void:
	device_id = Config.device_id()


## Point the client at a server and (maybe) an existing login.
func configure(server: String, access_token: String = "", uid: String = "") -> void:
	base = Api.normalize_server(server)
	token = access_token
	user_id = uid


func has_login() -> bool:
	return not token.is_empty() and not user_id.is_empty()


func inflight() -> int:
	return _inflight


# --- the request --------------------------------------------------------------------------------

func _headers(json_body: bool) -> PackedStringArray:
	var h := PackedStringArray([Api.auth_header(device_id, token), "Accept: application/json"])
	if json_body:
		h.append("Content-Type: application/json")
	return h


## `body` null = no body. `raw` returns the text as it came (a subtitle file) instead of parsing.
func request(method: int, path: String, body: Variant, cb: Callable, raw: bool = false) -> void:
	if base.is_empty():
		_call(cb, false, "no server address", 0)
		return
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = TIMEOUT_SECONDS
	http.max_redirects = 4
	add_child(http)
	_inflight += 1
	var url := base + path
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, bytes: PackedByteArray) -> void:
		_inflight -= 1
		http.queue_free()
		_on_done(url, result, code, bytes, cb, raw))
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(url, _headers(body != null), method, payload)
	if err != OK:
		_inflight -= 1
		http.queue_free()
		print("[Jellyfin] request not sent (%s): error %d" % [Api.redact(url), err])
		_set_reachable(false)
		_call(cb, false, "request failed (%d)" % err, 0)


func _on_done(url: String, result: int, code: int, bytes: PackedByteArray, cb: Callable, raw: bool) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[Jellyfin] %s: no answer (result %d)" % [Api.redact(url), result])
		_set_reachable(false)
		_call(cb, false, "no answer from the server", 0)
		return
	_set_reachable(true)
	var text := bytes.get_string_from_utf8()
	if code == 401 or code == 403:
		print("[Jellyfin] %s: refused (%d)" % [Api.redact(url), code])
		if has_login():
			auth_failed.emit()
		_call(cb, false, text, code)
		return
	if code < 200 or code >= 300:
		print("[Jellyfin] %s: HTTP %d" % [Api.redact(url), code])
		_call(cb, false, text, code)
		return
	if raw:
		_call(cb, true, text, code)
		return
	if text.strip_edges().is_empty():
		_call(cb, true, {}, code)
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		print("[Jellyfin] %s: the answer is not JSON" % Api.redact(url))
		_call(cb, false, "the server's answer was not understood", code)
		return
	_call(cb, true, parsed, code)


func _call(cb: Callable, ok: bool, data: Variant, code: int) -> void:
	if cb.is_valid():
		cb.call(ok, data, code)


func _set_reachable(r: bool) -> void:
	if r == reachable:
		return
	reachable = r
	print("[Jellyfin] server %s" % ("reachable again" if r else "UNREACHABLE"))
	reachable_changed.emit(r)


# --- the calls ----------------------------------------------------------------------------------

func ping(cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_public_info(), null, cb)


func public_users(cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_public_users(), null, cb)


func quick_connect_enabled(cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_qc_enabled(), null, cb)


func latest(cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_latest(user_id), null, cb)


func next_up(cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_next_up(user_id), null, cb)


func views(cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_views(user_id), null, cb)


func children(parent_id: String, cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_children(user_id, parent_id), null, cb)


func seasons(series_id: String, cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_seasons(user_id, series_id), null, cb)


func episodes(series_id: String, season_id: String, cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_episodes(user_id, series_id, season_id), null, cb)


func item(item_id: String, cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_item(user_id, item_id), null, cb)


func search(term: String, cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_search(user_id, term), null, cb)


func resume(cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, Api.path_resume(user_id), null, cb)


## Tell the server what is being played, the way every client does (kind: "start" | "progress" | "stopped"): it is what
## keeps "Continue watching" and the watched marks, and what its dashboard shows. A failure is logged, never fatal.
func report(kind: String, body: Dictionary) -> void:
	request(HTTPClient.METHOD_POST, Api.path_report(kind), body, func(ok: bool, _d: Variant, code: int) -> void:
		if not ok:
			print("[Jellyfin] playback report '%s' was not accepted (%d)" % [kind, code]))


func get_text(path: String, cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, path, null, cb, true)


# --- signing in ---------------------------------------------------------------------------------

## User + password. The password goes in this one request and nowhere else.
func sign_in_password(username: String, password: String) -> void:
	token = ""
	user_id = ""
	request(HTTPClient.METHOD_POST, Api.path_auth_by_name(), {"Username": username, "Pw": password},
		func(ok: bool, data: Variant, code: int) -> void:
			if not ok:
				sign_in_failed.emit("wrong user or password" if code == 401 else _why(data, code))
				return
			_finish_sign_in(data))


## Quick Connect: ask for a code, emit it, poll until somebody approves it, then sign in.
func sign_in_quick_connect() -> void:
	if _qc_busy:
		return
	token = ""
	user_id = ""
	_qc_busy = true
	quick_connect_enabled(func(ok: bool, data: Variant, code: int) -> void:
		if not ok or data != true:
			_qc_busy = false
			sign_in_failed.emit("Quick Connect is switched off on this server" if ok else _why(data, code))
			return
		request(HTTPClient.METHOD_POST, Api.path_qc_initiate(), null,
			func(ok2: bool, d2: Variant, c2: int) -> void:
				if not ok2 or not (d2 is Dictionary):
					_qc_busy = false
					sign_in_failed.emit(_why(d2, c2))
					return
				_qc_secret = str(d2.get("Secret", ""))
				var qc_code := str(d2.get("Code", ""))
				print("[Jellyfin] Quick Connect code issued")
				quick_connect_code.emit(qc_code)
				_start_polling()))


func cancel_quick_connect() -> void:
	_qc_busy = false
	_qc_secret = ""
	if _qc_timer != null:
		_qc_timer.stop()


func _start_polling() -> void:
	if _qc_timer == null:
		_qc_timer = Timer.new()
		_qc_timer.wait_time = QC_POLL_SECONDS
		_qc_timer.one_shot = false
		_qc_timer.timeout.connect(_poll_quick_connect)
		add_child(_qc_timer)
	_qc_started_msec = Time.get_ticks_msec()
	_qc_timer.start()


func _poll_quick_connect() -> void:
	if not _qc_busy or _qc_secret.is_empty():
		_qc_timer.stop()
		return
	if float(Time.get_ticks_msec() - _qc_started_msec) / 1000.0 > QC_GIVE_UP_SECONDS:
		cancel_quick_connect()
		sign_in_failed.emit("the code expired")
		return
	request(HTTPClient.METHOD_GET, Api.path_qc_poll(_qc_secret), null,
		func(ok: bool, data: Variant, code: int) -> void:
			if not _qc_busy:
				return
			if not ok:
				# A refused poll means the code is gone; a timeout is worth another try.
				if code != 0:
					cancel_quick_connect()
					sign_in_failed.emit(_why(data, code))
				return
			if data is Dictionary and bool(data.get("Authenticated", false)):
				var secret := _qc_secret
				cancel_quick_connect()
				request(HTTPClient.METHOD_POST, Api.path_auth_quick_connect(), {"Secret": secret},
					func(ok2: bool, d2: Variant, c2: int) -> void:
						if not ok2:
							sign_in_failed.emit(_why(d2, c2))
							return
						_finish_sign_in(d2)))


func _finish_sign_in(data: Variant) -> void:
	if not (data is Dictionary) or str(data.get("AccessToken", "")).is_empty():
		sign_in_failed.emit("the server did not give a token")
		return
	token = str(data["AccessToken"])
	var user: Dictionary = data.get("User", {})
	user_id = str(user.get("Id", ""))
	print("[Jellyfin] signed in as %s" % str(user.get("Name", "?")))
	signed_in.emit(user)


func _why(data: Variant, code: int) -> String:
	if code == 0:
		return str(data) if data is String else "no answer from the server"
	return "the server said %d" % code
