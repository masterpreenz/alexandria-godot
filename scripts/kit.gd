class_name Kit
extends RefCounted
## A party member's adventure kit: what they mean to carry on the road (five health potions, ten things to eat, two
## water pouches...). Back in the village a companion restocks by it on their own, once a visit: what's in their bag
## and not in the kit (loot, materials, more than the kit wants, gear they aren't wearing) goes into storage, then
## storage tops them up to the kit's counts. The one played has a kit too, used with "Restock now" in the village.
##
## A kit is {preset, auto, rows: [[what, how many]]}: "what" is a resource (HpPotion), a piece of gear (WaterPouch), or
## "food" for anything to eat, the best first. Saved with each person (person.kit); the one played keeps theirs with
## [Playable] while they're played.

const FOOD := "food"
## The ready-made kits, in the order the editor shows them; editing one makes it "Custom".
const PRESETS := {
	"Adventurer": [["HpPotion", 5], ["ManaPotion", 5], [FOOD, 10], ["WaterPouch", 2]],
	"Gatherer": [[FOOD, 5], ["WaterPouch", 1], ["Tools", 1]],
	"Light": [[FOOD, 3], ["HpPotion", 2]],
	"Empty": [],
}
const ORDER := ["Adventurer", "Gatherer", "Light", "Empty"]


## A new kit from preset [param preset].
static func make(preset := "Adventurer", auto := true) -> Dictionary:
	return {"preset": preset, "auto": auto, "rows": (PRESETS.get(preset, []) as Array).duplicate(true)}


## [param p]'s kit (a companion's, kept in their person; {} for the one played), made the first time it's asked for:
## the Adventurer's, restocking at home on its own.
static func of(p: Dictionary) -> Dictionary:
	if p.is_empty():
		if Playable.active == null:
			return make("Adventurer", false)
		if not Playable.active.kit is Dictionary or (Playable.active.kit as Dictionary).is_empty():
			Playable.active.kit = make("Adventurer", false)
		return Playable.active.kit
	if not p.get("kit") is Dictionary or not (p.kit as Dictionary).has("rows"):
		p["kit"] = make()
	return p.kit


## Puts preset [param preset] in [param k] (its own toggle kept).
static func use_preset(k: Dictionary, preset: String) -> void:
	k["preset"] = preset
	k["rows"] = (PRESETS.get(preset, []) as Array).duplicate(true)


## How many of [param what] the kit wants (0 when it isn't in it).
static func wants(k: Dictionary, what: String) -> int:
	for r in k.get("rows", []):
		if str(r[0]) == what:
			return int(r[1])
	return 0


## Sets how many of [param what] the kit wants (0 takes it out); the kit's "Custom" after.
static func set_count(k: Dictionary, what: String, n: int) -> void:
	var rows: Array = k.get("rows", [])
	for i in rows.size():
		if str(rows[i][0]) == what:
			if n <= 0:
				rows.remove_at(i)
			else:
				rows[i] = [what, n]
			k["preset"] = "Custom"
			return
	if n > 0:
		rows.append([what, n])
		k["rows"] = rows
		k["preset"] = "Custom"


## What a kit row is called in the game.
static func label(what: String) -> String:
	if what == FOOD:
		return "Food (any)"
	if UiKit.data.items.has(what):
		return str(UiKit.item(what).get("name", what))
	return UiKit.resource_name(what)


## Whether [param r] is something to eat (as a companion eats: [constant Villager.FOODS]).
static func is_food(r: String) -> bool:
	for f in Villager.FOODS:
		if f[0] == r:
			return true
	return false


## How many of [param what] are in [param bag].
static func carried(bag: Bag, what: String) -> int:
	if what == FOOD:
		var n := 0
		for f in Villager.FOODS:
			n += bag.count(str(f[0]))
		return n
	if UiKit.data.items.has(what):
		return bag.items.count(what)
	return bag.count(what)


