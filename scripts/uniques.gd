class_name Uniques
## Unique characters: named people who exist once (data/uniques.json), Miyu the first. One is never rolled as an
## ordinary newcomer. They come to the village through what happens (a rumor's outcome: [method arrive]) and can be
## lost for good before they do ([method lose]): both are written in the Chronicle ("unique:<id>", "lost:<id>"),
## so what follows can go by it. A person who's one has "unique": their id, and the Unique trait.

const FILE := "res://data/uniques.json"

static var _all := {}
static var _loaded := false


static func all() -> Dictionary:
	if not _loaded:
		_loaded = true
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			for u in d.get("uniques", []):
				_all[str(u.id)] = u
	return _all


## Whether [param name] is a unique character's (no ordinary newcomer is given it).
static func name_taken(name: String) -> bool:
	return all().values().any(func(u): return str(u.name) == name)


## The unique [param id] among [param people], or {}.
static func person(people: Villagers, id: String) -> Dictionary:
	for p in people.people:
		if str(p.get("unique", "")) == id:
			return p
	return {}


static func lost(id: String) -> bool:
	return Chronicle.active != null and Chronicle.active.happened("lost:" + id)


## Someone already here who is this unique (an older save's Miyu): made the unique one, as they are.
static func promote(people: Villagers) -> void:
	for u in all().values():
		var id := str(u.id)
		if not person(people, id).is_empty():
			_note(id)
			continue
		for p in people.people:
			if str(p.name) == str(u.name) and int(p.get("look", -1)) == int(u.look) and not p.has("unique"):
				p["unique"] = id
				Traits.give(p, u.traits)
				_note(id)
				break


static func _note(id: String) -> void:
	if Chronicle.active != null and not Chronicle.active.happened("unique:" + id):
		Chronicle.active.record("unique:" + id)


## The unique [param id] comes to the village (needing a bed, like any newcomer). False if they're here already, or
## lost.
static func arrive(people: Villagers, id: String, quiet := false) -> bool:
	var u: Dictionary = all().get(id, {})
	if u.is_empty() or lost(id) or not person(people, id).is_empty():
		return false
	var level := int(u.get("level", 1))
	var p := {"name": str(u.name), "look": int(u.look), "unique": id, "hasBed": false, "bedX": 0.0, "bedY": 0.0, "level": level, "xp": 0,
		"maxHp": 30.0 + 10.0 * level, "hp": 30.0 + 10.0 * level, "atk": 4.0 + 2.0 * level,
		"hunger": 70.0, "energy": 100.0, "job": 0, "toolsLeft": 0, "bag": "", "bagSlots": 0, "bagLeft": 0}
	Traits.give(p, u.traits)
	people._fix(p)
	people.people.append(p)
	_note(id)
	if not quiet:
		VillageLog.event("arrived:" + str(u.name), "%s has come to the village and needs a bed in a house" % str(u.name))
	return true


## The unique [param id] is lost for good (they never come now).
static func lose(id: String) -> void:
	if Chronicle.active != null and not lost(id):
		Chronicle.active.record("lost:" + id)
