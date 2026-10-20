class_name Creature
extends Node3D
## What a double really is, once it stops pretending: something like a
## banshee. Far too tall and thin, skin the grey of a drowned thing, ribs
## through the skin, black hair hanging wet over the face, eyes that are holes
## with a pinprick of light at the bottom, and a jaw that unhinges down to its
## chest. Built from primitives so it stays PS1-cheap.
##
## Poses: STAND (it waits in the dark, swaying), RUN (all fours, too fast),
## LUNGE (the catch: in your face, jaw wide, shaking).

enum Pose { STAND, RUN, LUNGE }

@export var skin := Color(0.58, 0.57, 0.55)
@export var height := 2.35

var pose := Pose.STAND
var t := 0.0
var mat: StandardMaterial3D
var hole: StandardMaterial3D
var gum: StandardMaterial3D
var tooth: StandardMaterial3D
var hair_mat: StandardMaterial3D
var pupil: StandardMaterial3D
var rig := Node3D.new()
var torso := Node3D.new()
var head := Node3D.new()
var jaw := Node3D.new()
var mouth: MeshInstance3D
var arms: Array[Node3D] = []
var forearms: Array[Node3D] = []
var thighs: Array[Node3D] = []
var shins: Array[Node3D] = []
var extra: Array[Node3D] = []
var hair: Array[Node3D] = []
var glow: OmniLight3D
var face_target := Vector3.INF
var face: StandardMaterial3D
var jaw_open := 0.0          # 0 shut .. 1 hanging to the chest
var jaw_want := 0.15


func _ready() -> void:
	mat = _mat(skin, 0.85)
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.rim_tint = 0.2
	face = _mat(skin.lightened(0.08), 0.8)
	face.albedo_texture = _corpse_skin()
	mat.albedo_texture = face.albedo_texture
	mat.uv1_scale = Vector3(3, 3, 3)
	hole = _mat(Color(0, 0, 0), 1.0, true)
	gum = _mat(Color(0.13, 0.01, 0.01), 0.6)
	tooth = _mat(Color(0.86, 0.82, 0.68), 0.4)
	hair_mat = _mat(Color(0.03, 0.03, 0.035), 0.3)
	hair_mat.metallic_specular = 0.9          # wet
	pupil = _mat(Color(0.9, 0.95, 1.0), 0.0, true)
	add_child(rig)
	_build()
	glow = OmniLight3D.new()
	glow.light_color = Color(0.62, 0.7, 0.8)
	glow.light_energy = 0.0
	glow.omni_range = 3.6
	glow.omni_attenuation = 0.7
	glow.shadow_enabled = false
	add_child(glow)
	glow.position = Vector3(0, 1.4, -0.9)


## Mottled dead skin: pale with grey-green blotches and dark veins, low-res
## so it reads as a PS1 texture.
func _corpse_skin() -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.09
	var v := FastNoiseLite.new()
	v.seed = 11
	v.noise_type = FastNoiseLite.TYPE_CELLULAR
	v.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	v.frequency = 0.12
	for y in 48:
		for x in 48:
			var b := n.get_noise_2d(x, y) * 0.5 + 0.5
			var vein := 1.0 - smoothstep(0.0, 0.08, v.get_noise_2d(x, y) + 0.9)
			var c := Color(1, 1, 1).lerp(Color(0.62, 0.68, 0.6), b * 0.7)
			c = c.lerp(Color(0.3, 0.32, 0.38), vein * 0.6)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _mat(c: Color, rough: float, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _cap(r: float, h: float, seg := 6) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.01)
	c.radial_segments = seg
	c.rings = 2
	return c


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


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
	# a knot of a joint at the far end
	_mi(p, _cap(r * 1.35, r * 2.7), Vector3(0, -length, 0))
	return p


