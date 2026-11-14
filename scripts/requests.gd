class_name Requests
extends Node
## Villagers' requests (data/requests.json): now and then a villager wants something of their own (a pouch to carry
## more in, a scarf before the cold, tools for worn-out ones), or the village as a whole does (pouches for every worker,
## scarves before winter). One with something to ask shows a gold ! over their head; talking to them, Sera gives her
## word and it goes in the journal (J). Handing the thing over (from her bag, or storage while she's in the village)
## settles it: thanks, and gold for her purse. Those for the whole village are settled once nobody's wanting any more,
## and what's put in storage for them is handed out to whoever's still without. Left too long, a villager gives up.

signal changed

const FILE := "res://data/requests.json"
const CHECK_EVERY := 1.0
const MOST_AT_ONCE := 3            ## personal asks offered or open at once, in the whole village
const ASK_CHANCE := 0.3            ## each hour, the chance one more villager comes to want something
const UNASKED_FOR := 48.0          ## hours an ask waits to be heard before they let it go
const AGAIN_AFTER := 48.0          ## hours after one ask's ended before the same villager asks again
const CARRIERS := [Villager.Job.HAULING, Villager.Job.MINING, Villager.Job.LUMBERING, Villager.Job.FARMING, Villager.Job.FISHING]

static var active: Requests

var world: World
var miko: Miko
var defs: Array = []
var by_id := {}
var asks := {}                     ## key -> {id, by (name), state: "offered"|"open"|"done"|"met"|"gone", since, took, ended, said}
var last := {}                     ## villager's name -> hours their last ask ended
var _clock := 0.0
var _hour := -1


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who
	active = self
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if d is Dictionary:
		defs = d.get("requests", [])
	for r in defs:
		by_id[str(r.id)] = r


func to_json() -> String:
	return JSON.stringify({"asks": asks, "last": last})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		asks = d.get("asks", {})
		last = d.get("last", {})
		for k in asks.keys():
			if not by_id.has(str(asks[k].get("id", ""))):
				asks.erase(k)   # (a request since taken out of the file)
	changed.emit()


func _process(delta: float) -> void:
	_clock += delta
	if _clock < CHECK_EVERY or Chronicle.active == null or world.clock == null or world.village == null:
		return
	_clock = 0.0
	var __t := Time.get_ticks_usec()
	_hand_out()
	_raise_soon()
	var h := int(Chronicle.active.now())
	if h != _hour:
		_hour = h
		_hourly()
	Perf.add(&"requests", __t)


# ---- Who wants what ----

## Whether [param p] wants what [param wants] names ("bag", "scarf", "tools"; "mistcrystal": one of the party with
## no mist crystal worn as a trinket, nothing between them and the mist).
func wanting(p: Dictionary, wants: String) -> bool:
	if wants == "mistcrystal":
		if Party.active == null or not Party.active.has_member(p):
			return false
		var st := Companions.stats_for(p)
		return st != null and st.worn_in("Trinket") == "" and not _carries(p, "CrystalNecklace")
	if p.has("unique"):
		return false   # (the uniques have their own ways: companions carry packs)
	match wants:
		"bag":
			return str(p.get("bag", "")) == "" and Villager.jobs_of(p).any(func(j): return CARRIERS.has(j))
		"scarf":
			return _cold_coming() and not bool(p.get("scarf", false))
		"tools":
			var jobs := Villager.jobs_of(p)
			return (jobs.has(Villager.Job.MINING) or jobs.has(Villager.Job.LUMBERING)) and int(p.get("toolsLeft", 0)) <= 0
	return false


# Whether [param p] has [param item] in their own bag already.
func _carries(p: Dictionary, item: String) -> bool:
	var bag := Companions.bag_of(p)
	return bag != null and bag.items.has(item)


# Whether the village is in the cold months, or the one before them.
func _cold_coming() -> bool:
	var s := world.clock.season()
	return s == GameClock.Season.AUTUMN or s == GameClock.Season.WINTER


# Those a whole-village ask is for (the workers for pouches; everyone for scarves), and how many still want it.
func _counts(def: Dictionary) -> Vector2i:
	var all := 0
	var short := 0
	for v in Villager.all:
		if not is_instance_valid(v) or v.person.has("unique"):
			continue
		var p: Dictionary = v.person
		if str(def.wants) == "bag" and not Villager.jobs_of(p).any(func(j): return CARRIERS.has(j)):
			continue
		all += 1
		if wanting(p, str(def.wants)):
			short += 1
	return Vector2i(all, short)


