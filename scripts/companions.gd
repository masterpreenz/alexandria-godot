class_name Companions
## Sera's companions as fighters: each unique who goes with her has stats of their own, as Sera has (a CharacterStats),
## made from who they are: their own HP and attack (which grow as they level up in the village), with the mana and
## magic data/companions.json gives them. Gear Sera puts on them (the same slots as hers) and the talents they learn
## change their HP, attack, defense, magic and mana like hers. A spell book given them (Miyu's book of water magic)
## teaches its spells for good. Kept in their person (Villagers) under "companion", saved with the village's people.
##
## Their person's maxHp, atk, maxMana and mana are kept to what their stats come to, so their cards, their bars and
## their fighting go by them; anything else that raises those (a level gained in the village) goes into their own.

const FILE := "res://data/companions.json"

static var _data: Dictionary = {}
static var _combat: Dictionary = {}
static var _by_id := {}            ## unique id -> {stats, person, natural, written}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"character": {}, "books": [], "magic": {}}
	return _data


static func combat() -> Dictionary:
	if _combat.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat.json"))
		_combat = d if d is Dictionary else {}
	return _combat


## A spell's data (combat.json's spells), or {} when there's no such spell yet.
static func spell(id: String) -> Dictionary:
	return combat().get("spells", {}).get(id, {})


## Whether [param p] is someone who can have stats of their own (a unique character).
static func can_have(p: Dictionary) -> bool:
	return p.has("unique") and str(p.unique) != ""


## [param p]'s stats: made the first time they're asked for (from what was saved with them, else from who they are).
static func stats_for(p: Dictionary) -> CharacterStats:
	if not can_have(p):
		return null
	var id := str(p.unique)
	var e: Dictionary = _by_id.get(id, {})
	if not e.is_empty() and is_instance_valid(e.stats) and is_same(e.person, p):
		return e.stats
	if not e.is_empty() and is_instance_valid(e.stats):
		(e.stats as Node).queue_free()
	var saved: Dictionary = p.get("companion", {}) if p.get("companion") is Dictionary else {}
	var natural: Dictionary = saved.get("natural", {}) if saved.get("natural") is Dictionary else {}
	if natural.is_empty():
		# (an older save, or new to it: what they have now is all their own)
		natural = {"maxHp": float(p.get("maxHp", 40.0)), "atk": float(p.get("atk", 6.0))}
	var st := CharacterStats.new()
	st.name = "Companion_" + id
	st.wears_bag = Playable.wears_bag(p)
	st.setup(character_of(p, natural), combat().get("items", {}))
	var json := str(saved.get("stats", ""))
	if json != "" and JSON.parse_string(json) is Dictionary:
		st.from_json(json)
	else:
		# New to it: their level as it is, a talent point for each level past the first, full of mana.
		st.level = maxi(1, int(p.get("level", 1)))
		st.talent_points = st.level - 1
		st.xp = int(p.get("xp", 0))
		st.mana = st.stat("maxMana")
	st.hp = float(p.get("hp", st.stat("maxHp")))
	if Party.active != null:
		st.speaker = Party.active.miko
		Party.active.add_child(st)
	_by_id[id] = {"stats": st, "person": p, "natural": natural, "written": {"maxHp": float(p.get("maxHp", 40.0)), "atk": float(p.get("atk", 6.0))}}
	sync(p)
	return st


## What [param p]'s stats are built on: the companions' base, with their own HP and attack (the talents are Sera's
## web); or, for Sera herself (a companion while someone else is played), her own as the player has them.
static func character_of(p: Dictionary, natural: Dictionary) -> Dictionary:
	if Playable.own_levels(p):
		var mine: Dictionary = (combat().get("character", {}) as Dictionary).duplicate(true)
		mine.base["maxHp"] = float(natural.get("maxHp", mine.base.get("maxHp", 100.0)))
		mine.base["attack"] = float(natural.get("atk", mine.base.get("attack", 6.0)))
		return mine
	return _character(natural)


# A companion's: the companions' base, with their own HP and attack; the talents are Sera's web.
static func _character(natural: Dictionary) -> Dictionary:
	var own: Dictionary = data().get("character", {})
	var c: Dictionary = combat().get("character", {}).duplicate()
	var base: Dictionary = (own.get("base", {}) as Dictionary).duplicate()
	base["maxHp"] = float(natural.get("maxHp", 40.0))
	base["attack"] = float(natural.get("atk", 6.0))
	c["base"] = base
	c["perLevel"] = own.get("perLevel", {})
	c["xpPerLevel"] = int(own.get("xpPerLevel", 30))
	return c


