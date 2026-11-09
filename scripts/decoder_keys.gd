## The decoder's keys on the front: the directional cross with OK (new keys, built here, at the faceplate's right end) above the transport row (the
## model's own REW / PLAY / FF / STOP caps, with their printed icons: skip back, play, skip forward, stop).
##
## The model has no arrows, so the five navigation keys are VRButtons made from an adopted key (a copy of the PLAY
## button, which already wears the front-panel turn and the press travel) with a cap of their own: a box in the same
## light plastic as the model's keys and a glyph on it (TransportGlyphs, as the remote's cells). They press like the
## others: a fingertip, the laser or a click; the shape of the ray's box IS the cap.
extends RefCounted

const Livery = preload("res://mods/xenu.jellyfin/scripts/decoder_livery.gd")

## The caps are the model's own keys' size and plastic; where the cross stands is the livery's (the strip's right end).
const CAP_COLOR := Color(0.66, 0.67, 0.70)
const GLYPH_COLOR := Color(0.07, 0.08, 0.10)
## How far a cap stands out of the faceplate at rest (the model's keys stand about a millimetre proud of their panel).
const PROUD := 0.0010

## name -> [glyph code, column, row] on the cross (row +1 is up).
const NAV := {
	"UpButton": ["up", 0, 1], "LeftButton": ["left", -1, 0], "OkButton": ["ok", 0, 0],
	"RightButton": ["right", 1, 0], "DownButton": ["down", 0, -1],
}


## Where a key of the cross stands, in the model's frame.
static func nav_position(column: int, row: int) -> Vector3:
	return Livery.cross_center() + Vector3(column * Livery.CROSS_PITCH.x, row * Livery.CROSS_PITCH.y, 0.0)


## Build the five keys of the cross on `host`, copying `template` (an adopted front-panel VRButton). Returns name -> VRButton.
static func build_cross(host: Node3D, template: VRButton) -> Dictionary:
	var out := {}
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = CAP_COLOR
	plastic.roughness = 0.5
	plastic.metallic = 0.0
	for key_name: String in NAV:
		var spec: Array = NAV[key_name]
		var b := template.duplicate() as VRButton
		b.name = key_name
		host.add_child(b)
		# The same turn as the template (the front-panel adoption turned it), at this key's place.
		b.transform = Transform3D(template.transform.basis, nav_position(int(spec[1]), int(spec[2])))
		var cap := b.get_node("ButtonMesh") as MeshInstance3D
		var box := BoxMesh.new()
		box.size = Livery.CROSS_CAP
		box.material = plastic
		cap.mesh = box
		# The key's origin is on the faceplate: the (centred) box goes back half its depth, less the millimetre it stands proud.
		cap.transform = cap.transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -Livery.CROSS_CAP.z * 0.5 + PROUD))
		cap.material_override = null
		for i in cap.get_surface_override_material_count():
			cap.set_surface_override_material(i, null)
		var shape := b.get_node("CollisionShape3D") as CollisionShape3D
		var sb := BoxShape3D.new()
		sb.size = Livery.CROSS_CAP
		shape.shape = sb
		shape.transform = cap.transform
		b.set_button_mesh(cap)
		cap.visible = true
		b.press_gate = ApplianceModel.footprint_gate(cap, 0.001)
		b.trigger_radius = Vector2(Livery.CROSS_CAP.x, Livery.CROSS_CAP.y).length() * 0.5 + 0.003
		var legend := b.get_node_or_null("ButtonLabel") as Node3D
		if legend != null:
			legend.visible = false
		# The glyph, printed on the cap's face (in the cap's own frame: x right, y up, z out).
		var label := Label3D.new()
		label.name = "Glyph"
		label.font = TransportGlyphs.font()
		label.text = TransportGlyphs.glyph(str(spec[0]))
		label.font_size = 48
		label.pixel_size = 0.00012
		label.modulate = GLYPH_COLOR
		label.shaded = false
		label.double_sided = false
		label.no_depth_test = false
		label.position = Vector3(0.0, 0.0, Livery.CROSS_CAP.z * 0.5 + 0.0008)
		cap.add_child(label)
		out[key_name] = b
	return out
