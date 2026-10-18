extends Node3D

@export var size := 220.0
@export var center := Vector2(12.0, 8.0)
@export var step := 2.0
@export var amp := 6.0
@export var freq := 0.022
@export var flat_margin := 3.0
@export var blend := 14.0
@export var rim_start := 55.0
@export var rim_slope := 0.16
@export var base := -0.035
@export var noise_seed := 1847
@export var uv_scale := 0.08
@export var yard := Rect2(-2.0, -3.0, 23.0, 16.0)
@export var flat_models: Array[String] = ["church", "shrek-house", "houses"]

var noise := FastNoiseLite.new()
var zones: Array[Rect2] = []


func _ready() -> void:
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var lv := get_parent()
	zones.append(yard)
	for n in flat_models:
		var m := lv.get_node_or_null(n)
		if m == null:
			continue
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = mi.global_transform * mi.get_aabb()
			zones.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z))
	var mat: Material = null
	var mud := lv.get_node_or_null("Outside/Ground/Mud") as CSGBox3D
	if mud:
		mat = mud.material
		mud.queue_free()
	build(mat)
	for c in lv.get_children():
		if c is Node3D and String(c.name).begins_with("tree"):
			var p: Vector3 = c.global_position
			c.global_position.y = height(p.x, p.z) - 0.05


func zone_dist(x: float, z: float) -> float:
	var best := INF
	for r in zones:
		var dx := maxf(maxf(r.position.x - x, 0.0), x - r.end.x)
		var dz := maxf(maxf(r.position.y - z, 0.0), z - r.end.y)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


func height(x: float, z: float) -> float:
	var t := smoothstep(flat_margin, flat_margin + blend, zone_dist(x, z))
	if t <= 0.0:
		return base
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * amp
	var r := Vector2(x, z).distance_to(center)
	var rim := maxf(r - rim_start, 0.0) * rim_slope
	return base + t * (hills + rim)


func build(mat: Material) -> void:
	var n := int(size / step) + 1
	var x0 := center.x - size * 0.5
	var z0 := center.y - size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var x := x0 + i * step
			var z := z0 + j * step
			st.set_uv(Vector2(x, z) * uv_scale)
			st.add_vertex(Vector3(x, height(x, z), z))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
