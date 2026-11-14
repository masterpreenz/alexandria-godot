class_name CharacterStats
extends Node
## A character's stats (from Unity's CharacterStats): their base for their level, plus their worn gear, their learnt
## talents and any buffs lent them; HP and mana with regen (HP comes back in ticks, not while being hurt), damage
## softened by defense, shields first; XP and levels (talent points with each). The skills they know come from their gear
## and their talents. The talents are a tree: each opens at a level and may need others learnt first, and some take
## several ranks (a core skill grows stronger with each, more so at its milestones).

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
var learned := {}                  ## spell -> the book it was learnt from: known for good, whatever's worn (a companion's)
var gifted := {}                   ## talent id -> ranks of it given for nothing (a book's), which can't be given back
var wears_bag := true              ## false for a companion: what they wear doesn't change the room in Sera's bag
var speaker: Node2D                ## who "not something to wear" shows over (else whoever these stats belong to)


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
	# (asked many times a frame, for every stat: worked out again only when something it's made of has changed)
	var key := [level, ranks.hash(), equipped.hash(), buffs.hash()]
	if key == _total_key and is_same(character, _total_char) and not _total.is_empty():
		return _total.duplicate()
	_total = _total_fresh()
	_total_key = key
	_total_char = character
	return _total.duplicate()


var _total := {}
var _total_key := []
var _total_char: Dictionary = {}


func _total_fresh() -> Dictionary:
	var t := {}
	_add(t, character.get("base", {}))
	_add(t, character.get("perLevel", {}), level - 1)
	for n in equipped:
		_add(t, item_stats.get(n, {}).get("stats", {}))
	for id in ranks:
		if _talents.has(id):
			_add(t, talent_stats(_talents[id], ranks[id]))
	for b in buffs.values():
		_add(t, b)
	return t


## Everything but the buffs (what hunger and the mist take a share of).
func unbuffed() -> Dictionary:
	var key := [level, ranks.hash(), equipped.hash()]
	if key == _bare_key and is_same(character, _bare_char) and not _bare.is_empty():
		return _bare.duplicate()
	var keep := buffs
	buffs = {}
	_bare = _total_fresh()
	buffs = keep
	_bare_key = key
	_bare_char = character
	return _bare.duplicate()


var _bare := {}
var _bare_key := []
var _bare_char: Dictionary = {}


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


## The talent points each level brings.
func points_per_level() -> int:
	return points_per_level_of(character)


static func points_per_level_of(c: Dictionary) -> int:
	return maxi(1, int(c.get("pointsPerLevel", 1)))


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
	for sp in learned:
		if not out.has(sp):
			out.append(sp)
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
	# Out of a fight a while, and not hurt lately: HP and mana come back quickly.
	var quick := resting() and _now() - _last_hurt >= REST_AFTER
	if quick and hp > 0.0 and hp < float(t.get("maxHp", 100.0)):
		var h := minf(float(t.get("maxHp", 100.0)), hp + float(t.get("maxHp", 100.0)) * REST_HP * delta)
		var tell_hp := floori(h) != floori(hp) or h >= float(t.get("maxHp", 100.0))
		hp = h
		if tell_hp:
			changed.emit()
	var m := clampf(mana + (float(t.get("manaRegen", 0.0)) + (float(t.get("maxMana", 50.0)) * REST_MANA if quick else 0.0)) * delta, 0.0, t.get("maxMana", 50.0))
	if m != mana:
		# (told only when the whole number shown changes, or it's full: not every frame of a refill)
		var tell := floori(m) != floori(mana) or m >= float(t.get("maxMana", 50.0))
		mana = m
		if tell:
			changed.emit()


# ---- Out of a fight: HP and mana come back quickly ----

const REST_AFTER := 4.0            ## seconds after the last fight (and the last hit) before the quick mending starts
const REST_HP := 0.05              ## share of max HP a second, then
const REST_MANA := 0.06            ## and of max mana
const FIGHT_NEAR := 12.0           ## units: a monster this near whoever's played, after them or lately hit, means a fight

static var _fight_seen := -99.0
static var _fight_checked := -1.0


## Whether the party's been out of a fight a while (no monster near whoever's played coming for them or lately hit, no
## raid): when HP and mana come back quickly, for them and their companions.
static func resting() -> bool:
	var now := _now()
	if now - _fight_checked >= 0.5:
		_fight_checked = now
		if _fight_now():
			_fight_seen = now
	return now - _fight_seen >= REST_AFTER


