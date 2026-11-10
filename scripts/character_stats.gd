class_name CharacterStats
extends Node
## A character's stats (from Unity's CharacterStats): their base for their level, plus their worn gear, their learnt
## talents and any buffs lent them; HP and mana with regen (HP comes back in ticks, not while being hurt), damage
## softened by defense, shields first; XP and levels (a talent point each). The skills they know come from their gear
## and their talents.

signal changed
signal hurt(amount: float)
signal downed
signal out_of_mana
signal leveled_up(level: int)
signal blocked                    ## a hit blocked outright (Bulwark)
signal second_wind                ## saved from a felling blow (Second Wind)

const REGEN_TICK := 5.0
const REGEN_PAUSE_AFTER_HIT := 5.0
const CALM_AFTER := 8.0           ## seconds unhurt before Deep Breath's regen starts
const WIND_COOLDOWN := 600.0      ## seconds between Second Winds
const WIND_HEAL := 0.5            ## share of max HP Second Wind mends...
const WIND_OVER := 3.0            ## ...over this many seconds
const WIND_SAFE := 1.5            ## seconds nothing can hurt her after it saves her

var character: Dictionary          ## base, perLevel, talents, xpPerLevel (combat.json's character)
var item_stats: Dictionary         ## item name -> {stats, grantsSpell}
var level := 1
var xp := 0
var talent_points := 0
var ranks := {}                    ## talent id -> rank
var equipped: Array = []           ## worn item names
var wear := {}                     ## item name -> seconds it's been worn (gear that wears out: the crystal necklace)
var hp := 0.0
var mana := 0.0
var buffs := {}                    ## source -> stat dict
var shields := {}                  ## source -> amount
var guards := {}                   ## source -> % less damage taken (the strongest counts, at most 90)
var _regen_clock := 0.0
var _last_hurt := -99.0
var wind_ready_at := 0.0           ## when Second Wind can save her again (_now's clock)
var _wind_left := 0.0              ## seconds of Second Wind's mending still to come
var _wind_safe_until := 0.0
var _talents := {}                 ## id -> talent


func setup(c: Dictionary, items: Dictionary) -> void:
	character = c
	item_stats = items
	for t in c.talents:
		_talents[t.id] = t
		if t.kind == "Start":
			ranks[t.id] = 1
	var tot := total()
	hp = tot.get("maxHp", 100.0)
	mana = tot.get("maxMana", 50.0)


static func _add(into: Dictionary, stats: Dictionary, k := 1.0) -> void:
	for f in stats:
		into[f] = float(into.get(f, 0.0)) + float(stats[f]) * k


## Everything together: base for the level, gear, talents, buffs.
func total() -> Dictionary:
	var t := {}
	_add(t, character.get("base", {}))
	_add(t, character.get("perLevel", {}), level - 1)
	for n in equipped:
		_add(t, item_stats.get(n, {}).get("stats", {}))
	for id in ranks:
		if _talents.has(id):
			_add(t, _talents[id].perRank, ranks[id])
	for b in buffs.values():
		_add(t, b)
	return t


## Everything but the buffs (what hunger and the mist take a share of).
func unbuffed() -> Dictionary:
	var keep := buffs
	buffs = {}
	var t := total()
	buffs = keep
	return t


## Lends (or, with null, takes back) the stats [param block] under [param key].
func set_buff(key, block: Variant) -> void:
	if block == null:
		if buffs.erase(key):
			changed.emit()
	else:
		buffs[key] = block
		changed.emit()


## Sets HP outright (within 0 and max).
func set_hp(v: float) -> void:
	hp = clampf(v, 0.0, stat("maxHp"))
	changed.emit()


func stat(nm: String) -> float:
	return float(total().get(nm, 0.0))


## A stat that's a percentage bonus, as a multiplier (10 -> 1.1).
static func percent(v: float) -> float:
	return 1.0 + v / 100.0


func xp_to_next() -> int:
	return int(character.get("xpPerLevel", 100)) * level


