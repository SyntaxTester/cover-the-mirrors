extends Node
## Photographs of tonight's mourners, hung on the wall between the window and
## the mirror. Each is rendered from the same villager generator as the guest
## at the door, so a double with "wrong_detail" visibly differs from its photo.

const SIZE := Vector2i(48, 60)        # pixels per photograph
const QUAD := Vector2(0.26, 0.325)    # metres
const WALL_X := 13.975                # inside face of the east wall
const Z0 := 4.72
const DZ := 0.43
const ROWS_Y := [1.86, 1.36]
const PER_ROW := 4

var level: Node3D
var holder: Node3D
var frames := {}     # name -> Node3D (photo + frame + label)
var flipped := ""


func _ready() -> void:
	add_to_group("portraits")
	level = get_node("../../Level")
	get_node("../Visitors").plan_ready.connect(_build)


func _build(plan: Dictionary) -> void:
	if holder:
		holder.queue_free()
	frames.clear()
	holder = Node3D.new()
	holder.name = "Portraits"
	level.add_child(holder)
	var lamp := OmniLight3D.new()   # a candle on a shelf so you can see the faces
	lamp.light_color = Color(1.0, 0.7, 0.42)
	lamp.light_energy = 0.55
	lamp.omni_range = 2.0
	lamp.shadow_enabled = false
	holder.add_child(lamp)
	lamp.position = Vector3(WALL_X - 0.45, 2.15, Z0 + DZ * 1.5)
	var raw: Dictionary = get_node("../Visitors").raw
	var looks: Dictionary = raw.get("looks", {})
	var names: Array = plan.get("portraits", [])
	for i in mini(names.size(), PER_ROW * ROWS_Y.size()):
		var n: String = names[i]
		var pos := Vector3(WALL_X, ROWS_Y[i / PER_ROW], Z0 + DZ * (i % PER_ROW))
		var tex := await _photo(str(looks.get(n, {}).get("model", "SEAN")))
		if not is_instance_valid(holder):
			return
		_hang(n, tex, pos)


## Renders one villager's head and shoulders into a small texture.
func _photo(model: String) -> Texture2D:
	var id := PS1Villager.character_from_name(model)
	var parts := PS1Villager.build_guest_parts(id, {"boots": "mud"})
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.31, 0.25)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.56, 0.5)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 160, 0)
	sun.light_energy = 0.9
	vp.add_child(sun)
	var piv: Dictionary = parts["pivots"]
	var mat: Material = parts["material"]
	for pair in [["body", Vector3.ZERO], ["legs", piv["legs"]], ["knee", piv["knee"]], ["head", piv["head"]]]:
		var m: Mesh = parts.get(pair[0])
		if m:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = mat
			mi.position = pair[1]
			vp.add_child(mi)
	var head: Vector3 = piv["head"]
	var cam := Camera3D.new()
	cam.fov = 26.0
	vp.add_child(cam)
	cam.position = head + Vector3(0, 0.14, -0.95)
	cam.look_at(head + Vector3(0, 0.08, 0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():   # headless runs have no renderer
		img = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.36, 0.31, 0.25))
	img.convert(Image.FORMAT_RGBA8)
	# an old photograph: a little faded and warm
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var g := c.get_luminance()
			img.set_pixel(x, y, c.lerp(Color(g * 1.08, g * 0.98, g * 0.82), 0.35))
	return ImageTexture.create_from_image(img)


func _hang(n: String, tex: Texture2D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = n
	holder.add_child(root)
	root.position = pos
	root.rotation_degrees.y = -90.0   # face into the room (-X)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(QUAD.x + 0.04, QUAD.y + 0.04, 0.02)
	frame.mesh = fm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.1, 0.06)
	wood.roughness = 1.0
	frame.material_override = wood
	root.add_child(frame)
	frame.position = Vector3(0, 0, -0.012)
	var photo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = QUAD
	photo.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = tex
	pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pm.roughness = 1.0
	photo.material_override = pm
	root.add_child(photo)
	var label := Label3D.new()
	label.text = n
	label.font_size = 26
	label.pixel_size = 0.0016
	label.modulate = Color(0.86, 0.8, 0.68)
	label.outline_size = 4
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	root.add_child(label)
	label.position = Vector3(0, -QUAD.y * 0.5 - 0.05, 0.005)
	frames[n] = root


## An omen: one photograph turns upside down (the director picks whose).
func flip(n: String) -> bool:
	if not frames.has(n) or flipped != "":
		return false
	flipped = n
	var f: Node3D = frames[n]
	create_tween().tween_property(f, "rotation_degrees:z", 180.0, 0.25)
	return true


func unflip() -> void:
	if flipped == "" or not frames.has(flipped):
		flipped = ""
		return
	var f: Node3D = frames[flipped]
	create_tween().tween_property(f, "rotation_degrees:z", 0.0, 0.25)
	flipped = ""


func frame_pos(n: String) -> Vector3:
	return (frames[n] as Node3D).global_position if frames.has(n) else Vector3.INF