static func _fight_now() -> bool:
	if Raids.on():
		return true
	var pl := Playable.active
	if pl == null or pl.miko == null or pl.world == null:
		return false
	var near := FIGHT_NEAR * pl.world.px
	for c in Creature.all:
		if not is_instance_valid(c) or c.asleep or c is Rabbit or c.hit == null or not c.hit.alive():
			continue
		if c.position.distance_to(pl.miko.position) >= near:
			continue
		# (one coming for them, a boar charging, or one hit in the last few seconds: idle monsters about don't count)
		if c.hostile() or MapMarks._hostile(c) or _now() - c.hit._last_hit < 3.0:
			return true
	return false


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
		talent_points += points_per_level()
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
	gifted = {}
	var g: Variant = d.get("gifted", {})
	if g is Dictionary:
		for id in g:
			gifted[str(id)] = int(g[id])
	learned = d.get("learned", {})
	# Spells an old book taught at once, now talents of their own tree (once: they're taken out of learned).
	var from_book := _from_book()
	# Saved on an older tree, or on someone else's (Miyu's talents were Sera's once): carried over onto this one.
	if from_book or str(d.get("treeId", "sera")) != tree_id() or int(d.get("tree", 1)) < int(character.get("treeVersion", 1)):
		_migrate()
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
	var who := speaker if speaker != null and is_instance_valid(speaker) else get_parent() as Node2D
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
	if wears_bag and kind == "Bag" and worn.has("Bag") and int(it.get("bagSlots", 0)) < int(UiKit.item(worn.Bag).get("bagSlots", 0)):
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
	if wears_bag:
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
	if wears_bag:
		bag.worn = equipped
	bag.changed.emit()
	_clamp()
	changed.emit()


## Takes off what's in [param slot], into the bag.
func unequip(bag: Bag, slot: String) -> void:
	if not worn.has(slot):
		return
	if slot == "Bag" and wears_bag:
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
	if wears_bag:
		bag.worn = equipped
	var to := bag.free_slot()
	if to < 0:
		worn[slot] = item
		_sync_equipped()
		if wears_bag:
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


# ---- The talent tree: learning talents (and what they need first), ranking them up, and giving them back ----

func talent(id: String) -> Dictionary:
	return _talents.get(id, {})


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func unlocked(id: String) -> bool:
	return rank(id) > 0


## The most ranks [param id] can be learnt to.
func max_rank(id: String) -> int:
	return maxi(1, int(talent(id).get("maxRank", 1)))


## Whether [param id] is learnt as far as it goes.
func maxed(id: String) -> bool:
	return rank(id) >= max_rank(id)


## What talent [param t] gives at rank [param r]: its stats for each rank, and each milestone it's reached.
static func talent_stats(t: Dictionary, r: int) -> Dictionary:
	var out := {}
	if r <= 0:
		return out
	_add(out, t.get("perRank", {}), r)
	var ms: Dictionary = t.get("milestones", {})
	for k in ms:
		if r >= int(k):
			_add(out, ms[k])
	return out


## The level [param id] opens at: its own, else its group's.
func level_for(id: String) -> int:
	var t := talent(id)
	var lv := int(t.get("level", 0))
	var g := int(t.get("group", -1))
	var groups: Array = character.get("groups", [])
	if lv <= 0 and g >= 0 and g < groups.size():
		lv = int(groups[g].get("level", 1))
	return maxi(1, lv)


## The talents that need [param id] learnt first.
func dependents(id: String) -> Array:
	var out := []
	for t in character.talents:
		if (t.get("needs", []) as Array).has(id):
			out.append(t.id)
	return out


## What learning one more rank of [param id] takes: every talent it needs that isn't learnt yet (the farthest back
## first), then itself; [] when it's learnt as far as it goes, null while it's beyond their level.
## Its length is the points it costs.
func path_to(id: String) -> Variant:
	if not _talents.has(id):
		return null
	if maxed(id):
		return []
	var path := [id]
	var queue := [id]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if level_for(n) > level or barred(n) != "":
			return null
		for need in talent(n).get("needs", []):
			if _talents.has(need) and not unlocked(need) and not path.has(need):
				path.push_front(need)
				queue.append(need)
	return path


## Whose tree this is ("sera" unless it says otherwise).
func tree_id() -> String:
	return str(character.get("treeId", "sera"))


## What keeps [param id] from being learnt at any level, if anything: its lockedBy event not yet happened (the
## event's name), or, not yet learnt, the book its first rank comes with ("book:" and the book); else "".
func barred(id: String) -> String:
	var t := talent(id)
	var ev := str(t.get("lockedBy", ""))
	if ev != "" and (Chronicle.active == null or not Chronicle.active.happened(ev)):
		return ev
	if str(t.get("book", "")) != "" and not unlocked(id):
		return "book:" + str(t.book)
	return ""


## What keeps [param id], or something it needs that isn't learnt yet, from being learnt (as barred), or "".
func barred_on_path(id: String) -> String:
	var queue := [id]
	var seen := {}
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if seen.has(n):
			continue
		seen[n] = true
		if not unlocked(n) or n == id:
			var why := barred(n)
			if why != "":
				return why
		for need in talent(n).get("needs", []):
			if not unlocked(need):
				queue.append(need)
	return ""


