@tool
class_name PS1Villager
extends Node3D
## ════════════════════════════════════════════════════════════════════════════
##  PS1 VILLAGER BUILDER  —  Godot 4.x   (@tool: renders live in the editor)
##
##  Procedurally builds any of the 20 wake villagers in the style of late-90s
##  PlayStation horror (Empty Gauge / Fears to Fathom / Lost Hopes):
##
##    • Geometry : smooth low-poly lofts — 10-sided torso, 12-sided head,
##                 6-sided limbs, hair shells with ragged strand edges —
##                 Gouraud (per-vertex) shaded, ~1000 triangles a villager.
##    • Texture  : one 64×128 texture per villager, painted in code: the face
##                 (eyes, brows, nose, lips, stubble, freckles…) and the front
##                 of the clothes (collars, lapels, buttons, apron bib…),
##                 projected from the front like PS1 artists did.
##    • Colour   : everything else is vertex colour, cut to 15-bit and
##                 multiplied by a 16×16 grain texture.
##    • Material : StandardMaterial3D — PER_VERTEX shading, NEAREST filtering,
##                 metallic / specular off, the painted texture as a UV2
##                 detail layer. With `vertex_jitter` on, a ShaderMaterial adds
##                 PS1 vertex snapping (wobble), affine texture warping,
##                 Bayer dithering and colour-depth reduction.
##
##  USAGE: add a Node3D to a scene, attach this script, pick a villager in
##         the Inspector. Tick "Show Whole Cast" to see all twenty at once.
##         Characters face +Z and stand on Y = 0 (about 1.75 m tall).
##
##  IN GAME: guests (scripts/guest.gd) call PS1Villager.build_guest_parts().
##         That builds the same character split into four meshes — "body",
##         "legs" (hip pivot), "knee" (knee pivot) and "head" (neck pivot) —
##         turned to face -Z like the rest of the game, so guests can sit
##         down and turn their heads. Results are cached per look.
## ════════════════════════════════════════════════════════════════════════════

