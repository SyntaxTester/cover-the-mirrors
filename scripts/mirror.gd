extends Interactable

@export var glass_size := Vector2(1.4, 1.9)
@export var res := Vector2i(140, 190)
@export var hidden_layers := 2

@onready var cloth: Node3D = $Cloth
@onready var glass: MeshInstance3D = $Glass

var lifted := false
var k := 0.0
var cloth_x := 0.0
var vp: SubViewport
var cam: Camera3D


func _ready() -> void:
	prompt = "Draw curtain"
	hold = true
	add_to_group("mirrors")
	cloth_x = cloth.position.x
	vp = SubViewport.new()
	vp.size = res
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.cull_mask = 0xFFFFF & ~hidden_layers
	vp.add_child(cam)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	m.albedo_color = Color(0.9, 0.92, 0.95)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(-1, 1, 1)
	m.uv1_offset = Vector3(1, 0, 0)
	glass.material_override = m


func interact(_p: Node) -> void:
	lifted = true


func release(_p: Node) -> void:
	lifted = false


func _process(dt: float) -> void:
	k = move_toward(k, 1.0 if lifted else 0.0, dt * 4.0)
	cloth.position.x = cloth_x - k * 0.74
	cloth.scale.x = 1.0 - k * 0.82
	cloth.scale.z = 1.0 + k * 1.5
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if k > 0.0 else SubViewport.UPDATE_DISABLED
	if k > 0.0:
		reflect()


func reflect() -> void:
	var pc := get_viewport().get_camera_3d()
	if not pc:
		return
	var g := glass.global_transform
	var n := g.basis.z.normalized()
	var mx := g.basis.x.normalized()
	var my := g.basis.y.normalized()
	var c := g.origin
	var p := pc.global_position
	var d := (p - c).dot(n)
	if d <= 0.02:
		return
	var r := p - 2.0 * d * n
	cam.global_transform = Transform3D(Basis(-mx, my, -n), r)
	var v := c - r
	cam.set_frustum(glass_size.y, Vector2(-v.dot(mx), v.dot(my)), maxf(d - 0.005, 0.02), 60.0)