## Brings [param p]'s person and body up to date with their stats (and their stats with anything the village gave
## them meanwhile: a level, more HP). [param body] is theirs in the world, if they're about.
static func sync(p: Dictionary, body: Villager = null) -> void:
	var e: Dictionary = _by_id.get(str(p.get("unique", "")), {})
	if e.is_empty() or not is_instance_valid(e.stats):
		return
	var st: CharacterStats = e.stats
	var nat: Dictionary = e.natural
	var wrote: Dictionary = e.written
	# Raised elsewhere since (a level gained at work): theirs to keep.
	var more_hp := float(p.get("maxHp", wrote.maxHp)) - float(wrote.maxHp)
	var more_atk := float(p.get("atk", wrote.atk)) - float(wrote.atk)
	if absf(more_hp) > 0.001 or absf(more_atk) > 0.001:
		nat.maxHp = float(nat.maxHp) + more_hp
		nat.atk = float(nat.atk) + more_atk
		st.character.base["maxHp"] = nat.maxHp
		st.character.base["attack"] = nat.atk
	# Their level is the village's: each one gained is a talent point.
	var lv := maxi(1, int(p.get("level", 1)))
	if lv > st.level:
		st.talent_points += lv - st.level
		st.level = lv
	st.xp = int(p.get("xp", 0))
	var t := st.total()
	var most := maxf(1.0, float(t.get("maxHp", 40.0)))
	p["maxHp"] = most
	p["atk"] = float(t.get("attack", 6.0))
	p["maxMana"] = float(t.get("maxMana", 0.0))
	p["mana"] = st.mana
	wrote.maxHp = most
	wrote.atk = p.atk
	if body == null:
		body = body_of(p)
	if body != null and body.hit != null and is_instance_valid(body.hit):
		if not is_equal_approx(body.hit.max_hp, most):
			body.hit.max_hp = most
			body.hit.hp = minf(body.hit.hp, most)
		st.hp = body.hit.hp
		p["hp"] = body.hit.hp
	else:
		p["hp"] = minf(float(p.get("hp", most)), most)
		st.hp = p.hp


## Everyone with stats brought up to date (the party's own clock, a couple of times a second).
static func sync_all() -> void:
	for id in _by_id.keys():
		var e: Dictionary = _by_id[id]
		if is_instance_valid(e.stats):
			sync(e.person)


## [param p]'s body in the world, or null.
static func body_of(p: Dictionary) -> Villager:
	for v in Villager.all:
		if is_instance_valid(v) and is_same(v.person, p):
			return v
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == str(p.get("unique", "?")):
			return v
	return null


## Writes everyone's stats into their person, for the save.
static func store_all(people: Array) -> void:
	for p in people:
		if p is Dictionary and can_have(p):
			store(p)


## [param p] isn't a companion now (they're the one played): their stats, written into their person, let go of.
static func forget(p: Dictionary) -> void:
	var id := str(p.get("unique", ""))
	var e: Dictionary = _by_id.get(id, {})
	if e.is_empty():
		return
	store(p)
	if is_instance_valid(e.stats):
		(e.stats as Node).queue_free()
	_by_id.erase(id)


static func store(p: Dictionary) -> void:
	var e: Dictionary = _by_id.get(str(p.get("unique", "")), {})
	if e.is_empty() or not is_instance_valid(e.stats) or not is_same(e.person, p):
		return
	sync(p)
	p["companion"] = {"stats": (e.stats as CharacterStats).to_json(), "natural": e.natural}


## A hit on a companion, softened by their defense the way Sera's is (5 defense takes a fifth off, 20 half): the
## share it takes off is given back as soon as it lands.
static func soften(p: Dictionary, hit: Damageable, amount: float) -> void:
	var e: Dictionary = _by_id.get(str(p.get("unique", "")), {})
	if e.is_empty() or not is_instance_valid(e.stats) or hit == null or not hit.alive():
		return
	var defense := maxf(0.0, (e.stats as CharacterStats).stat("defense"))
	if defense > 0.0:
		hit.heal(amount * (1.0 - 20.0 / (20.0 + defense)))


# ---- Spell books ----

## The book Sera could give [param p] now (she carries it, it's theirs, they haven't had it), or {}.
static func book_for(p: Dictionary, bag: Bag) -> Dictionary:
	if not can_have(p) or bag == null:
		return {}
	for b in data().get("books", []):
		if str(b.get("for", "")) != str(p.unique) or not bag.items.has(str(b.item)):
			continue
		var records: Array = b.get("records", [])
		if Chronicle.active != null and not records.is_empty() and Chronicle.active.happened(str(records[records.size() - 1])):
			continue
		return b
	return {}


## Sera hands [param p] the book [param b]: out of her bag, the story told of it, and its spells learnt at once.
## The spells they learnt.
static func give_book(p: Dictionary, b: Dictionary, bag: Bag) -> Array:
	var at := bag.items.find(str(b.item))
	if at < 0:
		return []
	bag.items[at] = ""
	bag.changed.emit()
	if Chronicle.active != null:
		for ev in b.get("records", []):
			if not Chronicle.active.happened(str(ev)):
				Chronicle.active.record(str(ev))
	var st := stats_for(p)
	var got := []
	for sp in b.get("spells", []):
		if not st.learned.has(sp):
			st.learned[str(sp)] = str(b.get("from", UiKit.item(str(b.item)).get("name", b.item)))
			got.append(str(sp))
	st.changed.emit()
	sync(p)
	return got


## A spell's name as the game shows it.
static func spell_name(id: String) -> String:
	return str(spell(id).get("name", id.capitalize()))
