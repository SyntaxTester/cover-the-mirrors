@tool
class_name PS1Villager
extends Node3D
## ════════════════════════════════════════════════════════════════════════════
##  PS1 VILLAGER BUILDER  —  Godot 4.x   (@tool: renders live in the editor)
##
##  Procedurally builds any of the 20 wake villagers as ONE low-poly,
##  vertex-coloured mesh, in the style of a 1997 PlayStation game:
##
##    • Geometry : axis boxes + 4–8 sided prisms only, flat face normals,
##                 faces drawn as single-quad "decals" (eyes, mouths, buttons).
##    • Colour   : baked into vertex colours, quantised to 15-bit (5 bits per
##                 channel), multiplied by a 16×16 procedural grain texture.
##    • Material : StandardMaterial3D — PER_VERTEX shading, NEAREST filtering,
##                 metallic / specular switched off.
##                 With `vertex_jitter` on, an equivalent ShaderMaterial adds
##                 PS1 vertex snapping (wobble), affine texture warping and
##                 colour-depth reduction.
##
##  USAGE: add a Node3D to a scene, attach this script, pick a villager in
##         the Inspector. Tick "Show Whole Cast" to see all twenty at once.
##         Characters face +Z and stand on Y = 0 (about 1.75 m tall).
## ════════════════════════════════════════════════════════════════════════════

enum Character {
	SULTAN_ESMAGZAM, SEAN, JAMES, MICHAEL, THOMAS,
	WILLIAM, DANIEL, JOSEPH, JOHN, HUGH,
	JEREMIAH, DENIS, TIMOTHY, PETER, MARTIN,
	MARY, BRIDGET, MARGARET, CATHERINE, ELLEN,
}

@export var character: Character = Character.SULTAN_ESMAGZAM:
	set(value):
		character = value
		_queue_rebuild()

## Lay all twenty villagers out in two rows, with floating name tags.
@export var show_whole_cast := false:
	set(value):
		show_whole_cast = value
		_queue_rebuild()

@export_group("PS1 Look")
## Use the vertex-snapping shader. Off = the plain StandardMaterial3D.
@export var vertex_jitter := true:
	set(value):
		vertex_jitter = value
		_queue_rebuild()
## Virtual screen resolution vertices snap to. Lower = more wobble.
@export var snap_resolution := Vector2(320, 240):
	set(value):
		snap_resolution = value
		_queue_rebuild()
## 0 = perspective-correct textures, 1 = full PS1 affine texture warping.
@export_range(0.0, 1.0) var affine_warp := 0.6:
	set(value):
		affine_warp = value
		_queue_rebuild()
## Bits per colour channel (the PS1 framebuffer used 5).
@export_range(3, 8) var color_depth_bits := 5:
	set(value):
		color_depth_bits = value
		_queue_rebuild()
## Darken vertices toward the feet: cheap baked "ambient occlusion".
@export var baked_vertex_shade := true:
	set(value):
		baked_vertex_shade = value
		_queue_rebuild()

@export_group("Stats")
@export var triangle_count := 0
@export var vertex_count := 0

# ─── constants ───────────────────────────────────────────────────────────────
const DEG := PI / 180.0
const EPS := 0.0025                      # decal layer spacing
const SIDES: Array[float] = [-1.0, 1.0]  # +1 = character's left (+X)
const CAP_NONE := 0
const CAP_BOTTOM := 1
const CAP_TOP := 2
const CAP_BOTH := 3

# [normal, u, v] for the six faces of a box
const _BOX_FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
]

# Arm poses: [L upper, L fore, R upper, R fore]
#   upper = (swing forward°, -, outward°)   fore = (bend forward°, inward°, -)
const POSES := {
	"rest": [Vector3(2, 0, 7), Vector3(-10, 0, 0), Vector3(2, 0, 7), Vector3(-10, 0, 0)],
	"nervous": [Vector3(6, 0, 2), Vector3(-40, 28, 0), Vector3(6, 0, 2), Vector3(-40, 28, 0)],
	"clasp": [Vector3(-12, 0, -6), Vector3(-75, 35, 0), Vector3(-12, 0, -6), Vector3(-75, 35, 0)],
	"ale": [Vector3(2, 0, 7), Vector3(-10, 0, 0), Vector3(-30, 0, 10), Vector3(-100, 0, 0)],
	"stick": [Vector3(2, 0, 7), Vector3(-10, 0, 0), Vector3(-18, 0, 10), Vector3(-45, 0, 0)],
	"bag": [Vector3(0, 0, 10), Vector3(-8, 0, 0), Vector3(2, 0, 7), Vector3(-10, 0, 0)],
	"fiddle": [Vector3(-55, 0, 25), Vector3(-70, 0, 0), Vector3(-40, 0, -5), Vector3(-80, 30, 0)],
}

# Palette — muted, earthy, slightly desaturated like a PS1 CLUT
const SKIN_FAIR := Color(0.86, 0.68, 0.56)
const SKIN_RUDDY := Color(0.88, 0.62, 0.50)
const SKIN_PALE := Color(0.87, 0.81, 0.75)
const SKIN_TAN := Color(0.76, 0.57, 0.41)
const SKIN_OLD := Color(0.82, 0.66, 0.57)
const SKIN_WEATHER := Color(0.77, 0.57, 0.44)

const HAIR_BLACK := Color(0.10, 0.09, 0.09)
const HAIR_DARK := Color(0.22, 0.15, 0.10)
const HAIR_BROWN := Color(0.38, 0.25, 0.15)
const HAIR_AUBURN := Color(0.46, 0.24, 0.12)
const HAIR_GINGER := Color(0.74, 0.38, 0.15)
const HAIR_RED := Color(0.64, 0.24, 0.11)
const HAIR_GREY := Color(0.60, 0.60, 0.58)
const HAIR_WHITE := Color(0.78, 0.77, 0.74)

const CLOTH_BLACK := Color(0.09, 0.09, 0.10)
const LINEN := Color(0.84, 0.80, 0.70)
const C_EYE_WHITE := Color(0.92, 0.90, 0.84)
const C_PUPIL := Color(0.10, 0.08, 0.07)
const C_MOUTH := Color(0.28, 0.10, 0.09)
const C_TEETH := Color(0.90, 0.87, 0.76)
const C_FRECKLE := Color(0.64, 0.38, 0.24)
const C_ROSY := Color(0.86, 0.38, 0.36)
const C_BRUISE := Color(0.40, 0.30, 0.42)
const C_RED_NOSE := Color(0.80, 0.30, 0.26)
const C_BRASS := Color(0.72, 0.58, 0.28)
const C_GOLD := Color(0.88, 0.72, 0.30)
const C_BONE := Color(0.82, 0.78, 0.66)
const C_BELT := Color(0.20, 0.13, 0.08)
const C_WOOD := Color(0.45, 0.30, 0.17)
const C_LEATHER := Color(0.42, 0.26, 0.14)
const C_PATCH := Color(0.45, 0.40, 0.30)
const C_MUD := Color(0.26, 0.21, 0.15)
const C_APRON := Color(0.88, 0.85, 0.76)
const C_METAL := Color(0.22, 0.19, 0.15)
const C_SILVER := Color(0.75, 0.72, 0.64)

const PS1_SHADER := """
shader_type spatial;
// Per-vertex (Gouraud) lighting, no specular — like the PS1 GTE.
render_mode vertex_lighting, specular_disabled, diffuse_lambert, cull_back;

uniform sampler2D grain_tex : filter_nearest, repeat_enable, hint_default_white;
uniform vec2 snap_resolution = vec2(320.0, 240.0);
uniform float affine_amount : hint_range(0.0, 1.0) = 0.6;
uniform float color_levels = 31.0;

varying vec3 affine_uv;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	// PS1 vertex snapping: the GTE had no sub-pixel precision, so every vertex
	// lands on a whole pixel of a low-res virtual screen -> the classic wobble.
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0001) {
		vec2 half_res = snap_resolution * 0.5;
		vec2 ndc = clip.xy / clip.w;
		ndc = round(ndc * half_res) / half_res;
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
	// Affine texture mapping: interpolate UV*w and w, divide per fragment.
	affine_uv = vec3(UV * clip.w, clip.w);
}

void fragment() {
	vec2 uv = mix(UV, affine_uv.xy / affine_uv.z, affine_amount);
	vec3 c = COLOR.rgb * texture(grain_tex, uv).rgb;   // sRGB vertex colour
	c = floor(c * color_levels + 0.5) / color_levels;   // 15-bit colour
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
"""

# ─── build state ─────────────────────────────────────────────────────────────
var _st: SurfaceTool
var _xf := Transform3D.IDENTITY      # current local transform (stack top)
var _base := Transform3D.IDENTITY    # per-character offset (cast lineup)
var _stack: Array[Transform3D] = []
var _rng := RandomNumberGenerator.new()
var _tris := 0
var _dirty := false
var _chin := Vector3.ZERO


func _ready() -> void:
	_queue_rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name == "triangle_count" or property.name == "vertex_count":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _queue_rebuild() -> void:
	if _dirty:
		return
	_dirty = true
	_rebuild.call_deferred()