## The skills they know: what their worn gear grants and their learnt talents grant.
func known_spells() -> Array:
	var out := []
	for n in equipped:
		var g: String = item_stats.get(n, {}).get("grantsSpell", "")
		if g != "" and not out.has(g):
			out.append(g)
	for id in ranks:
		var g2: String = _talents.get(id, {}).get("grantsSpell", "")
		if g2 != "" and ranks[id] > 0 and not out.has(g2):
			out.append(g2)
	return out


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"character_stats.process", __t)


func _process_timed(delta: float) -> void:
	var t := total()
	# HP in ticks, every few seconds, and not while being hurt (a drain still bites).
	_regen_clock += delta
	if _regen_clock >= REGEN_TICK:
		_regen_clock -= REGEN_TICK
		var amount := float(t.get("hpRegen", 0.0)) * REGEN_TICK
		var calm := _now() - _last_hurt >= REGEN_PAUSE_AFTER_HIT
		# Deep Breath: more when she's been out of a fight a while.
		if _now() - _last_hurt >= CALM_AFTER and amount >= 0.0:
			amount += float(t.get("calmRegen", 0.0)) * REGEN_TICK
		if hp > 0.0 and (amount < 0.0 or calm):
			hp = clampf(hp + amount, 0.0, t.get("maxHp", 100.0))
			changed.emit()
	# Second Wind's mending, a few seconds of it.
	if _wind_left > 0.0 and hp > 0.0:
		var step := minf(delta, _wind_left)
		_wind_left -= step
		hp = minf(float(t.get("maxHp", 100.0)), hp + float(t.get("maxHp", 100.0)) * WIND_HEAL * step / WIND_OVER)
		changed.emit()
	var m := clampf(mana + float(t.get("manaRegen", 0.0)) * delta, 0.0, t.get("maxMana", 50.0))
	if m != mana:
		mana = m
		changed.emit()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Uses [param amount] mana if there's enough; false (and none used) if not.
func spend_mana(amount: float) -> bool:
	if mana + 0.001 < amount:
		out_of_mana.emit()
		return false
	mana -= amount
	changed.emit()
	return true


## Takes damage, softened by defense: a share off rather than a flat amount (5 defense takes 20% off, 20 takes half),
## less again while guarded (a shield ward), never below 1; shields first.
func damage(amount: float) -> void:
	if _now() < _wind_safe_until:
		return
	# Bulwark: now and then a hit is blocked outright.
	var block := stat("blockChance")
	if block > 0.0 and randf() < block / 100.0:
		blocked.emit()
		return
	_last_hurt = _now()
	var defense := maxf(0.0, stat("defense"))
	var left := maxf(1.0, amount * 20.0 / (20.0 + defense) * (1.0 - guard() / 100.0))
	for k in shields.keys():
		var take := minf(shields[k], left)
		shields[k] -= take
		left -= take
		if shields[k] <= 0.01:
			shields.erase(k)
		if left <= 0.0:
			break
	var was_up := hp > 0.0
	hp = maxf(0.0, hp - left)
	# Second Wind: a felling blow leaves her at 1 HP, mending, once in a long while.
	if was_up and hp <= 0.0 and stat("secondWind") > 0.0 and _now() >= wind_ready_at:
		hp = 1.0
		wind_ready_at = _now() + WIND_COOLDOWN
		_wind_left = WIND_OVER
		_wind_safe_until = _now() + WIND_SAFE
		second_wind.emit()
	changed.emit()
	if left > 0.0:
		hurt.emit(left)
	if was_up and hp <= 0.0:
		downed.emit()


## The shield [param source] gives (0 to take it away).
func set_shield(source, amount: float) -> void:
	if amount <= 0.0:
		if shields.erase(source):
			changed.emit()
	elif shields.get(source, -1.0) != amount:
		shields[source] = amount
		changed.emit()


func shield_from(source) -> float:
	return float(shields.get(source, 0.0))


func shield() -> float:
	var t := 0.0
	for v in shields.values():
		t += v
	return t


