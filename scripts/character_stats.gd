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

const REGEN_TICK := 5.0
const REGEN_PAUSE_AFTER_HIT := 5.0

var character: Dictionary          ## base, perLevel, talents, xpPerLevel (combat.json's character)
var item_stats: Dictionary         ## item name -> {stats, grantsSpell}
var level := 1
var xp := 0
var talent_points := 0
var ranks := {}                    ## talent id -> rank
var equipped: Array = []           ## worn item names
var hp := 0.0
var mana := 0.0
var buffs := {}                    ## source -> stat dict
var shields := {}                  ## source -> amount
var guards := {}                   ## source -> % less damage taken (the strongest counts, at most 90)
var _regen_clock := 0.0
var _last_hurt := -99.0
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


func stat(name: String) -> float:
	return float(total().get(name, 0.0))


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
	var t := total()
	# HP in ticks, every few seconds, and not while being hurt (a drain still bites).
	_regen_clock += delta
	if _regen_clock >= REGEN_TICK:
		_regen_clock -= REGEN_TICK
		var amount := float(t.get("hpRegen", 0.0)) * REGEN_TICK
		var calm := _now() - _last_hurt >= REGEN_PAUSE_AFTER_HIT
		if hp > 0.0 and (amount < 0.0 or calm):
			hp = clampf(hp + amount, 0.0, t.get("maxHp", 100.0))
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


func set_guard(source, percent: float) -> void:
	if percent <= 0.0:
		guards.erase(source)
	else:
		guards[source] = percent


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
	changed.emit()


## The saved stats (Unity's player.stats: level, xp, talent points, hp, mana, talents, what's worn).
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	level = maxi(1, int(d.get("level", 1)))
	xp = maxi(0, int(d.get("xp", 0)))
	talent_points = maxi(0, int(d.get("talentPoints", 0)))
	ranks.clear()
	var ids: Array = d.get("talentIds", [])
	var rs: Array = d.get("talentRanks", [])
	for i in mini(ids.size(), rs.size()):
		ranks[ids[i]] = int(rs[i])
	for t in character.talents:
		if t.kind == "Start" and not ranks.has(t.id):
			ranks[t.id] = 1
	equipped = d.get("equipped", [])
	var tot := total()
	hp = clampf(float(d.get("hp", tot.get("maxHp", 100.0))), 1.0, tot.get("maxHp", 100.0))
	mana = clampf(float(d.get("mana", 0.0)), 0.0, tot.get("maxMana", 50.0))
	changed.emit()
