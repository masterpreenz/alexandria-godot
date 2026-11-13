class_name Tactics
extends RefCounted
## A companion's tactics (the Tactics window, from their row in the party window): how they fight beside the one
## played. Their stance: close in or keep their distance, how freely they spend their mana and how much they keep
## back, whether they step out of a strip a monster has marked for its charge or leap, and whom they look after
## first. And their rules, tried top to bottom each time they think: "when this, do that", the first that holds and
## can be done now is done, each as readily as its weight says. data/tactics.json holds the four presets (Melee,
## Ranged, Defender, Support) and the lists the rules are made from. Kept in their person (person.tactics), so they
## go with them and are saved; someone without any starts with the preset that suits them.

const FILE := "res://data/tactics.json"
const STANCE_KEYS := ["range", "frequency", "reserve", "dodge", "protect", "leash"]

static var _data := {}
static var _entries := {}          ## "list:id" -> its entry in data/tactics.json (looked up once)
static var _kinds := {}            ## spell -> what it's for (worked out once)
static var _drink_sound := "?"     ## the sound of a potion drunk (data/needs.json's drinkSound), once looked up


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.get_file_as_string(FILE)
		var d: Variant = JSON.parse_string(f) if f != "" else null
		_data = d if d is Dictionary else {"presets": []}
	return _data


## A preset by id (melee, ranged, defender, support), or {}.
static func preset(id: String) -> Dictionary:
	for p in data().get("presets", []):
		if str(p.id) == id:
			return p
	return {}


## The preset someone starts with: theirs by who they are (Miyu: Support; Sera: Ranged), else Melee.
static func default_preset(p: Dictionary) -> String:
	var d: Dictionary = data().get("defaults", {})
	var id := str(p.get("unique", ""))
	return str(d.get(id, d.get("", "melee")))


## Their tactics (made from their preset the first time they're asked for).
static func of(p: Dictionary) -> Dictionary:
	var t: Variant = p.get("tactics")
	if not (t is Dictionary and t.get("rules") is Array and t.get("stance") is Dictionary):
		t = _from_preset(default_preset(p))
		p["tactics"] = t
	return t


## Their tactics set to a preset's (its stance and rules, copied).
static func use_preset(p: Dictionary, id: String) -> void:
	p["tactics"] = _from_preset(id)


static func _from_preset(id: String) -> Dictionary:
	var pr := preset(id)
	if pr.is_empty():
		pr = preset("melee")
	return {"preset": str(pr.get("id", "custom")), "stance": (pr.get("stance", {}) as Dictionary).duplicate(true),
		"rules": (pr.get("rules", []) as Array).duplicate(true)}


## Something changed by hand: no longer a preset's.
static func edited(p: Dictionary) -> void:
	of(p)["preset"] = "custom"


static func stance(p: Dictionary) -> Dictionary:
	return of(p).stance


## Whether they keep their distance (fighting from range) rather than closing in.
static func keeps_distance(p: Dictionary) -> bool:
	return str(stance(p).get("range", "close")) == "distance"


static func _entry(list: String, id: String) -> Dictionary:
	var key := list + ":" + id
	if not _entries.has(key):
		var found := {}
		for e in data().get(list, []):
			if str(e.get("id", "")) == id:
				found = e
		_entries[key] = found
	return _entries[key]


static func condition(id: String) -> Dictionary:
	return _entry("conditions", id)


static func action(id: String) -> Dictionary:
	return _entry("actions", id)


static func frequency(id: String) -> Dictionary:
	var f := _entry("frequencies", id)
	return f if not f.is_empty() else {"gap": 1.2, "reserve": 0}


## A weight's settings, 1 (Rarely) to 5 (Always): every (seconds before it fires again), chance, label.
static func weight(w: int) -> Dictionary:
	var ws: Array = data().get("weights", [])
	if ws.is_empty():
		return {"label": "Normal", "every": 1.5, "chance": 1.0}
	return ws[clampi(w, 1, ws.size()) - 1]


## What a spell's for: attack, area (it covers where the monsters are thickest), heal, guard, or "" (not for a
## companion to cast on their own: a shikigami, one not made yet).
static func kind_of(sp: String) -> String:
	if not _kinds.has(sp):
		_kinds[sp] = _kind_of(sp)
	return _kinds[sp]


static func _kind_of(sp: String) -> String:
	var s := Companions.spell(sp)
	if s.is_empty() or str(s.get("effect", "")) in ["Shikigami", "Unmade"]:
		return ""
	var uses: Dictionary = Companions.data().get("magic", {}).get("spells", {})
	if uses.has(sp):
		var u := str(uses[sp].get("use", ""))
		if u == "attack" and str(uses[sp].get("aim", "")) == "group":
			return "area"
		return u
	if float(s.get("damage", 0.0)) <= 0.0:
		return ""
	var d := str(s.get("delivery", ""))
	if d in ["Ground", "SkyFall"] and float(s.get("aoeRadius", 0.0)) >= 150.0:
		return "area"
	return "attack" if d in ["Directional", "SkyFall", "Ground"] else ""


