extends Node3D
## Father Declan keeps the vigil in the coffin room with Ronan: he prays over
## the body, calls out when the coffin candles die, and is the first to see
## when the dead man stirs. He is not a guest and cannot be sent away.

const MODEL := "DECLAN"
const PRAYERS := [
	"Eternal rest grant unto him, O Lord, and let perpetual light shine upon him.",
	"May his soul and the souls of all the faithful departed rest in peace.",
	"(murmurs the rosary under his breath)",
	"Keep the glass covered, Ronan. Whatever you hear.",
	"Go to the door when they knock. I'll stay with your father.",
	"Eternal rest grant unto them— unto him, O Lord.",
	"You've not eaten a bite since the bog road, Ronan. Nor slept. Nor...",
	"When did you last look in a glass, son? No. Don't.",
]

var body: VillagerBody
var head := Node3D.new()
var hip_y := 0.85
var pray_t := 30.0
var warn_gap := 0.0
var lit_before := -1
var yaw := 0.0


func setup(seat: Transform3D) -> void:
	var id := PS1Villager.character_from_name(MODEL)
	var parts := PS1Villager.build_guest_parts(id, {"boots": "mud"})
	body = VillagerBody.new()
	add_child(body)
	body.build(parts, head)
	body.mode = "sit"
	body.set_seated(true, true)
	hip_y = body.hip.y
	# seated, facing the coffin
	global_transform = seat
	global_position.y = seat.origin.y - (hip_y - 0.05)
	add_to_group("priest")
	Game.corpse_stirred.connect(_stirred)


func _say(text: String) -> void:
	if Game.state == Game.State.PLAY:
		get_tree().call_group("hud", "say", "Father Declan", text)
		body.talk(2.0 + text.length() / 30.0)


func _player_near(d := 6.0) -> bool:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p != null and p.global_position.distance_to(global_position) < d


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	warn_gap = maxf(warn_gap - dt, 0.0)
	# heads bowed in prayer; looks up at Ronan when he comes close
	var look := 0.0
	var tp := -0.35
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p and _player_near(3.0):
		var l := to_local(p.global_position)
		look = clampf(atan2(-l.x, -l.z), -1.0, 1.0)
		tp = 0.0
	yaw = lerp_angle(yaw, look, dt * 2.0)
	head.rotation = Vector3(lerpf(head.rotation.x, tp, dt * 2.0), yaw, 0)
	pray_t -= dt
	if pray_t <= 0.0:
		pray_t = randf_range(45.0, 80.0)
		if _player_near():
			_say(PRAYERS.pick_random())
	# the candles: he notices every one that dies
	var lit := get_tree().get_nodes_in_group("coffin_candles").filter(func(c): return c.lit).size()
	if lit_before >= 0 and lit < lit_before and warn_gap <= 0.0:
		warn_gap = 20.0
		if lit == 0:
			_say("Ronan! The candles are out, all of them! Light them, quick, before it notices!")
		elif lit <= 2:
			_say("Ronan, the candles are going. Light them again.")
	lit_before = lit


func _stirred(stage: int) -> void:
	match stage:
		1:
			_say("Lord have mercy... his hand. Ronan, his hand moved.")
		2:
			_say("He's turning his head. One more of them reaches him and he'll rise. Don't let them in!")
		_:
			_say("God forgive us...")
