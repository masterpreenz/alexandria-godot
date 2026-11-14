class_name Playable
extends Node
## Who's played: Sera, or one of her companions (data/playables.json: Miyu for now). In the village, talking to a
## companion who's in the party or lives there, "Play as <name>" hands them the controls: the body that's played
## (Miko, always the one moved) takes on their name, their art, their stats (level, HP, mana, talents, gear, the spells
## they know, and the hotbar they had), and their hunger, thirst and tiredness; they stay where they stood. The one
## left becomes a companion where they stood, with their own stats and spells (cast on their own, as Miyu's are), in
## the party and following. "Play as Sera" on Sera, once she's a companion, turns it back.
##
## The one played is kept out of the village's people (their person is [member played]); the one left takes their
## place there: in their bed if they had one, and in the party. Each keeps their own bag (the one played has theirs
## as Miko's bag; the one left takes theirs as a companion's, person.pack), their water pouch's fill and their kit;
## the coins are the party's purse and stay with whoever's played, and so do the life skills.
##
## Saved as "player.playing"; "player.stats" is always Sera's own, so an older game (or one saved as Sera) loads as it
## always has.

const FILE := "res://data/playables.json"
const LEAD := "sera"              ## Sera's id (her person's "unique" while she's a companion)
## What a companion can be doing and still be switched to: standing, walking about, or following.
## What keeps someone from being played this moment: fighting, running for their life, asleep, down in the cellar.
## (Anything else, work included, they drop.)
const BUSY := [Villager.State.FIGHT, Villager.State.FLEE, Villager.State.ASLEEP, Villager.State.CELLAR]

static var active: Playable
static var _data := {}

var world: World
var miko: Miko
var people: Villagers
var hotbar: Hotbar
var who := LEAD                   ## the id of whoever's played
var played: Dictionary = {}       ## their person (Sera's, made the first time she's left as a companion)
var bars := {}                    ## id -> their hotbar as they left it: {bar (Hotbar.to_json), offered (skills put on it)}
var _lead_data: Dictionary        ## player.json: Sera's art as the player
var _lead_look: Dictionary = {}   ## Sera's art as a villager (made from hers as the player, the first time it's needed)
var _looks := {}                  ## id -> their art as the player (made from their villager look)
var kit: Dictionary = {}          ## the kit of whoever's played (see [Kit]): it goes with them into their person


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"playables": [{"id": LEAD, "name": Miko.NAME, "art": "player", "default": true}]}
	return _data


## What playables.json says of [param id], or {} when they can't be played.
static func entry(id: String) -> Dictionary:
	for e in data().get("playables", []):
		if str(e.get("id", "")) == id:
			return e
	return {}


## The name of whoever's played (Sera's when nobody's set up yet): the name on her card, in the party window, in a talk.
static func name_now() -> String:
	if active == null:
		return Miko.NAME
	return Playable.name_of(active.who)


## The name of [param id]: playables.json's, else the unique's.
static func name_of(id: String) -> String:
	var e := entry(id)
	if e.has("name"):
		return str(e.name)
	return str(Uniques.all().get(id, {}).get("name", id))


## Whether [param p] is Sera as a companion (her stats are hers as the player: they level by fighting, not by work,
## and her bag's the one she wears).
static func own_levels(p: Dictionary) -> bool:
	return str(entry(str(p.get("unique", ""))).get("stats", "")) == "player"


## Whether what [param _p] wears changes the room in their bag: everyone's, now each has a bag of their own.
static func wears_bag(_p: Dictionary) -> bool:
	return true


## [param p]'s art as a villager when it isn't a villagers.json look (Sera's, made from hers as the player), else {}.
static func villager_look(p: Dictionary) -> Dictionary:
	if active == null or not p.has("unique"):
		return {}
	if str(entry(str(p.unique)).get("art", "")) != "player":
		return {}
	return active._sera_as_villager()


## The bag's extra slots from the talents of whoever's played (Sera's pockets): the bag is theirs.
static func bag_slots(m: Miko) -> int:
	return int(m.stats.stat("bagSlots")) if m.stats != null else 0


## Their voice's pitch in a talk, when playables.json gives one (else 0: by their look).
static func pitch_of(p: Dictionary) -> float:
	return float(entry(str(p.get("unique", ""))).get("pitch", 0.0))