## The spells of theirs a rule's spell stands for (a kind, "@heal": all they know of it, the most valued first; or
## one by name, if they know it). [param known]: what they know, if it's to hand already.
static func spells_for(st: CharacterStats, spell: String, known: Array = []) -> Array:
	if st == null:
		return []
	if known.is_empty():
		known = st.known_spells()
	if not spell.begins_with("@"):
		return [spell] if known.has(spell) and kind_of(spell) != "" else []
	var kind := spell.substr(1)
	var uses: Dictionary = Companions.data().get("magic", {}).get("spells", {})
	var out := known.filter(func(k): return kind_of(str(k)) == kind)
	# (the best attack spell they have, else their area ones: someone with only Ice Blast still attacks)
	if out.is_empty() and kind == "attack":
		out = known.filter(func(k): return kind_of(str(k)) == "area")
	out.sort_custom(func(a, b): return float(uses.get(a, {}).get("priority", Companions.spell(a).get("damage", 0.0))) > float(uses.get(b, {}).get("priority", Companions.spell(b).get("damage", 0.0))))
	return out


## Whether a rule can be used by them at all (a spell they don't know: shown greyed, and passed over).
static func usable(st: CharacterStats, rule: Dictionary, known: Array = []) -> bool:
	if str(rule.get("do", "")) != "cast":
		return true
	return not spells_for(st, str(rule.get("spell", "")), known).is_empty()


## A spell choice's name in the window: a kind's ("Best heal") or the spell's own.
static func spell_label(spell: String) -> String:
	if spell.begins_with("@"):
		return str(_entry("spellKinds", spell).get("label", spell))
	return Companions.spell_name(spell)


## A rule in words: "Ally's HP below 50% -> Cast Best heal (Often)".
static func rule_text(r: Dictionary) -> String:
	var c := condition(str(r.get("when", "")))
	var w := str(c.get("label", r.get("when", "")))
	match str(c.get("value", "")):
		"pct": w += " %d%%" % int(r.get("value", c.get("default", 50)))
		"count": w += " %d" % int(r.get("value", c.get("default", 2)))
	var a := action(str(r.get("do", "")))
	var d := str(a.get("label", r.get("do", "")))
	if bool(a.get("spell", false)):
		d += " " + spell_label(str(r.get("spell", "@attack")))
	return "%s -> %s (%s)" % [w, d, weight(int(r.get("weight", 3))).label]


## The marked strip [param p] is standing in (one still to be got out of), or null.
static func strip_at(p: Vector2) -> Telegraph:
	var most := float(data().get("dodgeFill", 0.92))
	for s in Telegraph.live:
		if is_instance_valid(s) and s.length > 1.0 and s.fill < most and s.covers(p):
			return s
	return null


## [param body] drinks a [param potion] (HpPotion or ManaPotion), from their own bag, else the bag of the one played:
## what it gives back, as when Sera drinks one. Whether they drank; with none left they say so, quietly, now and then.
static func drink(body: Villager, st: CharacterStats, potion: String) -> bool:
	var w := body.world
	var bag := Companions.bag_of(body.person)
	if bag == null or bag.count(potion) <= 0:
		var lead := w.player as Miko
		bag = lead.bag if lead != null else null
	var what: String = Needs.POTIONS[potion][0]
	var hp_now := body.hit.hp if body.hit != null else st.hp
	var most: float = body.hit.max_hp if what == "hp" and body.hit != null else (st.stat("maxHp") if what == "hp" else st.stat("maxMana"))
	var now_v: float = hp_now if what == "hp" else st.mana
	if most <= 0.0 or now_v >= most - 0.5:
		return false
	if bag == null or bag.count(potion) <= 0:
		var t := Villager.now()
		if t >= float(body.get_meta("no_potion_said", -99.0)) + 12.0:
			body.set_meta("no_potion_said", t)
			FloatingText.spawn(w, "No %s left" % ("health potions" if what == "hp" else "mana potions"), body.position + Vector2(0, -1.4 * w.px), Color(0.8, 0.78, 0.72, 0.85), 14, 1.2)
		return false
	if not bag.spend(potion, 1):
		return false
	var got := minf(float(Needs.POTIONS[potion][1]), most - now_v)
	if what == "hp":
		if body.hit != null:
			body.hit.hp += got
		st.hp = minf(most, now_v + got)
		body.person["hp"] = st.hp
		FloatingText.spawn(w, "+%d HP" % roundi(got), body.position + Vector2(0, -1.4 * w.px), Color(0.95, 0.4, 0.4), 18, 1.0)
	else:
		st.mana += got
		body.person["mana"] = st.mana
		FloatingText.spawn(w, "+%d mana" % roundi(got), body.position + Vector2(0, -1.4 * w.px), Color(0.45, 0.65, 1.0), 18, 1.0)
	st.changed.emit()
	# A moment tipping it back, and the sound of it.
	body.cast_until = Villager.now() + 0.45
	body.cast_toward = body.position + Vector2(1.0 if body.facing_right else -1.0, 0.5)
	body.show_mood("success", 1.5)
	if _drink_sound == "?":
		var nd: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/needs.json"))
		_drink_sound = str(nd.get("drinkSound", "")) if nd is Dictionary else ""
	if _drink_sound != "":
		Sfx.play(w, Sfx.stream(_drink_sound), body.position, 0.7, 0.08)
	return true
