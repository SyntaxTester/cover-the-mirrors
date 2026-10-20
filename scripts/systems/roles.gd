extends Node
## The mourners are not furniture. Each "role" in guests.json gives a guest
## something to do while they are inside and awake:
##   lore        Bridget, Old Tom: tells you tonight's sign (true)
##   lore_wrong  Jeremiah: tells you a sign, half the time the wrong one
##   vouch       Peter: knows every voice; says whether the visitor is who they say (mostly right)
##   watcher     Eileen: sees who comes up the lane (often right)
##   gossip      Mary Kate: overhears whispering (often right)
##   nervous     Daniel: jumpy about someone (sometimes right)
##   pious       Joseph: shouts when a mirror cloth slips
##   carpenter   John: raises the alarm when someone heads for the coffin
##   singer      Esmagzam, James: a song wakes the sleepers; Esmagzam also talks nonsense
##   candles     Nora: relights a candle now and then
##   fiddler     Martin, drunk Denis: keep the wake lively (vigil)
##   drunk, sleepy  Denis, Paddy: nod off first

const RULES := {
	"no_breath": "Mind their breath on the cold air. The other crowd have none to give.",
	"clean_boots": "Look at their boots. No living soul walks the bog road clean.",
	"dog_growl": "Trust the dog. A dog always knows its own people.",
	"dry": "On a night like this, anything living comes in dripping wet.",
	"wrong_answer": "Ask them things. They know the words, but not what they mean.",
	"wrong_detail": "Look at the faces on the wall by the door. They never get it quite right.",
	"no_shadow": "Hold a light to them. The other crowd throw no shadow.",
	"cold": "Watch the flames. A candle burns low and blue beside the cold ones.",
}
const MIRROR_RULE := "And never trust one the glass won't hold."
const LORE_OPEN := {
	"Bridget": "Listen to me now, child. ",
	"Old Tom": "My grandmother used to say... ",
	"Jeremiah": "I'll tell you what the old people know. ",
}
const SAY_GAP := 11.0   # seconds between chatter lines, so subtitles stay readable

const WATCH_ODD := [
	"Someone's at the door... they didn't come up the lane. They were just there.",
	"I was watching the lane the whole time. Nobody walked up it. Nobody.",
	"That one came out of the field, not the road. Who walks the bog in the dark?",
	"Did you see their lantern? No? Neither did I. They had none.",
]
const WATCH_OK := [
	"It's only %s. I saw them coming up the lane.",
	"That's %s at the door. I watched them come all the way from the crossroads.",
	"%s, I'd say. Same slow walk up the lane as always.",
	"I saw %s stop at the gate and bless themselves. That's them, alright.",
]
const VOUCH_ODD := [
	"Hold on. That's not how %s talks.",
	"That's %s's voice... but %s never said a word like that in their life.",
	"Something's off. %s always stammers on the first word. Not tonight.",
	"I've known %s since we were children. That isn't them at the door.",
]
const VOUCH_OK := [
	"That's %s, right enough. I'd know that voice anywhere.",
	"Aye, that's %s. Nobody else mumbles like that.",
	"%s, sure as day. Let them in out of the rain.",
	"I'd swear to it, that's %s. Same as ever.",
]
const GOSSIP := [
	"I heard %s whispering at the door of the room. Whispering to HIM.",
	"%s hasn't touched the tea. Not a sip all night.",
	"I sat by %s for an hour. They never blinked. Not once.",
	"Did you notice? %s keeps counting us. Over and over.",
]
const NERVOUS := [
	"I-I don't like the way %s keeps looking at the coffin.",
	"Why is %s sitting so still? N-nobody sits that still.",
	"%s smiled at me. Just now. With all their teeth.",
	"I keep hearing %s breathing... b-but their chest doesn't move.",
]
const CARPENTER := [
	"Here! Who's that going in to him? Stop them!",
	"Somebody's going into the room! Ronan, get after them!",
	"That's not one of us walking in there! Stop it!",
]
const PIOUS := [
	"The glass! Somebody cover the glass, for the love of God!",
	"The mirror is bare! Cover it before it sees him!",
	"Mother of God, the cloth's come off the glass!",
]

var visitors
var vigil
var timers := {}       # guest instance id -> seconds to its next idle action
var told := []         # signs already announced tonight
var told_by := []      # who already gave their rule tonight
var gap := 0.0


func _ready() -> void:
	add_to_group("roles")
	add_to_group("debug")
	visitors = get_node("../Visitors")
	vigil = get_node("../Vigil")


func _inside_awake(role: String) -> Array:
	return visitors.inside.filter(func(g): return is_instance_valid(g) and g.role == role and g.is_seated())


func _say(g, text: String, urgent := false) -> void:
	if not is_instance_valid(g) or Game.state != Game.State.PLAY:
		return
	if gap > 0.0 and not urgent:
		return
	gap = SAY_GAP
	g.speak(text)