func setup(w: World, m: Miko, vs: Villagers, bar: Hotbar) -> void:
	world = w
	miko = m
	people = vs
	hotbar = bar
	active = self
	_lead_data = m.data
	for e in data().get("playables", []):
		if bool(e.get("default", false)):
			who = str(e.id)


# ---- Who can be switched to ----

## Why [param v] can't be played now ("" when they can): someone who can be played, in the village with her (in her
## party or not), up and about and not fighting or asleep, and the story not in the middle of something.
func why_not(v: Villager) -> String:
	if v == null or not is_instance_valid(v):
		return "nobody"
	var id := str(v.person.get("unique", ""))
	if id == "" or entry(id).is_empty():
		return "not playable"
	if id == who:
		return "already played"
	if not world.village.founded() or not world.village.contains(miko.position) or not world.village.contains(v.position):
		return "not in the village"
	if v.in_bed or v.state in BUSY or v.hit == null or not v.hit.alive():
		return "busy"
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs != null and needs.sleep != Needs.Sleep.AWAKE:
		return "asleep"
	var fainting: Fainting = miko.get_node_or_null("Fainting")
	if fainting != null and fainting.fainted:
		return "fainted"
	if Story.active != null and Story.active.beat >= 0:
		return "the story"
	if not Scenes.for_speaker(v.person).is_empty():
		return "a scene waits"
	if _rumor_unsafe():
		return "a rumor"
	return ""


# A rumor in the middle of a step that's marked "unsafe" (rumors.json: nobody's switched to then).
func _rumor_unsafe() -> bool:
	var r := Rumors.active
	if r == null:
		return false
	for id in r.heard:
		var st: Dictionary = r.heard[id]
		if str(st.get("state", "")) == "open" and r.by_id.has(id) and bool(r.step_of(r.by_id[id], st).get("unsafe", false)):
			return true
	return false


# ---- Switching ----

## Hands the controls to [param v] (see [method why_not]); the one played now is left as a companion where they
## stood. True if it happened.
func switch_to(v: Villager) -> bool:
	if why_not(v) != "":
		return false
	var them: Dictionary = v.person
	var to_id := str(them.unique)
	var me := _me_as_person()
	# Theirs as a companion, written into their person and let go of.
	Companions.stats_for(them)
	Companions.forget(them)
	# Where each stands now: they go on from where they are; the one left stays where they were.
	var here := miko.position
	var there := v.position
	var my_right := miko.facing_right
	var my_up := miko.facing_up
	_swap_in_village(them, me, to_id)
	_dress(v, me)
	_bags(me, them)
	_wear(to_id, them)
	_needs_from(them)
	miko.bag.worn = miko.stats.equipped
	miko.bag.changed.emit()
	miko.place(there)
	miko.facing_right = v.facing_right
	miko.facing_up = v.facing_up
	v.position = here
	v.reset_physics_interpolation()
	v.facing_right = my_right
	v.facing_up = my_up
	# The one left: their stats as a companion, from what was just written into their person.
	Companions.stats_for(me)
	Companions.sync(me, v)
	CompanionMagic.give(v)
	if Party.active != null:
		Party.active._hud()
	Puffs.burst(world, miko.position + Vector2(0, -0.4 * world.px), 0.6, 10)
	VillageLog.event("played:" + to_id, "You're playing %s now" % name_of(to_id))
	return true


# Each keeps their own bag: the one played now ([param me]) has theirs written into their person (the purse
# aside), and [param them] takes theirs as Miko's bag, with the purse; so too the water pouch's fill and the kit.
func _bags(me: Dictionary, them: Dictionary) -> void:
	var bag := miko.bag
	var gold := bag.count("Gold")
	bag.counts["Gold"] = 0
	me["pack"] = bag.to_json()
	var json := str(them.get("pack", ""))
	bag.from_json(json if json != "" and JSON.parse_string(json) is Dictionary else JSON.stringify({}), [])
	bag.counts["Gold"] = bag.count("Gold") + gold
	them.erase("pack")
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs != null:
		me["pouch"] = needs.pouch
		needs.pouch = clampf(float(them.get("pouch", Needs.MAX)), 0.0, Needs.MAX)
		them.erase("pouch")
	if not kit.is_empty():
		me["kit"] = kit
	kit = them.get("kit", {}) if them.get("kit") is Dictionary else {}
	them.erase("kit")


