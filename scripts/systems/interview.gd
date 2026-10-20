extends Node
## Questions through the hatch. Press 1 / 2 / 3 while talking to someone at
## the door. A few questions a night; doubles with the "wrong_answer" sign
## know the words but not the meaning.

const ORDER := ["who", "how", "gift"]
const KEYS := [KEY_1, KEY_2, KEY_3]

var left := 0
var visitors
var hatch


func _ready() -> void:
	add_to_group("debug")
	visitors = get_node("../Visitors")
	hatch = get_node("../../Level/FrontDoor/Swing/Hatch")
	Game.night_started.connect(func(_n): left = int(Game.cfg().get("questions", 3)))


func _can_ask() -> bool:
	return Game.state == Game.State.PLAY and hatch.open and visitors.at_door != null \
		and is_instance_valid(visitors.at_door) and visitors.spoken and left > 0


func _process(_dt: float) -> void:
	get_tree().call_group("hud", "set_questions", _menu())


func _menu() -> String:
	if not _can_ask():
		if hatch.open and visitors.at_door != null and visitors.spoken and left <= 0:
			return "No more questions tonight"
		return ""
	var qs: Dictionary = visitors.raw.get("questions", {})
	var g = visitors.at_door
	var lines := PackedStringArray()
	for i in ORDER.size():
		var q: String = ORDER[i]
		if g.asked.has(q):
			continue
		lines.append("[%d] %s" % [i + 1, qs.get(q, q)])
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\nquestions left tonight: %d" % left


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var i := KEYS.find((e as InputEventKey).physical_keycode)
	if i < 0 or not _can_ask():
		return
	var g = visitors.at_door
	var q: String = ORDER[i]
	if g.asked.has(q):
		return
	left -= 1
	Sounds.play(self, Sounds.UI_SELECT, -10.0)
	g.speak(g.answer(q), true)   # an answer to the player never waits behind chatter
	get_viewport().set_input_as_handled()


func debug_line() -> String:
	return "questions left %d" % left
