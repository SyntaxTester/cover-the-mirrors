class_name NightPlan
extends RefCounted
## Builds one night's visitors from data/guests.json, differently every run:
##   • real guests come in the order written in the data;
##   • doubles copy a guest of the night (or someone you left out in the rain
##     the night before) and knock before OR after the real one;
##   • every double shows Config.signs_per_double signs from the night's pool;
##   • a real guest may show one sign too, for an innocent reason they'll
##     explain if asked (cart, umbrella, the dog never liked them);
##   • a double with "wrong_detail" differs from the portrait by one detail.

const HUMAN_FAKE_SIGNS := ["clean_boots", "dry", "dog_growl"]


## Returns {"queue": [entry...], "portraits": [name...]}.
## entry = {name, double, signs, line, answers:{who,how,gift}, mutation:{}}
static func build(night: int, raw: Dictionary, run: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var looks: Dictionary = raw.get("looks", {})
	var nights: Array = raw.get("nights", [])
	var src: Array = nights[night] if night < nights.size() else []
	var cfg: Dictionary = Config.nights[night]
	var pool: Array = cfg.get("signs", ["no_breath", "clean_boots", "dog_growl"])

	var queue: Array = []
	for e: Dictionary in src:
		queue.append(_human(e, looks.get(e.name, {}), raw, rng))

	# who gets copied tonight
	var victims: Array = []
	for n in run.get("refused_last", []):   # the ones you left outside come back
		if looks.has(n) and not victims.has(n):
			victims.append(n)
	var names: Array = queue.map(func(e): return e.name)
	names.shuffle()
	var want := int(cfg.get("doubles", 1)) + victims.size()
	for n in names:
		if victims.size() >= want:
			break
		if not victims.has(n):
			victims.append(n)

	for n: String in victims:
		var real_i := -1
		for i in queue.size():
			if queue[i].name == n and not queue[i].double:
				real_i = i
				break
		var base: Dictionary = queue[real_i] if real_i >= 0 else _human(
			{"name": n, "line": _returning_line(n, raw)}, looks.get(n, {}), raw, rng)
		var d := _double(base, looks.get(n, {}), pool, raw, rng)
		var at: int
		if real_i < 0:
			at = rng.randi_range(maxi(1, queue.size() / 3), queue.size())
		elif real_i >= 1 and rng.randf() < 0.4:
			at = rng.randi_range(1, real_i)   # the copy knocks FIRST; the real one looks like the fake
		else:
			at = rng.randi_range(mini(real_i + 2, queue.size()), queue.size())
		queue.insert(at, d)

	var portraits: Array = []
	for e: Dictionary in queue:
		if not portraits.has(e.name):
			portraits.append(e.name)
	return {"queue": queue, "portraits": portraits}


static func _human(e: Dictionary, look: Dictionary, raw: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var answers: Dictionary = (look.get("answers", {}) as Dictionary).duplicate()
	var signs: Array = (look.get("innocent", []) as Array).duplicate()
	if signs.is_empty() and rng.randf() < Config.human_sign_chance:
		var fake: String = HUMAN_FAKE_SIGNS.pick_random()
		signs.append(fake)
		var why: Dictionary = raw.get("innocent_answers", {})
		if why.has(fake):
			answers["how"] = why[fake]
	return {"name": e.name, "double": false, "signs": signs, "line": e.get("line", ""),
		"answers": answers, "mutation": {}}


static func _double(base: Dictionary, look: Dictionary, pool: Array, raw: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var innocent: Array = look.get("innocent", [])
	var choices := pool.filter(func(s): return not innocent.has(s))
	choices.shuffle()
	var signs: Array = choices.slice(0, Config.signs_per_double)
	var d := base.duplicate(true)
	d["double"] = true
	d["signs"] = signs
	if signs.has("wrong_answer"):
		var bad: Dictionary = raw.get("double_answers", {})
		for q in ["who", "how", "gift"]:
			var opts: Array = bad.get(q, [])
			if not opts.is_empty():
				d.answers[q] = opts[rng.randi() % opts.size()]
		d["line"] = corrupt(d.line, rng)
	if signs.has("wrong_detail"):
		var id := PS1Villager.character_from_name(str(look.get("model", "")))
		if id >= 0:
			d["mutation"] = mutation_for(PS1Villager.profile_of(id), rng)
	return d


## One visible change against the portrait: glasses, beard, hat, hair colour,
## freckles or a mole.
static func mutation_for(p: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var opts: Array = []
	if p.get("glasses", false):
		opts.append({"glasses": false})
	match str(p.get("facial", "none")):
		"none":
			if not p.get("female", false):
				opts.append({"facial": "moustache"})
		"beard", "long_beard", "pointed_beard":
			opts.append({"facial": "stubble"})
		_:
			opts.append({"facial": "none"})
	if str(p.get("hat", "none")) != "none":
		opts.append({"hat": "none"})
	var hair: Color = p.get("hair", Color.BROWN)
	var other := Color(0.72, 0.70, 0.66) if hair.get_luminance() < 0.4 else Color(0.12, 0.10, 0.09)
	opts.append({"hair": other, "facial_col": other})
	opts.append({"freckles": not p.get("freckles", false)})
	opts.append({"mole": 1.0 if rng.randf() < 0.5 else -1.0})
	return opts[rng.randi() % opts.size()]


## How a double gets a line slightly wrong.
static func corrupt(line: String, rng: RandomNumberGenerator) -> String:
	var ways: Array = []
	if " him" in line:
		ways.append(func(l: String) -> String: return l.replace(" him", " her"))
	var parts := line.split(". ", false)
	if parts.size() > 1:
		ways.append(func(l: String) -> String: return l.split(". ", false)[0] + ".")
	ways.append(func(l: String) -> String:
		var w := l.split(" ", false)
		if w.size() < 3:
			return l + " " + l
		var i := rng.randi_range(0, w.size() - 2)
		w.insert(i + 1, w[i].trim_suffix(",").trim_suffix("."))
		return " ".join(w))
	var f: Callable = ways[rng.randi() % ways.size()]
	return f.call(line)


static func _returning_line(n: String, raw: Dictionary) -> String:
	for night: Array in raw.get("nights", []):
		for e: Dictionary in night:
			if e.name == n:
				return e.line
	return "Let me in. It's cold out here."
