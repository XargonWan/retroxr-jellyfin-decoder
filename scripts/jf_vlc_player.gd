## The libVLC engine (the game's VlcPlayer GDExtension) behind the JfPlayer seam.
##
## Created with ClassDB, behind class_exists, so a build without the extension still loads the scene
## (the decoder then says "VIDEO ENGINE UNAVAILABLE" on the TV). The instance is warmed on its own
## thread at once: left to the first open() it walks the whole plugin tree on the main thread.
extends "res://mods/xenu.jellyfin/scripts/jf_player.gd"

const Api = preload("res://mods/xenu.jellyfin/scripts/jf_api.gd")

var _vlc: Object = null
var _warned_options := false


func _init() -> void:
	if not ClassDB.class_exists("VlcPlayer"):
		push_warning("[Jellyfin] the VlcPlayer extension is not loaded: no video")
		return
	_vlc = ClassDB.instantiate("VlcPlayer")
	_vlc.finished.connect(func() -> void: finished.emit())
	_vlc.error.connect(func() -> void: failed.emit("the stream could not be played"))
	_vlc.playing.connect(func() -> void: started.emit())
	_vlc.stopped.connect(func() -> void: stopped.emit())
	_vlc.buffering.connect(func(percent: float) -> void: buffering.emit(percent))
	_vlc.warm_up()


func is_available() -> bool:
	return _vlc != null


func is_ready() -> bool:
	return _vlc != null and bool(_vlc.is_ready())


func open(url: String, options: PackedStringArray = PackedStringArray()) -> bool:
	if _vlc == null:
		return false
	if _vlc.has_method("set_media_options"):
		_vlc.set_media_options(options)
	elif not options.is_empty() and not _warned_options:
		# An older build of the extension: it plays, without the cache setting.
		_warned_options = true
		push_warning("[Jellyfin] this VlcPlayer has no set_media_options (old build): the network cache stays at its default")
	print("[Jellyfin] opening %s" % Api.redact(url))
	if not _vlc.open(url, false):
		print("[Jellyfin] VlcPlayer refused the address")
		return false
	return true


func play() -> void:
	if _vlc:
		_vlc.play()
		_vlc.set_volume(100)


func pause() -> void:
	if _vlc:
		_vlc.pause()


func set_paused(on: bool) -> void:
	if _vlc:
		_vlc.set_paused(on)


func stop() -> void:
	if _vlc:
		_vlc.stop()


func is_playing() -> bool:
	return _vlc != null and bool(_vlc.is_playing())


func position_s() -> float:
	return (float(_vlc.get_time()) / 1000.0) if _vlc else 0.0


func length_s() -> float:
	if _vlc == null:
		return -1.0
	var ms: int = _vlc.get_length()
	return (float(ms) / 1000.0) if ms > 0 else -1.0


func seek_s(seconds: float) -> void:
	if _vlc == null:
		return
	var length := length_s()
	if length > 0.0:
		_vlc.set_position(clampf(seconds / length, 0.0, 1.0))


func update() -> void:
	if _vlc:
		_vlc.update_frame()


func texture() -> Texture2D:
	return _vlc.get_texture() if _vlc else null


func frame_count() -> int:
	return int(_vlc.get_frame_count()) if _vlc else 0


func read_audio(frames: int) -> PackedVector2Array:
	return _vlc.read_audio(frames) if _vlc else PackedVector2Array()


func set_volume(v: float) -> void:
	if _vlc:
		_vlc.set_volume(int(clampf(v, 0.0, 1.0) * 100.0))


## libVLC lists a "Disable" row (id -1) among the tracks; the seam does not.
func _real(tracks: Array) -> Array:
	var out: Array = []
	for t in tracks:
		if t is Dictionary and int(t.get("id", -1)) >= 0:
			out.append({"id": int(t["id"]), "name": str(t.get("name", ""))})
	return out


func audio_tracks() -> Array:
	return _real(_vlc.get_audio_tracks()) if _vlc else []


func subtitle_tracks() -> Array:
	return _real(_vlc.get_subtitle_tracks()) if _vlc else []


func current_audio_id() -> int:
	return int(_vlc.get_audio_track()) if _vlc else -1


func current_subtitle_id() -> int:
	return int(_vlc.get_subtitle()) if _vlc else -1


func set_audio_track(id: int) -> void:
	if _vlc:
		_vlc.set_audio_track(id)


func set_subtitle(id: int) -> void:
	if _vlc:
		_vlc.set_subtitle(id)


func shutdown() -> void:
	if _vlc:
		_vlc.shutdown()
		_vlc = null