## Restocks [param bag] by kit [param k] from the village's storage: first what the kit doesn't want goes in (as
## far as the chests have room), then storage tops the bag up to the kit. Returns {stored: {what: n}, got: {what: n},
## short: {what: n}, kept: {what: n}} (kept: what storage had no room for, left in the bag).
static func restock(bag: Bag, k: Dictionary, village: Village) -> Dictionary:
	var out := {"stored": {}, "got": {}, "short": {}, "kept": {}}
	# What to keep of each stack: the kit's count of it, else (food) the best of it up to the kit's food.
	var keep := {}
	var food_left := wants(k, FOOD)
	for f in Villager.FOODS:
		var r := str(f[0])
		if wants(k, r) > 0:
			continue
		var n := mini(bag.count(r), food_left)
		keep[r] = n
		food_left -= n
	for r in bag.counts.keys():
		var r_s := str(r)
		if not Bag.slotted(r_s) or bag.count(r_s) <= 0:
			continue
		var extra := bag.count(r_s) - (wants(k, r_s) if wants(k, r_s) > 0 else int(keep.get(r_s, 0)))
		if extra <= 0:
			continue
		var room := maxi(0, village.stash_cap(r_s) - village.stored(r_s))
		var n := mini(extra, room)
		if n > 0:
			bag.spend(r_s, n)
			village.put_in_stash(r_s, n)
			_tally(out.stored, r_s, n)
		if extra > n:
			_tally(out.kept, r_s, extra - n)
	# Gear past the kit's count of it.
	var seen := {}
	for i in Bag.SIZE:
		var it: String = bag.items[i]
		if it == "":
			continue
		seen[it] = int(seen.get(it, 0)) + 1
		if int(seen[it]) <= wants(k, it):
			continue
		if village.store_item(bag, i):
			_tally(out.stored, it, 1)
		else:
			_tally(out.kept, it, 1)
	# Topped up to the kit.
	for row in k.get("rows", []):
		var what := str(row[0])
		var need := int(row[1]) - carried(bag, what)
		if need <= 0:
			continue
		if what == FOOD:
			for f in Villager.FOODS:
				var r := str(f[0])
				if need <= 0:
					break
				var n := mini(need, village.spare(r))
				if n > 0 and bag.add(r, n):
					village.take_from_stash(r, n)
					_tally(out.got, FOOD, n)
					need -= n
		elif UiKit.data.items.has(what):
			while need > 0:
				var at := village.items.find(what)
				if at < 0 or not village.take_item(bag, at):
					break
				_tally(out.got, what, 1)
				need -= 1
		else:
			var n := mini(need, village.spare(what))
			if n > 0 and bag.add(what, n):
				village.take_from_stash(what, n)
				_tally(out.got, what, n)
				need -= n
		if need > 0:
			_tally(out.short, what, need)
	return out


static func _tally(d: Dictionary, what: String, n: int) -> void:
	d[what] = int(d.get(what, 0)) + n


## A restock's result in a few words: "Restocked: +3 food, +2 HP potions" (with what went to storage), or "".
static func said(r: Dictionary) -> String:
	var bits := []
	for what in r.got:
		bits.append("+%d %s" % [int(r.got[what]), label(str(what)).replace(" (any)", "").to_lower() if what == FOOD else label(str(what))])
	var stored := 0
	for what in r.stored:
		stored += int(r.stored[what])
	var s := ("Restocked: " + ", ".join(bits)) if not bits.is_empty() else ""
	if stored > 0:
		s += ("  ·  " if s != "" else "") + "%d put in storage" % stored
	return s


## Restocks [param p] (a companion; {} the one played) by their kit, there and then: what they're told over their head,
## the pouch filled at home, the village log told what storage ran short of. Their restock's result.
static func restock_now(p: Dictionary) -> Dictionary:
	var party := Party.active
	if party == null:
		return {}
	var w := party.world
	var played := p.is_empty()
	var bag: Bag = party.miko.bag if played else Companions.pack_of(p)
	if bag == null:
		return {}
	var r := restock(bag, of(p), w.village)
	var who: Node2D = party.miko
	if not played:
		who = Companions.body_of(p)
	var whose := Playable.name_now() if played else str(p.get("name", "?"))
	# (a pouch brought home is filled there)
	if bag.items.has("WaterPouch"):
		party.set_pouch(p, Needs.MAX)
	var s := said(r)
	if who != null:
		# (two short lines over them rather than one long one: what they took, what they left in storage)
		var lines := s.split("  ·  ") if s != "" else PackedStringArray(["Kit's as it should be"])
		for i in lines.size():
			FloatingText.spawn(w, lines[i], who.position + Vector2(0, (-2.0 - 0.45 * (lines.size() - 1 - i)) * w.px), Color(0.75, 0.9, 0.7), 15, 2.5)
	for what in r.short:
		VillageLog.event("kit_short:%s:%s" % [whose, what], "Not enough %s in storage for %s's kit" % [label(str(what)), whose])
	if not r.kept.is_empty() and who != null:
		FloatingText.spawn(w, "Storage is full: some stays in the bag", who.position + Vector2(0, -2.5 * w.px), Color(0.9, 0.8, 0.6), 13, 2.5)
	return r