# The one played now as a person (to be left as a companion): their stats, HP and needs written in.
func _me_as_person() -> Dictionary:
	var p := played
	if p.is_empty():
		p = _new_sera()
	var st := miko.stats
	var t := st.total()
	p["name"] = name_of(who)
	p["level"] = st.level
	p["xp"] = st.xp
	p["maxHp"] = maxf(1.0, float(t.get("maxHp", 100.0)))
	p["hp"] = clampf(st.hp, 1.0, float(p.maxHp))
	p["atk"] = float(t.get("attack", 6.0))
	p["maxMana"] = float(t.get("maxMana", 0.0))
	p["mana"] = st.mana
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs != null:
		p["hunger"] = needs.hunger
		p["thirst"] = needs.thirst
		p["energy"] = needs.energy
	var was: Dictionary = p.get("companion", {}) if p.get("companion") is Dictionary else {}
	var natural: Dictionary = was.get("natural", {}) if was.get("natural") is Dictionary else {}
	if natural.is_empty():
		# (Sera: her base as the player has it)
		var base: Dictionary = st.character.get("base", {})
		natural = {"maxHp": float(base.get("maxHp", 100.0)), "atk": float(base.get("attack", 6.0))}
	p["companion"] = {"stats": st.to_json(), "natural": natural}
	return p


# Sera as a person, the first time she's left as a companion.
func _new_sera() -> Dictionary:
	var e := entry(LEAD)
	var p := {"name": name_of(LEAD), "look": int(e.get("look", 1)), "unique": LEAD, "hasBed": false, "bedX": 0.0, "bedY": 0.0,
		"level": 1, "xp": 0, "maxHp": 100.0, "hp": 100.0, "atk": 6.0, "hunger": 100.0, "energy": 100.0, "thirst": 100.0,
		"job": 0, "toolsLeft": 0, "bag": "", "bagSlots": 0, "bagLeft": 0, "traits": (e.get("traits", []) as Array).duplicate()}
	people._fix(p)
	return p


# The one left takes [param them]'s place among the village's people: their bed, their place in the party.
func _swap_in_village(them: Dictionary, me: Dictionary, to_id: String) -> void:
	for k in ["hasBed", "bedX", "bedY"]:
		me[k] = them.get(k, me.get(k))
	var i := -1
	for j in people.people.size():
		if is_same(people.people[j], them):
			i = j
	if i >= 0:
		people.people[i] = me
	else:
		people.people.append(me)
	for k in people.living:
		if is_same(people.living[k][0], them):
			people.living[k][0] = me
	var nm := str(them.name)
	if people.waiting.has(nm):
		people.waiting[str(me.name)] = people.waiting[nm]
		people.waiting.erase(nm)
	var party := Party.active
	if party == null:
		return
	# (they swap places: the one left takes the other's place in the party if they had one, else lives in the village as
	# they did: not brought along)
	var at := party.members.find(to_id)
	if at >= 0:
		party.members[at] = who
	party.waiting.erase(to_id)
	party.waiting.erase(who)
	# (she'd come along again, sent home)
	if Chronicle.active != null and not Chronicle.active.happened("party:" + who):
		Chronicle.active.record("party:" + who)


# Body [param v] becomes [param me]'s: their name, their art, their HP; whatever it was at, stopped.
func _dress(v: Villager, me: Dictionary) -> void:
	v._let_go()
	v.job = null
	v.route = null
	v.person = me
	v.name = str(me.name)
	var lk: Dictionary = people._look_for(me)
	v.look = lk
	v.s = lk.settings
	v.hit.max_hp = float(me.maxHp)
	v.hit.hp = clampf(float(me.hp), 1.0, v.hit.max_hp)
	v._stand(Villager.now(), 0.3)


# The body that's played becomes [param id]'s ([param p] their person): their stats, their art, their hotbar (not
# when loading: the hotbar loaded is theirs already).
func _wear(id: String, p: Dictionary, loading := false) -> void:
	if not loading:
		_bar_out(who)
	who = id
	played = p
	var saved: Dictionary = p.get("companion", {}) if p.get("companion") is Dictionary else {}
	var natural: Dictionary = saved.get("natural", {}) if saved.get("natural") is Dictionary else {}
	if natural.is_empty():
		natural = {"maxHp": float(p.get("maxHp", 40.0)), "atk": float(p.get("atk", 6.0))}
	_put_stats(Companions.character_of(p, natural), str(saved.get("stats", "")), wears_bag(p))
	miko.set_look(player_look(id, p))
	if not loading:
		_bar_in(id)