# ═════════════════════════════════════════════════════════════════════════════
#  REBUILD
# ═════════════════════════════════════════════════════════════════════════════
func _rebuild() -> void:
	_dirty = false
	var mi := _internal_child("_PS1Mesh", func(): return MeshInstance3D.new()) as MeshInstance3D
	var tags := _internal_child("_PS1NameTags", func(): return Node3D.new()) as Node3D
	for c in tags.get_children():
		tags.remove_child(c)
		c.queue_free()

	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tris = 0

	if show_whole_cast:
		for i in Character.size():
			var col := i % 10
			var row := floori(i / 10.0)
			_base = Transform3D(Basis(), Vector3((col - 4.5) * 1.0, 0.0, -row * 1.8))
			_build_character(i)
			_add_name_tag(tags, i)
	else:
		_base = Transform3D.IDENTITY
		_build_character(character)

	_st.index()
	var mesh := _st.commit()
	mi.mesh = mesh
	mi.material_override = _make_material()
	vertex_count = mesh.surface_get_array_len(0) if mesh.get_surface_count() > 0 else 0
	triangle_count = _tris
	notify_property_list_changed()


func _internal_child(node_name: String, make: Callable) -> Node:
	for c in get_children(true):
		if c.name == node_name:
			return c
	var n: Node = make.call()
	n.name = node_name
	add_child(n, false, Node.INTERNAL_MODE_BACK)   # unowned -> never saved
	return n


func _add_name_tag(parent: Node3D, id: int) -> void:
	var l := Label3D.new()
	l.text = String(Character.keys()[id]).replace("_", " ")
	l.font_size = 28
	l.pixel_size = 0.0035
	l.outline_size = 6
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.position = _base.origin + Vector3(0, 2.05, 0)
	parent.add_child(l)


# ═════════════════════════════════════════════════════════════════════════════
#  MATERIAL
# ═════════════════════════════════════════════════════════════════════════════
func _make_material() -> Material:
	var grain := _grain_texture()

	# The baseline PS1 material.
	var std := StandardMaterial3D.new()
	std.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	std.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	std.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	std.metallic = 0.0
	std.metallic_specular = 0.0
	std.roughness = 1.0
	std.vertex_color_use_as_albedo = true
	std.vertex_color_is_srgb = true
	std.albedo_texture = grain
	if not vertex_jitter:
		return std

	# Same look, plus vertex snapping / affine warping / colour depth.
	var shader := Shader.new()
	shader.code = PS1_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.set_shader_parameter("grain_tex", grain)
	sm.set_shader_parameter("snap_resolution", snap_resolution)
	sm.set_shader_parameter("affine_amount", affine_warp)
	sm.set_shader_parameter("color_levels", float((1 << color_depth_bits) - 1))
	return sm


func _grain_texture() -> ImageTexture:
	# 16×16 greyscale cloth/skin grain — multiplied with the vertex colour.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1997
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var v := 0.86 + 0.14 * rng.randf()
			if rng.randf() < 0.06:
				v -= 0.12
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


# ═════════════════════════════════════════════════════════════════════════════
#  CHARACTER PROFILES
# ═════════════════════════════════════════════════════════════════════════════
func _profile(id: int) -> Dictionary:
	var p := {
		"female": false, "height": 1.0, "girth": 1.0, "belly": 0.0, "hunch": 0.0,
		"skin": SKIN_FAIR, "head_w": 0.11, "jaw": 0.86,
		"hair": HAIR_BROWN, "hair_style": "short",
		"facial": "none", "facial_col": HAIR_BROWN,
		"top": "shirt", "top_col": LINEN, "shirt_col": LINEN,
		"pants_col": Color(0.25, 0.21, 0.17), "shoe_col": Color(0.14, 0.10, 0.08),
		"tall_boots": false, "hat": "none", "hat_col": Color(0.25, 0.22, 0.18),
		"shawl": false, "shawl_col": Color(0.42, 0.37, 0.30), "apron": false,
		"glasses": false, "prop": "none", "pose": "rest", "expr": "calm",
		"freckles": false, "red_nose": false, "rosy": false, "dark_circles": false,
		"sunken_cheeks": false, "sunken_eyes": false, "wrinkles": false,
		"big_hands": false, "oversized": false, "elegant": false, "rumpled": false,
		"cross": false, "dirty": false, "patched": false,
	}
	var female_base := {"female": true, "pants_col": Color(0.15, 0.13, 0.12),
		"shoe_col": Color(0.12, 0.09, 0.07), "top": "dress", "head_w": 0.104}
	var o: Dictionary = {}
	match id:
		Character.SULTAN_ESMAGZAM:   # goofy young ale-lover, round glasses
			o = {"height": 0.98, "girth": 0.95, "skin": SKIN_TAN, "head_w": 0.116, "jaw": 0.92,
				"hair": HAIR_BLACK, "hair_style": "messy", "top": "jacket",
				"top_col": Color(0.30, 0.34, 0.42), "pants_col": Color(0.30, 0.25, 0.19),
				"glasses": true, "rosy": true, "prop": "ale", "pose": "ale", "expr": "clueless"}
		Character.SEAN:              # quiet, suspicious farmer
			o = {"height": 1.05, "girth": 0.88, "skin": Color(0.80, 0.69, 0.60), "head_w": 0.10,
				"jaw": 0.76, "hair": HAIR_BLACK, "hair_style": "long", "facial": "stubble",
				"facial_col": HAIR_BLACK, "top": "coat", "top_col": CLOTH_BLACK,
				"shirt_col": Color(0.45, 0.42, 0.38), "sunken_cheeks": true, "expr": "suspicious"}
		Character.JAMES:             # cheerful singing neighbour
			o = {"girth": 1.15, "belly": 0.06, "skin": SKIN_RUDDY, "head_w": 0.125, "jaw": 0.98,
				"hair": HAIR_RED, "facial": "moustache_big", "facial_col": HAIR_RED,
				"top": "waistcoat", "top_col": Color(0.40, 0.26, 0.15), "rosy": true,
				"expr": "cheerful"}
		Character.MICHAEL:           # stern hunter
			o = {"height": 0.97, "girth": 1.28, "belly": 0.03, "skin": SKIN_WEATHER,
				"head_w": 0.12, "jaw": 0.95, "hair": HAIR_DARK, "facial": "beard",
				"facial_col": HAIR_DARK, "top": "cloak", "top_col": Color(0.17, 0.19, 0.15),
				"shirt_col": Color(0.32, 0.27, 0.20), "pants_col": Color(0.20, 0.18, 0.14),
				"tall_boots": true, "shoe_col": Color(0.25, 0.17, 0.10), "expr": "stern"}
		Character.THOMAS:            # old teller of legends
			o = {"height": 0.96, "girth": 0.95, "hunch": 0.22, "skin": SKIN_OLD,
				"hair": HAIR_GREY, "wrinkles": true, "top": "coat",
				"top_col": Color(0.33, 0.28, 0.21), "shirt_col": Color(0.70, 0.66, 0.56),
				"hat": "old_hat", "hat_col": Color(0.26, 0.22, 0.17), "prop": "stick",
				"pose": "stick", "expr": "storyteller"}
		Character.WILLIAM:           # wealthy, arrogant farmer
			o = {"height": 1.06, "girth": 1.02, "jaw": 0.88, "hair": HAIR_DARK,
				"hair_style": "slick", "top": "coat", "top_col": Color(0.16, 0.18, 0.32),
				"shirt_col": Color(0.92, 0.90, 0.84), "elegant": true, "tall_boots": true,
				"shoe_col": Color(0.06, 0.05, 0.05), "pants_col": Color(0.62, 0.56, 0.44),
				"expr": "arrogant"}
		Character.DANIEL:            # young, nervous
			o = {"height": 0.97, "girth": 0.82, "skin": Color(0.90, 0.74, 0.64), "head_w": 0.105,
				"jaw": 0.84, "hair": HAIR_BROWN, "hair_style": "messy", "freckles": true,
				"top": "jacket", "oversized": true, "top_col": Color(0.36, 0.34, 0.22),
				"expr": "nervous", "pose": "nervous"}
		Character.JOSEPH:            # religious, superstitious
			o = {"height": 1.02, "girth": 0.9, "skin": SKIN_PALE, "head_w": 0.105, "jaw": 0.80,
				"hair": HAIR_DARK, "dark_circles": true, "top": "coat", "top_col": CLOTH_BLACK,
				"shirt_col": Color(0.82, 0.80, 0.76), "cross": true, "expr": "fearful",
				"pose": "clasp"}
		Character.JOHN:              # quiet carpenter
			o = {"girth": 1.12, "skin": SKIN_WEATHER, "hair": HAIR_GREY, "facial": "beard",
				"facial_col": HAIR_GREY, "top": "shirt", "shirt_col": Color(0.62, 0.55, 0.42),
				"pants_col": Color(0.30, 0.25, 0.18), "big_hands": true, "patched": true,
				"expr": "calm"}
		Character.HUGH:              # grumpy hunched old man
			o = {"height": 0.95, "girth": 0.95, "hunch": 0.55, "skin": SKIN_OLD, "jaw": 0.82,
				"hair": HAIR_WHITE, "hair_style": "thinning", "facial": "stubble",
				"facial_col": HAIR_WHITE, "wrinkles": true, "top": "coat",
				"top_col": Color(0.27, 0.25, 0.21), "shirt_col": Color(0.55, 0.52, 0.45),
				"patched": true, "prop": "cane", "pose": "stick", "expr": "grumpy"}
		Character.JEREMIAH:          # believer in old folk legends
			o = {"girth": 0.92, "skin": SKIN_WEATHER, "jaw": 0.84,
				"hair": Color(0.32, 0.28, 0.22), "hair_style": "wild", "facial": "long_beard",
				"facial_col": Color(0.36, 0.31, 0.24), "top": "cloak",
				"top_col": Color(0.30, 0.26, 0.19), "shirt_col": Color(0.40, 0.36, 0.28),
				"dirty": true, "expr": "wild"}
		Character.DENIS:             # loud fun-loving drunk
			o = {"girth": 1.18, "belly": 0.09, "skin": SKIN_RUDDY, "head_w": 0.12, "jaw": 0.95,
				"hair": HAIR_GINGER, "hair_style": "messy", "red_nose": true, "rosy": true,
				"top": "waistcoat", "top_col": Color(0.30, 0.30, 0.34), "rumpled": true,
				"prop": "ale", "pose": "ale", "expr": "laugh"}
		Character.TIMOTHY:           # shy farmhand
			o = {"height": 0.98, "girth": 0.84, "head_w": 0.10, "jaw": 0.78, "hair": HAIR_BROWN,
				"facial": "small_moustache", "facial_col": HAIR_BROWN, "hat": "cap",
				"hat_col": Color(0.32, 0.30, 0.26), "shirt_col": Color(0.48, 0.52, 0.56),
				"pants_col": Color(0.32, 0.27, 0.20), "expr": "shy", "pose": "nervous"}
		Character.PETER:             # merchant who knows everyone
			o = {"jaw": 0.84, "hair": HAIR_DARK, "facial": "pointed_beard",
				"facial_col": HAIR_DARK, "top": "coat", "top_col": Color(0.20, 0.15, 0.11),
				"shirt_col": Color(0.80, 0.76, 0.66), "prop": "bag", "pose": "bag",
				"expr": "curious"}
		Character.MARTIN:            # fiddler
			o = {"girth": 0.98, "hair": HAIR_AUBURN, "hair_style": "curly",
				"facial": "moustache", "facial_col": HAIR_GINGER, "top": "waistcoat",
				"top_col": Color(0.20, 0.36, 0.20), "prop": "fiddle", "pose": "fiddle",
				"expr": "singing"}
		Character.MARY:              # caring helper at the wake
			o = female_base.merged({"height": 0.93, "girth": 1.06, "head_w": 0.106,
				"hair": HAIR_GREY, "hair_style": "bun", "hat": "bonnet",
				"hat_col": Color(0.88, 0.85, 0.76), "top_col": Color(0.16, 0.17, 0.24),
				"shirt_col": LINEN, "apron": true, "expr": "kind"}, true)
		Character.BRIDGET:           # strict keeper of funeral traditions
			o = female_base.merged({"height": 0.90, "hunch": 0.15, "skin": SKIN_OLD,
				"jaw": 0.82, "hair": HAIR_WHITE, "hat": "headscarf",
				"hat_col": Color(0.07, 0.07, 0.08), "top_col": Color(0.14, 0.12, 0.11),
				"shirt_col": Color(0.14, 0.12, 0.11), "shawl": true,
				"shawl_col": Color(0.43, 0.38, 0.30), "wrinkles": true, "expr": "strict",
				"pose": "clasp"}, true)
		Character.MARGARET:          # withdrawn widow
			o = female_base.merged({"height": 0.95, "girth": 0.88, "skin": SKIN_PALE,
				"head_w": 0.102, "jaw": 0.78, "hair": Color(0.17, 0.12, 0.09),
				"hair_style": "bun", "top_col": CLOTH_BLACK, "shirt_col": CLOTH_BLACK,
				"sunken_eyes": true, "expr": "sad", "pose": "clasp"}, true)
		Character.CATHERINE:         # curious eavesdropper
			o = female_base.merged({"height": 0.92, "girth": 0.9,
				"skin": Color(0.90, 0.74, 0.63), "jaw": 0.84, "hair": HAIR_BROWN,
				"hair_style": "long", "freckles": true, "top_col": Color(0.42, 0.29, 0.18),
				"shirt_col": Color(0.42, 0.29, 0.18), "expr": "eavesdrop"}, true)
		Character.ELLEN:             # quiet window-starer
			o = female_base.merged({"height": 0.94, "girth": 0.88, "skin": SKIN_PALE,
				"head_w": 0.103, "jaw": 0.80, "hair": HAIR_BLACK, "hair_style": "long",
				"top_col": Color(0.42, 0.42, 0.43), "shirt_col": Color(0.62, 0.62, 0.60),
				"expr": "distant"}, true)
	p.merge(o, true)
	return p


