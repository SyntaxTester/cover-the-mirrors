extends Interactable

signal changed(lit: bool)

@export var lit := true
@export var burns := true

@onready var light: OmniLight3D = $Light
@onready var flame: Node3D = $Flame

var left := 0.0
var base := 0.0
var ph := 0.0


func _ready() -> void:
	prompt = "Зажечь"
	if burns:
		add_to_group("coffin_candles")
	base = light.light_energy
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
	light.light_energy = base * (0.85 + 0.1 * sin(ph) + 0.05 * sin(ph * 2.7))
	flame.scale.y = 1.0 + 0.15 * sin(ph * 1.3)
	if burns and Game.state == Game.State.PLAY:
		left -= dt
		if left <= 0.0:
			put_out()


func can_interact(_p: Node) -> bool:
	return not lit


func interact(_p: Node) -> void:
	relight()