# Her stats become someone else's: what they're built on, then everything saved of theirs.
func _put_stats(c: Dictionary, json: String, wears: bool) -> void:
	var st := miko.stats
	st.character = c
	st._talents.clear()
	for t in c.get("talents", []):
		st._talents[t.id] = t
	st.wears_bag = wears
	st.buffs.clear()
	st.shields.clear()
	st.guards.clear()
	if json != "" and JSON.parse_string(json) is Dictionary:
		st.from_json(json)
	else:
		st.ranks.clear()
		st.learned = {}
		st.equipped = []
		st.from_json(JSON.stringify({"level": 1}))
	st.changed.emit()


# Their hunger, thirst and tiredness become hers (the pouch is the bag's: it stays).
func _needs_from(p: Dictionary) -> void:
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs == null:
		return
	needs.hunger = clampf(float(p.get("hunger", 100.0)), 0.0, Needs.MAX)
	needs.thirst = clampf(float(p.get("thirst", 100.0)), 0.0, Needs.MAX)
	needs.energy = clampf(float(p.get("energy", 100.0)), 0.0, Needs.MAX)


# The hotbar as [param id] left it (theirs, kept), or a new one for someone who's not been played: their skills put
# on it afresh (food kept).
func _bar_out(id: String) -> void:
	if hotbar != null:
		bars[id] = {"bar": hotbar.to_json(), "offered": hotbar._offered.keys()}


func _bar_in(id: String) -> void:
	if hotbar == null:
		return
	hotbar._offered.clear()
	if bars.has(id):
		hotbar.from_json(str(bars[id].bar))
		for sp in bars[id].get("offered", []):
			hotbar._offered[str(sp)] = true
	else:
		for i in hotbar.slots.size():
			if str(hotbar.slots[i]).begins_with("spell:"):
				hotbar.slots[i] = ""
	hotbar._sync_skills()


# ---- Art ----

## [param id]'s art as the player (laid out as player.json is): Sera's own, or made from their villager look: their
## walk and idle for moving and standing (the walk a bit quicker for running), the stab for a swing and its strike frame
## for a cast; their sleeping, mining, chopping, cooking, fishing and fainting for those.
func player_look(id: String, p: Dictionary = {}) -> Dictionary:
	if str(entry(id).get("art", "look")) == "player":
		return _lead_data
	if _looks.has(id):
		return _looks[id]
	var looks: Array = people.d.get("looks", [])
	var li := int(p.get("look", Uniques.all().get(id, {}).get("look", 0)))
	if looks.is_empty():
		return _lead_data
	var lk: Dictionary = looks[clampi(li, 0, looks.size() - 1)]
	var s: Dictionary = lk.settings
	var d: Dictionary = _lead_data.duplicate(true)
	var stab_down: Array = s.get("stabDown", [])
	var stab_up: Array = s.get("stabUp", [])
	var strike := int((s.get("stabStrikes", [0]) as Array)[0]) if not (s.get("stabStrikes", []) as Array).is_empty() else 0
	var swing := ((_lead_data.frames.get("attackDownLeft", []) as Array).size())
	d.frames = {
		"idleDownLeft": [int(s.idleDown)], "idleUpLeft": [int(s.idleUp)],
		"runDownLeft": s.get("walkDown", []), "runUpLeft": s.get("walkUp", []), "runDownRight": [], "runUpRight": [],
		"castDownLeft": [int(stab_down[mini(strike, stab_down.size() - 1)])] if not stab_down.is_empty() else [int(s.idleDown)],
		"castUpLeft": [int(stab_up[mini(strike, stab_up.size() - 1)])] if not stab_up.is_empty() else [int(s.idleUp)],
	}
	if not stab_down.is_empty():
		d.frames["attackDownLeft"] = _swing_from(stab_down, strike, swing)
		d.frames["attackUpLeft"] = _swing_from(stab_up if not stab_up.is_empty() else stab_down, strike, swing)
	else:
		d.frames.erase("attackDownLeft")
	d["walkFps"] = float(s.get("walkFps", 8))
	if s.has("walkCycle"):
		d["walkFps"] = (s.get("walkDown", []) as Array).size() / maxf(0.05, float(s.walkCycle))
	d["runFps"] = float(d.walkFps) * 1.5
	d["idleFps"] = 4.0
	if s.has("walkCycle"):
		d["upPace"] = float((s.get("walkUp", []) as Array).size()) / maxf(1.0, float((s.get("walkDown", []) as Array).size()))
	elif s.has("walkFpsUp"):
		d["upPace"] = float(s.walkFpsUp) / maxf(0.01, float(s.get("walkFps", 8)))
	else:
		d.erase("upPace")
	if lk.has("shadow"):
		d["shadow"] = (lk.shadow as Dictionary).duplicate()
	var anims := {}
	var take := func(key: String, value: Variant) -> void:
		if value is Array and (value as Array).is_empty():
			return
		if value != null:
			anims[key] = value
	take.call("mineDown", s.get("mineDown"))
	take.call("mineUp", s.get("mineUp"))
	take.call("strikeFrames", s.get("mineStrikesDown"))
	take.call("chopDown", s.get("chopDown"))
	take.call("chopUp", s.get("chopUp"))
	take.call("chopStrikeFrames", s.get("chopStrikesDown"))
	take.call("cookDown", s.get("cookDown"))
	take.call("cookUp", s.get("cookUp"))
	if not (s.get("sleepDown", []) as Array).is_empty():
		take.call("sleepDown", s.get("sleepDown"))
		take.call("sleepUp", s.get("sleepUp"))
		take.call("lieDownFrames", s.get("lieDownFrames"))
		take.call("lieDownFps", s.get("lieDownFps"))
		take.call("artFacesRight", false)
		take.call("lying", lk.get("lying"))
	if not (s.get("faintDown", []) as Array).is_empty():
		take.call("faintFront", s.get("faintDown"))
		take.call("faintBack", s.get("faintUp"))
		take.call("faintFacesRight", false)
	var fish_down: Array = s.get("fishDown", [])
	if not fish_down.is_empty():
		d["fishing"] = {"down": fish_down, "tipsDown": s.get("fishTipsDown", []), "up": s.get("fishUp", []),
			"tipsUp": s.get("fishTipsUp", []), "ppu": float(world.sprites[int(fish_down[0])].ppu)}
	else:
		d.erase("fishing")
	d["anims"] = anims
	_looks[id] = d
	return d