func _expr(expr_name: String) -> Dictionary:
	# brow = inner-end angle (+ angry, - worried), raise/asym = brow height,
	# eye_h = eye opening, look = pupil direction, mouth = mouth shape.
	var e := {"brow": 0.0, "raise": 0.0, "asym": 0.0, "eye_w": 1.0, "eye_h": 0.022,
		"pupil": 0.017, "look": Vector2.ZERO, "goofy": false, "mouth": "line"}
	var o: Dictionary = {}
	match expr_name:
		"clueless": o = {"brow": -8.0, "raise": 0.012, "eye_w": 1.2, "eye_h": 0.036,
			"pupil": 0.011, "goofy": true, "mouth": "open"}
		"suspicious": o = {"brow": 14.0, "raise": -0.004, "eye_h": 0.013, "pupil": 0.013,
			"look": Vector2(0.7, 0.0)}
		"cheerful": o = {"brow": -5.0, "raise": 0.008, "eye_h": 0.02, "mouth": "singing"}
		"stern": o = {"brow": 16.0, "raise": -0.005, "eye_h": 0.017}
		"storyteller": o = {"brow": -4.0, "raise": 0.006, "asym": 0.008, "eye_h": 0.02,
			"look": Vector2(0.3, 0.2), "mouth": "smile"}
		"arrogant": o = {"brow": 6.0, "asym": 0.012, "eye_h": 0.014,
			"look": Vector2(0.0, -0.3), "mouth": "smirk"}
		"nervous": o = {"brow": -16.0, "raise": 0.01, "eye_h": 0.03, "pupil": 0.012,
			"look": Vector2(-0.6, 0.1), "mouth": "wavy"}
		"fearful": o = {"brow": -13.0, "raise": 0.006, "eye_h": 0.026, "pupil": 0.012,
			"look": Vector2(0.5, 0.3), "mouth": "frown"}
		"calm": o = {"eye_h": 0.019}
		"grumpy": o = {"brow": 20.0, "raise": -0.008, "eye_h": 0.013, "mouth": "frown"}
		"wild": o = {"brow": -9.0, "raise": 0.014, "eye_w": 1.15, "eye_h": 0.036,
			"pupil": 0.011, "mouth": "open_small"}
		"laugh": o = {"brow": -7.0, "raise": 0.008, "eye_h": 0.009, "mouth": "grin"}
		"shy": o = {"brow": -9.0, "eye_h": 0.019, "look": Vector2(-0.3, -0.9), "mouth": "small"}
		"curious": o = {"brow": -3.0, "asym": 0.014, "eye_h": 0.025,
			"look": Vector2(0.6, 0.1), "mouth": "smirk"}
		"singing": o = {"brow": -6.0, "raise": 0.01, "eye_h": 0.012, "mouth": "singing"}
		"kind": o = {"brow": -6.0, "raise": 0.004, "eye_h": 0.019, "mouth": "smile"}
		"strict": o = {"brow": 18.0, "raise": -0.004, "eye_h": 0.016, "mouth": "frown"}
		"sad": o = {"brow": -14.0, "eye_h": 0.016, "look": Vector2(0.0, -0.9), "mouth": "frown"}
		"eavesdrop": o = {"brow": -2.0, "asym": 0.012, "eye_h": 0.024,
			"look": Vector2(1.0, 0.1), "mouth": "small"}
		"distant": o = {"brow": -4.0, "eye_h": 0.018, "look": Vector2(-0.9, 0.3)}
	e.merge(o, true)
	return e


# ═════════════════════════════════════════════════════════════════════════════
#  BODY ASSEMBLY
# ═════════════════════════════════════════════════════════════════════════════
func _build_character(id: int) -> void:
	var p := _profile(id)
	_rng.seed = hash(String(Character.keys()[id]))
	_stack.clear()
	_xf = Transform3D(Basis.from_scale(Vector3(1.0, float(p.height), 1.0)), Vector3.ZERO)

	_build_lower_body(p)

	var hunch_deg: float = float(p.hunch) * 45.0
	_push(_rot_about(Vector3(0, 0.95, -0.04), Vector3(hunch_deg, 0, 0)))   # bend at waist
	_build_torso(p)
	var hands := _build_arms(p)
	_push(_rot_about(Vector3(0, 1.47, 0), Vector3(-hunch_deg * 0.8, 0, 0)))  # look up again
	_build_head(p)
	_pop()
	_pop()

	_build_props(p, hands)


func _chest_w(p: Dictionary) -> float:
	return (0.32 if p.female else 0.38) * float(p.girth)


