extends Interactable

@export var glass_size := Vector2(1.4, 1.9)
@export var res := Vector2i(140, 190)
@export var hidden_layers := 2
@export var gain := 1.15
@export var max_height_px := 540

@onready var cloth: Node3D = $Cloth
@onready var glass: MeshInstance3D = $Glass

var lifted := false
var slipped := false   # the cloth has slid half off: the glass is looking into the room
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
	_own_environment()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	m.albedo_color = Color(0.97, 0.98, 1.0) * gain
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(-1, 1, 1)
	m.uv1_offset = Vector3(1, 0, 0)
	glass.material_override = m


func _own_environment() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var we := root.find_child("Env", true, false) as WorldEnvironment
	if we == null or we.environment == null:
		return
	var e := we.environment.duplicate() as Environment
	e.volumetric_fog_enabled = false
	e.glow_enabled = false
	e.adjustment_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	cam.environment = e


func _fit_resolution(pc: Camera3D, d: float) -> void:
	var screen_h := float(get_viewport().get_visible_rect().size.y)
	var span := glass_size.y / (2.0 * d * tan(deg_to_rad(pc.fov) * 0.5))
	var h := clampi(int(screen_h * span * 1.2), res.y, max_height_px)
	if absi(h - vp.size.y) > vp.size.y / 6:
		vp.size = Vector2i(int(h * glass_size.x / glass_size.y), h)


## Something pulled the cloth half off. It stays that way until straightened.
func slip() -> void:
	if slipped or lifted:
		return
	slipped = true
	Sounds.play_at(self, cloth.global_position, Sounds.CLOTH, -2.0, "SFX", 0.8, 0.05, 5.0)
	get_tree().call_group("roles", "on_mirror_slipped", self)


func get_prompt() -> String:
	return "Straighten the cloth" if slipped else prompt


func interact(_p: Node) -> void:
	if slipped:
		slipped = false
		Sounds.play_at(self, cloth.global_position, Sounds.CLOTH, -8.0, "SFX", 1.2, 0.08, 2.0)
		return
	if not lifted:
		Sounds.play_at(self, cloth.global_position, Sounds.CLOTH, -6.0, "SFX", 1.0, 0.08, 2.0)
	lifted = true


func release(_p: Node) -> void:
	if lifted:
		Sounds.play_at(self, cloth.global_position, Sounds.CLOTH, -8.0, "SFX", 1.2, 0.08, 2.0)
	lifted = false


func _process(dt: float) -> void:
	var tgt := 1.0 if lifted else (0.4 if slipped else 0.0)
	k = move_toward(k, tgt, dt * (4.0 if lifted or not slipped else 1.2))
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
	_fit_resolution(pc, d)
	var r := p - 2.0 * d * n
	cam.global_transform = Transform3D(Basis(-mx, my, -n), r)
	var v := c - r
	cam.set_frustum(glass_size.y, Vector2(-v.dot(mx), v.dot(my)), maxf(d - 0.005, 0.02), 60.0)