# A swing of [param count] frames from a longer stab: evenly up to its strike (which lands on the swing's
# Melee.DOWNSWING), then evenly to its end.
static func _swing_from(stab: Array, strike: int, count: int) -> Array:
	count = maxi(count, Melee.DOWNSWING + 2)
	strike = clampi(strike, 0, stab.size() - 1)
	var out := []
	for i in Melee.DOWNSWING:
		out.append(stab[int(float(i) * float(strike) / float(Melee.DOWNSWING))])
	out.append(stab[strike])
	var after := count - Melee.DOWNSWING - 1
	for i in after:
		out.append(stab[mini(stab.size() - 1, strike + 1 + int(float(i) * float(stab.size() - 1 - strike) / float(maxi(1, after))))])
	return out


# Sera as a villager: a villagers.json look (hers, for the collider and shadow) with her own frames from her art as
# the player: standing, walking (her run strip, slower), her staff for a stab, and her mining, chopping, cooking,
# sleeping, fishing and fainting from those moves' data.
func _sera_as_villager() -> Dictionary:
	if not _lead_look.is_empty():
		return _lead_look
	var looks: Array = people.d.get("looks", [])
	if looks.is_empty():
		return {}
	var lk: Dictionary = (looks[clampi(int(entry(LEAD).get("look", 1)), 0, looks.size() - 1)] as Dictionary).duplicate(true)
	var s: Dictionary = lk.settings
	var f: Dictionary = _lead_data.frames
	s["uniqueTo"] = LEAD
	s.erase("idleDownAnim")
	s.erase("idleUpAnim")
	s["idleDown"] = int(f.idleDownLeft[0])
	s["idleUp"] = int(f.idleUpLeft[0])
	s["walkDown"] = f.runDownLeft
	s["walkUp"] = f.runUpLeft
	s["walkFps"] = float(_lead_data.get("walkFps", 8))
	if f.has("attackDownLeft"):
		s["stabDown"] = f.attackDownLeft
		s["stabUp"] = f.attackUpLeft
		s["stabFps"] = float(_lead_data.get("attackFps", 16))
		s["stabStrikes"] = [Melee.DOWNSWING]
	var miner: Dictionary = (world._load_json("res://data/gather.json") as Dictionary).get("miner", {})
	for k in ["mineDown", "mineUp", "chopDown", "chopUp", "chopFps"]:
		if miner.has(k):
			s[k] = miner[k]
	s["mineFps"] = miner.get("fps", s.get("mineFps", 10))
	s["mineStrikesDown"] = miner.get("strikeFrames", s.get("mineStrikesDown", []))
	s["mineStrikesUp"] = miner.get("strikeFrames", s.get("mineStrikesUp", []))
	s["chopStrikesDown"] = miner.get("chopStrikeFrames", s.get("chopStrikesDown", []))
	s["chopStrikesUp"] = miner.get("chopStrikeFrames", s.get("chopStrikesUp", []))
	var cook: Dictionary = (world._load_json("res://data/farm.json") as Dictionary).get("cooking", {})
	for k in ["cookDown", "cookUp"]:
		if cook.has(k):
			s[k] = cook[k]
	s["cookFps"] = cook.get("fps", s.get("cookFps", 8))
	var nd: Dictionary = world._load_json("res://data/needs.json")
	var sleep: Dictionary = nd.get("needs", {})
	for k in ["sleepDown", "sleepUp", "lieDownFrames", "lieDownFps"]:
		if sleep.has(k):
			s[k] = sleep[k]
	# (her own sleeping art faces right, where the villagers' faces left; and its lying points are in her art's own
	# px, where a villager's are already at the size they're drawn)
	s["sleepFacesRight"] = bool(nd.get("needs", {}).get("artFacesRight", nd.get("artFacesRight", false)))
	if nd.has("lying"):
		var lying: Dictionary = (nd.lying as Dictionary).duplicate(true)
		for pose in lying:
			for pt in ["middle", "head"]:
				if lying[pose].has(pt):
					lying[pose][pt] = [float(lying[pose][pt][0]) * World.BODY_SCALE, float(lying[pose][pt][1]) * World.BODY_SCALE]
		lk["lying"] = lying
	var faint: Dictionary = (world._load_json("res://data/monsters.json") as Dictionary).get("fainting", {})
	if faint.has("faintFront"):
		s["faintDown"] = faint.faintFront
		s["faintUp"] = faint.faintBack
		s["faintFps"] = faint.get("staggerFps", 8)
	var fish: Dictionary = _lead_data.get("fishing", {})
	if not fish.is_empty():
		s["fishDown"] = fish.get("down", [])
		s["fishUp"] = fish.get("up", [])
		s["fishTipsDown"] = fish.get("tipsDown", [])
		s["fishTipsUp"] = fish.get("tipsUp", [])
	if lk.has("body"):
		lk.body["s"] = s.idleDown
	_lead_look = lk
	return lk


