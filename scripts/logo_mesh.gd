## The Jellyfin logo as an extruded mesh, in the logo's own colours (the gradient from #AA5CC3 to #00A4DC on the
## icon, white lettering). assets/jellyfin_logo.json is made by tools/make_logo_mesh.py from the official SVG: the
## logo's width is 1.0, the face looks along +Z, the back is at z = 0 and the front at z = depth.
##
## build() gives a MeshInstance3D sized in metres. The ArrayMesh is made once and shared by every instance.
extends RefCounted

const FILE := "res://mods/xenu.jellyfin/assets/jellyfin_logo.json"

static var _mesh: ArrayMesh = null
static var _data: Dictionary = {}
static var _material: StandardMaterial3D = null
static var _material_word: StandardMaterial3D = null


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_warning("[Jellyfin] the logo mesh %s did not load" % FILE)
	return _data


## The logo is `aspect` times as wide as it is tall.
static func aspect() -> float:
	return float(data().get("aspect", 3.5))


static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var d := data()
	if d.is_empty():
		return null
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var p: Array = d["positions"]
	var n: Array = d["normals"]
	var c: Array = d["colors"]
	for i in range(0, p.size(), 3):
		pos.append(Vector3(p[i], p[i + 1], p[i + 2]))
		nor.append(Vector3(n[i], n[i + 1], n[i + 2]))
		# The file holds the logo's colours as they are on screen (sRGB); vertex colours are read as linear.
		col.append(Color(c[i], c[i + 1], c[i + 2]).srgb_to_linear())
	var all: PackedInt32Array = PackedInt32Array(d["indices"])
	var split := clampi(int(d.get("word_from", all.size())), 0, all.size())
	# Two surfaces over the same vertices: the icon (the gradient) and the lettering (white), which want different
	# brightness under the game's tone mapping.
	_mesh = ArrayMesh.new()
	for part in 2:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nor
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_INDEX] = all.slice(0, split) if part == 0 else all.slice(split)
		if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			continue
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh.surface_set_material(_mesh.get_surface_count() - 1, material(part == 1))
	print("[Jellyfin] logo mesh: %d vertices, %d triangles" % [pos.size(), (d["indices"] as Array).size() / 3])
	return _mesh


## UNSHADED: the colours are the brand's whatever the room's light does (a lit white wordmark came out grey on the black
## plate). The lettering is driven a touch above 1 so the game's Filmic tone mapping, which brings a plain 1.0 down to
## about 0.8, still lands near white; more than that blooms into a halo (it did, at 1.8: that was a patch over a winding
## bug, not a need). The icon stays at 1.0, its gradient as drawn. The walls of the extrusion keep the darker vertex
## colour the tool gave them, which is what shows the depth.
static func material(lettering: bool = false) -> StandardMaterial3D:
	var cached: StandardMaterial3D = _material_word if lettering else _material
	if cached == null:
		cached = StandardMaterial3D.new()
		cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cached.vertex_color_use_as_albedo = true
		var k := 1.15 if lettering else 1.0
		cached.albedo_color = Color(k, k, k)
		cached.cull_mode = BaseMaterial3D.CULL_BACK
		cached.resource_name = "JellyfinLogoLettering" if lettering else "JellyfinLogoIcon"
		if lettering:
			_material_word = cached
		else:
			_material = cached
	return cached


## The logo `width` metres wide, `depth` metres proud of the surface it is put on (its origin is its centre, on
## that surface; it faces +Z).
static func build(width: float, depth: float) -> MeshInstance3D:
	var m := mesh()
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "JellyfinLogo"
	mi.mesh = m
	mi.scale = Vector3(width, width, depth / float(data().get("depth", 0.045)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.add_to_group("outline_exclude")
	return mi