func _build_lower_body(p: Dictionary) -> void:
	var g: float = p.girth
	var belly: float = p.belly
	var pants: Color = p.pants_col
	var shoe: Color = p.shoe_col
	var top: String = p.top
	var top_col: Color = p.top_col

	if p.female:
		for s: float in SIDES:
			_box(Vector3(s * 0.07, 0.04, 0.07), Vector3(0.09, 0.08, 0.19), shoe)
			_box(Vector3(s * 0.07, 0.11, 0.0), Vector3(0.07, 0.08, 0.07), pants)
		# two-tier, eight-sided skirt
		var r := 0.17 * g
		_prism(Vector3(0, 0.76, 0), r * 1.3, r, 0.42, 8, top_col, CAP_NONE)
		_prism(Vector3(0, 0.325, 0), r * 1.78, r * 1.3, 0.45, 8, top_col, CAP_BOTTOM)
		if p.apron:
			var y := 0.73
			var r_at := lerpf(r * 1.3, r, (y - 0.55) / 0.42)
			var tilt := rad_to_deg(atan((r * 0.3 * 0.924) / 0.42))
			_box(Vector3(0, y, r_at * 0.924 + 0.012), Vector3(0.25 * g, 0.44, 0.012), C_APRON,
				Vector3(-tilt, 0, 0))
		return

	var lx := 0.085 + 0.025 * (g - 1.0)
	var tw := 0.14 * lerpf(1.0, g, 0.6)
	for s: float in SIDES:
		var x := s * lx
		_box(Vector3(x, 0.67, 0.0), Vector3(tw, 0.40, 0.15), pants)                 # thigh
		if p.tall_boots:
			_box(Vector3(x, 0.28, 0.0), Vector3(tw * 0.92, 0.42, 0.145), shoe)      # boot shaft
			_box(Vector3(x, 0.475, 0.0), Vector3(tw * 1.05, 0.06, 0.165), shoe.lightened(0.18))
		else:
			_box(Vector3(x, 0.285, 0.0), Vector3(tw * 0.85, 0.39, 0.13), pants.darkened(0.08))
		_box(Vector3(x, 0.045, 0.035), Vector3(tw * 0.9, 0.09, 0.25), shoe)         # shoe
	_box(Vector3(0, 0.90, belly * 0.3), Vector3(0.34 * g, 0.14, 0.22 + belly * 0.6), pants)

	if top == "coat":
		# open-fronted frock-coat skirt: flared 4-sided prism, front face removed
		var sx := 0.34 * g * 0.5 + 0.03
		var sz := (0.22 + belly) * 0.5 + 0.025
		var t := Transform3D(Basis.from_scale(Vector3(sx, 1.0, sz)), Vector3(0, 0.70, belly * 0.5))
		_prism_t(t, 1.414 * 1.18, 1.414, 0.52, 4, top_col, CAP_NONE, 0.9, true,
			top_col.darkened(0.45))


func _build_torso(p: Dictionary) -> void:
	var female: bool = p.female
	var belly: float = p.belly
	var cw := _chest_w(p)
	var cd := 0.22 + belly
	var top: String = p.top
	var top_col: Color = p.top_col
	var shirt_col: Color = p.shirt_col
	var skin: Color = p.skin
	var over := 0.015 if p.oversized else 0.0
	var body_col := shirt_col if (top == "shirt" or top == "cloak") else top_col
	var zc := 0.115 + over + EPS               # chest front
	var zl := 0.11 + belly + over + EPS        # belly front

	# lower torso / belly
	var y0 := 0.86 if top == "jacket" else 0.93
	var lw := cw * (0.84 if female else 0.96) + over * 3.0
	var low_h := 1.20 - y0
	var low_rot := Vector3(0, 0, 4) if p.rumpled else Vector3.ZERO
	_box(Vector3(0, y0 + low_h * 0.5, belly * 0.5), Vector3(lw, low_h, cd + over * 2.0), body_col, low_rot)
	# chest
	_box(Vector3(0, 1.31, 0), Vector3(cw + over * 3.0, 0.25, 0.23 + over * 2.0), body_col)
	# neck
	_prism(Vector3(0, 1.47, 0), 0.056, 0.05, 0.09, 5, skin, CAP_NONE)

	match top:
		"shirt":
			_box(Vector3(0, 1.445, 0), Vector3(0.17, 0.035, 0.17), shirt_col.lightened(0.06))
			_decal(Vector3(0, 1.31, zc), 0.012, 0.22, shirt_col.darkened(0.18))
			for i in 3:
				_decal(Vector3(0, 1.38 - i * 0.07, zc + EPS), 0.012, 0.012, C_BONE)
			_box(Vector3(0, 0.955, belly * 0.5), Vector3(lw + 0.012, 0.035, cd + 0.012), C_BELT)
			_decal(Vector3(0, 0.955, zl + 0.006), 0.03, 0.026, C_BRASS)
		"waistcoat":
			_box(Vector3(0, 1.445, 0), Vector3(0.17, 0.035, 0.17), shirt_col)
			_decal(Vector3(0, 1.355, zc), 0.075, 0.16, shirt_col)                    # shirt V
			_decal(Vector3(0, 1.07, zl), 0.008, 0.26, top_col.darkened(0.3))         # opening
			for i in 4:
				var bx := 0.014 + (0.012 if p.rumpled and i == 2 else 0.0)          # odd button
				_decal(Vector3(bx, 1.0 + i * 0.06, zl + EPS), 0.013, 0.013, C_BRASS)
			for s: float in SIDES:
				_decal(Vector3(s * lw * 0.28, 1.02, zl), 0.06, 0.008, top_col.darkened(0.3))
			if p.rumpled:   # shirt tail hanging out
				_box(Vector3(cw * 0.3, 0.90, 0.07 + belly), Vector3(0.09, 0.09, 0.03), shirt_col,
					Vector3(0, 0, -10))
		"coat", "jacket":
			var is_coat := top == "coat"
			var lapel := top_col.lightened(0.18) if p.elegant else top_col.darkened(0.25)
			_decal(Vector3(0, 1.32, zc), 0.08 if is_coat else 0.07, 0.23, shirt_col)
			for s: float in SIDES:
				_decal(Vector3(s * 0.052, 1.33, zc + EPS), 0.035, 0.2, lapel, -s * 14.0)
			if is_coat:
				_box(Vector3(0, 1.455, -0.035), Vector3(cw * 0.55, 0.07, 0.12), top_col)  # collar
				_decal(Vector3(0, 1.07, zl), 0.008, 0.26, top_col.darkened(0.35))
				var btn := C_GOLD if p.elegant else top_col.darkened(0.5).lightened(0.1)
				for i in 3:
					_decal(Vector3(0.025, 1.0 + i * 0.075, zl + EPS), 0.016, 0.016, btn)
				if p.elegant:   # cravat + watch chain
					_box(Vector3(0, 1.415, 0.118), Vector3(0.055, 0.06, 0.02), Color(0.95, 0.93, 0.88))
					_decal(Vector3(0.05, 1.06, zl + EPS), 0.07, 0.006, C_GOLD, -15.0)
			else:
				_box(Vector3(0, 1.45, -0.02), Vector3(cw * 0.6, 0.05, 0.16), top_col.darkened(0.1))
				_decal(Vector3(0, 1.03, zl), 0.07, 0.33, shirt_col)                  # open front
				for s: float in SIDES:
					_decal(Vector3(s * lw * 0.3, 0.97, zl + EPS), 0.07, 0.05, top_col.darkened(0.15))
		"cloak":
			_box(Vector3(0, 0.955, belly * 0.5), Vector3(lw + 0.012, 0.035, cd + 0.012), C_BELT)
			var rx := cw * 0.5 + 0.12
			var rz := 0.2 + belly * 0.5
			# back half of a flared hexagonal tube, double-sided with dark lining
			var cloak_t := Transform3D(Basis.from_scale(Vector3(rx, 1.0, rz)), Vector3(0, 0.88, -0.01))
			_prism_t(cloak_t, 1.25, 1.0, 1.10, 6, top_col, CAP_NONE, 0.05, true, top_col.darkened(0.4))
			var mantle_t := Transform3D(Basis.from_scale(Vector3(rx * 0.95, 1.0, rz * 0.95)),
				Vector3(0, 1.42, -0.005))
			_prism_t(mantle_t, 1.08, 0.58, 0.13, 6, top_col.lightened(0.04), CAP_TOP)
			_box(Vector3(0, 1.48, -0.13), Vector3(0.22, 0.09, 0.08), top_col.darkened(0.1))  # hood
			_box(Vector3(0, 1.44, 0.125), Vector3(0.032, 0.032, 0.02), C_BRASS)              # clasp
			if p.dirty:
				for i in 7:
					var y := _rng.randf_range(0.4, 1.25)
					var k := clampf((y - 0.33) / 1.10, 0.0, 1.0)
					var zb := -0.01 - rz * lerpf(1.25, 1.0, k) * 0.866 - 0.006
					var x := _rng.randf_range(-rx * 0.35, rx * 0.35)
					_box(Vector3(x, y, zb), Vector3(_rng.randf_range(0.05, 0.1),
						_rng.randf_range(0.04, 0.08), 0.014), C_MUD.lerp(top_col, _rng.randf() * 0.4))
		"dress":
			_decal(Vector3(0, 1.30, zc), 0.008, 0.2, top_col.darkened(0.3))
			for i in 4:
				_decal(Vector3(0, 1.38 - i * 0.05, zc + EPS), 0.01, 0.01, top_col.darkened(0.45))
			if shirt_col != top_col:
				for s: float in SIDES:
					_decal(Vector3(s * 0.03, 1.415, zc + EPS * 2.0), 0.05, 0.03, shirt_col, -s * 12.0)
			_box(Vector3(0, 0.95, 0), Vector3(lw + 0.01, 0.03, 0.21), top_col.darkened(0.15))
			if p.apron:
				_decal(Vector3(0, 1.27, zc + EPS * 2.0), 0.15, 0.14, C_APRON)
				for s: float in SIDES:
					_decal(Vector3(s * 0.06, 1.39, zc + EPS * 2.0), 0.02, 0.09, C_APRON)
				_box(Vector3(0, 0.96, 0), Vector3(lw + 0.015, 0.025, 0.215), C_APRON)

	if p.shawl:
		var sc: Color = p.shawl_col
		_box(Vector3(0, 1.425, -0.005), Vector3(cw + 0.10, 0.06, 0.29), sc)
		for s: float in SIDES:   # crossed front drapes
			_box(Vector3(s * 0.075, 1.27, 0.128), Vector3(0.11, 0.30, 0.025), sc, Vector3(0, 0, -s * 18.0))
		var tri_t := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.15)), Vector3(0, 1.17, -0.13))
		_prism_t(tri_t, 0.0, (cw + 0.08) * 0.5 / 0.707, 0.48, 4, sc, CAP_TOP)    # back point
		_box(Vector3(0, 1.14, 0.135), Vector3(0.05, 0.04, 0.03), sc.darkened(0.15))

	if p.cross:
		for s: float in SIDES:
			_decal(Vector3(s * 0.02, 1.38, zc + EPS), 0.004, 0.11, C_PUPIL, -s * 22.0)
		_decal(Vector3(0, 1.30, zc + EPS * 2.0), 0.012, 0.055, C_SILVER)
		_decal(Vector3(0, 1.315, zc + EPS * 2.0), 0.036, 0.012, C_SILVER)

	if p.prop == "bag":   # strap over right shoulder down to the left hip
		var a := Vector3(-cw * 0.36, 1.43, 0.0)
		var b := Vector3(cw * 0.5 + 0.03, 0.97, 0.0)
		_beam(a + Vector3(0, 0, 0.121), b + Vector3(0, 0, 0.116 + belly), 0.035, 0.012, C_LEATHER)
		_beam(a + Vector3(0, 0, -0.121), b + Vector3(0, 0, -0.116), 0.035, 0.012, C_LEATHER)
		_box(Vector3(a.x, 1.44, 0), Vector3(0.035, 0.012, 0.245), C_LEATHER)

	if p.patched:
		var pc := body_col.lerp(C_PATCH, 0.5)
		_decal(Vector3(cw * 0.3, 1.23, zc + EPS * 2.0), 0.06, 0.05, pc, 6.0)
		_decal(Vector3(-cw * 0.2, 1.3, -(0.115 + over) - EPS), 0.07, 0.06, pc, 8.0, true)


