extends Node
## The Long One. Something four metres tall stands in the yard in a mourner's
## black coat. Its body is far above the window; its neck comes down out of
## the dark, bent like a hook, and lays its head on its side against the
## glass. The face is one you know: someone who is sitting inside the house
## right now, grinning wider than a mouth goes. Its hands are flat on the
## pane, fingers twice as long as they should be.
##
## Silent. It is there when you look over. It stares; then the head lifts,
## slowly, up past the top of the window, and is gone.

const COAT := Color(0.06, 0.055, 0.06)
const SKIN := Color(0.42, 0.27, 0.23)
const GLASS_X := 14.26          # just outside the pane
const WIN := Vector3(GLASS_X, 1.45, 3.9)
const STAND := Vector3(15.25, 0.0, 3.9)   # its feet, in the yard
const SHOULDER_Y := 3.35
## The head comes in through the window, lying on its side across it.
const HEAD_AT := Vector3(14.12, 1.5, 4.42)

var root: Node3D
var head_pivot := Node3D.new()
var neck: Array[MeshInstance3D] = []
var level: Node3D
var visitors
var coat: StandardMaterial3D
var skin: StandardMaterial3D
var armed_t := 0.0
var watched := 0.0
var lift := 0.0
var head_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("tall_one")
	level = get_node("../../Level")
	visitors = get_node_or_null("../Visitors")
	coat = _mat(COAT, 0.95)
	skin = _mat(SKIN, 0.8)
	root = Node3D.new()
	root.name = "TallOne"
	root.visible = false
	level.add_child(root)
	_build_body()
	root.add_child(head_pivot)
	var l := OmniLight3D.new()   # cold light on the face from the room side
	l.light_color = Color(0.62, 0.72, 0.8)
	l.light_energy = 2.2
	l.omni_range = 1.5
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	root.add_child(l)
	l.position = Vector3(13.55, 1.25, 4.1)


