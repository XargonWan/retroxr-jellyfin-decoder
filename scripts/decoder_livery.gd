## What makes the decoder not a VCR: the cassette bay taken off, the printed RETRO XR lines taken off the
## model's own print atlas, and the Jellyfin logo standing proud of the front in their place.
##
## The GLBs are never edited. The model's parts are hidden (Door, CassetteHolder, TapeCarrier), the print atlas
## is erased where the old lines are in a COPY of it (a material override on this instance: the shared mesh and
## material are untouched), and the logo is a mesh of its own (logo_mesh.gd).
##
## The decoder shows the model's CLOSE level at every distance: LOD1 and LOD2 are one Body with the cassette
## door baked in, which no part can hide.
extends RefCounted

const LogoMesh = preload("res://mods/xenu.jellyfin/scripts/logo_mesh.gd")

## The printed lines to take off, as fractions of the atlas' height: the HQ / 4 HEAD line, the big RETRO XR, the
## small RETRO XR, VIDEO CASSETTE RECORDER. LOD0 and LOD1 share a layout; LOD2's is its own.
const BANDS_TALL := [[0.005, 0.041], [0.049, 0.129], [0.138, 0.178], [0.211, 0.238]]
const BANDS_FLAT := [[0.005, 0.048], [0.062, 0.160], [0.183, 0.221], [0.250, 0.304]]
## The remote's big RETRO XR (LOD0 0.032-0.248, LOD1 0.031-0.237 of the height).
const REMOTE_BANDS := [[0.015, 0.262]]

## The decoder's front strip (the VCR model's frame, metres): the cassette bay and the old display window sit side
## by side at y -0.0014 .. 0.0299 from x -0.1664 to 0.168. One faceplate closes both, a little proud of the front, and
## carries, left to right, the Jellyfin logo (a quarter of the strip) and a long LED display (three quarters).
const STRIP_X0 := -0.1665
const STRIP_X1 := 0.1685
const STRIP_Y := 0.01425
const STRIP_HEIGHT := 0.0313
## Wider to the left than the strip: the recess in the body runs about 5 mm past the door's edge (a dark sliver showed).
const PLATE_SIZE := Vector3(0.3475, 0.0340, 0.0032)
const PLATE_CENTER := Vector3(-0.0027, STRIP_Y, 0.1349)
const PLATE_COLOR := Color(0.045, 0.048, 0.056)
## The plate's front face (z), where the logo and the display stand.
const PLATE_FRONT := 0.1349 + 0.0016
## The three slots the removed keys (EJECT, PAUSE, REC) left in the key rail, to the right of STOP.
const SLOTS_PLATE_SIZE := Vector3(0.0585, 0.0150, 0.0030)
const SLOTS_PLATE_CENTER := Vector3(0.1425, -0.0155, 0.1350)
## The logo cell is the strip's first quarter; the logo fills most of it.
const LOGO_CELL := 0.25
const LOGO_WIDTH := 0.078
const LOGO_DEPTH := 0.0035
## The directional cross and OK stand at the strip's RIGHT end, on the faceplate, as big as the model's own keys
## (16 x 8.6 mm caps, 6 mm deep); three rows of them fit the strip's 31 mm. The display gives up that much of its length.
const CROSS_CAP := Vector3(0.016, 0.0086, 0.0055)
const CROSS_PITCH := Vector2(0.0170, 0.0096)
const CROSS_MARGIN := 0.004
## Between the logo and the cross the display runs, 25 mm tall like the VCR's own, with a margin each side.
const DISPLAY_MARGIN := 0.003
const DISPLAY_HEIGHT := 0.025


static func strip_width() -> float:
	return STRIP_X1 - STRIP_X0


static func logo_center() -> Vector3:
	return Vector3(STRIP_X0 + strip_width() * LOGO_CELL * 0.5, STRIP_Y, PLATE_FRONT - 0.0002)


## The cross: its width, its middle (the key origin is the key's FACE, which stands on the faceplate).
static func cross_width() -> float:
	return CROSS_PITCH.x * 2.0 + CROSS_CAP.x


static func cross_center() -> Vector3:
	return Vector3(STRIP_X1 - CROSS_MARGIN - cross_width() * 0.5, STRIP_Y, PLATE_FRONT)


## Where the display starts and ends along x (the model's frame): after the logo's quarter, before the cross.
static func display_x0() -> float:
	return STRIP_X0 + strip_width() * LOGO_CELL + DISPLAY_MARGIN


static func display_x1() -> float:
	return cross_center().x - cross_width() * 0.5 - DISPLAY_MARGIN


## The display's size (m) and centre (the model's frame, on the plate's face).
static func display_size() -> Vector2:
	return Vector2(display_x1() - display_x0(), DISPLAY_HEIGHT)


static func display_center() -> Vector3:
	return Vector3((display_x0() + display_x1()) * 0.5, STRIP_Y, PLATE_FRONT + 0.0002)