func _build_arms(p: Dictionary) -> Dictionary:
	var g: float = p.girth
	var female: bool = p.female
	var top: String = p.top
	var skin: Color = p.skin
	var cw := _chest_w(p) + (0.045 if p.oversized else 0.0)
	var aw := (0.085 if female else 0.10) * lerpf(1.0, g, 0.5)
	if p.oversized:
		aw *= 1.25
	var l1 := 0.29
	var l2 := 0.27 + (0.05 if p.oversized else 0.0)
	var sleeve: Color = p.top_col if top in ["coat", "jacket", "dress"] else p.shirt_col
	var cuff: Color = p.shirt_col if top == "coat" else sleeve.darkened(0.12)
	var hs := Vector3(0.05, 0.095, 0.075) * (0.85 if female else 1.0)
	if p.big_hands:
		hs *= 1.45
	var pose: Array = POSES.get(p.pose, POSES["rest"])
	var out := {}
	for s: float in SIDES:
		var idx := 0 if s > 0.0 else 2
		var up: Vector3 = pose[idx]
		var fo: Vector3 = pose[idx + 1]
		var sh := Vector3(s * (cw * 0.5 + aw * 0.5 + 0.005), 1.39, 0.0)
		var ub := Basis.from_euler(Vector3(up.x * DEG, 0.0, s * up.z * DEG))
		_box(sh, Vector3(aw + 0.02, 0.09, aw + 0.03), sleeve)                               # shoulder
		_box_t(Transform3D(ub, sh + ub * Vector3(0, -l1 * 0.5, 0)), Vector3(aw, l1, aw * 1.05), sleeve)
		var elbow := sh + ub * Vector3(0, -l1, 0)
		var fb := ub * Basis.from_euler(Vector3(fo.x * DEG, -s * fo.y * DEG, 0.0))
		_box_t(Transform3D(fb, elbow + fb * Vector3(0, -l2 * 0.5, 0)),
			Vector3(aw * 0.9, l2 + 0.02, aw * 0.95), sleeve)                                 # forearm
		var wrist := elbow + fb * Vector3(0, -l2, 0)
		if top == "coat" or top == "jacket":
			_box_t(Transform3D(fb, wrist + fb * Vector3(0, 0.015, 0)), Vector3(aw * 0.95, 0.03, aw), cuff)
		var hand_c := wrist + fb * Vector3(0, -hs.y * 0.5 + (0.03 if p.oversized else 0.0), 0)
		_box_t(Transform3D(fb, hand_c), hs, skin)                                             # hand
		out["L" if s > 0.0 else "R"] = _xf * hand_c                                           # model space
	return out


