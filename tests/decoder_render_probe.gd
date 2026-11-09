## A picture of the decoder in a little room of its own (windowed; a headless renderer returns blanks):
##   OUT=dir godot --path RetroXR --resolution 320x240 --position 20,20 res://mods/xenu.jellyfin/tests/decoder_render_probe.tscn
## Run through run_net_tests.py's environment (XENU_JF_SETTINGS) so the player's real server is not touched.
extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 520)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC   # the game's (tonemap_mode = 2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(light)
	var d: Node3D = (load("res://mods/xenu.jellyfin/scenes/jellyfin_decoder.tscn") as PackedScene).instantiate()
	vp.add_child(d)
	d.set("ignore_gravity", true)
	d.set("freeze", true)
	var r: Node3D = (load("res://mods/xenu.jellyfin/scenes/jellyfin_remote.tscn") as PackedScene).instantiate()
	vp.add_child(r)
	r.set("freeze", true)
	r.position = Vector3(0.32, 0.0, 0.12)
	r.rotation_degrees = Vector3(0, -25, 0)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0.18, 0.28, 0.62)
	cam.look_at(Vector3(0.12, 0.03, 0.0))
	for i in 12:
		await get_tree().process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp"
	var img := vp.get_texture().get_image()
	img.save_png("%s/decoder_in_room.png" % out)
	print("[probe] wrote decoder_in_room.png (%dx%d)" % [img.get_width(), img.get_height()])
	# Something "playing", so the display has words and a counter (no player behind it: only the display is looked at).
	d.set("_row", {"id": "e3", "type": "Episode", "name": "Return to Zero, the Sanctuary", "series": "Re:Zero - Starting Life in Another World",
		"season": 2, "episode": 3, "year": 2020, "ticks": 0})
	d.set("mode", 1)
	d.set("is_playing", true)
	d.set("link", "ready")
	d.call("_update_vfd")
	# The front, close: the logo where RETRO XR was, no cassette bay.
	cam.current = true
	cam.fov = 40.0
	cam.position = Vector3(0.0, 0.06, 0.50)
	cam.look_at(Vector3(0.0, 0.0, 0.135))
	for i in 6:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png("%s/decoder_front.png" % out)
	print("[probe] wrote decoder_front.png")
	cam.position = Vector3(-0.30, 0.07, 0.32)
	cam.look_at(Vector3(-0.10, 0.025, 0.135))
	cam.fov = 30.0
	vp.get_texture().get_image()
	for i in 6:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png("%s/decoder_logo_angle.png" % out)
	cam.position = Vector3(0.18, 0.28, 0.62)
	cam.look_at(Vector3(0.0, 0.0, 0.0))
	cam.fov = 40.0
	r.position = Vector3(0.30, 0.0, 0.25)
	for i in 6:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png("%s/decoder_three_quarter.png" % out)
	# the handset close up, from above
	var logo_at := r.global_position + Vector3(0.0, 0.011, 0.058)
	cam.position = logo_at + Vector3(0.0, 0.10, 0.012)
	cam.look_at(logo_at)
	cam.fov = 30.0
	for i in 6:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png("%s/remote_top.png" % out)
	# TAB on the decoder, from where a player at a table stands: the menu must be IN VIEW.
	var table := Node3D.new()
	vp.add_child(table)
	d.position = Vector3(0, 0.78, 0)   # on a table, as it is in a room
	r.position = Vector3(0.32, 0.78, 0.12)
	cam.current = true
	cam.fov = 70.0
	cam.position = Vector3(0.0, 1.55, 0.95)
	cam.look_at(Vector3(0.0, 0.85, 0.0))
	d.call("toggle_options_ui", cam)
	for i in 30:
		await get_tree().process_frame
	var panel := d.get_node_or_null("DecoderOptionsPanel") as Node3D
	var in_view := panel != null and cam.is_position_in_frustum(panel.global_position)
	print("[probe] menu panel: %s visible=%s in_view=%s at %s (decoder at %s)" % [panel != null, panel.visible if panel else false,
		in_view, str(panel.global_position) if panel else "-", str(d.global_position)])
	img = vp.get_texture().get_image()
	img.save_png("%s/decoder_menu_open.png" % out)
	print("[probe] wrote decoder_menu_open.png")
	get_tree().quit(0 if in_view else 1)