## The remote (the tv-remote model's frame): the big RETRO XR is a 46 x 6 mm quad on the TOP face, near the back
## end (the tip is at -Z). The logo lies on it, its top towards the tip so it reads from the holder's side.
const REMOTE_LOGO_WIDTH := 0.038
const REMOTE_LOGO_DEPTH := 0.003
const REMOTE_LOGO_CENTER := Vector3(0.0, 0.01095, 0.0597)


## Strip the cassette bay and the old lettering off a VCR model, and put the logo on it. Returns the logo node.
static func dress(model: ApplianceModel) -> Node3D:
	_close_level_only(model)
	for part: String in ["Door", "CassetteHolder", "TapeCarrier"]:
		model.hide_part(part)
	var erased := erase_print(model, _vcr_bands)
	# The opening, closed: a faceplate a little proud of the front, the colour of the body.
	var plate := MeshInstance3D.new()
	plate.name = "BayPlate"
	var box := BoxMesh.new()
	box.size = PLATE_SIZE
	plate.mesh = box
	var pm := StandardMaterial3D.new()
	pm.albedo_color = PLATE_COLOR
	pm.roughness = 0.5
	pm.metallic = 0.0
	box.material = pm
	plate.position = PLATE_CENTER
	plate.add_to_group("outline_exclude")
	model.add_child(plate)
	# ... and the slots the removed keys left in the rail, closed the same way.
	var blank := MeshInstance3D.new()
	blank.name = "BlankPlate"
	var bbox := BoxMesh.new()
	bbox.size = SLOTS_PLATE_SIZE
	bbox.material = pm
	blank.mesh = bbox
	blank.position = SLOTS_PLATE_CENTER
	blank.add_to_group("outline_exclude")
	model.add_child(blank)
	var logo := LogoMesh.build(LOGO_WIDTH, LOGO_DEPTH)
	if logo != null:
		logo.position = logo_center()
		model.add_child(logo)
	print("[Jellyfin] livery: cassette bay closed, %d print atlas(es) cleaned, logo %s" % [erased, "on" if logo != null else "MISSING"])
	return logo


## The same for the handset: the RETRO XR on top gone, the logo in its place.
static func dress_remote(model: ApplianceModel) -> Node3D:
	_close_level_only(model)
	var erased := erase_print(model, _remote_bands)
	var logo := LogoMesh.build(REMOTE_LOGO_WIDTH, REMOTE_LOGO_DEPTH)
	if logo != null:
		# face up (+Y), its top towards -Z: x stays, y -> -z, z -> +y
		# (the node carries its size as a scale: keep it, turned)
		var turn := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
		logo.transform = Transform3D(turn * Basis.from_scale(logo.scale), REMOTE_LOGO_CENTER)
		model.add_child(logo)
	print("[Jellyfin] remote livery: %d print atlas(es) cleaned, logo %s" % [erased, "on" if logo != null else "MISSING"])
	return logo


static func _close_level_only(model: ApplianceModel) -> void:
	model.switch_distance = 100000.0
	model.far_distance = 200000.0
	model.call("_apply_ranges")


## The printed atlas of every level, with the old lines wiped to transparent in a copy. `bands_of(img)` says
## which rows (fractions of the height) to wipe for that atlas ([] = leave it). Returns how many were cleaned.
static func erase_print(model: ApplianceModel, bands_of: Callable) -> int:
	var done := 0
	for part in model.parts("BodyPrint"):
		var mi := part as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mat := mi.get_active_material(0) as StandardMaterial3D
		if mat == null or mat.albedo_texture == null:
			continue
		var img := mat.albedo_texture.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var bands: Array = bands_of.call(img)
		if bands.is_empty():
			continue
		wipe_bands(img, bands)
		img.generate_mipmaps()
		var copy := mat.duplicate() as StandardMaterial3D
		copy.albedo_texture = ImageTexture.create_from_image(img)
		mi.material_override = copy
		done += 1
	return done


## The VCR's atlases: LOD0 and LOD1 are tall and share a layout, LOD2 is flat.
static func _vcr_bands(img: Image) -> Array:
	return BANDS_TALL if img.get_height() > img.get_width() else BANDS_FLAT


## The remote's: LOD0 and LOD1 are about twice as wide as high (the big RETRO XR is the top band); LOD2 is a strip
## whose layout is not known, so it is left (the handset is only ever drawn at its close level).
static func _remote_bands(img: Image) -> Array:
	return REMOTE_BANDS if float(img.get_height()) / float(img.get_width()) > 0.3 else []


## Make the rows [from, to] (fractions of the height, whole width) transparent.
static func wipe_bands(img: Image, bands: Array) -> void:
	var h := img.get_height()
	var w := img.get_width()
	for b: Array in bands:
		var y0 := clampi(int(floor(float(b[0]) * h)), 0, h)
		var y1 := clampi(int(ceil(float(b[1]) * h)), 0, h)
		img.fill_rect(Rect2i(0, y0, w, y1 - y0), Color(0, 0, 0, 0))