# ═════════════════════════════════════════════════════════════════════════════
#  HEAD & FACE
# ═════════════════════════════════════════════════════════════════════════════
func _build_head(p: Dictionary) -> void:
	var skin: Color = p.skin
	var hw: float = p.head_w
	var jaw: float = p.jaw
	var hair: Color = p.hair
	var female: bool = p.female
	var e := _expr(p.expr)
	var hd := 0.115
	var zf := hd            # face front
	var zj := hd * 0.94     # jaw front

	_box(Vector3(0, 1.65, 0), Vector3(hw * 2.0, 0.18, hd * 2.0), skin)            # cranium
	_box(Vector3(0, 1.52, 0), Vector3(hw * 2.0 * jaw, 0.08, hd * 2.0 * 0.94), skin)  # jaw
	for s: float in SIDES:
		_box(Vector3(s * (hw + 0.011), 1.625, -0.01), Vector3(0.022, 0.06, 0.045), skin.darkened(0.06))
	_chin = _xf * Vector3(0.045, 1.47, 0.07)

	# ── nose ──
	if p.red_nose:
		_box(Vector3(0, 1.585, zf + 0.018), Vector3(0.05, 0.048, 0.045), C_RED_NOSE)
	else:
		_box(Vector3(0, 1.592, zf + 0.012), Vector3(0.034, 0.062, 0.034), skin.darkened(0.05))

	# ── skin details ──
	if p.rosy:
		for s: float in SIDES:
			_decal(Vector3(s * 0.07, 1.595, zf + EPS), 0.034, 0.022, skin.lerp(C_ROSY, 0.55))
	if p.sunken_cheeks:
		for s: float in SIDES:
			_decal(Vector3(s * 0.07, 1.578, zf + EPS), 0.026, 0.034, skin.darkened(0.22))
	if p.freckles:
		for s: float in SIDES:
			for i in 5:
				_decal(Vector3(s * (0.06 + _rng.randf_range(-0.02, 0.02)),
					1.605 + _rng.randf_range(-0.015, 0.015), zf + EPS * 2.0), 0.009, 0.009, C_FRECKLE)
			_decal(Vector3(s * 0.009, 1.60, zf + 0.0295 + EPS), 0.007, 0.007, C_FRECKLE)
	if p.wrinkles:
		var wc := skin.darkened(0.28)
		for i in 2:
			_decal(Vector3(0, 1.698 + i * 0.011, zf + EPS), 0.10 - i * 0.025, 0.005, wc)
		for s: float in SIDES:
			_decal(Vector3(s * 0.042, 1.572, zf + EPS), 0.005, 0.03, wc, s * 20.0)

	# ── eyes & brows ──
	var ex := hw * 0.44
	var ey := 1.645
	var sclera_w := 0.040 * float(e.eye_w)
	var eye_h: float = e.eye_h
	var pupil: float = e.pupil
	var brow_col := hair.darkened(0.15)
	for s: float in SIDES:
		var x := s * ex
		if p.sunken_eyes:
			_decal(Vector3(x, ey - 0.004, zf + EPS), sclera_w + 0.018, eye_h + 0.026,
				skin.darkened(0.32).lerp(C_BRUISE, 0.3))
		if p.dark_circles:
			_decal(Vector3(x, ey - eye_h * 0.5 - 0.009, zf + EPS * 2.0), sclera_w + 0.006, 0.014,
				skin.darkened(0.25).lerp(C_BRUISE, 0.55))
		if eye_h <= 0.012:   # squint / closed-eye slit
			_decal(Vector3(x, ey, zf + EPS * 3.0), sclera_w, maxf(eye_h * 0.7, 0.006), C_PUPIL)
		else:
			_decal(Vector3(x, ey, zf + EPS * 3.0), sclera_w, eye_h, C_EYE_WHITE)
			var look: Vector2 = e.look
			if e.goofy:   # pupils that don't quite agree with each other
				look = Vector2(0.55, 0.45) if s > 0.0 else Vector2(-0.2, -0.35)
			var ph := minf(pupil * 1.2, eye_h)
			_decal(Vector3(x + look.x * (sclera_w - pupil) * 0.5, ey + look.y * (eye_h - ph) * 0.5,
				zf + EPS * 4.0), pupil, ph, C_PUPIL)
		if female:
			_decal(Vector3(x, ey + eye_h * 0.5 + 0.002, zf + EPS * 4.0), sclera_w + 0.006, 0.006, C_PUPIL)
		var raise: float = float(e.raise) + (float(e.asym) if s > 0.0 else 0.0)
		_decal(Vector3(x, ey + 0.03 + raise, zf + EPS * 2.0), 0.046, 0.011, brow_col, s * float(e.brow))

	# ── facial hair (decides where the mouth sits) ──
	var facial: String = p.facial
	var fc: Color = p.facial_col
	var mouth_y := 1.53
	var mouth_z := zj + EPS
	match facial:
		"stubble":
			_decal(Vector3(0, 1.515, zj + EPS * 0.5), hw * 2.0 * jaw * 0.92, 0.06, skin.lerp(fc, 0.32))
		"moustache":
			_moustache(1.0, 12.0, 1.548, zj + 0.016, fc)
			mouth_y = 1.522
		"moustache_big":
			_moustache(1.25, 18.0, 1.546, zj + 0.017, fc)
			mouth_y = 1.518
		"small_moustache":
			_box(Vector3(0, 1.549, zj + 0.008), Vector3(0.045, 0.014, 0.018), fc)
			mouth_y = 1.527
		"beard", "long_beard", "pointed_beard":
			if facial == "pointed_beard":
				_box(Vector3(0, 1.495, zj + 0.008), Vector3(hw * 1.1, 0.07, 0.03), fc)
				_prism(Vector3(0, 1.43, zj + 0.006), 0.0, 0.038, 0.08, 4, fc, CAP_TOP)
				mouth_z = zj + 0.024
			else:
				var bw := hw * 2.0 + 0.01
				_box(Vector3(0, 1.50, zj + 0.012), Vector3(bw, 0.10, 0.03), fc)        # chin
				for s: float in SIDES:
					_box(Vector3(s * (hw - 0.004), 1.55, -0.005), Vector3(0.024, 0.14, hd * 1.8), fc)
				_box(Vector3(0, 1.465, 0.01), Vector3(bw, 0.04, hd * 1.7), fc)          # under chin
				mouth_z = zj + 0.028
			_moustache(1.05, 14.0, 1.548, zj + 0.022, fc)
			mouth_y = 1.515
			if facial == "long_beard":
				_box(Vector3(0, 1.36, zj + 0.012), Vector3(0.15, 0.20, 0.045), fc, Vector3(-6, 0, 0))
				_box(Vector3(0.008, 1.22, zj + 0.022), Vector3(0.10, 0.12, 0.04), fc.darkened(0.1),
					Vector3(-8, 0, 3))

	var lip := skin.darkened(0.45).lerp(Color(0.55, 0.2, 0.18), 0.5 if female else 0.3)
	_mouth(e.mouth, mouth_y, mouth_z + EPS, lip)

	_build_hair(p)
	_build_hat(p)

	# ── round glasses ──
	if p.glasses:
		var gz := zf + 0.014
		for s: float in SIDES:
			_ring(Vector3(s * ex, ey, gz), 0.031, 0.025, 6, C_METAL)
			_decal(Vector3(s * ex - 0.012, ey + 0.012, gz + 0.001), 0.008, 0.008, Color(0.95, 0.95, 0.92))
			var hinge_x0 := ex + 0.031
			var hinge_x1 := hw + 0.006
			_box(Vector3(s * (hinge_x0 + hinge_x1) * 0.5, ey + 0.004, gz),
				Vector3(hinge_x1 - hinge_x0 + 0.006, 0.007, 0.006), C_METAL)
			_box(Vector3(s * hinge_x1, ey + 0.004, gz * 0.5), Vector3(0.006, 0.007, gz), C_METAL)
		_box(Vector3(0, ey + 0.006, gz), Vector3(ex * 2.0 - 0.05, 0.006, 0.006), C_METAL)


func _moustache(size: float, droop: float, y: float, z: float, col: Color) -> void:
	for s: float in SIDES:
		_box(Vector3(s * 0.026 * size, y, z), Vector3(0.054 * size, 0.022 * size, 0.026), col,
			Vector3(0, 0, -s * droop))


func _mouth(kind: String, y: float, z: float, lip: Color) -> void:
	match kind:
		"line":
			_decal(Vector3(0, y, z), 0.062, 0.011, lip)
		"small":
			_decal(Vector3(0, y, z), 0.032, 0.010, lip)
		"smile":
			_decal(Vector3(0, y, z), 0.04, 0.011, lip)
			for s: float in SIDES:
				_decal(Vector3(s * 0.028, y + 0.005, z), 0.022, 0.010, lip, s * 30.0)
		"frown":
			_decal(Vector3(0, y, z), 0.04, 0.011, lip)
			for s: float in SIDES:
				_decal(Vector3(s * 0.027, y - 0.005, z), 0.02, 0.010, lip, -s * 30.0)
		"open":
			_decal(Vector3(0, y - 0.004, z), 0.042, 0.034, C_MOUTH)
		"open_small":
			_decal(Vector3(0, y - 0.002, z), 0.03, 0.022, C_MOUTH)
		"singing":
			_decal(Vector3(0, y - 0.003, z), 0.04, 0.026, C_MOUTH)
			for s: float in SIDES:
				_decal(Vector3(s * 0.026, y + 0.006, z), 0.016, 0.009, lip, s * 35.0)
		"grin":
			_decal(Vector3(0, y, z), 0.072, 0.03, C_MOUTH)
			_decal(Vector3(0, y + 0.009, z + EPS), 0.058, 0.009, C_TEETH)
			for s: float in SIDES:
				_decal(Vector3(s * 0.042, y + 0.012, z), 0.02, 0.01, lip, s * 35.0)
		"smirk":
			_decal(Vector3(-0.006, y, z), 0.048, 0.010, lip, 6.0)
			_decal(Vector3(0.03, y + 0.007, z), 0.018, 0.009, lip, 30.0)
		"wavy":
			for i in 3:
				_decal(Vector3(-0.022 + i * 0.022, y + (0.003 if i % 2 == 1 else -0.002), z),
					0.024, 0.009, lip, 12.0 if i % 2 == 0 else -12.0)


# ── hair ─────────────────────────────────────────────────────────────────────
func _hair_cap(hw: float, hd: float, col: Color) -> void:
	_box(Vector3(0, 1.75, -0.006), Vector3(hw * 2.0 + 0.024, 0.04, hd * 2.0 + 0.024), col)


func _hair_back(hw: float, hd: float, col: Color, y: float, h: float) -> void:
	_box(Vector3(0, y, -(hd + 0.008)), Vector3(hw * 2.0 + 0.024, h, 0.024), col)


func _hair_sides(hw: float, hd: float, col: Color) -> void:
	for s: float in SIDES:
		_box(Vector3(s * (hw + 0.008), 1.70, -0.025), Vector3(0.022, 0.09, hd * 1.55), col)