func set_guard(source, pct: float) -> void:
	if pct <= 0.0:
		guards.erase(source)
	else:
		guards[source] = pct


func guard() -> float:
	var g := 0.0
	for v in guards.values():
		g = maxf(g, v)
	return clampf(g, 0.0, 90.0)


func heal(amount: float) -> void:
	hp = minf(stat("maxHp"), hp + amount)
	changed.emit()


func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		talent_points += 1
		leveled_up.emit(level)
	changed.emit()


## The saved stats (Unity's player.stats: level, xp, talent points, hp, mana, talents, what's worn).
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	level = maxi(1, int(d.get("level", 1)))
	xp = maxi(0, int(d.get("xp", 0)))
	talent_points = maxi(0, int(d.get("talentPoints", 0)))
	wind_ready_at = _now() + maxf(0.0, float(d.get("windIn", 0.0)))   # (Second Wind's wait carries over)
	ranks.clear()
	var ids: Array = d.get("talentIds", [])
	var rs: Array = d.get("talentRanks", [])
	for i in mini(ids.size(), rs.size()):
		ranks[ids[i]] = int(rs[i])
	# Saved on an older tree: the points in talents it's since rebuilt (or dropped) come back to be spent again.
	if int(d.get("tree", 1)) < int(character.get("treeVersion", 1)):
		for id in ranks.keys():
			var tl: Dictionary = _talents.get(id, {})
			if tl.is_empty() or (str(tl.get("region", "")) == "Shikigami" and tl.kind != "Start"):
				talent_points += int(ranks[id])
				ranks.erase(id)
	for t in character.talents:
		if t.kind == "Start" and not ranks.has(t.id):
			ranks[t.id] = 1
	equipped = d.get("equipped", [])
	wear = d.get("wear", {})
	wear_saved()
	var tot := total()
	hp = clampf(float(d.get("hp", tot.get("maxHp", 100.0))), 1.0, tot.get("maxHp", 100.0))
	mana = clampf(float(d.get("mana", 0.0)), 0.0, tot.get("maxMana", 50.0))
	changed.emit()


# ---- What's worn, slot by slot (Unity's EquipSlot) ----

const SLOTS := ["LeftHand", "RightHand", "Armor", "Gloves", "Pants", "Shoes", "Necklace", "Ring1", "Ring2", "Bag"]

var worn := {}                     ## slot -> item name


## Puts the saved gear on, slot by slot (after [method from_json]).
func wear_saved() -> void:
	worn.clear()
	for n in equipped:
		var clear := []
		var slot := slot_for(n, clear)
		for s in clear:
			worn.erase(s)
		worn[slot] = n
	_sync_equipped()


func _sync_equipped() -> void:
	var list := []
	for s in SLOTS:
		if worn.has(s) and not list.has(worn[s]):
			list.append(worn[s])
	equipped = list


func worn_in(slot: String) -> String:
	return str(worn.get(slot, ""))


## Whether the right hand is taken up by a two-handed weapon in the left.
func right_hand_blocked() -> bool:
	return worn.has("LeftHand") and str(UiKit.item(worn.LeftHand).get("kind", "")) == "TwoHanded"


## The slot an item of its kind goes in, and (in [param clear]) what it pushes out of the way.
func slot_for(item: String, clear: Array) -> String:
	var kind := str(UiKit.item(item).get("kind", ""))
	match kind:
		"OneHanded":
			clear.append("LeftHand")
			return "LeftHand"
		"TwoHanded":
			clear.append_array(["LeftHand", "RightHand"])
			return "LeftHand"
		"Shield":
			clear.append("RightHand")
			if right_hand_blocked():
				clear.append("LeftHand")
			return "RightHand"
		"Bag":
			clear.append("Bag")
			return "Bag"
		"Ring":
			var ring := "Ring1" if not worn.has("Ring1") else ("Ring2" if not worn.has("Ring2") else "Ring1")
			clear.append(ring)
			return ring
	var slot: String = kind if kind in ["Armor", "Gloves", "Pants", "Shoes"] else "Necklace"
	clear.append(slot)
	return slot


