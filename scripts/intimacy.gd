class_name Intimacy
## How close a unique character is to Miko: 0 to 100, theirs alone (ordinary villagers have none). It grows by
## talking with them (the first time each day; and their own topics, each once, by what Miko answers) and by gifts
## (one a day: loved, liked, plain or disliked, by their tastes). It's shown as hearts. Passing each of their
## milestones is said in the village log and written in the Chronicle ("intimacy:<id>:<n>"), so what follows can go
## by it: at 100 Miyu asks for a book. Everything about a character's tastes and talk is in uniques.json.

const MOST := 100.0
const HEARTS := 5
const DAILY_TALK := 2.0
const GIFT := {"loved": 8.0, "liked": 4.0, "plain": 1.0, "disliked": -3.0}


static func has(p: Dictionary) -> bool:
	# (the story's people, the elders, aren't companions; nor is Sera, one while someone else is played)
	return p.has("unique") and Traits.has(p, "unique") and Uniques.all().has(str(p.unique))


static func of(p: Dictionary) -> float:
	return float(p.get("intimacy", 0.0))


## Hearts for [param p], as "♥♥♥♡♡" ("" for someone who isn't unique).
static func hearts(p: Dictionary) -> String:
	if not has(p):
		return ""
	var full := floori(of(p) / (MOST / HEARTS) + 0.001)
	return "♥".repeat(full) + "♡".repeat(HEARTS - full)


static func _def(p: Dictionary) -> Dictionary:
	return Uniques.all().get(str(p.get("unique", "")), {})


## Adds [param amount] (it may be less than none); milestones passed are announced and recorded.
static func gain(p: Dictionary, amount: float) -> void:
	if not has(p):
		return
	var was := of(p)
	p["intimacy"] = clampf(was + amount, 0.0, MOST)
	for m in _def(p).get("milestones", []):
		var at := float(m.at)
		var event := "intimacy:%s:%d" % [str(p.unique), int(at)]
		if was < at and of(p) >= at and Chronicle.active != null and not Chronicle.active.happened(event):
			Chronicle.active.record(event)
			VillageLog.event(event, str(m.get("says", "")))


## The first talk of the day counts for a little. Whether it did.
static func talked(p: Dictionary, day: int) -> bool:
	if not has(p) or int(p.get("talkedDay", -1)) == day:
		return false
	p["talkedDay"] = day
	gain(p, DAILY_TALK)
	return true


## How they take [param item]: "loved", "liked", "disliked" or "plain".
static func taste(p: Dictionary, item: String) -> String:
	var g: Dictionary = _def(p).get("gifts", {})
	for kind in ["loved", "liked", "disliked"]:
		if (g.get(kind, []) as Array).has(item):
			return kind
	return "plain"


static func gifted_today(p: Dictionary, day: int) -> bool:
	return int(p.get("giftDay", -1)) == day


## A gift given: how it was taken ("loved"...), and what they say.
static func give(p: Dictionary, item: String, day: int) -> Array:
	var kind := taste(p, item)
	p["giftDay"] = day
	gain(p, float(GIFT[kind]))
	return [kind, line(p, "giftSays", kind)]


## One of their lines of a [param kind] ("giftSays": "loved"...), or "".
static func line(p: Dictionary, group: String, kind: String) -> String:
	var pool: Array = _def(p).get(group, {}).get(kind, [])
	return str(pool.pick_random()).format({"miko": Playable.name_now()}) if not pool.is_empty() else ""


## Their greeting, by how close they are, or "" (the usual one).
static func greeting(p: Dictionary) -> String:
	var best: Array = []
	for g in _def(p).get("greetings", []):
		if of(p) >= float(g.get("min", 0)):
			best = g.get("says", [])
	return str(best.pick_random()).format({"miko": Playable.name_now()}) if not best.is_empty() else ""


## The next thing there is to talk about: the first of their topics not yet talked through that they're close enough
## for, or {}.
static func topic(p: Dictionary) -> Dictionary:
	var done: Array = p.get("topics", [])
	for t in _def(p).get("topics", []):
		if not done.has(str(t.id)) and of(p) >= float(t.get("min", 0)):
			return t
	return {}


## A topic talked through, with the answer picked: what they say back.
static func answer(p: Dictionary, t: Dictionary, reply: Dictionary) -> String:
	var done: Array = p.get("topics", [])
	done.append(str(t.id))
	p["topics"] = done
	gain(p, float(reply.get("gain", 0)))
	return str(reply.get("answer", "")).format({"miko": Playable.name_now()})