func _build_hair(p: Dictionary) -> void:
	var col: Color = p.hair
	var hw: float = p.head_w
	var hd := 0.115
	var style: String = p.hair_style
	var hat: String = p.hat
	if hat == "bonnet" or hat == "headscarf":   # just a strip peeking out
		_box(Vector3(0, 1.728, hd - 0.002), Vector3(hw * 2.0 - 0.01, 0.026, 0.02), col)
		return
	var hatted := hat != "none"

	match style:
		"thinning":
			_hair_back(hw, hd, col, 1.625, 0.10)
			for s: float in SIDES:
				_box(Vector3(s * (hw + 0.008), 1.665, -0.03), Vector3(0.022, 0.06, hd * 1.4), col)
				_box(Vector3(s * (hw + 0.016), 1.70, -0.02), Vector3(0.03, 0.03, 0.04),
					col.lightened(0.1), Vector3(0, 0, s * 35.0))
			if not hatted:   # comb-over strands across a bald pate
				for i in 3:
					_box(Vector3(-0.035 + i * 0.035, 1.744, -0.01), Vector3(0.008, 0.006, hd * 1.6),
						col.lightened(0.08), Vector3(0, _rng.randf_range(-15.0, 15.0), 0))
		"long", "wild":
			if not hatted:
				_hair_cap(hw, hd, col)
				for s: float in SIDES:   # centre parting
					_box(Vector3(s * hw * 0.5, 1.728, hd + 0.002), Vector3(hw + 0.012, 0.03, 0.026), col,
						Vector3(0, 0, -s * 10.0))
			_box(Vector3(0, 1.58, -(hd + 0.012)), Vector3(hw * 2.0 + 0.034, 0.36, 0.03), col)
			for s: float in SIDES:
				_box(Vector3(s * (hw + 0.012), 1.62, -0.02), Vector3(0.026, 0.28, hd * 1.3), col)
				_box(Vector3(s * (hw - 0.002), 1.53, hd * 0.75), Vector3(0.03, 0.2, 0.04), col)
			if style == "wild":
				for i in 10:
					var a := _rng.randf_range(-2.3, 2.3)
					var pos := Vector3(sin(a) * (hw + 0.02), _rng.randf_range(1.5, 1.79),
						-cos(a) * (hd + 0.02))
					_box(pos, Vector3(0.045, 0.07, 0.04), col.lightened(_rng.randf_range(-0.05, 0.1)),
						Vector3(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40), _rng.randf_range(-40, 40)))
		"curly":
			if not hatted:
				_box(Vector3(0, 1.745, -0.006), Vector3(hw * 2.0 + 0.01, 0.03, hd * 2.0 + 0.01), col)
			_hair_back(hw, hd, col, 1.67, 0.14)
			for i in 12:
				var a := TAU * float(i) / 12.0
				var dir := Vector3(sin(a), 0, cos(a))
				if dir.z > 0.6 and hatted:
					continue
				var pos := Vector3(dir.x * (hw + 0.02), 1.70 + _rng.randf_range(-0.04, 0.05),
					dir.z * (hd + 0.02))
				if dir.z > 0.6:
					pos.y = 1.745   # hairline curls stay above the brows
				_box(pos, Vector3.ONE * _rng.randf_range(0.045, 0.06),
					col.lightened(_rng.randf_range(-0.06, 0.08)),
					Vector3(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30), _rng.randf_range(-30, 30)))
			if not hatted:
				for i in 5:
					_box(Vector3(_rng.randf_range(-hw, hw), 1.77, _rng.randf_range(-hd, hd * 0.6)),
						Vector3.ONE * 0.055, col.lightened(_rng.randf_range(-0.05, 0.08)),
						Vector3(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30), 0))
		"slick":
			if not hatted:
				_box(Vector3(0, 1.748, -0.01), Vector3(hw * 2.0 + 0.024, 0.032, hd * 2.0 + 0.02), col)
				for i in 3:   # pomade shine streaks
					_box(Vector3(-0.04 + i * 0.04, 1.766, -0.01), Vector3(0.01, 0.006, hd * 1.9),
						col.lightened(0.3))
				_box(Vector3(0, 1.738, hd + 0.002), Vector3(hw * 2.0, 0.022, 0.02), col)
			_hair_back(hw, hd, col, 1.665, 0.15)
			_hair_sides(hw, hd, col)
		"bun":
			if not hatted:
				_hair_cap(hw, hd, col)
				_box(Vector3(0, 1.735, hd + 0.002), Vector3(hw * 2.0 + 0.014, 0.022, 0.02), col)
			_hair_back(hw, hd, col, 1.66, 0.16)
			_hair_sides(hw, hd, col)
			_prism_t(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 1.68, -(hd + 0.045))),
				0.045, 0.04, 0.06, 6, col)
		_:   # "short" / "messy"
			if not hatted:
				_hair_cap(hw, hd, col)
				_box(Vector3(0, 1.724, hd + 0.002), Vector3(hw * 2.0 + 0.01, 0.034, 0.026), col)
			_hair_back(hw, hd, col, 1.66, 0.16)
			_hair_sides(hw, hd, col)
			if style == "messy" and not hatted:
				for i in 6:
					_box(Vector3(_rng.randf_range(-hw, hw), 1.775, _rng.randf_range(-hd, hd)),
						Vector3(0.05, 0.04, 0.05), col.lightened(_rng.randf_range(-0.04, 0.08)),
						Vector3(_rng.randf_range(-25, 25), _rng.randf_range(-40, 40), _rng.randf_range(-25, 25)))


# ── hats ─────────────────────────────────────────────────────────────────────
func _build_hat(p: Dictionary) -> void:
	var c: Color = p.hat_col
	var hw: float = p.head_w
	var jaw: float = p.jaw
	var hd := 0.115
	match p.hat:
		"cap":   # flat farmhand's cap, pulled down at the front
			_push(_rot_about(Vector3(0, 1.75, 0), Vector3(6, 0, 0)))
			_box(Vector3(0, 1.775, -0.005), Vector3(hw * 2.0 + 0.045, 0.06, hd * 2.0 + 0.05), c)
			_box(Vector3(0, 1.79, 0.03), Vector3(hw * 2.0 + 0.03, 0.03, hd * 1.4), c.lightened(0.05))
			_box(Vector3(0, 1.75, hd + 0.045), Vector3(hw * 1.8, 0.016, 0.075), c.darkened(0.15))
			_box(Vector3(0, 1.81, -0.01), Vector3(0.02, 0.012, 0.02), c.darkened(0.2))
			_pop()
		"old_hat":   # battered wide-brimmed felt hat, jauntily tilted
			_push(_rot_about(Vector3(0, 1.75, 0), Vector3(4, 0, 6)))
			_prism(Vector3(0, 1.752, 0), 0.21, 0.20, 0.018, 8, c)
			_prism(Vector3(0, 1.778, 0), 0.143, 0.141, 0.03, 6, c.darkened(0.35), CAP_NONE)
			_prism(Vector3(0, 1.83, 0), 0.14, 0.125, 0.13, 6, c, CAP_TOP)
			_box(Vector3(0.05, 1.86, 0.06), Vector3(0.05, 0.04, 0.012), c.lightened(0.08), Vector3(0, 30, 0))
			_pop()
		"bonnet":   # linen bonnet with frilled brim and chin ribbon
			_box(Vector3(0, 1.765, -0.02), Vector3(hw * 2.0 + 0.05, 0.06, hd * 2.0 + 0.03), c)
			_box(Vector3(0, 1.66, -(hd + 0.02)), Vector3(hw * 2.0 + 0.05, 0.22, 0.035), c)
			for s: float in SIDES:
				_box(Vector3(s * (hw + 0.022), 1.65, -0.01), Vector3(0.028, 0.20, hd * 2.0 + 0.02), c)
				_box(Vector3(s * (hw + 0.035), 1.66, hd), Vector3(0.022, 0.20, 0.03), c.lightened(0.06))
				_box(Vector3(s * 0.07, 1.50, 0.07), Vector3(0.012, 0.10, 0.012), c.darkened(0.1),
					Vector3(0, 0, s * 25.0))
			_box(Vector3(0, 1.765, hd + 0.012), Vector3(hw * 2.0 + 0.08, 0.055, 0.025), c.lightened(0.06))
			_box(Vector3(0, 1.465, 0.08), Vector3(0.04, 0.025, 0.02), c)
		"headscarf":   # black scarf wrapped round the head, knotted under the chin
			_box(Vector3(0, 1.762, -0.01), Vector3(hw * 2.0 + 0.04, 0.05, hd * 2.0 + 0.03), c)
			_box(Vector3(0, 1.60, -(hd + 0.015)), Vector3(hw * 2.0 + 0.04, 0.32, 0.03), c)
			for s: float in SIDES:
				_box(Vector3(s * (hw + 0.016), 1.60, -0.005), Vector3(0.024, 0.30, hd * 2.0 + 0.01), c)
			_box(Vector3(0, 1.735, hd + 0.004), Vector3(hw * 2.0 + 0.04, 0.035, 0.02), c)
			_box(Vector3(0, 1.46, 0.03), Vector3(hw * 2.0 * jaw + 0.03, 0.035, hd * 1.7), c)
			_box(Vector3(0, 1.45, hd + 0.01), Vector3(0.05, 0.035, 0.03), c.lightened(0.05))
			_box(Vector3(0.025, 1.40, hd), Vector3(0.025, 0.08, 0.015), c, Vector3(0, 0, 15))
			var flap := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.25)), Vector3(0, 1.39, -(hd + 0.02)))
			_prism_t(flap, 0.0, 0.10, 0.10, 4, c, CAP_TOP)


