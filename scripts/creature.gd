class_name Creature
extends Node3D

enum Pose { STAND, RUN, LUNGE }

@export var skin := Color(0.075, 0.068, 0.066)
@export var height := 2.35

var pose := Pose.STAND
var t := 0.0
var mat: StandardMaterial3D
var hole: StandardMaterial3D
var rig := Node3D.new()
var torso := Node3D.new()
var head := Node3D.new()
var mouth: MeshInstance3D
var arms: Array[Node3D] = []
var forearms: Array[Node3D] = []
var thighs: Array[Node3D] = []
var shins: Array[Node3D] = []
var extra: Array[Node3D] = []
var glow: OmniLight3D
var face_target := Vector3.INF
var face: StandardMaterial3D


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.albedo_color = skin
	mat.roughness = 0.75
	mat.rim_enabled = true
	mat.rim = 1.0
	mat.rim_tint = 0.35
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	face = mat.duplicate()
	face.albedo_color = Color(0.2, 0.185, 0.17)
	hole = StandardMaterial3D.new()
	hole.albedo_color = Color(0, 0, 0)
	hole.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(rig)
	_build()
	glow = OmniLight3D.new()
	glow.light_color = Color(0.55, 0.62, 0.75)
	glow.light_energy = 0.0
	glow.omni_range = 3.6
	glow.omni_attenuation = 0.7
	glow.shadow_enabled = false
	add_child(glow)
	glow.position = Vector3(0, 1.7, -0.75)


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.01)
	c.radial_segments = 6
	c.rings = 2
	return c


func _mi(parent: Node3D, m: Mesh, pos: Vector3, material: Material = null) -> MeshInstance3D:
	var x := MeshInstance3D.new()
	x.mesh = m
	x.material_override = material if material else mat
	x.position = pos
	parent.add_child(x)
	return x


func _limb(parent: Node3D, at: Vector3, r: float, length: float) -> Node3D:
	var p := Node3D.new()
	p.position = at
	parent.add_child(p)
	_mi(p, _cap(r, length), Vector3(0, -length * 0.5, 0))
	return p


func _build() -> void:
	var s := height / 2.35
	rig.scale = Vector3.ONE * s
	var hip_h := 1.18
	torso.position = Vector3(0, hip_h, 0)
	rig.add_child(torso)
	_mi(torso, _cap(0.075, 0.42), Vector3(0, 0.16, 0))
	_mi(torso, _cap(0.13, 0.62), Vector3(0, 0.62, 0.02))
	for i in 4:
		_mi(torso, _cap(0.02, 0.24), Vector3(0, 0.5 + i * 0.07, -0.11)).rotation.z = PI / 2
	_mi(torso, _cap(0.035, 0.22), Vector3(0, 1.0, -0.05)).rotation.x = -0.6
	head.position = Vector3(0, 1.1, -0.16)
	torso.add_child(head)
	var sk := SphereMesh.new()
	sk.radius = 0.12
	sk.height = 0.36
	sk.radial_segments = 8
	sk.rings = 5
	_mi(head, sk, Vector3(0, 0.08, 0), face)
	var eye := SphereMesh.new()
	eye.radius = 0.04
	eye.height = 0.085
	eye.radial_segments = 6
	eye.rings = 3
	for x in [-0.048, 0.048]:
		_mi(head, eye, Vector3(x * 1.1, 0.15, -0.093), hole)
	var mo := SphereMesh.new()
	mo.radius = 0.045
	mo.height = 0.17
	mo.radial_segments = 6
	mo.rings = 4
	mouth = _mi(head, mo, Vector3(0, -0.02, -0.098), hole)
	for side in [-1.0, 1.0]:
		var a := _limb(torso, Vector3(0.16 * side, 0.88, 0.0), 0.035, 0.72)
		var f := _limb(a, Vector3(0, -0.72, 0), 0.03, 0.78)
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.78, 0)
		f.add_child(hand)
		for k in 4:
			var fp := _limb(hand, Vector3((k - 1.5) * 0.018, 0, 0), 0.008, 0.26)
			fp.rotation = Vector3(0.15, 0, (k - 1.5) * 0.12)
		arms.append(a)
		forearms.append(f)
		var th := _limb(rig, Vector3(0.09 * side, hip_h, 0), 0.04, 0.62)
		var sh := _limb(th, Vector3(0, -0.62, 0), 0.032, 0.58)
		thighs.append(th)
		shins.append(sh)
		for k in 2:
			var e := _limb(torso, Vector3(0.08 * side, 0.55 + k * 0.18, 0.1), 0.014, 0.9)
			e.visible = false
			extra.append(e)


func set_pose(p: Pose) -> void:
	pose = p
	for e in extra:
		e.visible = p != Pose.STAND
	glow.light_energy = 0.0 if p == Pose.STAND else 2.2


func reveal(on: bool) -> void:
	glow.light_energy = 2.6 if on else 0.0


func _process(dt: float) -> void:
	t += dt
	match pose:
		Pose.STAND:
			torso.rotation = Vector3(-0.38 + sin(t * 1.3) * 0.015, 0, sin(t * 0.7) * 0.02)
			head.rotation = Vector3(0.25, sin(t * 0.4) * 0.15, 0.25 * sin(t * 0.23))
			for i in 2:
				var sd := -1.0 if i == 0 else 1.0
				arms[i].rotation = Vector3(0.25, 0, 0.12 * sd)
				forearms[i].rotation = Vector3(-0.15, 0, 0)
				thighs[i].rotation = Vector3(0.2, 0, 0.05 * sd)
				shins[i].rotation = Vector3(-0.35, 0, 0)
			rig.position.y = 0.0
		Pose.RUN, Pose.LUNGE:
			var f := 22.0 if pose == Pose.RUN else 40.0
			var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06
			torso.rotation = Vector3(-1.25, 0, sin(t * f * 0.5) * 0.15) + jit
			head.rotation = Vector3(1.05 + sin(t * 31.0) * 0.12, randf_range(-0.2, 0.2), randf_range(-0.3, 0.3))
			rig.position.y = -0.45 + abs(sin(t * f)) * 0.08
			for i in 2:
				var ph := t * f + i * PI
				arms[i].rotation = Vector3(-1.2 + sin(ph) * 0.9, 0, (0.5 + 0.3 * cos(ph)) * (-1.0 if i == 0 else 1.0))
				forearms[i].rotation = Vector3(-0.6 + cos(ph) * 0.7, 0, 0)
				thighs[i].rotation = Vector3(0.9 + sin(ph + PI) * 0.8, 0, 0.25 * (-1.0 if i == 0 else 1.0))
				shins[i].rotation = Vector3(-1.1 + cos(ph) * 0.6, 0, 0)
			for k in extra.size():
				var ph2 := t * f * 1.3 + k * 1.7
				var sd := -1.0 if k < 2 else 1.0
				extra[k].rotation = Vector3(-0.4 + sin(ph2) * 1.0, 0, (1.3 + 0.4 * cos(ph2)) * sd)
			mouth.scale = Vector3(1.0, 1.4 + sin(t * 18.0) * 0.3, 1.0) if pose == Pose.LUNGE else Vector3.ONE * 1.15
			if pose == Pose.LUNGE and face_target != Vector3.INF:
				head.look_at(face_target, Vector3.UP)
				head.rotate_object_local(Vector3.FORWARD, randf_range(-0.12, 0.12))