## How a whole-village ask stands: [those with it now, those it's for].
func progress(key: String) -> Vector2i:
	var c := _counts(by_id[str(asks[key].id)])
	return Vector2i(c.x - c.y, c.x)


func _villager(nm: String) -> Villager:
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.name) == nm:
			return v
	return null


# ---- Asks coming and going, once an hour ----

func _hourly() -> void:
	if not world.village.founded():
		return
	var now := Chronicle.active.now()
	var was := asks.duplicate(true)
	for k in asks.keys():
		var st: Dictionary = asks[k]
		var def: Dictionary = by_id[str(st.id)]
		if st.state == "offered":
			# (never asked about, or the wish has passed: let go of quietly)
			var v := _villager(str(st.by))
			if now - float(st.since) > UNASKED_FOR or v == null or not _still(def, v):
				asks.erase(k)
				last[str(st.by)] = now
		elif st.state == "open":
			if bool(def.get("every", false)):
				if progress(k).x >= progress(k).y:
					_settle(k, null)
				continue
			var v := _villager(str(st.by))
			if v != null and not wanting(v.person, str(def.wants)):
				_end(k, "met")   # (they found one themselves: storage, most likely)
			elif float(def.get("days", 0)) > 0.0 and now - float(st.took) > float(def.days) * 24.0:
				_end(k, "gone")
				if v != null:
					v.show_mood("frustration", 4.0)
					VillageLog.event("request:" + str(k), "%s gave up waiting for %s" % [str(st.by), str(def.thing)], VillageLog.Kind.WARNING)
	_raise_every()
	if randf() < ASK_CHANCE:
		_raise_one(now)
	if was != asks:
		changed.emit()


# Whether [param v] still wants what [param def]'s about (for a whole-village ask: whether enough still do).
func _still(def: Dictionary, v: Villager) -> bool:
	if bool(def.get("every", false)):
		return _counts(def).y >= int(def.get("least", 1))
	return wanting(v.person, str(def.wants))


# Asks that don't wait their turn ("soon"): one of the party with no mist crystal asks for one straight away.
func _raise_soon() -> void:
	for def in defs:
		if not bool(def.get("soon", false)):
			continue
		for v in Villager.all:
			if is_instance_valid(v) and wanting(v.person, str(def.wants)) and not _asking(v):
				offer(def, v)


# One more villager comes to want something of their own (a few at once in the village at most).
func _raise_one(now: float) -> void:
	var mine := asks.values().filter(func(st): return not bool(by_id[str(st.id)].get("every", false)) and (st.state == "offered" or st.state == "open"))
	if mine.size() >= MOST_AT_ONCE:
		return
	var busy := {}
	for st in asks.values():
		if st.state == "offered" or st.state == "open":
			busy[str(st.by)] = true
	var picks := []
	for v in Villager.all:
		if not is_instance_valid(v) or busy.has(str(v.person.name)) or now - float(last.get(str(v.person.name), -INF)) < AGAIN_AFTER:
			continue
		for def in defs:
			if bool(def.get("every", false)) or bool(def.get("soon", false)) or not wanting(v.person, str(def.wants)):
				continue
			if _every_open_for(str(def.wants)):
				continue   # (the whole village is already asking for it)
			picks.append([v, def])
	if picks.is_empty():
		return
	var pick: Array = picks.pick_random()
	offer(pick[1], pick[0])


# A whole-village ask comes up once enough are wanting (once ever, each; while none other's going).
func _raise_every() -> void:
	for st in asks.values():
		if bool(by_id[str(st.id)].get("every", false)) and (st.state == "offered" or st.state == "open"):
			return
	for def in defs:
		if not bool(def.get("every", false)) or asks.has(str(def.id)):
			continue
		if def.has("season") and str(def.season) == "autumn" and world.clock.season() != GameClock.Season.AUTUMN:
			continue
		if _counts(def).y < int(def.get("least", 1)):
			continue
		var tellers := Villager.all.filter(func(v): return is_instance_valid(v) and wanting(v.person, str(def.wants)) and not _asking(v))
		if tellers.is_empty():
			continue
		offer(def, tellers.pick_random())
		return


func _every_open_for(wants: String) -> bool:
	for st in asks.values():
		var def: Dictionary = by_id[str(st.id)]
		if bool(def.get("every", false)) and str(def.wants) == wants and (st.state == "offered" or st.state == "open"):
			return true
	return false


# Whether [param v] has an ask of their own going (offered or open).
func _asking(v: Villager) -> bool:
	for st in asks.values():
		if str(st.by) == str(v.person.name) and (st.state == "offered" or st.state == "open"):
			return true
	return false


