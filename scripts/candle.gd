extends Interactable

signal changed(lit: bool)

@export var lit := true
@export var burns := true
@export var shadow := true

@onready var light: OmniLight3D = $Light
@onready var flame: Node3D = $Flame

var left := 0.0
var base := 0.0
var ph := 0.0
var chill := 0.0        # 0..1: blue, low flame
var chill_t := 0.0      # forced chill from an omen, seconds
var base_col := Color.WHITE

const COLD_DIST := 1.9
const COLD_COL := Color(0.55, 0.7, 1.0)


func _ready() -> void:
	prompt = "Light"
	light.shadow_enabled = shadow
	if burns:
		add_to_group("coffin_candles")
	base = light.light_energy
	base_col = light.light_color
	ph = randf() * TAU
	if lit:
		relight()
	else:
		apply()


func relight() -> void:
	lit = true
	left = randf_range(Game.cfg().candle_min, Game.cfg().candle_max)
	apply()


func put_out() -> void:
	lit = false
	apply()


func apply() -> void:
	light.visible = lit
	flame.visible = lit
	changed.emit(lit)


func _process(dt: float) -> void:
	if not lit:
		return
	ph += dt * 9.0
	chill_t = maxf(chill_t - dt, 0.0)
	var cold := 1.0 if chill_t > 0.0 else 0.0
	for c in get_tree().get_nodes_in_group("cold_ones"):
		if (c as Node3D).global_position.distance_to(global_position) < COLD_DIST:
			cold = 1.0
	chill = move_toward(chill, cold, dt * 2.0)
	light.light_color = base_col.lerp(COLD_COL, chill)
	light.light_energy = base * (0.85 + 0.1 * sin(ph) + 0.05 * sin(ph * 2.7)) * (1.0 - 0.45 * chill)
	flame.scale.y = (1.0 + 0.15 * sin(ph * 1.3)) * (1.0 - 0.4 * chill)
	if burns and Game.state == Game.State.PLAY:
		left -= dt
		if left <= 0.0:
			put_out()


## An omen: the flame burns low and blue for a while.
func chill_for(t: float) -> void:
	chill_t = maxf(chill_t, t)


func can_interact(_p: Node) -> bool:
	return not lit


func interact(_p: Node) -> void:
	relight()