func _say(text: String, c := Color(1, 0.6, 0.5)) -> void:
	var who := get_parent() as Node2D
	if who != null and UiKit._world != null:
		FloatingText.spawn(UiKit._world, text, who.position + Vector2(0, -1.2 * UiKit._world.px), c)


## Wears the gear in bag slot [param from], putting what it pushes off back in the bag (the first into the slot it came
## from). Nothing changes if the bag can't take what comes off.
func equip(bag: Bag, from: int) -> void:
	var item: String = bag.items[from]
	if item == "":
		return
	var it := UiKit.item(item)
	var kind := str(it.get("kind", ""))
	if not bool(it.get("wearable", true)) or kind == "Tools":
		_say("Tools are for the villagers: put them in storage" if kind == "Tools" else "Not something to wear", Color(0.9, 0.85, 0.7))
		return
	var clear := []
	var slot := slot_for(item, clear)
	var off := []
	for s in clear:
		if worn.has(s) and not off.has(worn[s]):
			off.append(worn[s])
	# A smaller bag than the one on: only if what's in the old bag's slots fits.
	if kind == "Bag" and worn.has("Bag") and int(it.get("bagSlots", 0)) < int(UiKit.item(worn.Bag).get("bagSlots", 0)):
		if _used_past(bag, Bag.BASE_SLOTS + int(it.get("bagSlots", 0)), from) > 0:
			_say("Empty the bag's slots first")
			return
	var free := 0
	for i in bag.capacity():
		if bag.items[i] == "" and bag.stack_in(i) == "":
			free += 1
	if off.size() > free + 1:
		return
	bag.items[from] = ""
	for s in clear:
		worn.erase(s)
	worn[slot] = item
	_sync_equipped()
	bag.worn = equipped
	for i in off.size():
		var to := from if i == 0 else bag.free_slot()
		if to >= 0:
			bag.items[to] = off[i]
	bag.changed.emit()
	_clamp()
	changed.emit()


# How many things sit in bag slots at or past [param past] (other than slot [param skip]).
func _used_past(bag: Bag, past: int, skip := -1) -> int:
	var n := 0
	for i in range(past, Bag.SIZE):
		if i != skip and (bag.items[i] != "" or bag.stack_in(i) != ""):
			n += 1
	return n


## How much of [param item]'s life is left, 1 (new) to 0, or -1 for gear that doesn't wear out. (Kept by name: a
## necklace taken off and put on again picks up where it was; another of the same kind shares it.)
func durability_left(item: String) -> float:
	var most := float(item_stats.get(item, {}).get("durability", 0.0))
	if most <= 0.0:
		return -1.0
	return clampf(1.0 - float(wear.get(item, 0.0)) / most, 0.0, 1.0)


## Wears [param item] for [param seconds] more; true when that's used it up.
func wear_out(item: String, seconds: float) -> bool:
	wear[item] = float(wear.get(item, 0.0)) + seconds
	return durability_left(item) == 0.0


## Gear in [param slot] used up: gone (not back in the bag), and the next of its kind starts new.
func break_worn(bag: Bag, slot: String) -> void:
	var item := worn_in(slot)
	if item == "":
		return
	worn.erase(slot)
	wear.erase(item)
	_sync_equipped()
	bag.worn = equipped
	bag.changed.emit()
	_clamp()
	changed.emit()


## Takes off what's in [param slot], into the bag.
func unequip(bag: Bag, slot: String) -> void:
	if not worn.has(slot):
		return
	if slot == "Bag":
		var used := 0
		for i in Bag.BASE_SLOTS:
			if bag.items[i] != "" or bag.stack_in(i) != "":
				used += 1
		var past := _used_past(bag, Bag.BASE_SLOTS)
		if past > 0 or used >= Bag.BASE_SLOTS:
			_say("No room for the bag" if past == 0 else "Empty the bag's slots first")
			return
	var item: String = worn[slot]
	worn.erase(slot)
	_sync_equipped()
	bag.worn = equipped
	var to := bag.free_slot()
	if to < 0:
		worn[slot] = item
		_sync_equipped()
		bag.worn = equipped
		_say("The bag is full")
		return
	bag.items[to] = item
	bag.changed.emit()
	_clamp()
	changed.emit()