# ═════════════════════════════════════════════════════════════════════════════
#  PROPS  (built in model space from the hand positions)
# ═════════════════════════════════════════════════════════════════════════════
func _build_props(p: Dictionary, hands: Dictionary) -> void:
	var saved := _xf
	_xf = Transform3D.IDENTITY
	var prop: String = p.prop
	match prop:
		"ale":   # wooden tankard with a head of foam, raised mid-song
			var h: Vector3 = hands.R
			var mug := h + Vector3(0, 0.035, 0)
			_prism(mug, 0.042, 0.042, 0.11, 6, C_WOOD, CAP_BOTTOM)
			_prism(mug + Vector3(0, -0.03, 0), 0.045, 0.045, 0.015, 6, C_METAL, CAP_NONE)
			_prism(mug + Vector3(0, 0.062, 0), 0.044, 0.04, 0.02, 6, Color(0.93, 0.89, 0.78), CAP_TOP)
			_box(mug + Vector3(-0.055, 0, 0), Vector3(0.015, 0.07, 0.015), C_WOOD)
		"stick", "cane":
			var h: Vector3 = hands.R
			var top_y := h.y + (0.06 if prop == "stick" else 0.02)
			var foot := Vector3(h.x - 0.02, 0.0, h.z + 0.08)
			var tip := Vector3(h.x, top_y, h.z)
			_beam(foot, tip, 0.028, 0.028, C_WOOD)
			if prop == "stick":   # gnarled walking stick
				_box(tip + Vector3(0, 0.02, 0), Vector3(0.042, 0.042, 0.042), C_WOOD.darkened(0.2), Vector3(0, 45, 20))
				for k in 2:
					_box(foot.lerp(tip, 0.35 + k * 0.25), Vector3(0.034, 0.03, 0.034), C_WOOD.darkened(0.12),
						Vector3(0, 30 * k, 0))
			else:                 # crook-handled cane
				_box(tip + Vector3(0, 0.01, 0.04), Vector3(0.028, 0.028, 0.10), C_WOOD)
				_box(tip + Vector3(0, -0.02, 0.085), Vector3(0.026, 0.06, 0.026), C_WOOD)
		"bag":   # merchant's leather satchel on the left hip
			var x := _chest_w(p) * 0.5 + 0.07
			_box(Vector3(x, 0.86, 0.02), Vector3(0.08, 0.20, 0.24), C_LEATHER)
			_box(Vector3(x + 0.002, 0.93, 0.02), Vector3(0.085, 0.07, 0.245), C_LEATHER.darkened(0.15))
			_box(Vector3(x + 0.045, 0.91, 0.02), Vector3(0.008, 0.025, 0.025), C_BRASS)
		"fiddle":   # tucked under the chin, bowed with the right hand
			var lh: Vector3 = hands.L
			var rh: Vector3 = hands.R
			var yv := (lh - _chin).normalized()
			var xv := yv.cross(Vector3.UP).normalized()
			var zv := xv.cross(yv)
			var fb := Basis(xv, yv, zv)
			var dark := Color(0.15, 0.10, 0.07)
			var wood := Color(0.55, 0.27, 0.10)
			_box_t(Transform3D(fb, _chin + yv * 0.07 - zv * 0.03), Vector3(0.20, 0.13, 0.045), wood)
			_box_t(Transform3D(fb, _chin + yv * 0.20 - zv * 0.03), Vector3(0.16, 0.12, 0.045), wood)
			_box_t(Transform3D(fb, _chin + yv * 0.36 - zv * 0.01), Vector3(0.03, 0.22, 0.03), dark)
			_box_t(Transform3D(fb, _chin + yv * 0.49 - zv * 0.01), Vector3(0.035, 0.05, 0.05), dark)
			_box_t(Transform3D(fb, _chin + yv * 0.02), Vector3(0.07, 0.04, 0.02), dark)
			var bridge := _chin + yv * 0.11 - zv * 0.005
			var bdir := (bridge - rh).normalized()
			_beam(rh - bdir * 0.06, rh + bdir * 0.62, 0.01, 0.01, C_WOOD.darkened(0.2))
			_beam(rh - bdir * 0.04 + Vector3(0, -0.012, 0), rh + bdir * 0.6 + Vector3(0, -0.012, 0),
				0.006, 0.006, Color(0.90, 0.88, 0.80))
	_xf = saved


# ═════════════════════════════════════════════════════════════════════════════
#  LOW-POLY PRIMITIVES
# ═════════════════════════════════════════════════════════════════════════════
func _push(t: Transform3D) -> void:
	_stack.append(_xf)
	_xf = _xf * t


func _pop() -> void:
	_xf = _stack.pop_back()


func _rot_about(pivot: Vector3, euler_deg: Vector3) -> Transform3D:
	return Transform3D(Basis(), pivot) * Transform3D(Basis.from_euler(euler_deg * DEG), Vector3.ZERO) \
		* Transform3D(Basis(), -pivot)


## Axis-aligned (optionally rotated) box: 12 triangles.
func _box(center: Vector3, size: Vector3, col: Color, rot_deg := Vector3.ZERO) -> void:
	_box_t(Transform3D(Basis.from_euler(rot_deg * DEG), center), size, col)


func _box_t(t: Transform3D, size: Vector3, col: Color) -> void:
	var m := _base * _xf * t
	var h := size * 0.5
	for f in _BOX_FACES:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		_quad(m * ((n - u - v) * h), m * ((n + u - v) * h), m * ((n + u + v) * h),
			m * ((n - u + v) * h), m.basis * n, col)


## Box stretched between two points (sticks, straps, bows).
func _beam(a: Vector3, b: Vector3, w: float, d: float, col: Color) -> void:
	var y := b - a
	var length := y.length()
	if length < 0.0001:
		return
	y /= length
	var ref := Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	_box_t(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, length, d), col)


func _prism(c: Vector3, r_bot: float, r_top: float, height: float, sides: int, col: Color,
		caps: int = CAP_BOTH) -> void:
	_prism_t(Transform3D(Basis(), c), r_bot, r_top, height, sides, col, caps)


## N-sided cylinder / cone along local Y. A flat face points at +Z.
## skip_z: side faces whose direction has z > skip_z are left out (open fronts).
func _prism_t(t: Transform3D, r_bot: float, r_top: float, height: float, sides: int, col: Color,
		caps: int = CAP_BOTH, skip_z: float = 2.0, double_sided: bool = false,
		inner_col: Color = Color.BLACK) -> void:
	var m := _base * _xf * t
	var hy := height * 0.5
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var a := TAU * (float(i) + 0.5) / float(sides)
		var d := Vector3(sin(a), 0.0, cos(a))
		bot.append(m * (d * r_bot + Vector3(0, -hy, 0)))
		top.append(m * (d * r_top + Vector3(0, hy, 0)))
	var center := m * Vector3.ZERO
	var axis := (m.basis * Vector3.UP).normalized()
	for i in sides:
		var j := (i + 1) % sides
		if cos(TAU * float(i + 1) / float(sides)) > skip_z:
			continue
		var mid := (bot[i] + bot[j] + top[i] + top[j]) * 0.25
		var radial := mid - (center + axis * axis.dot(mid - center))
		_prism_side(bot[i], bot[j], top[j], top[i], radial, col, r_bot, r_top)
		if double_sided:
			_prism_side(bot[i], bot[j], top[j], top[i], -radial, inner_col, r_bot, r_top)
	if (caps & CAP_BOTTOM) != 0 and r_bot > 0.0001:
		for i in range(1, sides - 1):
			_tri(bot[0], bot[i], bot[i + 1], -axis, col)
	if (caps & CAP_TOP) != 0 and r_top > 0.0001:
		for i in range(1, sides - 1):
			_tri(top[0], top[i], top[i + 1], axis, col)


func _prism_side(b0: Vector3, b1: Vector3, t1: Vector3, t0: Vector3, hint: Vector3, col: Color,
		r_bot: float, r_top: float) -> void:
	if r_top <= 0.0001:
		_tri(b0, b1, t0, hint, col)
	elif r_bot <= 0.0001:
		_tri(b0, t1, t0, hint, col)
	else:
		_quad(b0, b1, t1, t0, hint, col)


## Single quad facing local +Z (or -Z with back = true): eyes, mouths, buttons…
func _decal(pos: Vector3, w: float, h: float, col: Color, rot_z := 0.0, back := false) -> void:
	var b := Basis(Vector3(0, 0, 1), rot_z * DEG)
	if back:
		b = Basis(Vector3.UP, PI) * b
	var m := _base * _xf * Transform3D(b, pos)
	var hw := w * 0.5
	var hh := h * 0.5
	_quad(m * Vector3(-hw, -hh, 0), m * Vector3(hw, -hh, 0), m * Vector3(hw, hh, 0),
		m * Vector3(-hw, hh, 0), m.basis * Vector3(0, 0, 1), col)


## Flat N-gon ring facing ±Z (glasses rims).
func _ring(c: Vector3, r_out: float, r_in: float, sides: int, col: Color) -> void:
	var m := _base * _xf
	var fwd := m.basis * Vector3(0, 0, 1)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		var o0 := m * (c + d0 * r_out)
		var o1 := m * (c + d1 * r_out)
		var i0 := m * (c + d0 * r_in)
		var i1 := m * (c + d1 * r_in)
		_quad(o0, o1, i1, i0, fwd, col)
		_quad(o0, o1, i1, i0, -fwd, col)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, col: Color) -> void:
	_tri(a, b, c, hint, col)
	_tri(a, c, d, hint, col)


## Emits one flat-shaded triangle. Winding is fixed automatically so the face
## points along `hint` (Godot treats clockwise triangles as front faces).
func _tri(a: Vector3, b: Vector3, c: Vector3, hint: Vector3, col: Color) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-14:
		return
	if g.dot(hint) > 0.0:
		var tmp := b
		b = c
		c = tmp
		g = -g
	var n := -g.normalized()
	for v: Vector3 in [a, b, c]:
		_st.set_color(_final_color(col, v))
		_st.set_normal(n)
		_st.set_uv(_uv(v, n))
		_st.add_vertex(v)
	_tris += 1


func _final_color(col: Color, p: Vector3) -> Color:
	var c := col
	if baked_vertex_shade:
		var k := lerpf(0.70, 1.0, clampf(p.y / 1.75, 0.0, 1.0))
		c = Color(c.r * k, c.g * k, c.b * k)
	var lv := float((1 << color_depth_bits) - 1)   # quantise like the PS1's 15-bit colour
	return Color(roundf(c.r * lv) / lv, roundf(c.g * lv) / lv, roundf(c.b * lv) / lv)


func _uv(p: Vector3, n: Vector3) -> Vector2:
	# Box-projected UVs: about 2.5 cm per texel of the 16 px grain texture.
	var a := n.abs()
	var uv: Vector2
	if a.x >= a.y and a.x >= a.z:
		uv = Vector2(p.z, -p.y)
	elif a.y >= a.z:
		uv = Vector2(p.x, p.z)
	else:
		uv = Vector2(p.x, -p.y)
	return uv * 2.5
