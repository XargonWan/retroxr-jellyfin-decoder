## The decoder's picture while it is not playing: a Teletext / Televideo service in a SubViewport.
##
## 512 x 384 (4:3: the set's scanlines come from this height). It is redrawn ONLY when asked
## (refresh()), as UPDATE_ONCE -- never UPDATE_ALWAYS, which hangs a headless run and costs a Quest
## frame time for a page that changes a few times a minute. One ViewportTexture is handed out for
## good: the set compares texture identity to know the picture is the same one.
##
## For the chooser pages laid over a film, a backdrop texture can sit behind the canvas and the
## canvas goes transparent; the viewport then redraws every frame (outside a headless run) so the
## film keeps moving under it.
extends Node

const Canvas = preload("res://mods/xenu.jellyfin/scripts/teletext_canvas.gd")
const Pages = preload("res://mods/xenu.jellyfin/scripts/jf_pages.gd")

const SIZE := Vector2i(512, 384)

var pages: RefCounted = null

var _viewport: SubViewport = null
var _canvas: Control = null
var _backdrop: TextureRect = null
var _over_video := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "TeletextViewport"
	_viewport.size = SIZE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.gui_disable_input = true
	add_child(_viewport)
	_backdrop = TextureRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.size = Vector2(SIZE)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.visible = false
	_viewport.add_child(_backdrop)
	_canvas = Canvas.new()
	_canvas.name = "Canvas"
	_canvas.size = Vector2(SIZE)
	_viewport.add_child(_canvas)
	if pages == null:
		pages = Pages.new()
	refresh()


func texture() -> Texture2D:
	return _viewport.get_texture() if _viewport else null


## Redraw the page now.
func refresh() -> void:
	if _canvas == null:
		return
	var t := Time.get_datetime_dict_from_system()
	var clock := "%s %02d %s %02d:%02d:%02d" % [
		["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(t["weekday"])], int(t["day"]),
		["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(t["month"]) - 1],
		int(t["hour"]), int(t["minute"]), int(t["second"])]
	_canvas.set_lines(pages.render(clock))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if not _over_video \
			else _live_mode()


func _live_mode() -> int:
	# A dummy renderer never finishes an ALWAYS viewport; a headless test only needs the page drawn once.
	return SubViewport.UPDATE_ONCE if DisplayServer.get_name() == "headless" else SubViewport.UPDATE_ALWAYS


## Lay the page over a picture (the film) or take it off again. `tex` null = opaque page.
func set_backdrop(tex: Texture2D) -> void:
	var over := tex != null
	_backdrop.texture = tex
	_backdrop.visible = over
	_canvas.transparent = over
	if over != _over_video:
		_over_video = over
		refresh()


func is_over_video() -> bool:
	return _over_video


## Whether the next refresh() will have drawn (a test reads the canvas's lines).
func current_lines() -> Array:
	return _canvas.lines if _canvas else []
