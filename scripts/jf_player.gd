## The seam between the decoder and a video engine. The decoder talks to THIS and never to
## VlcPlayer directly, so the engine can change without touching it: libVLC today (jf_vlc_player.gd,
## desktop and Quest), ExoPlayer on the Quest when the decoder moves into the game (an Android
## plugin cannot ship in a mod -- see CLAUDE.md, "Debt on purpose").
##
## Times are in seconds; track lists are [{id, name}] where `id` is the engine's own handle and the
## ORDER is the stream order, which is what jf_api's `ordinal` indexes (no "disabled" row in them).
## This base class is a null engine: it plays nothing and says so, which is also what the decoder
## gets in a build without the video extension.
extends RefCounted

signal finished
signal failed(message: String)
signal started
signal stopped
## Percent buffered, as the engine says it (a stream that runs dry says so here).
signal buffering(percent: float)

## Whether an engine is actually behind this.
func is_available() -> bool:
	return false


## True when it can take an open() now (libVLC builds its instance on a thread at start-up).
func is_ready() -> bool:
	return true


func open(_url: String, _options: PackedStringArray = PackedStringArray()) -> bool:
	return false


func play() -> void:
	pass


func pause() -> void:
	pass


func set_paused(_on: bool) -> void:
	pass


func stop() -> void:
	pass


func is_playing() -> bool:
	return false


func position_s() -> float:
	return 0.0


## -1 while unknown (a stream whose length has not arrived).
func length_s() -> float:
	return -1.0


func seek_s(_seconds: float) -> void:
	pass


## Pull the latest picture; once per frame.
func update() -> void:
	pass


func texture() -> Texture2D:
	return null


## How many pictures have arrived since open(): a stalled stream stops counting.
func frame_count() -> int:
	return 0


func read_audio(_frames: int) -> PackedVector2Array:
	return PackedVector2Array()


## 0..1, the engine's own gain (the set's level is applied on the emitter).
func set_volume(_v: float) -> void:
	pass


func audio_tracks() -> Array:
	return []


func subtitle_tracks() -> Array:
	return []


func current_audio_id() -> int:
	return -1


func current_subtitle_id() -> int:
	return -1


func set_audio_track(_id: int) -> void:
	pass


## -1 = subtitles off.
func set_subtitle(_id: int) -> void:
	pass


func shutdown() -> void:
	pass
