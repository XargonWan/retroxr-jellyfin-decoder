## Where the printed "RETRO XR" lines are on the VCR model (from the BodyPrint mesh's UVs): a measuring tool.
##   godot --headless --path RetroXR --script res://mods/xenu.jellyfin/tests/print_locate_probe.gd
extends SceneTree

const RECTS := {
	"hq4head": [0.0, 0.008, 1.0, 0.038], "big": [0.0, 0.052, 1.0, 0.126],
	"medium": [0.0, 0.141, 0.46, 0.175], "vcr_text": [0.0, 0.214, 0.78, 0.235],
	"remote_top": [0.0, 0.0, 1.0, 0.27],
}


func _init() -> void:
	var model := OS.get_environment("MODEL")
	if model.is_empty():
		model = "res://imported-assets/appliances/vcr/vcr_mobile.glb"
	var scene := load(model) as PackedScene
	var root := scene.instantiate() as Node3D
	root.name = "ModelRoot"
	get_root().add_child(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		print("[probe] mesh %s surfaces %d aabb %s" % [n.name, (n as MeshInstance3D).mesh.get_surface_count(), (n as MeshInstance3D).get_aabb()])
	var mi := root.find_child("BodyPrint", true, false) as MeshInstance3D
	if mi == null:
		print("[probe] no BodyPrint")
		quit(1)
		return
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var mat := mi.mesh.surface_get_material(0)
	print("[probe] BodyPrint: %d verts, %d tris, material %s, node transform %s" % [v.size(), ix.size() / 3, mat, mi.transform])
	if mat is BaseMaterial3D:
		print("[probe] albedo texture %s, transparency %d" % [(mat as BaseMaterial3D).albedo_texture, (mat as BaseMaterial3D).transparency])
	for k: String in RECTS:
		var r: Array = RECTS[k]
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var nsum := Vector3.ZERO
		var tris := 0
		for t in range(0, ix.size(), 3):
			var c := (uv[ix[t]] + uv[ix[t + 1]] + uv[ix[t + 2]]) / 3.0
			if c.x >= r[0] and c.x <= r[2] and c.y >= r[1] and c.y <= r[3]:
				tris += 1
				for q in 3:
					var p := mi.transform * v[ix[t + q]]
					lo = lo.min(p)
					hi = hi.max(p)
				nsum += nr[ix[t]]
		print("[probe] %-9s tris %3d  min %s  max %s  size %s  normal %s" % [k, tris, str(lo), str(hi), str(hi - lo), str((nsum / maxf(tris, 1)).normalized())])
	quit(0)
