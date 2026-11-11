class_name Traits
## Villager traits: permanent quirks, good and bad, each villager's own (data/traits.json). Rolled when they arrive:
## one good, one bad, now and then a third. What a trait does is its "mods": numbers the villager's code asks for by
## name ([method mul] for those multiplied: work, hunger, speed, flee, chat; [method add] for those added: carry,
## cold, start, end, fishing, learn, gossip). hp and atk are applied once, when the traits are given.

const FILE := "res://data/traits.json"

static var _all := {}             ## id -> the trait
static var _loaded := false


static func all() -> Dictionary:
	if not _loaded:
		_loaded = true
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			for t in d.get("traits", []):
				_all[str(t.id)] = t
	return _all


## The traits of person [param p] (their ids).
static func of(p: Dictionary) -> Array:
	return p.get("traits", [])


static func has(p: Dictionary, id: String) -> bool:
	return of(p).has(id)


## Everything [param p]'s traits multiply [param key] by (1 with none).
static func mul(p: Dictionary, key: String) -> float:
	var m := 1.0
	for id in of(p):
		m *= float(all().get(id, {}).get("mods", {}).get(key, 1.0))
	return m


## Everything [param p]'s traits add to [param key] (0 with none).
static func add(p: Dictionary, key: String) -> float:
	var a := 0.0
	for id in of(p):
		a += float(all().get(id, {}).get("mods", {}).get(key, 0.0))
	return a


## Gives [param p] the traits [param ids] (once: their health and strength are changed by them here).
static func give(p: Dictionary, ids: Array) -> void:
	p["traits"] = ids.duplicate()
	var hp := mul(p, "hp")
	p["maxHp"] = roundf(float(p.get("maxHp", 40.0)) * hp)
	p["hp"] = minf(float(p.get("hp", p.maxHp)) * hp, float(p.maxHp))
	p["atk"] = roundf(float(p.get("atk", 6.0)) * mul(p, "atk"))


## Rolls traits for a newcomer: one good and one bad that go together, and one time in three a third.
static func roll(p: Dictionary) -> void:
	var picked: Array = []
	for want_good in [true, false, randf() < 0.5]:
		if picked.size() == 2 and randf() >= 0.34:
			break
		var pool := all().values().filter(func(t):
			return str(t.id) != "unique" and bool(t.good) == want_good and not picked.has(str(t.id)) \
				and (not bool(t.get("rare", false)) or randf() < 0.15) \
				and not picked.any(func(q): return (t.opposite as Array).has(q) or (all()[q].opposite as Array).has(str(t.id))))
		if not pool.is_empty():
			picked.append(str(pool.pick_random().id))
	give(p, picked)


## The traits' names, for showing: [[name, good, about], ...].
static func shown(p: Dictionary) -> Array:
	var out := []
	for id in of(p):
		var t: Dictionary = all().get(id, {})
		if not t.is_empty():
			out.append([str(t.name), bool(t.good), str(t.about)])
	return out
