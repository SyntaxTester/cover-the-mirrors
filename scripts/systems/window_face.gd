extends Node
## The face at the window (Outside/Face). It used to be a blue ball; now it is
## somebody: a drowned woman from the bog road, grey-blue, hair plastered to
## her skull, eyes all white, mouth hanging open, both palms flat on the glass.
##
## It never comes with a sound. It is there when you look, it stares, then
## drags itself down the glass and out of sight.

const MODEL := "MARGARET"
const LOOK := {"expr": "drowned", "skin": Color(0.53, 0.60, 0.63), "sunken_eyes": true,
	"dark_circles": true, "sunken_cheeks": true, "hair": Color(0.04, 0.045, 0.05),
	"hair_style": "long", "hat": "none", "glasses": false, "shawl": false, "dirty": true,
	"top_col": Color(0.16, 0.17, 0.17), "boots": "mud"}

var face: Node3D          # Outside/Face: shown/hidden by the director and omens
var body: VillagerBody
var holder := Node3D.new()   # placement and the slide (the body poses itself)
var head := Node3D.new()
var light: OmniLight3D
var base := Vector3.ZERO
var watched := 0.0
var armed_t := 0.0        # > 0: waiting for you to look
var slide := 0.0
var level: Node3D


func _ready() -> void:
	add_to_group("window_face")
	level = get_node("../../Level")
	face = level.get_node_or_null("Outside/Face") as Node3D
	if face == null:
		return
	for c in face.get_children():
		if c is MeshInstance3D:
			c.queue_free()   # the old sphere head
		elif c is OmniLight3D:
			light = c
	var parts := PS1Villager.build_guest_parts(PS1Villager.character_from_name(MODEL), LOOK)
	body = VillagerBody.new()
	body.calm = false
	face.add_child(holder)
	holder.add_child(body)
	body.build(parts, head)
	# both hands up on the glass either side of the face
	body.arm_pose = [Vector3(2.75, 0.0, -0.35), Vector3(2.75, 0.0, 0.35)]
	# face the house (-X), the face just behind the glass
	holder.rotation.y = PI * 0.5
	holder.scale = Vector3.ONE * 1.2   # a little too big for a person
	body._apply(0.0)
	var f := head.global_transform * Vector3(0, 0.1, -0.09)
	base = holder.position + (face.global_position + Vector3(-0.26, 0.06, 0.0) - f)
	holder.position = base
	if light:
		light.light_color = Color(0.6, 0.72, 0.8)
		light.light_energy = 2.4
		light.omni_range = 1.6
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.position = Vector3(-0.55, -0.25, 0.0)   # from below, on the house side of the glass


## The director's window event: she'll be there next time you look over.
func arm() -> bool:
	if face == null or face.visible or armed_t > 0.0:
		return false
	var m := level.get_node_or_null("Markers/WindowFace") as Node3D
	if m and Sight.sees(self, m.global_position, 12.0, 0.5):
		return false   # only while your back is turned
	armed_t = 14.0
	watched = 0.0
	slide = 0.0
	holder.position = base
	head.rotation = Vector3.ZERO
	face.visible = true
	return true


func _process(dt: float) -> void:
	if face == null or not face.visible or armed_t <= 0.0:
		return
	armed_t -= dt
	var m := level.get_node_or_null("Markers/WindowFace") as Node3D
	var seen := m != null and Sight.sees(self, m.global_position, 12.0, 0.6)
	if seen:
		watched += dt
	# she tilts her head as you look, then slides down the glass
	head.rotation.z = lerpf(head.rotation.z, 0.45 if watched > 0.6 else 0.0, dt * 2.0)
	if watched > 1.4:
		slide += dt * 1.6
		holder.position = base + Vector3(0, -slide * slide, 0)
	if slide > 1.0 or armed_t <= 0.0:
		face.visible = false
		armed_t = 0.0
		holder.position = base
		head.rotation = Vector3.ZERO