## [param v] comes to want what [param def] is about: a ! over their head till Sera talks to them. Its key.
func offer(def: Dictionary, v: Villager) -> String:
	var now := Chronicle.active.now()
	var key := str(def.id) if bool(def.get("every", false)) else "%s:%s:%d" % [str(def.id), str(v.person.name), int(now)]
	asks[key] = {"id": str(def.id), "by": str(v.person.name), "state": "offered", "since": now, "took": -1.0, "ended": -1.0,
		"said": str((def.ask as Array).pick_random())}
	changed.emit()
	return key


# ---- Talking ----

## The ask [param v] has to make (its key), or "".
func offered_by(v: Villager) -> String:
	for k in asks:
		if asks[k].state == "offered" and str(asks[k].by) == str(v.person.name):
			return k
	return ""


## What they say asking.
func said(key: String) -> String:
	return _fill(str(asks[key].said), key)


## What Sera says, giving her word.
func accept_line(key: String) -> String:
	return str(by_id[str(asks[key].id)].accept)


## Sera's given her word: it's in the journal now.
func accept(key: String) -> void:
	var st: Dictionary = asks[key]
	st.state = "open"
	st.took = Chronicle.active.now()
	Chronicle.active.record("request:" + key, {"by": st.by})
	changed.emit()


## The ask [param v] could be handed something for now (theirs, or a whole-village one they're wanting for), or "".
func open_for(v: Villager) -> String:
	for k in asks:
		var st: Dictionary = asks[k]
		if st.state != "open":
			continue
		var def: Dictionary = by_id[str(st.id)]
		if str(st.by) == str(v.person.name) and not bool(def.get("every", false)):
			return k
		if bool(def.get("every", false)) and wanting(v.person, str(def.wants)):
			return k
	return ""


## Where Sera has what [param def] asks for (a thing of its kind, or the one item it names) to hand over: [bag slot,
## -1], [-1, storage index], or [] if nowhere.
func find_thing(def: Dictionary) -> Array:
	var fits := func(nm: String) -> bool:
		return nm != "" and (nm == str(def.item) if def.has("item") else str(UiKit.item(nm).get("kind", "")) == str(def.kind))
	for i in miko.bag.items.size():
		if fits.call(str(miko.bag.items[i])):
			return [i, -1]
	if world.village.in_reach(miko):
		for i in world.village.items.size():
			if fits.call(str(world.village.items[i])):
				return [-1, i]
	return []


## The name of the thing [param key]'s for, as handed over ("Sachet").
func thing_name(key: String) -> String:
	var at := find_thing(by_id[str(asks[key].id)])
	if at.is_empty():
		return str(by_id[str(asks[key].id)].thing)
	var nm := str(miko.bag.items[at[0]]) if at[0] >= 0 else str(world.village.items[at[1]])
	return str(UiKit.item(nm).get("name", nm))


## Sera hands [param v] what [param key] asks for: theirs to use from now. What they say, thanking her.
func give(key: String, v: Villager) -> String:
	var st: Dictionary = asks[key]
	var def: Dictionary = by_id[str(st.id)]
	var at := find_thing(def)
	if at.is_empty():
		return ""
	var nm: String
	if at[0] >= 0:
		nm = str(miko.bag.items[at[0]])
		miko.bag.items[at[0]] = ""
		miko.bag.changed.emit()
	else:
		nm = str(world.village.items[at[1]])
		world.village.items.remove_at(at[1])
		world.village.changed.emit()
	_put_on(v.person, str(def.wants), nm)
	if bool(def.get("every", false)):
		# (one more of the village has theirs; the whole ask's settled once all have)
		var line := "Thank you, %s! One more of us with %s." % [Playable.name_now(), str(def.thing).to_lower()]
		var p := progress(key)
		if p.x >= p.y:
			return _settle(key, v)
		changed.emit()
		return line
	return _settle(key, v)


# [param p] has [param item] now, for what they wanted: a pouch on their belt, a scarf on, a fresh set of tools.
func _put_on(p: Dictionary, wants: String, item: String) -> void:
	match wants:
		"bag":
			p["bag"] = item
			p["bagSlots"] = int(UiKit.item(item).get("bagSlots", 0))
			p["bagLeft"] = Villager.BAG_TRIPS
		"scarf":
			p["scarf"] = true
		"tools":
			p["toolsLeft"] = Villager.TOOL_USES
		"mistcrystal":
			# (round their neck: into their bag, and worn from there)
			var bag := Companions.bag_of(p)
			var st := Companions.stats_for(p)
			var slot := bag.free_slot() if bag != null else -1
			if slot >= 0 and st != null:
				bag.items[slot] = item
				st.equip(bag, slot)
				Companions.sync(p)


