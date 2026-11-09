## The decoder and the remote, rendered on a TRANSPARENT background, for artwork (windowed):
##   OUT=dir godot --path RetroXR --resolution 1280x720 --position 20,20 res://mods/xenu.jellyfin/tests/elements_render_probe.tscn
extends Node

const DECODER := "res://mods/xenu.jellyfin/scenes/jellyfin_decoder.tscn"
const REMOTE := "res://mods/xenu.jellyfin/scenes/jellyfin_remote.tscn"


func _ready() -> void:
	_run.call_deferred()


func _shot(vp: SubViewport, name: String, out: String) -> void:
	for i in 8:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	# crop to what is drawn (alpha bounding box)
	var bb := img.get_used_rect()
	img = img.get_region(bb)
	img.save_png("%s/%s.png" % [out, name])
	print("[probe] wrote %s.png %s alpha=%s" % [name, str(img.get_size()), str(img.get_pixel(0, 0).a)])


func _run() -> void:
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp"
	var vp := SubViewport.new()
	vp.size = Vector2i(2000, 1400)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.background_color = Color(0, 0, 0, 0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(light)
	var d: Node3D = (load(DECODER) as PackedScene).instantiate()
	vp.add_child(d)
	d.set("ignore_gravity", true)
	d.set("freeze", true)
	d.set("link", "ready")
	d.set("_row", {"id": "e3", "type": "Episode", "name": "Return to Zero, the Sanctuary", "series": "Re:Zero - Starting Life in Another World", "season": 2, "episode": 3, "year": 2020, "ticks": 0})
	d.set("mode", 1)
	d.set("is_playing", true)
	d.call("_update_vfd")
	var r: Node3D = (load(REMOTE) as PackedScene).instantiate()
	vp.add_child(r)
	r.set("freeze", true)
	r.position = Vector3(0.36, 0.0, 0.10)
	r.rotation_degrees = Vector3(0, -25, 0)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.fov = 34.0
	# the decoder alone, three-quarter
	cam.position = Vector3(0.18, 0.28, 0.62)
	cam.look_at(Vector3(0.0, 0.0, 0.0))
	d.position = Vector3.ZERO
	r.visible = false
	await _shot(vp, "decoder_three_quarter", out)
	# the front, straight on
	cam.position = Vector3(0.0, 0.06, 0.75)
	cam.look_at(Vector3(0.0, 0.0, 0.135))
	await _shot(vp, "decoder_front", out)
	# the remote, from above
	r.visible = true
	d.visible = false
	cam.position = Vector3(0.0, 0.34, 0.16)
	cam.look_at(Vector3(0, 0, 0.0))
	r.position = Vector3.ZERO
	r.rotation_degrees = Vector3(0, 0, 0)
	await _shot(vp, "remote_top", out)
	get_tree().quit(0)