func _clamp() -> void:
	var t := total()
	hp = minf(hp, float(t.get("maxHp", hp)))
	mana = minf(mana, float(t.get("maxMana", mana)))


# ---- The talent web: learning a path out from what's learnt, and giving talents back ----

func talent(id: String) -> Dictionary:
	return _talents.get(id, {})


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func unlocked(id: String) -> bool:
	return rank(id) > 0


## The talents [param id] connects to, both ways.
func neighbours(id: String) -> Array:
	if _links.is_empty():
		for t in character.talents:
			for l in t.links:
				if not _talents.has(l):
					continue
				if not _links.has(t.id): _links[t.id] = []
				if not _links.has(l): _links[l] = []
				if not _links[t.id].has(l): _links[t.id].append(l)
				if not _links[l].has(t.id): _links[l].append(t.id)
	return _links.get(id, [])


var _links := {}


## The cheapest run of locked talents from what's learnt out to [param id] (ending with it), [] when it's learnt, or
## null when it can't be reached. Its length is the points it costs.
func path_to(id: String) -> Variant:
	if unlocked(id):
		return []
	var from := {}
	var queue := []
	for t in character.talents:
		if unlocked(t.id):
			from[t.id] = ""
			queue.append(t.id)
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if n == id:
			break
		for nx in neighbours(n):
			if not from.has(nx):
				from[nx] = n
				queue.append(nx)
	if not from.has(id):
		return null
	var path := []
	var at := id
	while at != "" and not unlocked(at):
		path.push_front(at)
		at = from[at]
	return path


## Learns the whole path out to [param id] if there are the points for it.
func learn_path(id: String) -> bool:
	var path: Variant = path_to(id)
	if path == null or path.is_empty() or path.size() > talent_points:
		return false
	for n in path:
		ranks[n] = 1
	talent_points -= path.size()
	changed.emit()
	return true


## Whether [param id] can be given back: learnt, not the start, and everything else learnt still joins up to the start
## without it.
func can_refund(id: String) -> bool:
	if not unlocked(id) or str(talent(id).get("kind", "")) == "Start":
		return false
	var start := ""
	for t in character.talents:
		if t.kind == "Start":
			start = t.id
	if start == "":
		return true
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		for nx in neighbours(queue.pop_front()):
			if nx != id and unlocked(nx) and not seen.has(nx):
				seen[nx] = true
				queue.append(nx)
	for t in character.talents:
		if unlocked(t.id) and t.id != id and not seen.has(t.id):
			return false
	return true


func refund_cost() -> int:
	return int(character.get("refundCost", 10))


## Gives back [param id]'s point, for gold from [param bag]; false if it can't.
func refund(id: String, bag: Bag) -> bool:
	if not can_refund(id):
		return false
	if bag != null and not bag.spend("Gold", refund_cost()):
		return false
	ranks.erase(id)
	talent_points += 1
	_clamp()
	changed.emit()
	return true


## The skills known, each with where it comes from: [[spell, from]] (gear first, then talents).
func spell_sources() -> Array:
	var out := []
	for n in equipped:
		var g: String = item_stats.get(n, {}).get("grantsSpell", "")
		if g != "":
			out.append([g, str(UiKit.item(n).get("name", n))])
	for t in character.talents:
		if unlocked(t.id) and str(t.get("grantsSpell", "")) != "":
			out.append([t.grantsSpell, str(t.name)])
	return out


# ---- Stats as words ----