# What's put in storage for a whole-village ask goes to those still without, one a second.
func _hand_out() -> void:
	for k in asks:
		var st: Dictionary = asks[k]
		var def: Dictionary = by_id[str(st.id)]
		if st.state != "open" or not bool(def.get("every", false)):
			continue
		var idx := -1
		for i in world.village.items.size():
			if str(UiKit.item(str(world.village.items[i])).get("kind", "")) == str(def.kind):
				idx = i
				break
		if idx < 0:
			continue
		for v in Villager.all:
			if is_instance_valid(v) and wanting(v.person, str(def.wants)) and _counts_for(def, v.person):
				var nm := str(world.village.items[idx])
				world.village.items.remove_at(idx)
				world.village.changed.emit()
				_put_on(v.person, str(def.wants), nm)
				VillageLog.event("request.take:" + str(v.person.name), "%s took %s from storage" % [str(v.person.name), str(UiKit.item(nm).get("name", nm)).to_lower()])
				v.show_mood("cheerful", 3.0)
				if progress(k).x >= progress(k).y:
					_settle(k, null)
				else:
					changed.emit()
				return


func _counts_for(def: Dictionary, p: Dictionary) -> bool:
	return str(def.wants) != "bag" or Villager.jobs_of(p).any(func(j): return CARRIERS.has(j))


# Done: thanks, gold in Sera's purse, the village log and the journal. What's said ([param v] says it, if anyone).
func _settle(key: String, v: Villager) -> String:
	var st: Dictionary = asks[key]
	var def: Dictionary = by_id[str(st.id)]
	_end(key, "done")
	var gold := int(def.get("gold", 0))
	if gold > 0:
		miko.bag.add("Gold", gold)
	FloatingText.spawn(world, ("Request done  +%d gold" % gold) if gold > 0 else "Request done", miko.position + Vector2(0, -2.2 * world.px), Color(1, 0.86, 0.45), 20, 2.5)
	VillageLog.event("request:" + key, "%s: done" % _fill(str(def.title), key))
	var teller := v if v != null else _villager(str(st.by))
	if teller != null:
		teller.show_mood("affection", 4.0)
	var line := _fill(str((def.thanks as Array).pick_random()), key)
	if v == null and teller != null:
		teller.say_line(line)
	return line


func _end(key: String, how: String) -> void:
	var st: Dictionary = asks[key]
	st.state = how
	st.ended = Chronicle.active.now()
	last[str(st.by)] = st.ended
	Chronicle.active.record("request.%s:%s" % [how, key], {"by": st.by})
	changed.emit()


# ---- The journal ----

## The asks Sera's given her word on, those still open first, then the latest ended.
func listed() -> Array:
	var ks := asks.keys().filter(func(k): return asks[k].state != "offered")
	ks.sort_custom(func(a, b):
		var oa: bool = asks[a].state == "open"
		var ob: bool = asks[b].state == "open"
		if oa != ob:
			return oa
		return float(asks[a].took) > float(asks[b].took))
	return ks


func title(key: String) -> String:
	return _fill(str(by_id[str(asks[key].id)].title), key)


## What the journal says of [param key]: [text, muted] lines.
func lines(key: String) -> Array:
	var st: Dictionary = asks[key]
	var def: Dictionary = by_id[str(st.id)]
	var out := [["\"%s\"" % said(key), false]]
	match str(st.state):
		"open":
			out.append([_fill(str(def.get("note", "")), key), false])
			if bool(def.get("every", false)):
				var p := progress(key)
				out.append(["%d of %d have %s." % [p.x, p.y, str(def.thing).to_lower()], false])
			elif float(def.get("days", 0)) > 0.0:
				var left := float(def.days) * 24.0 - (Chronicle.active.now() - float(st.took))
				out.append(["%s will wait about %d more day%s." % [str(st.by), maxi(1, ceili(left / 24.0)), "" if left <= 24.0 else "s"], false])
		"done":
			out.append([("Done. Thanked with %d gold." % int(def.get("gold", 0))) if int(def.get("gold", 0)) > 0 else "Done.", true])
		"met":
			out.append(["They found one themselves.", true])
		"gone":
			out.append(["Left too long: they stopped waiting.", true])
	return out


func _fill(s: String, key: String) -> String:
	return s.format({"name": str(asks[key].by), "miko": Playable.name_now()})