## What's said of a talent barred by [param why] (the tree's locks), or a plain word.
func lock_text(why: String) -> String:
	var said := str(character.get("locks", {}).get(why, ""))
	if said != "":
		return said
	if why.begins_with("book:"):
		return "This comes with the %s." % str(UiKit.item(why.trim_prefix("book:")).get("name", why.trim_prefix("book:")))
	return "This can't be learnt yet."


## The ranks of [param id] given for nothing.
func gifted_rank(id: String) -> int:
	return int(gifted.get(id, 0))


## Learns [param id] one rank further (and what it needs first) if there are the points for it.
func learn_path(id: String) -> bool:
	var path: Variant = path_to(id)
	if path == null or path.is_empty() or path.size() > talent_points:
		return false
	for n in path:
		ranks[n] = rank(n) + 1
	talent_points -= path.size()
	changed.emit()
	return true


## Whether a rank of [param id] can be given back: learnt, and (for its last rank) nothing learnt needs it.
func can_refund(id: String) -> bool:
	if not unlocked(id) or str(talent(id).get("kind", "")) == "Start" or rank(id) <= gifted_rank(id):
		return false
	if rank(id) > 1:
		return true
	for d in dependents(id):
		if unlocked(d):
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
	ranks[id] = rank(id) - 1
	if ranks[id] <= 0:
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
	for sp in learned:
		out.append([sp, str(learned[sp])])
	return out


# ---- Stats as words ----

## Each stat's name and unit, in Unity's StatBlock order.
const STAT_NAMES := [["maxHp", "Max HP", ""], ["maxMana", "Max Mana", ""], ["attack", "Attack", ""], ["defense", "Defense", ""],
	["magic", "Magic", ""], ["hpRegen", "HP Regen", "/s"], ["manaRegen", "Mana Regen", "/s"], ["castSpeed", "Cast Speed", "%"],
	["spellDamage", "Spell Damage", "%"], ["cooldownReduction", "Cooldown Reduction", "%"], ["summonEffect", "Summon Effect", "%"],
	["summonDuration", "Summon Duration", "%"], ["summonDamage", "Summon Damage", "%"], ["summonHp", "Summon HP", "%"],
	["attackSpeed", "Attack Speed", "%"], ["maxSummons", "Max Shikigami", ""], ["summonSeconds", "s Summon Duration", ""],
	["summonAttackSpeed", "Shikigami Attack Speed", "%"], ["summonDoubleAttack", "Chance to Strike Twice", "%"],
	["summonCritChance", "Shikigami Critical Chance", "%"], ["summonCritDamage", "Shikigami Critical Damage", "%"],
	["summonMagicToAttack", "of Magic as Shikigami Attack", "%"], ["summonHeal", "Shikigami Healing", "%"],
	["healDuration", "Healing Circle Duration", "%"], ["lastingHeal", "HP Regen after a Healing Circle", "/s"],
	["shieldPower", "Shield Strength", "%"], ["shieldManaRegen", "Mana Regen inside a Shield", "/s"],
	["attackerSummons", "Attack Shikigami at once", ""], ["healerSummons", "Healing Shikigami at once", ""],
	["defenderSummons", "Shield Shikigami at once", ""], ["summonSpeed", "Shikigami Move Speed", "%"],
	["kindredSpirits", "Shikigami Damage in a Healing Circle", "%"], ["bondSeconds", "s Attack and Healing Shikigami Duration", ""],
	["mendShikigami", "of Circle Healing Mends Your Shikigami", "%"], ["circleSear", "Damage a Second in a Healing Circle", ""],
	["circleSize", "Healing Circle Size", "%"], ["thornWard", "of Blows Struck Back by the Shield Shikigami", "%"],
	["wardBurst", "Damage as the Shield Shikigami Bursts", ""], ["wardSeconds", "s Shield Ward Duration", ""],
	["wardGuard", "Less Damage inside the Ward", "%"], ["meteorDamage", "Meteor Damage", "%"], ["meteorArea", "Meteor Area", "%"],
	["meteorCooldown", "Shorter Meteor Cooldown", "%"], ["meteorShower", "Extra Meteor", ""], ["burnTime", "Longer Burns", "%"],
	["burnDamage", "Harder Burns", "%"], ["gatherSpeed", "Gather Speed", "%"], ["woodYield", "Wood Yield", "%"],
	["stoneYield", "Stone Yield", "%"], ["growthSpeed", "Tree Growth", "%"], ["moveSpeed", "Move Speed", "%"],
	["harvestBonus", "Chance of an Extra Crop", "%"], ["foodKeeps", "Slower Food Spoiling", "%"], ["cookSpeed", "Cooking Speed", "%"],
	["cookBonus", "Chance of an Extra Dish", "%"], ["craftBonus", "Chance of an Extra when Making Materials", "%"],
	["bagSlots", "Bag Slots", ""], ["rabbitBreeding", "Rabbit Breeding Speed", "%"], ["butcherBonus", "Meat from Butchering", ""],
	["villageWork", "Villager Work Speed", "%"], ["calmRegen", "HP Regen out of a Fight", "/s"],
	["mistResist", "Slower Mist Sickness", "%"], ["hungerResist", "Less Starving Damage", "%"],
	["knockResist", "Knockback Resistance", "%"], ["blockChance", "Chance to Block a Hit", "%"],
	["shardDamage", "Ice Shard Damage", "%"], ["twinShard", "Extra Ice Shard", ""], ["frostbiteDamage", "Harder Frostbite", "%"],
	["poolHeal", "Healing Blanket Mending", "%"], ["poolSeconds", "Longer Healing Blanket", "%"],
	["blanketShare", "of the Blanket on the Most Hurt Ally Near", "%"], ["blanketFrost", "Cold Comfort (the wrapped ally's blows frostbite)", ""],
	["armorStrength", "Frost Armor Strength", "%"],
	["armorSeconds", "Longer Frost Armor", "%"], ["armorBurst", "Frost Armor Burst Damage", "%"],
	["armorFrost", "Harder Frostbite from the Burst", "%"], ["blastDamage", "Ice Blast Damage", "%"], ["blastArea", "Ice Blast Area", "%"],
	["blastCooldown", "Shorter Ice Blast Cooldown", "%"], ["blastFrozenGround", "s of Frozen Ground after an Ice Blast", ""],
	["coldSnap", "Chance for Ice to Freeze Solid", "%"], ["stormDamage", "Blizzard Damage", "%"], ["stormShards", "More Blizzard Shards", ""],
	["stormSeconds", "Longer Blizzard", "%"], ["stormArea", "Blizzard Area", "%"], ["rime", "Blizzard Shards Frostbite", ""]]


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
			_add(t, talent_stats(_talents[id], ranks[id]))
	return t