func _mat(c: Color, r: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = r
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


func _cap(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(a.distance_to(b) + r * 2.0, r * 2.0 + 0.01)
	c.radial_segments = 6
	c.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	parent.add_child(mi)
	var mid := (a + b) * 0.5
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	mi.global_transform = Transform3D(Basis(side, up, side.cross(up)), mid)
	return mi


## Legs like fence posts, a narrow body high above the eaves, arms that hang
## down to the window, and the long bent neck.
func _build_body() -> void:
	var hip := Vector3(STAND.x + 0.1, 2.35, STAND.z)
	for dz in [-0.13, 0.13]:
		var knee := Vector3(STAND.x - 0.15, 1.2, STAND.z + dz * 1.4)
		_cap(root, Vector3(STAND.x, 0.05, STAND.z + dz * 1.6), knee, 0.055, coat)   # shin
		_cap(root, knee, hip + Vector3(0, 0, dz), 0.07, coat)                      # thigh
		_cap(root, Vector3(STAND.x - 0.05, 0.03, STAND.z + dz * 1.6), Vector3(STAND.x - 0.28, 0.03, STAND.z + dz * 1.6), 0.04, coat)   # foot
	var chest := Vector3(STAND.x + 0.05, SHOULDER_Y, STAND.z)
	_cap(root, hip, chest, 0.17, coat)                         # a long narrow trunk in a coat
	_cap(root, hip + Vector3(0, 0.1, 0), hip + Vector3(-0.08, -0.55, 0), 0.2, coat)   # coat tails
	# arms: down from the shoulders, bent, hands flat on the glass
	# one flat on the fixed pane, one curled over the sill of the open side
	var hands := [Vector3(GLASS_X + 0.03, 1.8, 3.6), Vector3(14.12, 0.97, 4.15)]
	var shoulders := [Vector3(chest.x, SHOULDER_Y - 0.08, STAND.z - 0.24), Vector3(chest.x, SHOULDER_Y - 0.08, STAND.z + 0.24)]
	for i in 2:
		var sh: Vector3 = shoulders[i]
		var hd: Vector3 = hands[i]
		var elbow := sh.lerp(hd, 0.5) + Vector3(0.55, 0.15, (-0.35 if i == 0 else 0.35))
		_cap(root, sh, elbow, 0.045, coat)
		_cap(root, elbow, hd + Vector3(0.12, 0, 0), 0.038, coat)
		_hand(hd, i == 0)
	# the neck: out of the collar, forward over the eaves, then hooked down to the glass
	var pts := [chest + Vector3(0, 0.18, 0), Vector3(15.0, 3.75, 3.95), Vector3(14.62, 3.45, 4.15),
		Vector3(14.42, 2.7, 4.45), Vector3(14.3, 2.0, 4.5), HEAD_AT]
	for i in pts.size() - 1:
		neck.append(_cap(root, pts[i], pts[i + 1], 0.06 - i * 0.004, skin))


## A hand pressed flat on the pane: palm and five long fingers.
func _hand(at: Vector3, upper: bool) -> void:
	var palm := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.02, 0.1, 0.09)
	palm.mesh = b
	palm.material_override = skin
	root.add_child(palm)
	palm.global_position = at
	for k in 5:
		var spread := (k - 2) * 0.32 + (0.0 if upper else PI)
		var dir := Vector3(0, cos(spread), sin(spread))
		var base := at + dir * 0.05
		_cap(root, base, base + dir * (0.24 if k != 0 else 0.15), 0.011, skin)


## Its head is the creature's: a long column of a face (the same picture as
## Creature, assets/textures/creature_face.png), laid on its side through the
## open half of the window.
func _make_head() -> void:
	if head_mesh:
		return
	head_mesh = MeshInstance3D.new()
	var sk := SphereMesh.new()
	sk.radius = Creature.HEAD_R
	sk.height = Creature.HEAD_LEN
	sk.radial_segments = 10
	sk.rings = 8
	head_mesh.mesh = sk
	var flesh := _mat(Color(1, 1, 1), 0.85)
	flesh.albedo_texture = Creature.SKIN_TEX
	flesh.uv1_triplanar = true
	flesh.uv1_scale = Vector3(4, 4, 4)
	head_mesh.material_override = flesh
	head_mesh.position = Creature.HEAD_C
	head_pivot.add_child(head_mesh)
	var mask := MeshInstance3D.new()
	mask.mesh = Creature._face_patch(Creature.HEAD_R, Creature.HEAD_LEN * 0.5, Creature.HEAD_C)
	var mm := _mat(Color(1, 1, 1), 0.85)
	mm.albedo_texture = Creature.FACE_TEX
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mm.alpha_scissor_threshold = 0.4
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mm.emission_enabled = true
	mm.emission_texture = Creature.FACE_TEX
	mm.emission_energy_multiplier = 0.6
	mask.material_override = mm
	head_pivot.add_child(mask)
	# lying on its side, face into the room (-X), the neck end at HEAD_AT
	head_pivot.global_transform = Transform3D(
		Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.FORWARD, PI * 0.5), HEAD_AT)


## The director's window event.
func arm() -> bool:
	if root.visible or armed_t > 0.0:
		return false
	var m := level.get_node_or_null("Markers/WindowFace") as Node3D
	if m and Sight.sees(self, m.global_position, 12.0, 0.5):
		return false   # only while your back is turned
	_make_head()
	armed_t = 18.0
	watched = 0.0
	lift = 0.0
	root.position = Vector3.ZERO
	root.visible = true
	return true


func _process(dt: float) -> void:
	if not root.visible:
		return
	armed_t -= dt
	var m := level.get_node_or_null("Markers/WindowFace") as Node3D
	if m and Sight.sees(self, m.global_position, 12.0, 0.6):
		watched += dt
	# it stares; the head twitches once; then it draws itself up out of sight
	if watched > 0.9 and watched < 1.0:
		head_pivot.rotate_object_local(Vector3.RIGHT, 0.25)
	if watched > 2.2:
		lift += dt * 0.9
		root.position.y = lift * lift * 2.5
	if lift > 1.4 or armed_t <= 0.0 or Game.state != Game.State.PLAY:
		root.visible = false
		armed_t = 0.0