enum Character {
	SULTAN_ESMAGZAM, SEAN, JAMES, MICHAEL, THOMAS,
	WILLIAM, DANIEL, JOSEPH, JOHN, HUGH,
	JEREMIAH, DENIS, TIMOTHY, PETER, MARTIN,
	MARY, BRIDGET, MARGARET, CATHERINE, ELLEN,
	DECLAN,
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
## Drain colour toward grey for a grim, washed-out horror palette.
@export_range(0.0, 1.0) var desaturate := 0.2:
	set(value):
		desaturate = value
		_queue_rebuild()
## Ordered (Bayer) dithering before the colour-depth cut, like PS1 hardware.
@export_range(0.0, 2.0) var dither := 1.0:
	set(value):
		dither = value
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
const SKIN_GRAIN := 0.3                  # skin shows less grain than cloth
const CLOTH_GRAIN := 0.55

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
	"nervous": [Vector3(6, 0, 2), Vector3(-48, 24, 0), Vector3(6, 0, 2), Vector3(-48, 24, 0)],
	"clasp": [Vector3(-8, 0, -2), Vector3(-62, 30, 0), Vector3(-8, 0, -2), Vector3(-62, 30, 0)],
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
const C_EYE_WHITE := Color(0.74, 0.71, 0.64)   # dim, bloodshot-ish: no cartoon eyes
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
const C_MUD_CAKED := Color(0.47, 0.38, 0.25)   # light enough to read in candlelight
const C_MUD_WET := Color(0.55, 0.45, 0.30)
const C_SHINE := Color(0.58, 0.58, 0.62)
const C_APRON := Color(0.88, 0.85, 0.76)
const C_METAL := Color(0.22, 0.19, 0.15)
const C_SILVER := Color(0.75, 0.72, 0.64)
const C_LASH := Color(0.11, 0.08, 0.07)
const EYE_BROWN := Color(0.34, 0.22, 0.13)
const EYE_DARK := Color(0.20, 0.14, 0.10)
const EYE_BLUE := Color(0.33, 0.46, 0.58)
const EYE_GREY := Color(0.46, 0.50, 0.52)
const EYE_GREEN := Color(0.36, 0.42, 0.24)

# ─── body rig (metres, before the per-character height scale) ───────────────
const HIP_Y := 0.86          # legs pivot
const KNEE_Y := 0.47         # knee pivot
const Y_SHOULDER := 1.385
const Y_NECK := 1.47         # head pivot
const Y_CHIN := 1.49         # head-local y = 0
const HEAD_TOP := 0.256      # head-local
const FACE_W := 0.18         # width / height the face texture is projected over
const FACE_H := 0.26
const FALL_Y := 0.12         # long hair hangs straight down below this (head-local)
const FACE_DIR := "res://assets/faces/"   # optional face pictures, <name>.png

# Head cross-sections, chin to crown: [y, half-width, half-depth, centre z]
const HEAD_RINGS := [
	[0.000, 0.000, 0.000, 0.030],   # under the chin
	[0.008, 0.026, 0.030, 0.035],   # chin
	[0.030, 0.046, 0.058, 0.022],
	[0.060, 0.060, 0.076, 0.010],   # mouth / jaw
	[0.098, 0.069, 0.088, 0.004],   # nose tip / cheekbones
	[0.140, 0.074, 0.095, 0.000],   # eyes
	[0.185, 0.073, 0.096, -0.004],  # brow
	[0.222, 0.064, 0.088, -0.010],
	[0.243, 0.046, 0.066, -0.012],
	[0.253, 0.022, 0.032, -0.012],
	[0.256, 0.000, 0.000, -0.012],  # crown
]

# Hair shells. front / side / back = head-local y where the lower edge ends.
const HAIR_STYLES := {
	"short": {"front": 0.198, "side": 0.125, "back": 0.06, "grow": 0.010, "jag": 0.006},
	"messy": {"front": 0.19, "side": 0.12, "back": 0.055, "grow": 0.016, "jag": 0.016, "bump": 0.010},
	"slick": {"front": 0.212, "side": 0.13, "back": 0.05, "grow": 0.007, "streak": 0.12},
	"curly": {"front": 0.195, "side": 0.11, "back": 0.05, "grow": 0.02, "jag": 0.012, "bump": 0.016,
		"cols": 18},
	"long": {"front": 0.168, "side": -0.11, "back": -0.15, "grow": 0.012, "jag": 0.012, "fall": true,
		"part": true, "rows": 8},
	"wild": {"front": 0.17, "side": -0.06, "back": -0.12, "grow": 0.02, "jag": 0.03, "bump": 0.02,
		"fall": true, "rows": 8},
	"bun": {"front": 0.205, "side": 0.12, "back": 0.045, "grow": 0.008},
	"thinning": {"front": 0.17, "side": 0.095, "back": 0.06, "grow": 0.008, "jag": 0.008,
		"top": 0.178, "a_min": PI * 0.42, "a_max": PI * 1.58},
}

const EYE_COLS := {
	"SEAN": EYE_DARK, "JAMES": EYE_BLUE, "MICHAEL": EYE_GREY, "THOMAS": EYE_BLUE,
	"WILLIAM": EYE_DARK, "DANIEL": EYE_GREEN, "JOSEPH": EYE_GREY, "JOHN": EYE_GREY,
	"HUGH": EYE_GREY, "DENIS": EYE_BLUE, "MARTIN": EYE_GREEN, "MARY": EYE_BLUE,
	"BRIDGET": EYE_GREY, "MARGARET": EYE_DARK, "CATHERINE": EYE_GREEN, "ELLEN": EYE_GREY,
}

const PS1_SHADER := """
shader_type spatial;
// Per-vertex (Gouraud) lighting, no specular — like the PS1 GTE.
render_mode vertex_lighting, specular_disabled, diffuse_lambert, cull_back;

uniform sampler2D grain_tex : filter_nearest, repeat_enable, hint_default_white;
uniform sampler2D face_tex : filter_nearest, repeat_disable, hint_default_transparent;
uniform vec2 snap_resolution = vec2(320.0, 240.0);
uniform float affine_amount : hint_range(0.0, 1.0) = 0.6;
uniform float color_levels = 31.0;
uniform float dither_amount : hint_range(0.0, 2.0) = 1.0;

varying vec3 affine_uv;
varying vec3 affine_uv2;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// 4x4 Bayer matrix value in [0, 1), built from the 2x2 one: (0 2 / 3 1).
float bayer4(vec2 frag) {
	vec2 p = mod(floor(frag), 4.0);
	vec2 lo = mod(p, 2.0);
	vec2 hi = floor(p / 2.0);
	float b_lo = mod(2.0 * lo.x + 3.0 * lo.y, 4.0);
	float b_hi = mod(2.0 * hi.x + 3.0 * hi.y, 4.0);
	return (4.0 * b_lo + b_hi) / 16.0;
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
	affine_uv2 = vec3(UV2 * clip.w, clip.w);
}

void fragment() {
	vec2 uv = mix(UV, affine_uv.xy / affine_uv.z, affine_amount);
	vec2 uv2 = mix(UV2, affine_uv2.xy / affine_uv2.z, affine_amount);
	// sRGB vertex colour x grain; vertex alpha says how much grain (skin < cloth)
	vec3 c = COLOR.rgb * mix(vec3(1.0), texture(grain_tex, uv).rgb, COLOR.a);
	// the painted face / clothes texture sits on top where it is opaque
	vec4 f = texture(face_tex, uv2);
	c = mix(c, f.rgb, f.a);
	// ordered dithering, then cut to 15-bit colour, as the PS1 GPU did
	c += (bayer4(FRAGCOORD.xy) - 0.5) * dither_amount / color_levels;
	c = clamp(floor(c * color_levels + 0.5) / color_levels, 0.0, 1.0);
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
var _grain := CLOTH_GRAIN            # grain strength stored in vertex alpha
var _jaw := 1.0                      # head shape for the current villager
var _hollow := false
var _torso_tw := 0.5                 # width the clothes texture is projected over

# painted texture atlas: one 64×128 cell per villager (face on top, clothes below)
const CELL := Vector2i(64, 128)
const NO_TEX := Vector2(-1.0, -1.0)  # uv2 marker: "this vertex is not textured"
var _atlas: Image
var _cell := Vector2i.ZERO
var _no_uv := Vector2.ZERO
var _clip := Rect2i()

# split build (in-game guests)
var _split := false
var _parts := {}                 # part name -> SurfaceTool
var _pivots := {}                # part name -> pivot (model space)
var _pivot := Vector3.ZERO       # subtracted from every vertex of the current part
var _overrides := {}             # merged over the character profile
var _mouth_pos := Vector3.ZERO   # mouth position relative to the head pivot

static var _guest_cache := {}
static var _shader: Shader
static var _grain_tex: ImageTexture


# ═════════════════════════════════════════════════════════════════════════════
#  IN-GAME API
# ═════════════════════════════════════════════════════════════════════════════
## "SEAN", "Old Tom"... -> Character id, or -1 if unknown.
## The look of a villager as data (hair, glasses, hat, facial hair...), so the
## game can pick a detail to change on a double. Same keys build_guest_parts
## accepts as overrides.
static func profile_of(id: int) -> Dictionary:
	var b := PS1Villager.new()
	var p := b._profile(id)
	p["eye_col"] = EYE_COLS.get(Character.keys()[id], EYE_BROWN)
	b.free()
	return p


static func character_from_name(model: String) -> int:
	return Character.keys().find(model.strip_edges().to_upper().replace(" ", "_"))


## Builds a guest as separate meshes, facing -Z. `overrides` replaces profile
## fields, e.g. {"shoe_col": Color.BLACK, "boots": "mud"}. Returns
## {body, legs, knee, head: ArrayMesh, pivots: {legs, knee, head: Vector3},
##  mouth: Vector3 (relative to head pivot), material: Material}.
static func build_guest_parts(id: int, overrides: Dictionary = {}) -> Dictionary:
	var key := "%d|%s" % [id, var_to_str(overrides)]
	if _guest_cache.has(key):
		return _guest_cache[key]
	var b := PS1Villager.new()
	var r := b._build_split(id, overrides)
	b.free()
	_guest_cache[key] = r
	return r


func _build_split(id: int, overrides: Dictionary) -> Dictionary:
	_split = true
	_parts.clear()
	_pivots.clear()
	_overrides = overrides
	_tris = 0
	_new_atlas(Vector2i(CELL.x, CELL.y))
	_set_cell(Vector2i.ZERO)
	_base = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)   # game characters face -Z
	_build_character(id)
	var out := {}
	for part: String in _parts:
		var st: SurfaceTool = _parts[part]
		st.index()
		out[part] = st.commit()
	out["pivots"] = _pivots.duplicate()
	out["mouth"] = _mouth_pos
	# the game renders 480x270: keep the snapping grid 16:9
	out["material"] = _make_material(ImageTexture.create_from_image(_atlas), Vector2(320, 180))
	return out


## Routes the following geometry to `part`, relative to `pivot` (local space).
func _use_part(part: String, pivot := Vector3.ZERO) -> void:
	if not _split:
		return
	if not _parts.has(part):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_parts[part] = st
	_st = _parts[part]
	_pivot = Vector3.ZERO if part == "body" else _base * _xf * pivot
	_pivots[part] = _pivot


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
#  REBUILD (editor preview)
# ═════════════════════════════════════════════════════════════════════════════
func _rebuild() -> void:
	_dirty = false
	_split = false
	_pivot = Vector3.ZERO
	var mi := _internal_child("_PS1Mesh", func(): return MeshInstance3D.new()) as MeshInstance3D
	var tags := _internal_child("_PS1NameTags", func(): return Node3D.new()) as Node3D
	for c in tags.get_children():
		tags.remove_child(c)
		c.queue_free()

	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tris = 0

	if show_whole_cast:
		_new_atlas(Vector2i(CELL.x * 10, CELL.y * 2))
		for i in Character.size():
			var col := i % 10
			var row := floori(i / 10.0)
			_set_cell(Vector2i(col * CELL.x, row * CELL.y))
			_base = Transform3D(Basis(), Vector3((col - 4.5) * 1.0, 0.0, -row * 1.8))
			_build_character(i)
			_add_name_tag(tags, i)
	else:
		_new_atlas(CELL)
		_set_cell(Vector2i.ZERO)
		_base = Transform3D.IDENTITY
		_build_character(character)

	_st.index()
	var mesh := _st.commit()
	mi.mesh = mesh
	mi.material_override = _make_material(ImageTexture.create_from_image(_atlas), snap_resolution)
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
func _make_material(face: Texture2D, snap: Vector2) -> Material:
	var grain := _grain_texture()
	if not vertex_jitter:
		# The baseline PS1 material: Gouraud, nearest, no specular; the painted
		# face / clothes texture rides on UV2 as a detail layer.
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
		std.detail_enabled = true
		std.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		std.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
		std.detail_albedo = face
		return std

	# Same look, plus vertex snapping / affine warping / dithering / colour depth.
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PS1_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	sm.set_shader_parameter("grain_tex", grain)
	sm.set_shader_parameter("face_tex", face)
	sm.set_shader_parameter("snap_resolution", snap)
	sm.set_shader_parameter("affine_amount", affine_warp)
	sm.set_shader_parameter("color_levels", float((1 << color_depth_bits) - 1))
	sm.set_shader_parameter("dither_amount", dither)
	return sm


static func _grain_texture() -> ImageTexture:
	# 16×16 greyscale cloth/skin grain — multiplied with the vertex colour.
	if _grain_tex != null:
		return _grain_tex
	var rng := RandomNumberGenerator.new()
	rng.seed = 1997
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var v := 0.8 + 0.2 * rng.randf()   # gritty, worn-cloth noise
			if rng.randf() < 0.08:
				v -= 0.14
			img.set_pixel(x, y, Color(v, v, v))
	_grain_tex = ImageTexture.create_from_image(img)
	return _grain_tex


func _new_atlas(size: Vector2i) -> void:
	_atlas = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	_atlas.fill(Color(0, 0, 0, 0))


func _set_cell(origin: Vector2i) -> void:
	_cell = origin
	_no_uv = _cell_uv(0.5, 0.5)   # column 0 of every cell stays transparent


## Pixel position inside the current cell -> atlas UV.
func _cell_uv(px: float, py: float) -> Vector2:
	return Vector2((_cell.x + px) / float(_atlas.get_width()),
		(_cell.y + py) / float(_atlas.get_height()))


## Head-local point -> face texture UV (front projection), or NO_TEX.
func _face_uv(x: float, y: float, front: bool) -> Vector2:
	if not front:
		return NO_TEX
	return _cell_uv(clampf(1.0 + (x / FACE_W + 0.5) * 62.0, 0.5, 63.5),
		clampf((1.0 - y / FACE_H) * 64.0, 0.5, 63.5))


## Body-local point -> clothes texture UV (front projection), or NO_TEX.
func _torso_uv(x: float, y: float, front: bool) -> Vector2:
	if not front:
		return NO_TEX
	return _cell_uv(clampf(1.0 + (x / _torso_tw + 0.5) * 62.0, 0.5, 63.5),
		clampf(64.0 + (1.0 - (y - 0.80) / 0.70) * 64.0, 64.5, 127.5))


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
		"cross": false, "dirty": false, "patched": false, "collar": false,
		"mole": 0.0,   # a dark mole on a cheek: +1 = character's left, -1 = right
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
		Character.DECLAN:            # the priest who keeps the vigil with Ronan
			o = {"height": 1.03, "girth": 0.96, "skin": SKIN_OLD, "head_w": 0.108, "jaw": 0.84,
				"hair": HAIR_GREY, "hair_style": "slick", "wrinkles": true, "top": "coat",
				"top_col": CLOTH_BLACK, "shirt_col": Color(0.12, 0.12, 0.13), "collar": true,
				"pants_col": CLOTH_BLACK, "shoe_col": Color(0.05, 0.05, 0.05), "cross": true,
				"glasses": true, "expr": "kind", "pose": "clasp"}
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
	var key: String = Character.keys()[id]
	p["eye_col"] = EYE_COLS.get(key, EYE_BROWN)
	p.merge(_overrides, true)
	_stack.clear()
	_grain = CLOTH_GRAIN
	_torso_tw = 0.5 * float(p.girth) + (0.06 if p.oversized else 0.0)
	var photo := _face_photo(key)
	p["photo"] = photo != null
	if photo != null:
		p["skin"] = _photo_skin(photo)   # neck, ears and hands match the photo
		p["glasses"] = false             # the picture already shows the real face
	_rng.seed = hash(key)
	_paint_face(p)
	if photo != null:
		_paste_face(photo)
	_paint_marks(p)
	_paint_clothes(p)
	_rng.seed = hash(key + "/mesh")
	_xf = Transform3D(Basis.from_scale(Vector3(1.0, float(p.height), 1.0)), Vector3.ZERO)

	_use_part("body")
	_build_lower_body(p)
	_use_part("body")

	var hunch_deg: float = float(p.hunch) * 45.0
	_push(_rot_about(Vector3(0, 0.95, -0.04), Vector3(hunch_deg, 0, 0)))   # bend at waist
	_build_torso(p)
	var hands := _build_arms(p)
	_push(_rot_about(Vector3(0, Y_NECK, 0), Vector3(-hunch_deg * 0.8, 0, 0)))  # look up again
	_build_head(p)
	_pop()
	_pop()

	_use_part("body")
	_build_props(p, hands)


## Torso cross-sections, hips to neck: Vector4(y, half-width, half-depth, centre z).
func _torso_rings(p: Dictionary) -> Array:
	var g: float = p.girth
	var belly: float = p.belly
	var over := 0.018 if p.oversized else 0.0
	var src: Array
	if p.female:
		src = [[0.86, 0.150, 0.105, 0.0], [0.93, 0.172, 0.112, 0.0], [1.04, 0.128, 0.088, 0.0],
			[1.15, 0.134, 0.094, 0.008], [1.25, 0.150, 0.118, 0.016], [1.34, 0.158, 0.100, 0.006],
			[1.405, 0.150, 0.085, 0.0], [1.445, 0.090, 0.065, -0.005], [1.475, 0.045, 0.042, -0.005]]
	else:
		src = [[0.80, 0.105, 0.080, 0.0], [0.88, 0.165, 0.100, 0.0], [0.97, 0.158, 0.098, 0.0],
			[1.06, 0.152, 0.098, 0.0], [1.17, 0.166, 0.106, 0.004], [1.28, 0.182, 0.112, 0.008],
			[1.375, 0.192, 0.100, 0.0], [1.435, 0.120, 0.078, -0.006], [1.475, 0.050, 0.048, -0.006]]
	var out: Array = []
	for i in src.size():
		var r: Array = src[i]
		var y: float = r[0]
		var last := i == src.size() - 1
		var k := lerpf(1.0, g, 0.4) if last else g
		var bw := clampf(1.0 - absf(y - 1.07) / 0.17, 0.0, 1.0)   # where a belly sits
		var o := over if (y >= 0.95 and not last) else 0.0
		out.append(Vector4(y, float(r[1]) * k + o + belly * bw * 0.3,
			float(r[2]) * k + o + belly * bw, float(r[3]) + belly * bw * 0.6))
	return out


func _chest_w(p: Dictionary) -> float:
	return _ring_at(_torso_rings(p), 1.28).y * 2.0


func _build_lower_body(p: Dictionary) -> void:
	var g: float = p.girth
	var pants: Color = p.pants_col
	var shoe: Color = p.shoe_col
	var boots: String = p.get("boots", "")
	var rings := _torso_rings(p)

	if p.female:
		var tc: Color = p.top_col
		var hip := _ring_at(rings, 0.93)
		_use_part("knee", Vector3(0, KNEE_Y, 0))
		for s: float in SIDES:
			var x := s * 0.062
			_tube([Vector3(x, 0.52, 0.0), Vector3(x, 0.30, 0.004), Vector3(x, 0.075, 0.0)],
				[Vector2(0.040, 0.040), Vector2(0.036, 0.037), Vector2(0.027, 0.028)], 6,
				[pants, pants, pants], Vector3.RIGHT, false, false)
			_shoe(x, 0.025, 0.88, shoe, boots)
		# skirt: the upper half rides on the thighs (a lap when seated),
		# the lower half hangs from the knees
		var top := Vector4(0.93, hip.y + 0.012, hip.z + 0.012, hip.w)
		var knee_r := Vector4(KNEE_Y, top.y * 1.22, top.z * 1.3, 0.01)
		var hem := Vector4(0.10, top.y * 1.42, top.z * 1.55, 0.02)
		_drape([knee_r, hem], 0.0, TAU, 10, [tc, tc.darkened(0.06)], tc.darkened(0.45), true, true)
		if boots == "mud":   # splashes on the hem from the bog road
			for i in 5:
				var y := _rng.randf_range(0.11, 0.2)
				var k := (KNEE_Y - y) / (KNEE_Y - 0.10)
				var z := lerpf(knee_r.z, hem.z, k) + lerpf(knee_r.w, hem.w, k) + 0.004
				_box(Vector3(_rng.randf_range(-0.09, 0.09), y, z),
					Vector3(_rng.randf_range(0.03, 0.06), _rng.randf_range(0.02, 0.045), 0.01),
					C_MUD_WET.lerp(C_MUD_CAKED, _rng.randf()))
		_use_part("legs", Vector3(0, HIP_Y, 0))
		var mid := top.lerp(knee_r, 0.5)
		_drape([top, mid, knee_r], 0.0, TAU, 10, [tc, tc, tc], tc.darkened(0.45), true, true)
		if p.apron:
			var lift := Vector4(0.0, 0.007, 0.007, 0.0)
			_drape([Vector4(0.95, top.y, top.z, top.w) + lift, mid + lift,
				Vector4(0.52, lerpf(top.y, knee_r.y, 0.9), lerpf(top.z, knee_r.z, 0.9), knee_r.w) + lift],
				-0.26 * PI, 0.26 * PI, 4, [C_APRON, C_APRON, C_APRON.darkened(0.05)],
				C_APRON.darkened(0.3), true, false)
		_use_part("body")
		return

	var lx := 0.085 + 0.03 * (g - 1.0)
	var tr := 0.078 * lerpf(1.0, g, 0.7)
	for s: float in SIDES:
		var x := s * lx
		_use_part("legs", Vector3(0, HIP_Y, 0))
		_tube([Vector3(x, 0.93, 0.0), Vector3(x, 0.70, 0.006), Vector3(x, 0.47, 0.004)],
			[Vector2(tr, tr * 0.95), Vector2(tr * 0.86, tr * 0.86), Vector2(0.056, 0.056)], 6,
			[pants, pants, pants], Vector3.RIGHT, false, true)
		_use_part("knee", Vector3(0, KNEE_Y, 0))
		var boot: bool = p.tall_boots
		var leg := shoe if boot else pants.darkened(0.06)
		var rr := 1.1 if boot else 1.0
		_tube([Vector3(x, 0.49, 0.004), Vector3(x, 0.30, -0.004), Vector3(x, 0.07, 0.0)],
			[Vector2(0.056, 0.056) * rr, Vector2(0.05, 0.052) * rr, Vector2(0.038, 0.04) * rr], 6,
			[leg, leg, leg], Vector3.RIGHT, true, false)
		if boot:   # turned-down cuff
			_tube([Vector3(x, 0.505, 0.004), Vector3(x, 0.445, 0.004)],
				[Vector2(0.068, 0.07), Vector2(0.066, 0.068)], 6,
				[shoe.lightened(0.15), shoe.lightened(0.15)], Vector3.RIGHT, false, false)
		_shoe(x, 0.0, 1.0, shoe, boots)
		if boots == "mud":   # splashes up the shins
			for i in 3:
				_decal(Vector3(x + _rng.randf_range(-0.02, 0.02), _rng.randf_range(0.12, 0.24),
					0.05 * rr + EPS), _rng.randf_range(0.02, 0.035), _rng.randf_range(0.018, 0.03),
					C_MUD_WET.lerp(C_MUD_CAKED, _rng.randf()), _rng.randf_range(-30.0, 30.0))
	_use_part("body")

	if p.top == "coat":
		# frock-coat skirt, open at the front; rides on the thighs so a seated
		# guest's coat drapes over the lap
		_use_part("legs", Vector3(0, HIP_Y, 0))
		var tc: Color = p.top_col
		var w := _ring_at(rings, 0.97)
		var r0 := Vector4(0.99, w.y + 0.022, w.z + 0.02, w.w)
		var r1 := Vector4(0.45, r0.y * 1.24, r0.z * 1.2, w.w)
		_drape([r0, r1], 0.17 * PI, 1.83 * PI, 10, [tc, tc.darkened(0.05)], tc.darkened(0.45), true, false)
		_use_part("body")


## Low-poly shoe: a loft from heel to toe with a flat sole. Mud cakes the sole of
## a real guest's boots (the "clean_boots" tell); a double's are polished.
func _shoe(x: float, z0: float, sc: float, col: Color, boots: String) -> void:
	const STATIONS := [[-0.05, 0.034, 0.075], [0.0, 0.042, 0.085], [0.07, 0.045, 0.068],
		[0.13, 0.04, 0.048]]
	const N := 8
	var mud := boots == "mud"
	var pts: Array = []
	var cols: Array = []
	var heel := Vector3(x, 0.04 * sc, z0 - 0.06 * sc)
	pts.append(_repeat(heel, N))
	cols.append(_repeat(col, N))
	for stn: Array in STATIONS:
		var z: float = z0 + float(stn[0]) * sc
		var hw: float = float(stn[1]) * sc
		var h: float = float(stn[2]) * sc
		var row: Array = []
		var crow: Array = []
		for k in N:
			var a := TAU * (k + 0.5) / N
			var v := Vector3(x + sin(a) * hw, maxf(0.003, h * 0.5 * (1.0 + cos(a))), z)
			row.append(v)
			crow.append(C_MUD_CAKED if (mud and v.y < 0.046 * sc) else col)
		pts.append(row)
		cols.append(crow)
	pts.append(_repeat(Vector3(x, 0.02 * sc, z0 + 0.158 * sc), N))
	cols.append(_repeat(col, N))
	_surface(pts, cols, [], true, Vector3(x, 0.035 * sc, z0 + 0.04 * sc))
	if mud:
		_box(Vector3(x + 0.004, 0.06 * sc, z0 + 0.08 * sc), Vector3(0.07, 0.016, 0.08) * sc, C_MUD_WET,
			Vector3(-18, 0, 0))
		_decal(Vector3(x, 0.03 * sc, z0 + 0.15 * sc), 0.06 * sc, 0.035 * sc, C_MUD_WET)   # caked toe
	elif boots == "clean":
		_box(Vector3(x - 0.008 * sc, 0.067 * sc, z0 + 0.06 * sc), Vector3(0.03, 0.005, 0.045) * sc,
			C_SHINE, Vector3(-15, 0, 0))


func _build_torso(p: Dictionary) -> void:
	var female: bool = p.female
	var top: String = p.top
	var pants: Color = p.pants_col
	var body_col: Color = p.shirt_col if (top == "shirt" or top == "cloak") else p.top_col
	var rings := _torso_rings(p)
	var rows: Array = rings.duplicate()
	if not female:
		# a crisp hem where the shirt / coat meets the trousers
		var hem := 0.86 if top == "jacket" else 0.97
		rows.append(_ring_at(rings, hem - 0.014))
		rows.append(_ring_at(rings, hem))
		rows.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.x < b.x)
	var cols: Array = []
	var hem_y := 0.86 if top == "jacket" else 0.97
	for r: Vector4 in rows:
		cols.append(pants if (not female and r.x < hem_y - 0.001) else body_col)
	var first: Vector4 = rows[0]
	rows.insert(0, Vector4(first.x - 0.025, 0.0, 0.0, first.w))
	cols.insert(0, cols[0])
	rows.append(Vector4(1.49, 0.0, 0.0, -0.006))
	cols.append(body_col)
	_drape(rows, 0.0, TAU, 10, cols, Color.BLACK, false, true, true)

	# neck
	_grain = SKIN_GRAIN
	var nr := (0.038 if female else 0.045) * lerpf(1.0, float(p.girth), 0.3)
	_tube([Vector3(0, 1.41, -0.008), Vector3(0, 1.53, -0.012)], [Vector2(nr, nr), Vector2(nr, nr) * 0.95],
		6, [p.skin, p.skin], Vector3.RIGHT, false, false)
	_grain = CLOTH_GRAIN

	var tc: Color = p.top_col
	var sh := _ring_at(rings, 1.375)
	if top == "shirt" or top == "cloak":
		var w := _ring_at(rings, 0.975)
		_drape([Vector4(0.995, w.y + 0.007, w.z + 0.007, w.w), Vector4(0.955, w.y + 0.007, w.z + 0.007, w.w)],
			0.0, TAU, 10, [C_BELT, C_BELT], Color.BLACK, false, true)
		_box(Vector3(0, 0.975, w.w + w.z + 0.01), Vector3(0.03, 0.03, 0.008), C_BRASS)
	if top == "coat" or top == "jacket":   # turned-up collar behind the neck
		_drape([Vector4(1.505, 0.064, 0.06, -0.008), Vector4(1.44, 0.08, 0.072, -0.004)],
			0.24 * PI, 1.76 * PI, 8, [tc, tc.darkened(0.08)], tc.darkened(0.4), true, false)

	if top == "cloak":
		var lo := Vector4(0.33, (sh.y + 0.07) * 1.25, (sh.z + 0.07) * 1.25, -0.03)
		_drape([Vector4(1.43, sh.y + 0.035, sh.z + 0.04, -0.01), Vector4(0.90, sh.y + 0.07, sh.z + 0.07, -0.02),
			lo], 0.42 * PI, 1.58 * PI, 8, [tc, tc, tc.darkened(0.06)], tc.darkened(0.45), true, false)
		_drape([Vector4(1.49, 0.07, 0.065, -0.006), Vector4(1.40, sh.y + 0.04, sh.z + 0.045, 0.0),
			Vector4(1.27, sh.y + 0.06, sh.z + 0.06, 0.0)], 0.14 * PI, 1.86 * PI, 10,
			[tc.lightened(0.04), tc.lightened(0.04), tc], tc.darkened(0.45), true, false)
		_tube([Vector3(-0.09, 1.46, -0.09), Vector3(0, 1.495, -0.125), Vector3(0.09, 1.46, -0.09)],
			[Vector2(0.035, 0.035), Vector2(0.04, 0.04), Vector2(0.035, 0.035)], 6,
			[tc.darkened(0.1), tc.darkened(0.1), tc.darkened(0.1)], Vector3.UP, true, true)
		_box(Vector3(0, 1.445, 0.1), Vector3(0.03, 0.03, 0.02), C_BRASS)
		if p.dirty:
			for i in 8:
				var y := _rng.randf_range(0.42, 1.2)
				var k := (y - 0.90) / (0.33 - 0.90) if y < 0.90 else (1.43 - y) / (1.43 - 0.90)
				var rz := lerpf(sh.z + 0.07, lo.z, k) if y < 0.90 else lerpf(sh.z + 0.04, sh.z + 0.07, k)
				_box(Vector3(_rng.randf_range(-0.12, 0.12), y, -0.02 - rz - 0.008),
					Vector3(_rng.randf_range(0.05, 0.1), _rng.randf_range(0.04, 0.08), 0.012),
					C_MUD.lerp(tc, _rng.randf() * 0.4))

	if p.shawl:
		var sc: Color = p.shawl_col
		var ch := _ring_at(rings, 1.22)
		_drape([Vector4(1.495, 0.075, 0.068, -0.006), Vector4(1.40, sh.y + 0.03, sh.z + 0.035, 0.0),
			Vector4(1.20, ch.y + 0.035, ch.z + 0.035, ch.w)], 0.07 * PI, 1.93 * PI, 12,
			[sc, sc, sc.darkened(0.05)], sc.darkened(0.4), true, false)
		var tri_t := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.15)),
			Vector3(0, 1.08, ch.w - ch.z - 0.05))
		_prism_t(tri_t, 0.0, (ch.y + 0.03) / 0.707, 0.26, 4, sc, CAP_TOP)        # back point
		_box(Vector3(0, 1.20, ch.w + ch.z + 0.04), Vector3(0.05, 0.045, 0.03), sc.darkened(0.15))


func _build_arms(p: Dictionary) -> Dictionary:
	var g: float = p.girth
	var female: bool = p.female
	var top: String = p.top
	var skin: Color = p.skin
	var sh_ring := _ring_at(_torso_rings(p), Y_SHOULDER)
	var ar := (0.040 if female else 0.047) * lerpf(1.0, g, 0.5) * (1.25 if p.oversized else 1.0)
	var l1 := 0.28
	var l2 := 0.25 + (0.04 if p.oversized else 0.0)
	var sleeve: Color = p.top_col if top in ["coat", "jacket", "dress"] else p.shirt_col
	var cuff: Color = p.shirt_col if top == "coat" else sleeve.darkened(0.12)
	var hsz := (0.88 if female else 1.0) * (1.4 if p.big_hands else 1.0)
	var pose: Array = POSES.get(p.pose, POSES["rest"])
	var out := {}
	for s: float in SIDES:
		var idx := 0 if s > 0.0 else 2
		var up: Vector3 = pose[idx]
		var fo: Vector3 = pose[idx + 1]
		var sh := Vector3(s * (sh_ring.y - ar * 0.55), Y_SHOULDER, sh_ring.w)
		var ub := Basis.from_euler(Vector3(up.x * DEG, 0.0, s * up.z * DEG))
		var elbow := sh + ub * Vector3(0, -l1, 0)
		var fb := ub * Basis.from_euler(Vector3(fo.x * DEG, -s * fo.y * DEG, 0.0))
		var wrist := elbow + fb * Vector3(0, -l2, 0)
		_tube([sh + ub * Vector3(0, ar * 0.7, 0), sh, sh.lerp(elbow, 0.5), elbow, elbow.lerp(wrist, 0.5), wrist],
			[Vector2(ar * 0.5, ar * 0.5), Vector2(ar, ar * 1.05), Vector2(ar * 0.92, ar * 0.95),
				Vector2(ar * 0.82, ar * 0.85), Vector2(ar * 0.78, ar * 0.8), Vector2(ar * 0.66, ar * 0.7)], 6,
			[sleeve, sleeve, sleeve, sleeve, sleeve, sleeve], ub.x, true, false)
		if top == "coat" or top == "jacket":
			_tube([wrist + fb * Vector3(0, 0.03, 0), wrist + fb * Vector3(0, -0.004, 0)],
				[Vector2(ar * 0.74, ar * 0.78), Vector2(ar * 0.72, ar * 0.76)], 6, [cuff, cuff], fb.x, false, false)
		# hand: a mitten, palm toward the body, plus a thumb; a relaxed wrist
		# lets it hang a little lower than the forearm points
		var hd := (fb * Vector3(0, -1, 0)).lerp(Vector3.DOWN, 0.45).normalized()
		var hz := (fb.z - hd * fb.z.dot(hd)).normalized()
		_grain = SKIN_GRAIN
		_tube([wrist - hd * 0.006, wrist + hd * 0.068 * hsz, wrist + (hd * 0.122 + hz * 0.004) * hsz],
			[Vector2(0.02, 0.028) * hsz, Vector2(0.019, 0.034) * hsz, Vector2(0.012, 0.024) * hsz], 6,
			[skin, skin, skin.darkened(0.04)], fb.x, true, true)
		_tube([wrist + (hd * 0.022 + hz * 0.022) * hsz, wrist + (hd * 0.062 + hz * 0.038) * hsz],
			[Vector2(0.011, 0.011) * hsz, Vector2(0.008, 0.008) * hsz], 5, [skin, skin], fb.x, true, true)
		_grain = CLOTH_GRAIN
		out["L" if s > 0.0 else "R"] = _xf * (wrist + hd * 0.06 * hsz)   # model space
	return out


# ═════════════════════════════════════════════════════════════════════════════
#  HEAD (head-local space: y = 0 under the chin, face toward +Z)
# ═════════════════════════════════════════════════════════════════════════════
func _build_head(p: Dictionary) -> void:
	_use_part("head", Vector3(0, Y_NECK, 0))
	var hs: float = float(p.head_w) / 0.11 * (0.95 if p.female else 1.0)
	var hgt: float = p.height
	_push(Transform3D(Basis.from_scale(Vector3(hs, hs / hgt, hs)), Vector3(0, Y_CHIN, 0)))
	_jaw = clampf(float(p.jaw) / 0.86, 0.86, 1.14)
	_hollow = p.sunken_cheeks
	var skin: Color = p.skin
	_grain = SKIN_GRAIN

	var pts: Array = []
	var cols: Array = []
	var uvs: Array = []
	for ring: Array in HEAD_RINGS:
		var y: float = ring[0]
		var row: Array = []
		var crow: Array = []
		var urow: Array = []
		for c in 12:
			var a := TAU * c / 12.0
			var v := _head_at(a, y)
			row.append(v)
			crow.append(skin)
			urow.append(_face_uv(v.x, v.y, cos(a) > -0.05))
		pts.append(row)
		cols.append(crow)
		uvs.append(urow)
	_surface(pts, cols, uvs, true, Vector3(0, 0.12, 0))

	# nose: a small wedge, textured with the same face projection
	var m := _base * _xf
	var big := 1.25 if p.red_nose else 1.0
	var nt := Vector3(0, 0.150, 0.093)
	var np := Vector3(0, 0.102, 0.092 + 0.019 * big)
	var nl := Vector3(-0.012 * big, 0.098, 0.09)
	var nr := Vector3(0.012 * big, 0.098, 0.09)
	for t: Array in [[nt, nl, np, Vector3(-1, 0.2, 0.6)], [nt, np, nr, Vector3(1, 0.2, 0.6)],
			[nl, nr, np, Vector3(0, -1, 0.3)]]:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		_tri(m * a, m * b, m * c, m.basis * (t[3] as Vector3), skin,
			[_face_uv(a.x, a.y, true), _face_uv(b.x, b.y, true), _face_uv(c.x, c.y, true)])
	for s: float in SIDES:   # ears
		var ex := _head_at(s * PI * 0.5, 0.125).x + s * 0.004
		_box(Vector3(ex, 0.122, -0.008), Vector3(0.016, 0.05, 0.03), skin.darkened(0.06), Vector3(0, -s * 12.0, 0))

	_mouth_pos = _base * _xf * Vector3(0, 0.062, _head_at(0.0, 0.062).z + 0.02) - _pivot
	_chin = _xf * Vector3(0.035, 0.0, 0.05)
	_grain = CLOTH_GRAIN
	_build_facial_hair(p)
	_build_hair(p)
	_build_hat(p)
	if p.glasses:
		_build_glasses()
	_pop()


func _build_facial_hair(p: Dictionary) -> void:
	var fc: Color = p.facial_col
	var facial: String = p.facial
	match facial:
		"beard", "long_beard":
			_shell({"top_front": 0.036, "top_side": 0.15, "front": 0.0, "side": 0.0, "back": 0.0,
				"grow": 0.011, "bump": 0.006, "a_min": -0.6 * PI, "a_max": 0.6 * PI, "rows": 3, "cols": 10}, fc)
			if facial == "long_beard":
				_tube([Vector3(0, 0.02, 0.06), Vector3(0, -0.11, 0.068), Vector3(0, -0.24, 0.058)],
					[Vector2(0.055, 0.034), Vector2(0.045, 0.03), Vector2(0.018, 0.014)], 6,
					[fc, fc.darkened(0.06), fc.darkened(0.12)], Vector3.RIGHT, false, true)
		"pointed_beard":
			_shell({"top_front": 0.036, "top_side": 0.07, "front": 0.0, "side": 0.03, "back": 0.03,
				"grow": 0.009, "a_min": -0.4 * PI, "a_max": 0.4 * PI, "rows": 2, "cols": 8}, fc)
			_tube([Vector3(0, 0.012, 0.072), Vector3(0, -0.035, 0.074), Vector3(0, -0.075, 0.07)],
				[Vector2(0.03, 0.02), Vector2(0.016, 0.012), Vector2(0.003, 0.003)], 5,
				[fc, fc, fc.darkened(0.1)], Vector3.RIGHT, true, false)
		"moustache_big":
			for s: float in SIDES:
				_box(Vector3(s * 0.017, 0.078, 0.093), Vector3(0.032, 0.009, 0.012), fc, Vector3(0, 0, -s * 20.0))


func _build_hair(p: Dictionary) -> void:
	var col: Color = p.hair
	var hat: String = p.hat
	if hat == "bonnet" or hat == "headscarf":   # just a strip peeking out at the forehead
		_shell({"front": 0.19, "side": 0.17, "back": 0.17, "top": 0.216, "a_min": -0.3 * PI,
			"a_max": 0.3 * PI, "grow": 0.012, "rows": 1, "cols": 6}, col)
		return
	var style: String = p.hair_style
	_shell(HAIR_STYLES.get(style, HAIR_STYLES["short"]), col)
	if style == "bun":
		_tube([Vector3(0, 0.15, -0.098), Vector3(0, 0.153, -0.135), Vector3(0, 0.15, -0.168)],
			[Vector2(0.03, 0.03), Vector2(0.038, 0.038), Vector2(0.018, 0.018)], 7,
			[col, col.lightened(0.05), col], Vector3.RIGHT, true, true)
	elif style == "thinning" and hat == "none":   # a few combed-over strands on a bald crown
		for i in 3:
			_box(Vector3(-0.03 + i * 0.03, 0.251, -0.005), Vector3(0.006, 0.004, 0.14), col.lightened(0.06),
				Vector3(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-15.0, 15.0), 0))


func _build_hat(p: Dictionary) -> void:
	var c: Color = p.hat_col
	var hat: String = p.hat
	match hat:
		"cap":   # flat farmhand's cap
			_shell({"front": 0.205, "side": 0.15, "back": 0.11, "grow": 0.024, "streak": 0.0,
				"cols": 12, "rows": 3}, c)
			_box(Vector3(0, 0.205, 0.12), Vector3(0.13, 0.008, 0.075), c.darkened(0.15), Vector3(-8, 0, 0))
			_box(Vector3(0, 0.284, -0.01), Vector3(0.018, 0.01, 0.018), c.darkened(0.2))
		"old_hat":   # battered felt hat, jauntily tilted
			_push(_rot_about(Vector3(0, 0.22, 0), Vector3(4, 0, 6)))
			var oval := Basis.from_scale(Vector3(1.0, 1.0, 1.15))
			_prism_t(Transform3D(oval, Vector3(0, 0.222, -0.006)), 0.165, 0.158, 0.012, 9, c)
			_prism_t(Transform3D(oval, Vector3(0, 0.243, -0.008)), 0.094, 0.093, 0.03, 8, c.darkened(0.35), CAP_NONE)
			_prism_t(Transform3D(oval, Vector3(0, 0.282, -0.008)), 0.096, 0.074, 0.05, 8, c, CAP_TOP)
			_box(Vector3(0, 0.305, -0.008), Vector3(0.018, 0.01, 0.11), c.darkened(0.2))   # pinched crown
			_box(Vector3(0.05, 0.27, 0.07), Vector3(0.04, 0.03, 0.01), c.lightened(0.08), Vector3(0, 30, 0))
			_pop()
		"bonnet":   # linen bonnet with a frilled brim and chin ribbons
			_shell({"front": 0.215, "side": 0.04, "back": 0.01, "grow": 0.024, "cols": 14, "rows": 4,
				"streak": 0.03, "double": true}, c)
			_arch(Vector3(0, 0.13, 0.078), Vector2(0.086, 0.122), Vector2(0.104, 0.138), 0.012,
				-0.6 * PI, 0.6 * PI, 10, c.lightened(0.06))
			for s: float in SIDES:
				_box(Vector3(s * 0.05, 0.0, 0.06), Vector3(0.012, 0.09, 0.008), c.darkened(0.1), Vector3(0, 0, s * 30.0))
			_box(Vector3(0, -0.035, 0.07), Vector3(0.035, 0.022, 0.016), c)
		"headscarf":   # black scarf round the face, knotted under the chin
			_shell({"front": 0.205, "side": -0.03, "back": -0.06, "grow": 0.02, "fall": true, "cols": 14,
				"rows": 5, "streak": 0.03}, c)
			_arch(Vector3(0, 0.075, 0.03), Vector2(0.07, 0.085), Vector2(0.088, 0.105), 0.012,
				0.62 * PI, 1.38 * PI, 6, c)
			_box(Vector3(0, -0.03, 0.075), Vector3(0.04, 0.03, 0.028), c.lightened(0.05))
			_box(Vector3(0.018, -0.07, 0.07), Vector3(0.022, 0.06, 0.012), c, Vector3(0, 0, 15))


func _build_glasses() -> void:
	var gz := 0.108
	for s: float in SIDES:
		_ring(Vector3(s * 0.032, 0.14, gz), 0.019, 0.015, 7, C_METAL)
		_box(Vector3(s * 0.0625, 0.143, gz - 0.004), Vector3(0.024, 0.004, 0.004), C_METAL)
		_box(Vector3(s * 0.077, 0.143, gz * 0.45), Vector3(0.004, 0.004, gz * 1.1), C_METAL)
		_decal(Vector3(s * 0.032 - 0.007, 0.148, gz + 0.001), 0.005, 0.005, Color(0.92, 0.92, 0.88))
	_box(Vector3(0, 0.146, gz + 0.002), Vector3(0.026, 0.004, 0.004), C_METAL)


# ═════════════════════════════════════════════════════════════════════════════
#  PAINTED TEXTURES (64×64 face + 64×64 clothes front per villager)
# ═════════════════════════════════════════════════════════════════════════════
## A colour as it will look next to vertex-coloured surfaces at model height y.
func _tex(c: Color, y: float, grain := SKIN_GRAIN) -> Color:
	var f := _final_color(c, Vector3(0, y, 0))
	var grey := f.r * 0.3 + f.g * 0.59 + f.b * 0.11
	var k := 1.0 - 0.11 * grain * (1.0 - 0.55 * grey)
	return Color(f.r * k, f.g * k, f.b * k)


func _fx(x: float) -> float:
	return 1.0 + (x / FACE_W + 0.5) * 62.0


func _fy(y: float) -> float:
	return (1.0 - y / FACE_H) * 64.0


func _tx(x: float) -> float:
	return 1.0 + (x / _torso_tw + 0.5) * 62.0


func _ty(y: float) -> float:
	return 64.0 + (1.0 - (y - 0.80) / 0.70) * 64.0


func _paint_face(p: Dictionary) -> void:
	var e := _expr(p.expr)
	var female: bool = p.female
	_clip = Rect2i(1, 0, 62, 64)
	var skin := _tex(p.skin, 1.6)
	var hair: Color = p.hair
	for y in 64:   # base skin: darker toward the sides, under the jaw and at the hairline
		for x in range(1, 63):
			var u := (x + 0.5 - 32.0) / 31.0
			var k := 1.0 - 0.16 * u * u
			if y >= 58:
				k *= 0.88
			elif y < 9:
				k *= 0.94
			k *= 1.0 + _rng.randf_range(-0.025, 0.025)
			_px(x, y, Color(skin.r * k, skin.g * k, skin.b * k))
	if p.photo:
		return   # the face picture supplies the features

	var cx := 32.0
	var ey := _fy(0.140)
	var ny := _fy(0.098)
	var my := _fy(0.062)
	var eo := 11.0
	var lash := _tex(C_LASH, 1.6, 0.0)
	var sclera := _tex(C_EYE_WHITE, 1.6, 0.0)
	var iris := _tex(p.eye_col, 1.6, 0.0)
	var shade := skin.darkened(0.16)

	# sockets, sunken eyes, dark circles
	for s: float in SIDES:
		var x := cx + s * eo
		_pell(x, ey - 1.0, 6.5, 3.6, shade, 0.55)
		if p.sunken_eyes:
			_pell(x, ey, 7.0, 5.0, skin.darkened(0.3).lerp(_tex(C_BRUISE, 1.6), 0.3), 0.7)
		if p.dark_circles:
			_pell(x, ey + 2.6, 5.0, 1.6, skin.darkened(0.25).lerp(_tex(C_BRUISE, 1.6), 0.5), 0.75)

	# cheeks, age, freckles
	if p.rosy:
		for s: float in SIDES:
			_pell(cx + s * 12.0, ny - 2.0, 4.5, 2.5, _tex(C_ROSY, 1.6), 0.35)
	if p.sunken_cheeks:
		for s: float in SIDES:
			_pell(cx + s * 13.0, ny + 3.0, 3.0, 5.0, skin.darkened(0.25), 0.5)
	if p.wrinkles:
		var wc := skin.darkened(0.22)
		for wy: float in [12.0, 15.0]:
			_pline(cx - 9.0, wy, cx + 9.0, wy, wc, 0.7)
		for s: float in SIDES:
			_pline(cx + s * 16.5, ey - 1.0, cx + s * 18.5, ey - 2.5, wc, 0.7)
			_pline(cx + s * 16.5, ey + 1.0, cx + s * 18.5, ey + 2.5, wc, 0.7)
			_pline(cx + s * 6.5, ny + 1.0, cx + s * 9.0, ny + 8.0, wc, 0.45)
	if p.freckles:
		for i in 12:
			_px(cx + _rng.randf_range(-14.0, 14.0), _rng.randf_range(ey + 3.0, ny + 3.0), _tex(C_FRECKLE, 1.6), 0.5)

	# eyes
	var ew := 4.2 * float(e.eye_w)
	var eh := clampf(float(e.eye_h) / 0.022 * 1.55, 0.5, 2.9)
	var ir := 1.7 if float(e.pupil) >= 0.013 else 1.25
	for s: float in SIDES:
		var x := cx + s * eo
		if eh < 0.95:   # squint / shut
			_pline(x - ew, ey, x + ew, ey, lash, 1.0, 1)
			continue
		_pell(x, ey, ew, eh, sclera)
		var look: Vector2 = e.look
		if e.goofy:   # pupils that don't quite agree with each other
			look = Vector2(0.55, 0.45) if s > 0.0 else Vector2(-0.2, -0.35)
		var ix := x + look.x * (ew - ir) * 0.7
		var iy := ey - look.y * maxf(eh - ir, 0.0)
		_pell(ix, iy, ir, minf(ir, eh), iris)
		_px(ix, iy, lash)
		_pline(x - ew - 0.3, ey - eh, x + ew + 0.3, ey - eh, lash)   # upper lid
		if female:
			_pline(x - ew, ey - eh - 1.0, x + ew + 0.5, ey - eh - 1.0, lash, 0.6)
			_px(x + s * (ew + 1.0), ey - eh - 1.0, lash)
		_pline(x - ew + 1.0, ey + eh + 0.5, x + ew - 1.0, ey + eh + 0.5, skin.darkened(0.2), 0.6)

	# brows
	var brow := _tex(hair.darkened(0.2), 1.6, 0.0)
	for s: float in SIDES:
		var raise := (float(e.raise) + (float(e.asym) if s > 0.0 else 0.0)) / FACE_H * 64.0 * 0.8
		var tilt := sin(float(e.brow) * DEG) * 5.0
		var by := ey - 5.5 - raise
		_pline(cx + s * 4.5, by + tilt, cx + s * 15.0, by - tilt * 0.4, brow, 1.0, 1 if female else 2)

	# nose
	_pline(cx - 2.5, ey + 1.0, cx - 2.0, ny - 1.0, skin.darkened(0.12), 0.7)
	_pline(cx - 3.0, ny + 1.0, cx + 3.0, ny + 1.0, skin.darkened(0.2), 0.8)
	_px(cx - 2.0, ny + 0.5, skin.darkened(0.45))
	_px(cx + 1.0, ny + 0.5, skin.darkened(0.45))
	_px(cx, ny - 1.5, skin.lightened(0.08))
	if p.red_nose:
		_pell(cx, ny - 1.0, 3.2, 2.6, _tex(C_RED_NOSE, 1.6), 0.75)

	# beards and stubble go under the mouth, moustaches over it
	var fc := _tex(p.facial_col, 1.55, 0.6)
	var facial: String = p.facial
	var mw := 7.0
	match facial:
		"stubble":
			for y in range(int(ny + 2.0), 63):
				for x in range(14, 51):
					if _rng.randf() < 0.35 and not (absf(y - my) < 1.5 and absf(x - cx) < mw):
						_px(x, y, fc, 0.25)
		"beard", "long_beard":
			for y in range(int(ey + 4.0), 64):
				for x in range(1, 63):
					var side := absf(x + 0.5 - cx)
					var low := y > my + 1.5 + _rng.randf_range(-0.6, 0.6)
					var burn := side > 19.0 - maxf(y - ny, 0.0) * 0.6 + _rng.randf_range(-1.0, 1.0)
					if (low or burn) and side < 28.0:
						_px(x, y, fc * _rng.randf_range(0.88, 1.08))
		"pointed_beard":
			for y in range(int(my + 2.0), 64):
				for x in range(int(cx - 8.0), int(cx + 8.0)):
					_px(x, y, fc * _rng.randf_range(0.88, 1.08))
	_paint_mouth(e.mouth, cx, my, mw, skin, female)
	match facial:
		"moustache", "beard", "long_beard", "pointed_beard":
			for s: float in SIDES:
				_pline(cx + s * 1.0, my - 2.6, cx + s * 8.0, my - 0.5, fc, 1.0, 2)
		"moustache_big":
			for s: float in SIDES:
				_pline(cx + s * 1.0, my - 3.0, cx + s * 9.5, my + 0.5, fc, 1.0, 3)
		"small_moustache":
			_pline(cx - 4.0, my - 2.2, cx + 4.0, my - 2.2, fc, 1.0, 2)


## A face picture for a villager, if one exists: res://assets/faces/<name>.png
## (or .jpg / .webp), e.g. sultan_esmagzam.png. It is laid over the painted
## face, so transparent pixels fall back to it. Layout (any size, stretched to
## 62×64): eyes 22 % of the width apart on row 46 %, mouth on row 76 %, chin
## at the bottom edge.
func _face_photo(key: String) -> Image:
	for ext: String in ["png", "jpg", "jpeg", "webp"]:
		var path := FACE_DIR + key.to_lower() + "." + ext
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != 62 or img.get_height() != 64:
			img.resize(62, 64, Image.INTERPOLATE_BILINEAR)
		return img
	return null


## Average cheek colour of a face picture.
func _photo_skin(img: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(32, 45):
		for x: int in [11, 13, 15, 17, 19, 42, 44, 46, 48, 50]:
			var c := img.get_pixel(x, y)
			if c.a > 0.95:
				sum += Color(c.r, c.g, c.b, 0)
				n += 1
	if n == 0:
		return SKIN_FAIR
	return Color(sum.r / n, sum.g / n, sum.b / n)


func _paste_face(img: Image) -> void:
	_clip = Rect2i(1, 0, 62, 64)
	for y in 64:
		for x in 62:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				_px(x + 1, y, _tex(Color(c.r, c.g, c.b), 1.6), c.a)


## Marks painted over any face, painted or photo: a mole on one cheek.
func _paint_marks(p: Dictionary) -> void:
	var side: float = p.get("mole", 0.0)
	if is_zero_approx(side):
		return
	_clip = Rect2i(1, 0, 62, 64)
	var mx := 32.0 + signf(side) * 13.0
	var my := _fy(0.090)
	var c := _tex(Color(0.22, 0.13, 0.09), 1.6, 0.0)
	_pell(mx, my, 1.4, 1.4, c)


func _paint_mouth(kind: String, cx: float, my: float, mw: float, skin: Color, female: bool) -> void:
	var lip := skin.darkened(0.15).lerp(_tex(Color(0.66, 0.28, 0.26), 1.6), 0.5 if female else 0.28)
	var ld := lip.darkened(0.4)
	var dark := _tex(C_MOUTH, 1.6, 0.0)
	_px(cx, my - 3.0, skin.darkened(0.08))   # philtrum
	match kind:
		"line":
			_pline(cx - mw, my, cx + mw, my, ld)
			_pline(cx - 4.0, my + 1.0, cx + 4.0, my + 1.0, lip, 0.7)
		"small":
			_pline(cx - 4.0, my, cx + 4.0, my, ld)
			_pline(cx - 2.5, my + 1.0, cx + 2.5, my + 1.0, lip, 0.7)
		"smile", "frown":
			var d := -1.5 if kind == "smile" else 1.5
			_pline(cx - mw, my + d, cx - 3.0, my, ld)
			_pline(cx - 3.0, my, cx + 3.0, my, ld)
			_pline(cx + 3.0, my, cx + mw, my + d, ld)
			_pline(cx - 3.0, my + 1.0, cx + 3.0, my + 1.0, lip, 0.7)
		"open":
			_pell(cx, my + 0.5, 4.5, 2.6, dark)
			_pline(cx - 3.0, my + 3.2, cx + 3.0, my + 3.2, lip, 0.8)
		"open_small":
			_pell(cx, my + 0.5, 3.0, 1.8, dark)
		"singing":
			_pell(cx, my + 0.8, 3.6, 3.2, dark)
			_pline(cx - 2.5, my - 2.3, cx + 2.5, my - 2.3, ld)
		"grin":
			_pell(cx, my + 0.3, 6.5, 2.2, dark)
			_pline(cx - 5.0, my - 0.6, cx + 5.0, my - 0.6, _tex(C_TEETH, 1.6, 0.0))
		"smirk":
			_pline(cx - mw, my + 0.6, cx + mw, my - 1.4, ld)
			_pline(cx - 3.0, my + 1.3, cx + 3.0, my + 0.6, lip, 0.7)
		"wavy":
			for i in 4:
				var up := 0.8 if i % 2 == 0 else -0.8
				_pline(cx - mw + i * 3.5, my + up, cx - mw + (i + 1) * 3.5, my - up, ld)


func _paint_clothes(p: Dictionary) -> void:
	_clip = Rect2i(1, 64, 62, 64)
	var top: String = p.top
	var tc := _tex(p.top_col, 1.15, 1.0)
	var sc := _tex(p.shirt_col, 1.25, 1.0)
	match top:
		"shirt", "cloak":
			_pline(_tx(0.0), _ty(1.45), _tx(0.0), _ty(0.99), sc.darkened(0.2))
			for i in 4:
				_px(_tx(0.01), _ty(1.40 - i * 0.09), _tex(C_BONE, 1.2, 0.0))
			for s: float in SIDES:
				_pline(_tx(s * 0.012), _ty(1.47), _tx(s * 0.05), _ty(1.425), sc.darkened(0.15), 1.0, 2)
		"waistcoat":
			_v_fill(1.475, 1.19, 0.075, 0.0, sc)
			for s: float in SIDES:
				_pline(_tx(s * 0.012), _ty(1.47), _tx(s * 0.05), _ty(1.43), sc.darkened(0.15), 1.0, 2)
				_pline(_tx(s * 0.06), _ty(1.04), _tx(s * 0.11), _ty(1.04), tc.darkened(0.35))
				_pline(_tx(s * 0.01), _ty(0.97), _tx(s * 0.06), _ty(0.99), tc.darkened(0.3))
			_pline(_tx(0.0), _ty(1.19), _tx(0.0), _ty(0.97), tc.darkened(0.35))
			for i in 4:
				var bx := 0.014 + (0.022 if p.rumpled and i == 2 else 0.0)   # one in the wrong hole
				_px(_tx(bx), _ty(1.16 - i * 0.055), _tex(C_BRASS, 1.1, 0.0))
			if p.rumpled:   # shirt tail hanging out
				_prect(_tx(0.07), _ty(0.97), _tx(0.12), _ty(0.92), sc)
		"coat", "jacket":
			var jacket := top == "jacket"
			var lapel := tc.lightened(0.15) if p.elegant else tc.darkened(0.3)
			if jacket:
				_v_fill(1.475, 0.87, 0.07, 0.045, sc)
				_pline(_tx(0.0), _ty(1.44), _tx(0.0), _ty(0.98), sc.darkened(0.2))
				_prect(_tx(-0.045), _ty(0.975), _tx(0.045), _ty(0.95), _tex(C_BELT, 1.0))
				for s: float in SIDES:
					_pline(_tx(s * 0.075), _ty(1.47), _tx(s * 0.045), _ty(1.15), lapel, 1.0, 3)
					_pline(_tx(s * 0.07), _ty(0.95), _tx(s * 0.13), _ty(0.95), tc.darkened(0.35))
			else:
				_v_fill(1.475, 1.17, 0.075, 0.0, sc)
				_pline(_tx(0.0), _ty(1.17), _tx(0.0), _ty(0.97), tc.darkened(0.4))
				var btn := _tex(C_GOLD, 1.1, 0.0) if p.elegant else tc.darkened(0.5)
				for i in 3:
					_px(_tx(0.025), _ty(1.12 - i * 0.065), btn)
				for s: float in SIDES:
					_pline(_tx(s * 0.08), _ty(1.47), _tx(s * 0.012), _ty(1.17), lapel, 1.0, 3)
				if p.elegant:   # cravat and watch chain
					_prect(_tx(-0.018), _ty(1.47), _tx(0.018), _ty(1.38), _tex(Color(0.95, 0.93, 0.88), 1.3, 0.0))
					_pline(_tx(0.0), _ty(1.46), _tx(0.0), _ty(1.39), _tex(Color(0.8, 0.78, 0.74), 1.3, 0.0))
					_pline(_tx(0.03), _ty(1.04), _tx(0.10), _ty(1.07), _tex(C_GOLD, 1.0, 0.0))
		"dress":
			if p.shirt_col != p.top_col:
				for s: float in SIDES:
					_pline(_tx(s * 0.005), _ty(1.475), _tx(s * 0.055), _ty(1.43), sc, 1.0, 2)
			for i in 5:
				_px(_tx(0.0), _ty(1.43 - i * 0.05), tc.darkened(0.45))
			_pline(_tx(-0.25), _ty(1.0), _tx(0.25), _ty(1.0), tc.darkened(0.25))
			if p.apron:
				var ap := _tex(C_APRON, 1.15, 1.0)
				_prect(_tx(-0.07), _ty(1.30), _tx(0.07), _ty(0.99), ap)
				_prect(_tx(-0.2), _ty(1.005), _tx(0.2), _ty(0.98), ap)
				for s: float in SIDES:
					_pline(_tx(s * 0.065), _ty(1.30), _tx(s * 0.1), _ty(1.45), ap, 1.0, 2)
	if p.collar:   # a priest's white collar
		_prect(_tx(-0.03), _ty(1.478), _tx(0.03), _ty(1.452), _tex(Color(0.95, 0.94, 0.9), 1.3, 0.0))
	if p.cross:
		var chain := _tex(Color(0.3, 0.3, 0.32), 1.3, 0.0)
		var silver := _tex(C_SILVER, 1.3, 0.0)
		for s: float in SIDES:
			_pline(_tx(s * 0.045), _ty(1.46), _tx(0.0), _ty(1.34), chain)
		_pline(_tx(0.0), _ty(1.34), _tx(0.0), _ty(1.26), silver)
		_pline(_tx(-0.016), _ty(1.315), _tx(0.016), _ty(1.315), silver)
	if p.patched:
		var cloth: Color = p.shirt_col if top == "shirt" else p.top_col
		var pc := _tex(cloth.lerp(C_PATCH, 0.5), 1.2, 1.0)
		_prect(_tx(0.07), _ty(1.25), _tx(0.125), _ty(1.18), pc)
		_pline(_tx(0.07), _ty(1.25), _tx(0.125), _ty(1.25), pc.darkened(0.3))
	if p.prop == "bag":
		_pline(_tx(-0.15), _ty(1.43), _tx(0.17), _ty(0.95), _tex(C_LEATHER, 1.1, 1.0), 1.0, 2)


## Fills a V (shirt between coat fronts) from y_top down to y_bot.
func _v_fill(y_top: float, y_bot: float, w_top: float, w_bot: float, c: Color) -> void:
	for py in range(int(_ty(y_top)), int(_ty(y_bot)) + 1):
		var y_m := 0.80 + (1.0 - (py + 0.5 - 64.0) / 64.0) * 0.70
		var k := clampf((y_top - y_m) / (y_top - y_bot), 0.0, 1.0)
		var w := lerpf(w_top, w_bot, k)
		_prect(_tx(-w), py, _tx(w), py + 1, c)


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
## `uvs` optionally gives the painted-texture UV2 of a, b, c.
func _tri(a: Vector3, b: Vector3, c: Vector3, hint: Vector3, col: Color, uvs: Array = []) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-14:
		return
	var ua := _no_uv
	var ub := _no_uv
	var uc := _no_uv
	if uvs.size() == 3:
		ua = uvs[0]
		ub = uvs[1]
		uc = uvs[2]
	if g.dot(hint) > 0.0:
		var tmp := b
		b = c
		c = tmp
		var tu := ub
		ub = uc
		uc = tu
		g = -g
	var n := -g.normalized()
	_vert(a, n, col, ua)
	_vert(b, n, col, ub)
	_vert(c, n, col, uc)
	_tris += 1


## One vertex in model space: colour (with grain strength in alpha), grain UV,
## painted-texture UV2; moved into the current part's pivot space.
func _vert(p: Vector3, n: Vector3, col: Color, uv2: Vector2) -> void:
	_st.set_color(_final_color(col, p))
	_st.set_normal(n)
	_st.set_uv(_uv(p, n))
	_st.set_uv2(uv2)
	_st.add_vertex(p - _pivot)


## Smooth-shaded (Gouraud) surface through a grid of local points.
## `pts` / `cols` / `uv2s` are row-major Arrays of Arrays (`uv2s` may be empty;
## NO_TEX entries leave a face untextured). Columns wrap when `closed`.
## Faces point away from `inside`. Rows of identical points make poles.
func _surface(pts: Array, cols: Array, uv2s: Array, closed: bool, inside: Vector3,
		double_sided := false, inner: Color = Color.BLACK) -> void:
	var m := _base * _xf
	var rows := pts.size()
	var ncol: int = (pts[0] as Array).size()
	var w: Array = []
	var nrm: Array = []
	for r in rows:
		var row_w: Array = []
		var row_n: Array = []
		for c in ncol:
			row_w.append(m * (pts[r][c] as Vector3))
			row_n.append(Vector3.ZERO)
		w.append(row_w)
		nrm.append(row_n)
	var w_in := m * inside
	var faces: Array = []
	var orient := 0.0
	var cmax := ncol if closed else ncol - 1
	for r in rows - 1:
		for c in cmax:
			var c1 := (c + 1) % ncol
			var q := [Vector2i(r, c), Vector2i(r, c1), Vector2i(r + 1, c1), Vector2i(r + 1, c)]
			for tri: Array in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
				var i0: Vector2i = tri[0]
				var i1: Vector2i = tri[1]
				var i2: Vector2i = tri[2]
				var p0: Vector3 = w[i0.x][i0.y]
				var p1: Vector3 = w[i1.x][i1.y]
				var p2: Vector3 = w[i2.x][i2.y]
				var n := (p1 - p0).cross(p2 - p0)
				if n.length_squared() < 1e-12:
					continue
				faces.append(tri)
				for v: Vector2i in tri:
					nrm[v.x][v.y] += n
				orient += n.dot((p0 + p1 + p2) / 3.0 - w_in)
	var s := 1.0 if orient >= 0.0 else -1.0   # +1: the geometric normals point outward
	var has_uv := not uv2s.is_empty()
	for tri: Array in faces:
		var order: Array = [tri[0], tri[2], tri[1]] if s > 0.0 else [tri[0], tri[1], tri[2]]
		var textured := has_uv
		if has_uv:
			for v: Vector2i in tri:
				if uv2s[v.x][v.y] == NO_TEX:
					textured = false
		for v: Vector2i in order:
			var n: Vector3 = (nrm[v.x][v.y] as Vector3).normalized() * s
			_vert(w[v.x][v.y], n, cols[v.x][v.y], uv2s[v.x][v.y] if textured else _no_uv)
		_tris += 1
		if double_sided:
			for v: Vector2i in [order[0], order[2], order[1]]:
				var n2: Vector3 = (nrm[v.x][v.y] as Vector3).normalized() * -s
				_vert(w[v.x][v.y], n2, inner, _no_uv)
			_tris += 1


## Tube through `pts` (local) with elliptical cross-sections: radii[i].x across
## `ref`, radii[i].y the other way. Limbs, hands, necks, beards. Smooth shaded.
func _tube(pts: Array, radii: Array, sides: int, cols: Array, ref: Vector3,
		cap_start := true, cap_end := true) -> void:
	var grid: Array = []
	var cgrid: Array = []
	var n := pts.size()
	var center := Vector3.ZERO
	for i in n:
		var p: Vector3 = pts[i]
		center += p / float(n)
		var t: Vector3
		if i == 0:
			t = (pts[1] as Vector3) - p
		elif i == n - 1:
			t = p - (pts[i - 1] as Vector3)
		else:
			t = ((pts[i + 1] as Vector3) - p).normalized() + (p - (pts[i - 1] as Vector3)).normalized()
		t = t.normalized()
		var r_ax := ref - t * ref.dot(t)
		if r_ax.length_squared() < 1e-6:
			r_ax = Vector3.FORWARD - t * Vector3.FORWARD.dot(t)
		var x := r_ax.normalized()
		var z := t.cross(x)
		var r: Vector2 = radii[i]
		var row: Array = []
		for k in sides:
			var a := TAU * (k + 0.5) / sides
			row.append(p + x * sin(a) * r.x + z * cos(a) * r.y)
		grid.append(row)
		cgrid.append(_repeat(cols[i], sides))
	if cap_start:
		grid.insert(0, _repeat(pts[0], sides))
		cgrid.insert(0, _repeat(cols[0], sides))
	if cap_end:
		grid.append(_repeat(pts[n - 1], sides))
		cgrid.append(_repeat(cols[n - 1], sides))
	_surface(grid, cgrid, [], true, center)


## Elliptical drape / loft (local, around the Y axis). rows: Vector4(y,
## half-width, half-depth, centre z); angle 0 = front. Coats, skirts, cloaks,
## the torso itself (`torso_uv` projects the clothes texture onto it).
func _drape(rows: Array, a0: float, a1: float, n: int, row_cols: Array, inner: Color,
		double_sided: bool, closed: bool, torso_uv := false) -> void:
	var pts: Array = []
	var cols: Array = []
	var uvs: Array = []
	var ncol := n if closed else n + 1
	var center := Vector3.ZERO
	for r in rows.size():
		var q: Vector4 = rows[r]
		center += Vector3(0.0, q.x, q.w) / float(rows.size())
		var row: Array = []
		var urow: Array = []
		for c in ncol:
			var a := a0 + (a1 - a0) * c / float(n)
			var v := Vector3(sin(a) * q.y, q.x, q.w + cos(a) * q.z)
			row.append(v)
			if torso_uv:
				urow.append(_torso_uv(v.x, v.y, cos(a) > -0.1))
		pts.append(row)
		cols.append(_repeat(row_cols[r], ncol))
		uvs.append(urow)
	_surface(pts, cols, uvs if torso_uv else [], closed, center, double_sided, inner)


## Flat double-sided band along an elliptical arc facing +Z (bonnet frill,
## scarf under the chin). Angles are measured from straight up.
func _arch(c: Vector3, r_in: Vector2, r_out: Vector2, dz: float, a0: float, a1: float, n: int,
		col: Color) -> void:
	var inner_row: Array = []
	var outer_row: Array = []
	for k in n + 1:
		var t := a0 + (a1 - a0) * k / float(n)
		inner_row.append(c + Vector3(sin(t) * r_in.x, cos(t) * r_in.y, 0.0))
		outer_row.append(c + Vector3(sin(t) * r_out.x, cos(t) * r_out.y, dz))
	_surface([inner_row, outer_row], [_repeat(col, n + 1), _repeat(col.darkened(0.08), n + 1)], [],
		false, c - Vector3(0, 0, 0.2), true, col.darkened(0.3))


## Shell hugging the skull (head-local): hair, caps, bonnets, scarves, beards.
## spec: front / side / back = head-local y of the lower edge there; grow =
## thickness; jag = ragged strand ends; bump = lumpiness; fall = hang straight
## down below the cheekbones; part = centre parting; top (or top_front /
## top_side) = upper edge; a_min / a_max = angular range; streak = strand
## shading; cols / rows = resolution.
func _shell(spec: Dictionary, col: Color) -> void:
	var n: int = spec.get("cols", 16)
	var rows: int = spec.get("rows", 6)
	var grow: float = spec.get("grow", 0.012)
	var jag: float = spec.get("jag", 0.0)
	var bump: float = spec.get("bump", 0.0)
	var fall: bool = spec.get("fall", false)
	var streak: float = spec.get("streak", 0.06)
	var a0: float = spec.get("a_min", -PI)
	var a1: float = spec.get("a_max", PI)
	var closed := is_equal_approx(a1 - a0, TAU)
	var ncol := n if closed else n + 1
	var angles: Array = []
	var bottoms: Array = []
	var tops: Array = []
	for c in ncol:
		var a := a0 + (a1 - a0) * c / float(n)
		var t := absf(wrapf(a, -PI, PI)) / PI   # 0 = front, 1 = back
		var yb := _shell_edge(spec, t)
		if jag > 0.0:
			yb += (jag if c % 2 == 0 else -jag * 0.6) + _rng.randf_range(-jag, jag) * 0.4
		var yt: float = spec.get("top", HEAD_TOP)
		if spec.has("top_front"):
			yt = lerpf(spec.top_front, spec.top_side, smoothstep(0.08, 0.4, t))
		angles.append(a)
		bottoms.append(yb)
		tops.append(yt)
	# rows bunch up near the crown so long hair stays round on top
	var crown_ease := 1.5 if not spec.has("top_front") and float(spec.get("top", HEAD_TOP)) >= HEAD_TOP else 1.0
	var pts: Array = []
	var cols: Array = []
	for r in rows + 1:
		var k := float(r) / rows
		var row: Array = []
		var crow: Array = []
		for c in ncol:
			var a: float = angles[c]
			var y := lerpf(tops[c], bottoms[c], pow(k, crown_ease))
			var v: Vector3
			if y >= HEAD_TOP - 0.0005:
				v = Vector3(0.0, HEAD_TOP + grow, _head_ring(HEAD_TOP).z)   # crown
			elif fall and y < FALL_Y:
				v = _head_at(a, FALL_Y, grow) + Vector3(sin(a), 0.0, cos(a)) * (FALL_Y - y) * 0.12
				v.y = y
			else:
				v = _head_at(a, y, grow + (_rng.randf() * bump if r > 0 else 0.0))
			row.append(v)
			var cc := col
			match c % 3:
				0:
					cc = col.lightened(streak)
				1:
					cc = col.darkened(streak)
			crow.append(cc.darkened(0.14 * k * k))
		pts.append(row)
		cols.append(crow)
	_surface(pts, cols, [], closed, Vector3(0, 0.12, 0), spec.get("double", fall), col.darkened(0.5))


func _shell_edge(spec: Dictionary, t: float) -> float:
	var f: float = spec.get("front", 0.2)
	var s: float = spec.get("side", 0.12)
	var b: float = spec.get("back", 0.06)
	var y := lerpf(f, s, smoothstep(0.12, 0.5, t)) if t <= 0.5 else lerpf(s, b, smoothstep(0.5, 0.88, t))
	if spec.get("part", false) and t < 0.07:
		y += 0.012
	return y


## Head cross-section at head-local height y: (half-width, half-depth, centre z).
func _head_ring(y: float) -> Vector3:
	var first: Array = HEAD_RINGS[0]
	if y <= float(first[0]):
		return Vector3(first[1], first[2], first[3])
	for i in range(1, HEAD_RINGS.size()):
		var r1: Array = HEAD_RINGS[i]
		if y <= float(r1[0]):
			var r0: Array = HEAD_RINGS[i - 1]
			var t := (y - float(r0[0])) / (float(r1[0]) - float(r0[0]))
			return Vector3(lerpf(r0[1], r1[1], t), lerpf(r0[2], r1[2], t), lerpf(r0[3], r1[3], t))
	var last: Array = HEAD_RINGS[HEAD_RINGS.size() - 1]
	return Vector3(last[1], last[2], last[3])


## Point on the skull (head-local) at angle a (0 = face) and height y, pushed
## out by `grow`. The jaw width and hollow cheeks come from the villager.
func _head_at(a: float, y: float, grow := 0.0) -> Vector3:
	var r := _head_ring(y)
	var rx := r.x
	if y < 0.1:
		rx *= lerpf(_jaw, 1.0, clampf(y / 0.1, 0.0, 1.0))
	if _hollow and y > 0.045 and y < 0.11:
		rx *= 0.95
	var rz := r.y * lerpf(1.0, 1.07, clampf(-cos(a), 0.0, 1.0))   # rounder at the back
	return Vector3(sin(a) * (rx + grow), y, r.z + cos(a) * (rz + grow))


func _ring_at(rings: Array, y: float) -> Vector4:
	var first: Vector4 = rings[0]
	if y <= first.x:
		return first
	for i in range(1, rings.size()):
		var r1: Vector4 = rings[i]
		if y <= r1.x:
			var r0: Vector4 = rings[i - 1]
			return r0.lerp(r1, (y - r0.x) / (r1.x - r0.x))
	return rings[rings.size() - 1]


func _repeat(v: Variant, count: int) -> Array:
	var a: Array = []
	a.resize(count)
	a.fill(v)
	return a


# ─── texture painting (cell pixel coordinates, clipped to `_clip`) ───────────
func _px(xf: float, yf: float, c: Color, a := 1.0) -> void:
	var x := floori(xf)
	var y := floori(yf)
	if x < _clip.position.x or y < _clip.position.y or x >= _clip.end.x or y >= _clip.end.y:
		return
	var X := _cell.x + x
	var Y := _cell.y + y
	if a >= 0.999:
		_atlas.set_pixel(X, Y, Color(c.r, c.g, c.b, 1.0))
		return
	var o := _atlas.get_pixel(X, Y)
	if o.a < 0.5:
		return   # blend only onto paint
	_atlas.set_pixel(X, Y, Color(lerpf(o.r, c.r, a), lerpf(o.g, c.g, a), lerpf(o.b, c.b, a), 1.0))


func _pell(cx: float, cy: float, rx: float, ry: float, c: Color, a := 1.0) -> void:
	_px(cx, cy, c, a)
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / maxf(rx, 0.01)
			var dy := (y + 0.5 - cy) / maxf(ry, 0.01)
			if dx * dx + dy * dy <= 1.0 and not (x == floori(cx) and y == floori(cy)):
				_px(x, y, c, a)


func _prect(x0: float, y0: float, x1: float, y1: float, c: Color, a := 1.0) -> void:
	for y in range(floori(minf(y0, y1)), ceili(maxf(y0, y1))):
		for x in range(floori(minf(x0, x1)), ceili(maxf(x0, x1))):
			_px(x, y, c, a)


## Line `w` pixels thick (extending downward).
func _pline(x0: float, y0: float, x1: float, y1: float, c: Color, a := 1.0, w := 1) -> void:
	var steps := int(maxf(absf(x1 - x0), absf(y1 - y0)) * 2.0) + 1
	var done := {}
	for i in steps + 1:
		var t := float(i) / steps
		var p := Vector2i(floori(lerpf(x0, x1, t)), floori(lerpf(y0, y1, t)))
		for k in w:
			var q := p + Vector2i(0, k)
			if not done.has(q):
				done[q] = true
				_px(q.x, q.y, c, a)


## RGB = final vertex colour, A = how strongly the grain texture shows (shader only).
func _final_color(col: Color, p: Vector3) -> Color:
	var c := col
	if baked_vertex_shade:
		var k := lerpf(0.70, 1.0, clampf(p.y / 1.75, 0.0, 1.0))
		c = Color(c.r * k, c.g * k, c.b * k)
	var grey := c.r * 0.3 + c.g * 0.59 + c.b * 0.11   # washed-out, grim palette
	c = c.lerp(Color(grey, grey, grey), desaturate)
	var lv := float((1 << color_depth_bits) - 1)   # quantise like the PS1's 15-bit colour
	var grain := _grain * (1.0 - 0.55 * grey)   # pale linen would turn to camouflage
	return Color(roundf(c.r * lv) / lv, roundf(c.g * lv) / lv, roundf(c.b * lv) / lv, grain)


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
