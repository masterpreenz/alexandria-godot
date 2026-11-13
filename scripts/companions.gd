class_name Companions
## Sera's companions as fighters: each unique who goes with her has stats of their own, as Sera has (a CharacterStats),
## made from who they are: their own HP and attack (which grow as they level up in the village), with the mana and
## magic data/companions.json gives them. Gear Sera puts on them (the same slots as hers) and the talents they learn
## change their HP, attack, defense, magic and mana like hers. A spell book given them (Miyu's book of water magic)
## opens their own tree of its magic (Miyu's ice and water), its first skill learnt at once. Kept in their person
## (Villagers) under "companion", saved with the village's people.
##
## Their person's maxHp, atk, maxMana and mana are kept to what their stats come to, so their cards, their bars and
## their fighting go by them; anything else that raises those (a level gained in the village) goes into their own.

const FILE := "res://data/companions.json"

static var _data: Dictionary = {}
static var _combat: Dictionary = {}
static var _by_id := {}            ## unique id -> {stats, person, natural, written}
static var _trees := {}            ## unique id -> their own talent tree, or {}


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
		# New to it: their level as it is, talent points for each level past the first, full of mana.
		st.level = maxi(1, int(p.get("level", 1)))
		st.talent_points = (st.level - 1) * st.points_per_level()
		st.xp = int(p.get("xp", 0))
		st.mana = st.stat("maxMana")
	st.hp = float(p.get("hp", st.stat("maxHp")))
	if Party.active != null:
		st.speaker = Party.active.miko
		Party.active.add_child(st)
	_by_id[id] = {"stats": st, "person": p, "natural": natural, "written": {"maxHp": float(p.get("maxHp", 40.0)), "atk": float(p.get("atk", 6.0))}}
	sync(p)
	return st


## What [param p]'s stats are built on: the companions' base, with their own HP and attack, and their own talent tree
## if they have one (Miyu's ice and water), else Sera's; or, for Sera herself (a companion while someone else is
## played), her own as the player has them.
static func character_of(p: Dictionary, natural: Dictionary) -> Dictionary:
	if Playable.own_levels(p):
		var mine: Dictionary = (combat().get("character", {}) as Dictionary).duplicate(true)
		mine.base["maxHp"] = float(natural.get("maxHp", mine.base.get("maxHp", 100.0)))
		mine.base["attack"] = float(natural.get("atk", mine.base.get("attack", 6.0)))
		return mine
	return _character(natural, str(p.get("unique", "")))


# A companion's: the companions' base, with their own HP and attack; the talents are their own tree's, else Sera's.
static func _character(natural: Dictionary, id := "") -> Dictionary:
	var own: Dictionary = data().get("character", {})
	var c: Dictionary = combat().get("character", {}).duplicate()
	var own_tree := tree(id)
	for k in own_tree:
		c[k] = own_tree[k]
	var base: Dictionary = (own.get("base", {}) as Dictionary).duplicate()
	base["maxHp"] = float(natural.get("maxHp", 40.0))
	base["attack"] = float(natural.get("atk", 6.0))
	c["base"] = base
	c["perLevel"] = own.get("perLevel", {})
	c["xpPerLevel"] = int(own.get("xpPerLevel", 30))
	return c


## [param id]'s own talent tree (data/companions.json's trees), with Sera's Life & Body row added to it (its
## talents, its lines and the old ids folded into them); {} for someone who learns on Sera's.
static func tree(id: String) -> Dictionary:
	if _trees.has(id):
		return _trees[id]
	var path := str(data().get("trees", {}).get(id, ""))
	var out := {}
	if path != "":
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			out = d
			var sera: Dictionary = combat().get("character", {})
			var talents: Array = (out.get("talents", []) as Array).duplicate()
			var life := {}
			for t in sera.get("talents", []):
				if int(t.get("group", -1)) < 0:
					talents.append(t)
					life[str(t.id)] = true
			out["talents"] = talents
			out["lifeLines"] = sera.get("lifeLines", [])
			var merged := {}
			for k in sera.get("merged", {}):
				if life.has(str(sera.merged[k])):
					merged[k] = sera.merged[k]
			out["merged"] = merged
			out["freeIds"] = sera.get("freeIds", [])
	_trees[id] = out
	return out


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
	# Their level is the village's: each one gained brings talent points.
	var lv := maxi(1, int(p.get("level", 1)))
	if lv > st.level:
		st.talent_points += (lv - st.level) * st.points_per_level()
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


## Sera hands [param p] the book [param b]: out of her bag, the story told of it, and what it teaches learnt at once
## (the first rank of its talent in their own tree, opening the rest of it). The spells they learnt.
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
	var got := teach(st, b)
	sync(p)
	return got


## What book [param b] teaches, put into [param st]: its talent at rank 1 for nothing (and any spells it teaches
## outright). The spells learnt.
static func teach(st: CharacterStats, b: Dictionary) -> Array:
	var got := []
	var id := str(b.get("talent", ""))
	if id != "" and not st.talent(id).is_empty() and not st.unlocked(id):
		st.ranks[id] = 1
		st.gifted[id] = 1
		var g := str(st.talent(id).get("grantsSpell", ""))
		if g != "":
			got.append(g)
	for sp in b.get("spells", []):
		if not st.learned.has(sp):
			st.learned[str(sp)] = str(b.get("from", UiKit.item(str(b.item)).get("name", b.item)))
			got.append(str(sp))
	st.changed.emit()
	return got


## A spell's name as the game shows it.
static func spell_name(id: String) -> String:
	return str(spell(id).get("name", id.capitalize()))


## A companion's own bag, for what they carry for themselves (their potions), or null while they have none: what
## they'd take then comes from the bag of the one played.
static func bag_of(_p: Dictionary) -> Bag:
	return null