## Each stat's name and unit, in Unity's StatBlock order.
const STAT_NAMES := [["maxHp", "Max HP", ""], ["maxMana", "Max Mana", ""], ["attack", "Attack", ""], ["defense", "Defense", ""],
	["magic", "Magic", ""], ["hpRegen", "HP Regen", "/s"], ["manaRegen", "Mana Regen", "/s"], ["castSpeed", "Cast Speed", "%"],
	["spellDamage", "Spell Damage", "%"], ["cooldownReduction", "Cooldown Reduction", "%"], ["summonEffect", "Summon Effect", "%"],
	["summonDuration", "Summon Duration", "%"], ["summonDamage", "Summon Damage", "%"], ["summonHp", "Summon HP", "%"],
	["maxSummons", "Max Shikigami", ""], ["summonSeconds", "s Summon Duration", ""],
	["summonAttackSpeed", "Shikigami Attack Speed", "%"], ["summonDoubleAttack", "Chance to Strike Twice", "%"],
	["summonCritChance", "Shikigami Critical Chance", "%"], ["summonCritDamage", "Shikigami Critical Damage", "%"],
	["summonMagicToAttack", "of Magic as Shikigami Attack", "%"], ["summonHeal", "Shikigami Healing", "%"],
	["healDuration", "Healing Circle Duration", "%"], ["lastingHeal", "HP Regen after a Healing Circle", "/s"],
	["shieldPower", "Shield Strength", "%"], ["shieldManaRegen", "Mana Regen inside a Shield", "/s"],
	["attackerSummons", "Attack Shikigami at once", ""], ["healerSummons", "Healing Shikigami at once", ""],
	["defenderSummons", "Shield Shikigami at once", ""], ["gatherSpeed", "Gather Speed", "%"], ["woodYield", "Wood Yield", "%"],
	["stoneYield", "Stone Yield", "%"], ["growthSpeed", "Tree Growth", "%"], ["moveSpeed", "Move Speed", "%"],
	["harvestBonus", "Chance of an Extra Crop", "%"], ["foodKeeps", "Slower Food Spoiling", "%"], ["cookSpeed", "Cooking Speed", "%"],
	["cookBonus", "Chance of an Extra Dish", "%"], ["craftBonus", "Chance of an Extra when Making Materials", "%"],
	["bagSlots", "Bag Slots", ""], ["rabbitBreeding", "Rabbit Breeding Speed", "%"], ["butcherBonus", "Meat from Butchering", ""],
	["villageWork", "Villager Work Speed", "%"], ["calmRegen", "HP Regen out of a Fight", "/s"],
	["mistResist", "Slower Mist Sickness", "%"], ["hungerResist", "Less Starving Damage", "%"],
	["knockResist", "Knockback Resistance", "%"], ["blockChance", "Chance to Block a Hit", "%"]]


static func fmt(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	return ("%.1f" % v).trim_suffix(".0")


## A stat block in words: "+5 Magic, +3% Cast Speed".
static func describe(block: Dictionary) -> String:
	var parts := []
	for s in STAT_NAMES:
		var v := float(block.get(s[0], 0.0))
		if absf(v) > 0.001:
			parts.append("%s%s%s %s" % ["+" if v > 0 else "", fmt(v), s[2], s[1]])
	return ", ".join(parts)


## What gear and talents add (no base, no level, no buffs).
func bonuses() -> Dictionary:
	var t := {}
	for n in equipped:
		_add(t, item_stats.get(n, {}).get("stats", {}))
	for id in ranks:
		if _talents.has(id):
			_add(t, _talents[id].perRank, ranks[id])
	return t


## The stats as Unity's player.stats.
func to_json() -> String:
	var ids := []
	var rs := []
	for id in ranks:
		ids.append(id)
		rs.append(int(ranks[id]))
	return JSON.stringify({"level": level, "xp": xp, "talentPoints": talent_points, "hp": hp, "mana": mana, "tree": int(character.get("treeVersion", 1)), "windIn": maxf(0.0, wind_ready_at - _now()),
		"talentIds": ids, "talentRanks": rs, "equipped": equipped, "wear": wear})