func _build() -> void:
	var s := height / 2.35
	rig.scale = Vector3.ONE * s
	var hip_h := 1.18
	torso.position = Vector3(0, hip_h, 0)
	rig.add_child(torso)
	# pelvis, a caved-in belly, a long narrow chest, the spine showing
	_mi(torso, _cap(0.09, 0.2), Vector3(0, 0.05, 0))
	_mi(torso, _cap(0.06, 0.4), Vector3(0, 0.3, 0.01))
	_mi(torso, _cap(0.12, 0.5), Vector3(0, 0.7, 0.0))
	for i in 6:
		var rib := _mi(torso, _cap(0.012, 0.26), Vector3(0, 0.52 + i * 0.055, -0.1 + i * 0.004), hole)
		rib.rotation.z = PI / 2
		rib.scale = Vector3(1, 1, 1) * (1.0 - i * 0.04)
	for i in 5:
		_mi(torso, _cap(0.022, 0.05), Vector3(0, 0.45 + i * 0.1, 0.12))   # vertebrae
	_mi(torso, _cap(0.03, 0.26), Vector3(0, 1.02, -0.06)).rotation.x = -0.55   # neck, pushed forward
	head.position = Vector3(0, 1.12, -0.16)
	torso.add_child(head)
	# a long skull
	var sk := SphereMesh.new()
	sk.radius = 0.11
	sk.height = 0.36
	sk.radial_segments = 8
	sk.rings = 6
	_mi(head, sk, Vector3(0, 0.1, 0), face)
	# sunken sockets (a dark ring), the holes inside, a pinprick of light deep
	# in each; one eye a little bigger and lower than the other
	var ring := SphereMesh.new()
	ring.radius = 0.042
	ring.height = 0.07
	ring.radial_segments = 6
	ring.rings = 3
	var shade := _mat(skin.darkened(0.6), 0.9)
	var eye := SphereMesh.new()
	eye.radius = 0.026
	eye.height = 0.07
	eye.radial_segments = 6
	eye.rings = 3
	var pin := SphereMesh.new()
	pin.radius = 0.0035
	pin.height = 0.007
	pin.radial_segments = 4
	pin.rings = 2
	for k in 2:
		var x := -0.045 if k == 0 else 0.047
		var big := 1.0 if k == 0 else 1.18
		var dy := 0.0 if k == 0 else -0.008
		_mi(head, ring, Vector3(x, 0.152 + dy, -0.078), shade).scale = Vector3(big, big * 0.9, 0.6)
		_mi(head, eye, Vector3(x, 0.15 + dy, -0.09), hole).scale = Vector3(big, big, 1.0)
		_mi(head, pin, Vector3(x * 0.94, 0.146 + dy, -0.115), pupil)
	# where the nose was, and the cheeks fallen in
	var nose := PrismMesh.new()
	nose.size = Vector3(0.03, 0.04, 0.02)
	_mi(head, nose, Vector3(0, 0.1, -0.108), hole).rotation.x = PI
	for x in [-0.06, 0.06]:
		_mi(head, ring, Vector3(x, 0.075, -0.07), shade).scale = Vector3(0.7, 1.3, 0.5)
	# upper teeth: crooked points along the top of the mouth
	var fang := PrismMesh.new()
	fang.size = Vector3(0.018, 0.05, 0.014)
	for i in 9:
		var a := (i - 4) * 0.21
		var f := _mi(head, fang, Vector3(sin(a) * 0.05, 0.038, -0.118 + absf(sin(a)) * 0.03), tooth)
		f.rotation = Vector3(PI, 0, randf_range(-0.25, 0.25))
		f.scale.y = randf_range(0.8, 1.5)
	jaw.position = Vector3(0, 0.07, -0.02)
	head.add_child(jaw)
	_mi(jaw, _box(Vector3(0.1, 0.03, 0.12)), Vector3(0, -0.03, -0.055), face)          # the jawbone
	mouth = _mi(jaw, _box(Vector3(0.08, 0.075, 0.07)), Vector3(0, 0.0, -0.035), gum)   # inside the mouth
	_mi(jaw, _box(Vector3(0.07, 0.07, 0.02)), Vector3(0, -0.005, -0.03), hole)         # the throat
	for i in 8:   # lower teeth pointing up out of the stretched jaw
		var a := (i - 3.5) * 0.23
		var f := _mi(jaw, fang, Vector3(sin(a) * 0.044, -0.012, -0.122 + absf(sin(a)) * 0.03), tooth)
		f.rotation = Vector3(0, 0, randf_range(-0.25, 0.25))
		f.scale.y = randf_range(0.8, 1.6)
	# wet hair: long strands from the crown, hanging over the face
	for i in 16:
		var a := TAU * i / 16.0
		var root := Node3D.new()
		root.position = Vector3(sin(a) * 0.085, 0.24, cos(a) * 0.085)
		head.add_child(root)
		var front := cos(a) < -0.3
		var hl := randf_range(0.5, 0.75) if not front else randf_range(0.32, 0.45)
		var strand := _mi(root, _box(Vector3(randf_range(0.018, 0.03), hl, 0.012)), Vector3(0, -hl * 0.5, 0), hair_mat)
		strand.rotation.y = a
		root.rotation = Vector3(sin(a + PI) * 0.25 * (-1.0 if front else 1.0), 0, cos(a) * 0.1)
		hair.append(root)
		root.set_meta("front", front)
		root.set_meta("side", signf(sin(a)) if absf(sin(a)) > 0.05 else (1.0 if i % 2 == 0 else -1.0))
	# arms far too long, hands with long fingers and nails
	for side in [-1.0, 1.0]:
		var a := _limb(torso, Vector3(0.15 * side, 0.92, 0.0), 0.03, 0.74)
		var f := _limb(a, Vector3(0, -0.74, 0), 0.026, 0.8)
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.82, 0)
		f.add_child(hand)
		_mi(hand, _box(Vector3(0.07, 0.07, 0.025)), Vector3(0, -0.02, 0))
		for k in 4:
			var fp := _limb(hand, Vector3((k - 1.5) * 0.018, -0.05, 0), 0.007, 0.28 + absf(k - 1.5) * -0.03)
			fp.rotation = Vector3(0.2, 0, (k - 1.5) * 0.1)
		arms.append(a)
		forearms.append(f)
		var th := _limb(rig, Vector3(0.08 * side, hip_h, 0), 0.04, 0.62)
		var sh := _limb(th, Vector3(0, -0.62, 0), 0.03, 0.58)
		_mi(sh, _box(Vector3(0.05, 0.03, 0.17)), Vector3(0, -0.6, -0.05))   # long bare feet
		thighs.append(th)
		shins.append(sh)
		for k in 2:   # the extra arms it keeps folded until it runs
			var e := _limb(torso, Vector3(0.08 * side, 0.55 + k * 0.18, 0.08), 0.014, 0.9)
			e.visible = false
			extra.append(e)