## Her face for the card and the party window: her portrait as Sera, else the played one's (as on a party card).
## The standing pose of whoever's played (the maps show it).
func pose() -> Texture2D:
	if Party.active == null:
		return null
	return Party.active.pose({} if str(entry(who).get("art", "look")) == "player" else played)


func portrait() -> Texture2D:
	if str(entry(who).get("art", "look")) == "player" or Party.active == null:
		return HudStyle.icon("portrait")
	return Party.active.face(played)


# ---- Saving ----

## Sera's own stats, saved as the player's whoever's played (so a game loads as it always has, then switches).
func lead_stats_json() -> String:
	if who == LEAD:
		return miko.stats.to_json()
	var p := Uniques.person(people, LEAD)
	var st := Companions.stats_for(p) if not p.is_empty() else null
	return st.to_json() if st != null else str(p.get("companion", {}).get("stats", miko.stats.to_json()))


func to_json() -> String:
	_bar_out(who)
	var me := _me_as_person() if who != LEAD or not played.is_empty() else {}
	return JSON.stringify({"who": who, "played": me, "bars": bars, "kit": kit})


## Loads who was played (after the player's stats, the village's people and the party): their stats, art and hotbar
## put on.
func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if not d is Dictionary:
		return
	bars = d.get("bars", {}) if d.get("bars") is Dictionary else {}
	kit = d.get("kit", {}) if d.get("kit") is Dictionary else {}
	var id := str(d.get("who", LEAD))
	var p: Dictionary = d.get("played", {}) if d.get("played") is Dictionary else {}
	for k in ["level", "xp", "job", "toolsLeft", "bagSlots", "bagLeft", "look"]:
		if p.has(k):
			p[k] = int(p[k])
	if id == LEAD or entry(id).is_empty() or p.is_empty():
		played = p if id == LEAD else {}
		who = LEAD
		return
	_wear(id, p, true)
	miko.bag.worn = miko.stats.equipped