func _later(t: float, f: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(f)


## From the second night the other crowd get into people's heads: while one of
## them sits in the house, everyone's hints are less to be trusted.
func _rel(base: float) -> float:
	if Game.night >= 1 and visitors.inside.any(func(x): return is_instance_valid(x) and x.double):
		return base * 0.6
	return base


func _tonight_signs() -> Array:
	var out: Array = []
	for e in visitors.queue:
		if e.get("double", false):
			for s in e.signs:
				if not out.has(s):
					out.append(s)
	return out


# ── events ───────────────────────────────────────────────────────────────────
func on_seated(g) -> void:
	if g.double or told_by.has(g.nick):
		return
	if g.role == "lore" or g.role == "lore_wrong":
		told_by.append(g.nick)
		_later(3.0, func(): _tell_rule(g))
	timers[g.get_instance_id()] = randf_range(25.0, 45.0)


func _tell_rule(g) -> void:
	var real := _tonight_signs()
	var sign := ""
	var fresh := real.filter(func(s): return not told.has(s))
	var wrong_chance := 0.5 if g.role == "lore_wrong" else 1.0 - _rel(1.0)
	if randf() < wrong_chance:
		var fake: Array = RULES.keys().filter(func(s): return not real.has(s))
		if not fake.is_empty():
			sign = fake.pick_random()
	if sign == "":
		sign = fresh.pick_random() if not fresh.is_empty() else (real.pick_random() if not real.is_empty() else "")
	if sign == "":
		_say(g, MIRROR_RULE, true)
		return
	told.append(sign)
	var text: String = LORE_OPEN.get(g.nick, "") + RULES[sign]
	if g.nick == "Bridget":
		text += " " + MIRROR_RULE
	_say(g, text, true)


func on_visitor_arrived(v) -> void:
	for w in _inside_awake("watcher"):
		var right := randf() < _rel(0.65)
		var says_double: bool = v.double == right
		var text: String = WATCH_ODD.pick_random() if says_double else WATCH_OK.pick_random() % v.nick
		_later(2.0, func(): _say(w, text))
		break


func on_visitor_spoke(v) -> void:
	# give the visitor's own line time to be read first
	for p in _inside_awake("vouch"):
		var right := randf() < _rel(0.8)
		var says_double: bool = v.double == right
		var tpl: String = VOUCH_ODD.pick_random() if says_double else VOUCH_OK.pick_random()
		var text: String = tpl.replace("%s", v.nick)
		_later(5.0, func(): _say(p, text, true))
		return
	for s in _inside_awake("singer"):
		if s.nick == "Esmagzam" and randf() < 0.5:
			_later(5.0, func(): _say(s, ["Let them in! The more the merrier!",
				"Is that the priest? Tell him I've been good!",
				"Ask them if they brought ale!"].pick_random()))
			return


func on_mirror_slipped(_m) -> void:
	for j in _inside_awake("pious"):
		_say(j, PIOUS.pick_random(), true)
		return


func on_stalk(d) -> void:
	for c in _inside_awake("carpenter"):
		var line: String = CARPENTER.pick_random()
		_later(1.0, func(): _say(c, line, true))
		return


func on_sabotage(_d) -> void:
	pass


# ── idle behaviour ───────────────────────────────────────────────────────────
func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	gap = maxf(gap - dt, 0.0)
	for g in visitors.inside:
		if not is_instance_valid(g) or g.double or not g.is_seated():
			continue
		match g.role:
			"fiddler", "drunk":
				vigil.vigil = minf(vigil.vigil + 0.35 * dt, 100.0)   # music and noise keep the wake going
		var id: int = g.get_instance_id()
		if not timers.has(id):
			timers[id] = randf_range(25.0, 45.0)
		timers[id] -= dt
		if timers[id] > 0.0:
			continue
		timers[id] = randf_range(40.0, 75.0)
		_idle(g)


func _idle(g) -> void:
	var doubles: Array = visitors.inside.filter(func(x): return is_instance_valid(x) and x.double)
	var others: Array = visitors.inside.filter(func(x): return is_instance_valid(x) and x != g)
	match g.role:
		"singer":
			var woke := 0
			for x in visitors.inside:
				if is_instance_valid(x) and x.is_asleep():
					x.wake()
					woke += 1
			vigil.vigil = minf(vigil.vigil + 6.0, 100.0)
			_say(g, "(sings) Oh the night was dark and the road was long..." if g.nick == "Esmagzam" \
				else "(sings) And we'll all go together to the wake of old Patrick...")
		"candles":
			var out := get_tree().get_nodes_in_group("coffin_candles").filter(func(c): return not c.lit)
			if not out.is_empty():
				out.pick_random().relight()
				_say(g, "I've seen to the candles in the room. Don't you worry.")
		"gossip":
			if not doubles.is_empty() and randf() < _rel(0.7):
				_say(g, (GOSSIP.pick_random() as String).replace("%s", doubles.pick_random().nick))
			elif not others.is_empty() and randf() < 0.3:
				_say(g, (GOSSIP.pick_random() as String).replace("%s", others.pick_random().nick))
		"nervous":
			if not doubles.is_empty() and randf() < _rel(0.6):
				_say(g, (NERVOUS.pick_random() as String).replace("%s", doubles.pick_random().nick))
			elif not others.is_empty() and randf() < 0.4:
				_say(g, (NERVOUS.pick_random() as String).replace("%s", others.pick_random().nick))
		"fiddler":
			_say(g, "(plays a slow air on the fiddle)")
		"drunk":
			_say(g, ["To Paddy! May he be in heaven an hour before the devil knows he's dead!",
				"Who took my glass? Who took it?", "(laughs much too loudly)"].pick_random())


func debug_line() -> String:
	return "roles told %s" % [told]
