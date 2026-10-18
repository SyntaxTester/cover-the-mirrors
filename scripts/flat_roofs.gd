extends Node

@export var round_house := "shrek-house"
@export var round_cut := 1.9
@export var village := "houses"
@export var pitched_roofs: Array[String] = ["roof", "roof_003"]
@export var roof_in_mesh: Array[String] = ["Destroyed house"]
@export var slab := 0.12


func _ready() -> void:
	var lv := get_parent()
	var rh := lv.get_node_or_null(round_house) as Node3D
	if rh:
		for mi in rh.find_children("*", "MeshInstance3D", true, false):
			flatten(mi, rh.global_position.y + round_cut)
	var vl := lv.get_node_or_null(village)
	if vl == null:
		return
	for mn in roof_in_mesh:
		var mi := vl.get_node_or_null(mn) as MeshInstance3D
		if mi:
			var low := roof_bottom(mi)
			if low < INF:
				flatten(mi, low + slab)
	for rn in pitched_roofs:
		var roof := vl.get_node_or_null(rn) as MeshInstance3D
		if roof == null:
			continue
		var ra: AABB = roof.global_transform * roof.get_aabb()
		var cut := ra.position.y + slab
		roof.visible = false
		for mi in vl.find_children("*", "MeshInstance3D", true, false):
			if mi == roof or not mi.visible:
				continue
			var a: AABB = mi.global_transform * mi.get_aabb()
			var c := a.get_center()
			var inside := c.x > ra.position.x - 0.5 and c.x < ra.end.x + 0.5 and c.z > ra.position.z - 0.5 and c.z < ra.end.z + 0.5
			if inside and a.end.y > cut:
				flatten(mi, cut)


func roof_bottom(mi: MeshInstance3D) -> float:
	var gt := mi.global_transform
	var low := INF
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m == null or not m.resource_name.to_lower().contains("roof"):
			continue
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			low = minf(low, (gt * v).y)
	return low


func flatten(mi: MeshInstance3D, cut: float) -> void:
	var src := mi.mesh
	if src == null:
		return
	var gt := mi.global_transform
	var inv := gt.affine_inverse()
	var up := (inv.basis * Vector3.UP).normalized()
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		for i in v.size():
			var w := gt * v[i]
			if w.y > cut:
				w.y = cut
				v[i] = inv * w
				if i < nr.size():
					nr[i] = up
		arr[Mesh.ARRAY_VERTEX] = v
		if nr.size() > 0:
			arr[Mesh.ARRAY_NORMAL] = nr
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
		out.surface_set_material(s, mi.get_active_material(s))
	mi.mesh = out