## A save from an older tree onto this one: talents folded into one with ranks add their ranks up (past its most,
## the points come back); talents the tree no longer has give their points back; the start (never paid for) goes.
func _migrate() -> void:
	var merged: Dictionary = character.get("merged", {})
	var free: Array = character.get("freeIds", [])
	var old := ranks.duplicate()
	ranks.clear()
	for id in old:
		var r := int(old[id])
		if free.has(id) or r <= 0:
			continue
		var to := str(merged.get(id, id))
		if not _talents.has(to):
			talent_points += r
			continue
		ranks[to] = rank(to) + r
	for id in ranks.keys():
		var over := rank(id) - max_rank(id)
		if over > 0:
			talent_points += over
			ranks[id] = max_rank(id)
	# More points come with each level now: whatever's short of that for the levels gained so far, given at once.
	var spent := 0
	for id in ranks:
		spent += maxi(0, rank(id) - gifted_rank(id))
	talent_points += maxi(0, (level - 1) * points_per_level() - (talent_points + spent))
	for id in gifted.keys():
		if not _talents.has(id):
			gifted.erase(id)


# The spells an old book taught at once (Miyu's four from the Water Spell Book), now talents of this tree: each given
# at rank 1 for nothing (one that opens at a later level than theirs gives a point back instead), and taken out of
# what they'd learnt. Whether there were any.
func _from_book() -> bool:
	var map: Dictionary = character.get("fromBook", {})
	var any := false
	for sp in learned.keys():
		if not map.has(sp):
			continue
		any = true
		learned.erase(sp)
		var to: Variant = map[sp]
		var id := str(to.get("talent", "")) if to is Dictionary else str(to)
		var from_level := int(to.get("fromLevel", 0)) if to is Dictionary else 0
		if id == "" or not _talents.has(id):
			continue
		if level < from_level:
			talent_points += 1
			continue
		if rank(id) < 1:
			ranks[id] = 1
		gifted[id] = maxi(gifted_rank(id), 1)
	return any


## The stats as Unity's player.stats.
func to_json() -> String:
	var ids := []
	var rs := []
	for id in ranks:
		ids.append(id)
		rs.append(int(ranks[id]))
	return JSON.stringify({"level": level, "xp": xp, "talentPoints": talent_points, "hp": hp, "mana": mana, "tree": int(character.get("treeVersion", 1)), "windIn": maxf(0.0, wind_ready_at - _now()),
		"treeId": tree_id(),
		"talentIds": ids, "talentRanks": rs, "gifted": gifted, "equipped": equipped, "wear": wear, "learned": learned})
