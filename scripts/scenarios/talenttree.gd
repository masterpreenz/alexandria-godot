extends Scenario
## The talent tree: K opens it (pictures of the whole tree, scrolled to its right end, and a talent picked); Sera up to
## a high level learns a path through every group (the core skills to rank 5), printing the skills she knows and the
## new talents' stats; then some of them in play: Meteor Shower's extra meteors, Searing Circle and Purifying Light
## hurting and burning a slime in a healing circle, Spirit Host's extra attack shikigami, Thorned Ward striking back
## and Bursting Ward bursting. Last, an old save's talents carried over onto the tree. Run with --window=talenttree.

var md: Dictionary
var sd: Dictionary
var combat: Dictionary


func _press(k: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		Input.parse_input_event(ev)
		await get_tree().process_frame
	for i in 4:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run() -> void:
	await _frames(30)
	md = world._load_json("res://data/monsters.json")
	sd = world._load_json("res://data/shikigami.json")
	combat = world._load_json("res://data/combat.json")
	if Chronicle.active != null and not Chronicle.active.happened("village_given"):
		Chronicle.active.record("village_given")
	var st: CharacterStats = miko.stats
	print("Tree: Sera level ", st.level, ", points ", st.talent_points, ", ranks ", st.ranks)
	await _press(KEY_K)
	var cp: CharacterPanel = CharacterPanel._active
	var tw: TalentsWindow = cp.talents
	print("Tree: K opens the talents ", tw.visible)
	await _frames(20)
	shot("tree")
	# A level gained: two points with it, and the banner says so.
	var pts0 := st.talent_points
	st.gain_xp(st.xp_to_next() - st.xp)
	await _frames(20)
	print("Tree: a level up gives ", st.talent_points - pts0, " points; banner says '", Loc.t("levelup.banner", {"level": st.level, "points": st.points_per_level()}), "'")
	shot("levelup")
	# A high level, and the points to spend.
	st.level = 25
	st.talent_points = 70
	st.changed.emit()
	var plan := ["s2", "s2", "s2", "s2", "s2", "u6", "a1", "a1", "a1", "a1", "k5", "sw", "hl2", "hl2", "hl2", "hl2", "hl2", "sc", "pl",
		"hl6", "f8", "f8", "f8", "f8", "f8", "ms", "sco", "sf", "wc", "sh", "ks", "lb", "mp", "d2", "d2", "d2", "d2", "d2", "tw", "bu",
		"d6", "b0", "b0", "h0"]
	var failed := []
	for id in plan:
		if not st.learn_path(id):
			failed.append(id)
	print("Tree: learnt the path, failed ", failed, ", points left ", st.talent_points)
	var shown := []
	for id in ["s2", "u6", "a1", "k1", "k5", "hl2", "f8", "ms", "sh", "d2", "b0"]:
		shown.append("%s %d/%d" % [id, st.rank(id), st.max_rank(id)])
	print("Tree: ranks ", ", ".join(shown))
	print("Tree: known spells ", st.known_spells())
	var tot := st.total()
	var keys := ["summonDamage", "summonSeconds", "summonDoubleAttack", "summonSpeed", "summonHeal", "healDuration", "circleSize",
		"circleSear", "circleBurn", "meteorDamage", "meteorArea", "meteorShower", "meteorCooldown", "burnTime", "burnDamage",
		"attackerSummons", "healerSummons", "defenderSummons", "kindredSpirits", "bondSeconds", "mendShikigami", "shieldPower",
		"wardSeconds", "wardGuard", "summonHp", "thornWard", "wardBurst"]
	var line := []
	for k in keys:
		line.append("%s %s" % [k, CharacterStats.fmt(float(tot.get(k, 0.0)))])
	print("Tree: stats ", ", ".join(line))
	print("Tree: Skyfall at rank 5 reads: ", tw.effect_text(st.talent("f8")).replace("\n", " | "))
	var caster: SpellCaster = world.get_node("Caster")
	print("Tree: meteor cooldown ", snappedf(caster._cooldown("MeteorStrike"), 0.01), " (of ", caster.spells.MeteorStrike.cooldown, "), area ", snappedf(float(SpellEffects.tuned(caster.spells.MeteorStrike, st).aoeRadius), 0.1), " (of ", caster.spells.MeteorStrike.aoeRadius, ")")
	tw.refresh()
	await _frames(10)
	shot("learnt")
	tw.select("f8")
	await _frames(40)
	tw.show_tip(tw.describe("f8"))
	await _frames(5)
	shot("picked")
	tw.hide_tip()
	tw.web.scroll_to(1.0)
	await _frames(10)
	shot("right")
	tw.web.scroll_to(0.0)
	await _press(KEY_K)
	print("Tree: K again closes it ", not tw.visible)
	await _effects(st, caster)
	_migration()
	print("Tree: done")


func _effects(st: CharacterStats, caster: SpellCaster) -> void:
	miko.place(_open_spot())
	st.hp = st.stat("maxHp")
	st.mana = st.stat("maxMana")
	await _frames(10)
	# Meteor Shower: count the meteors that fall from one cast.
	var target := miko.position + Vector2(5.0, 0.0) * world.px
	SpellEffects.begin(world, caster.spells.MeteorStrike, st, target + Vector2(-320, -1024), target, target)
	var seen := {}
	for i in 200:
		await get_tree().process_frame
		for c in world.get_children():
			if c is SpellEffects.Projectile and (c as SpellEffects.Projectile).falling:
				seen[c.get_instance_id()] = true
	print("Tree: Meteor Shower: ", seen.size(), " meteors fell from one cast (1 + ", int(st.stat("meteorShower")), " more)")
	# Searing Circle and Purifying Light: a slime in a healing circle.
	var sl: Slime = Slime.spawn(world, md.slime, false, miko.position + Vector2(0.3, 0.2) * world.px, 1.0)
	await _frames(5)
	var hp0 := sl.hit.hp
	var healer := Shikigami.summon(world, "ShikigamiHealer", sd["ShikigamiHealer"], miko, st, caster, miko.position)
	var burnt := false
	for i in 150:
		await get_tree().process_frame
		if is_instance_valid(sl) and StatusEffects.has_effect(sl.hit, "Burn"):
			burnt = true
	print("Tree: Searing Circle: slime HP ", snappedf(hp0, 0.1), " -> ", snappedf(sl.hit.hp, 0.1) if is_instance_valid(sl) else "gone", ", burning ", burnt, ", circles out ", HealingCircle.live.size(), ", circle radius ", snappedf(HealingCircle.live[0].radius / world.px, 0.01) if not HealingCircle.live.is_empty() else 0.0)
	shot("circle")
	# Spirit Host: how many attack shikigami at once (Second Spear and Spirit Host: three; Spirit Host alone: two).
	for k in 4:
		Shikigami.summon(world, "ShikigamiAttacker", sd["ShikigamiAttacker"], miko, st, caster, miko.position)
		await _frames(2)
	print("Tree: attack shikigami out with Second Spear and Spirit Host: ", _out("Attacker"))
	var spear := st.rank("u6")
	st.ranks.erase("u6")
	for k in 3:
		Shikigami.summon(world, "ShikigamiAttacker", sd["ShikigamiAttacker"], miko, st, caster, miko.position)
		await _frames(2)
	print("Tree: attack shikigami out with Spirit Host alone: ", _out("Attacker"), "; healing ones may be ", 1 + int(st.stat("healerSummons")))
	st.ranks["u6"] = spear
	if is_instance_valid(healer):
		healer.dismiss()
	# Thorned Ward and Bursting Ward: a slime drawn onto the shield shikigami.
	var ward := Shikigami.summon(world, "ShikigamiDefender", sd["ShikigamiDefender"], miko, st, caster, miko.position)
	await _frames(10)
	var sl2: Slime = Slime.spawn(world, md.slime, false, ward.position + Vector2(0.6, 0.2) * world.px, 1.0)
	await _frames(5)
	sl2.taunted_by = ward
	sl2.taunt_until = Creature.now() + 10.0
	var before := sl2.hit.hp
	ward.hurt(20.0)
	await _frames(2)
	print("Tree: Thorned Ward: the ward took 20, the slime ", snappedf(before, 0.1), " -> ", snappedf(sl2.hit.hp, 0.1) if is_instance_valid(sl2) else "gone")
	print("Tree: the ward's guard ", float(sd.ShikigamiDefender.guardPercent) + ward.ward_guard, "%, ward seconds +", ward.ward_secs, ", HP ", roundi(ward.max_hp), ", speed x", ward.speed_k)
	before = sl2.hit.hp if is_instance_valid(sl2) else 0.0
	sl2.position = ward.position + Vector2(0.5, 0.2) * world.px
	ward.dismiss()
	await _frames(3)
	print("Tree: Bursting Ward: the slime ", snappedf(before, 0.1), " -> ", snappedf(sl2.hit.hp, 0.1) if is_instance_valid(sl2) else "gone (burst down)")
	shot("burst")
	for s in Shikigami.active.duplicate():
		if is_instance_valid(s):
			s.dismiss()


func _out(kind: String) -> int:
	return Shikigami.active.filter(func(a): return is_instance_valid(a) and a.kind == kind and a.dismissed_at < 0.0).size()


# An old save's talents carried over: the four Quick Jabs into one at rank 4, three Keen Eyes into one at rank 3,
# the water branch's Ice Blast and the Clear Mind connector given back, the start dropped; and the second point a level
# made up.
func _migration() -> void:
	var st := CharacterStats.new()
	add_child(st)
	st.setup(combat.character, combat.get("items", {}))
	var old := {"level": 10, "xp": 0, "talentPoints": 1, "tree": 2, "talentIds": ["start", "s0", "s1", "s2", "a1", "a2", "a3", "a4", "k1", "k2", "k3", "w1", "w2", "r1"],
		"talentRanks": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]}
	st.from_json(JSON.stringify(old))
	var spent := 0
	for id in st.ranks:
		spent += st.rank(id)
	print("Tree: migration: ranks ", st.ranks, ", points ", st.talent_points, " (had 1; 4 given back: s0, w1, w2, r1), spent ", spent, ", level 10 makes ", 9 * st.points_per_level(), " in all")
	print("Tree: migration: saved again on tree ", JSON.parse_string(st.to_json()).tree, "; loaded again: ", _again(st))
	st.queue_free()


func _again(st: CharacterStats) -> String:
	var st2 := CharacterStats.new()
	add_child(st2)
	st2.setup(combat.character, combat.get("items", {}))
	st2.from_json(st.to_json())
	var out := "ranks %s, points %d" % [st2.ranks, st2.talent_points]
	st2.queue_free()
	return out


# Somewhere open and dry, out of the village.
func _open_spot() -> Vector2:
	var c0 := world.village.banner_cell()
	for r in range(8, 60, 2):
		for k in 24:
			var a := k * TAU / 24.0
			var c := c0 + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			var at := world.floors.cell_centre(c)
			if world.water_depth(at) <= 0.0 and Wilds.open(world, at, 4.0, 0.3) and Wilds.open(world, at + Vector2(5.0, 0.0) * world.px, 3.0, 0.3):
				return at
	return world.floors.cell_centre(c0 + Vector2i(12, 0))