func set_pose(p: Pose) -> void:
	pose = p
	# lunging, the face catches the light whatever the room is doing
	face.emission_enabled = p == Pose.LUNGE
	face.emission = skin * 0.35
	for e in extra:
		e.visible = p != Pose.STAND
	glow.light_energy = 0.0 if p == Pose.STAND else 2.2
	jaw_want = 0.15 if p == Pose.STAND else (0.55 if p == Pose.RUN else 1.0)


func reveal(on: bool) -> void:
	glow.light_energy = 2.6 if on else 0.0


func _process(dt: float) -> void:
	t += dt
	jaw_open = move_toward(jaw_open, jaw_want, dt * (9.0 if pose == Pose.LUNGE else 2.0))
	var shake := 0.0
	if pose == Pose.LUNGE:
		shake = 1.0
	jaw.rotation.x = -jaw_open * 1.1 + sin(t * 47.0) * 0.08 * shake
	jaw.scale = Vector3(1.0, 1.0 + jaw_open * 0.9, 1.0 + jaw_open * 0.4)   # the jaw stretches as it drops
	# the hair hangs, sways, whips when it moves
	var whip := 0.0 if pose == Pose.STAND else (0.5 if pose == Pose.RUN else 1.0)
	for i in hair.size():
		var h := hair[i]
		h.rotation.x = lerpf(h.rotation.x, sin(t * (1.3 + whip * 20.0) + i) * (0.06 + whip * 0.4), minf(dt * 10.0, 1.0))
		# lunging, the hair over the face flies apart so you see all of it
		var part := 1.25 * float(h.get_meta("side", 1.0)) if (pose == Pose.LUNGE and h.get_meta("front", false)) else 0.0
		h.rotation.z = lerpf(h.rotation.z, part, minf(dt * 18.0, 1.0))
	match pose:
		Pose.STAND:
			# it sways and its head ticks sideways, slowly, wrongly
			var tick := floorf(t * 1.5) * 0.37
			torso.rotation = Vector3(-0.42 + sin(t * 1.3) * 0.015, 0, sin(t * 0.7) * 0.03)
			head.rotation = Vector3(0.35, sin(tick) * 0.18, 0.45 * sin(t * 0.23) + sin(tick * 3.0) * 0.1)
			for i in 2:
				var sd := -1.0 if i == 0 else 1.0
				arms[i].rotation = Vector3(0.3, 0, 0.1 * sd)
				forearms[i].rotation = Vector3(-0.1, 0, 0)
				thighs[i].rotation = Vector3(0.22, 0, 0.05 * sd)
				shins[i].rotation = Vector3(-0.4, 0, 0)
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
			if pose == Pose.LUNGE:
				# up on its feet, bent over you, face level with yours and
				# shaking; arms out wide either side of your head
				rig.position.y = 0.0
				torso.rotation = Vector3(-0.3, 0, 0) + jit * 0.6
				head.rotation = Vector3(0.3 + randf_range(-0.06, 0.06), randf_range(-0.12, 0.12), randf_range(-0.2, 0.2))
				for i in 2:
					arms[i].rotation = Vector3(-1.9 + sin(t * 30.0 + i) * 0.08, 0, 1.15 * (-1.0 if i == 0 else 1.0))
					forearms[i].rotation = Vector3(-1.1, 0, 0)
					thighs[i].rotation = Vector3(0.1, 0, 0.08 * (-1.0 if i == 0 else 1.0))
					shins[i].rotation = Vector3(-0.15, 0, 0)
