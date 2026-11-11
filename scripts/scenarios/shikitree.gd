extends Scenario
## The rebuilt shikigami tree: an old save's points come back; every node learnt, its stats; how many
## of each shikigami can be out; crits and double thrusts on a dummy.
## Run with --window=shikitree.


func run() -> void:
	var st: CharacterStats = miko.stats
	var old := JSON.parse_string(st.to_json()) as Dictionary
	old.erase("tree")
	old.talentIds = ["start", "s0", "sa2", "sd2", "sa6"]
	old.talentRanks = [1, 1, 1, 1, 1]
	old.talentPoints = 2
	st.from_json(JSON.stringify(old))
	print("Shiki tree: old save -> points ", st.talent_points, ", ranks ", st.ranks.keys())
	for tl in st.character.talents:
		if str(tl.region) == "Shikigami":
			st.ranks[tl.id] = 1
	st.changed.emit()
	var tot := st.total()
	for k in ["magic", "castSpeed", "summonAttackSpeed", "summonDoubleAttack", "summonCritChance", "summonCritDamage", "summonSeconds", "summonMagicToAttack", "summonHeal", "healDuration", "lastingHeal", "shieldPower", "shieldManaRegen", "attackerSummons", "healerSummons", "defenderSummons"]:
		print("  ", k, " ", tot.get(k, 0))
	print("Shiki tree: a node in words: '", CharacterStats.describe(st._talents["k5"].perRank), "', '", CharacterStats.describe(st._talents["u1"].perRank), "'")
	var caster_node: SpellCaster = world.get_node("Caster")
	var sd: Dictionary = world._load_json("res://data/shikigami.json")
	var out_now := func() -> Array:
		var by := {}
		for a in Shikigami.active:
			if is_instance_valid(a) and a.dismissed_at < 0.0:
				by[a.kind] = int(by.get(a.kind, 0)) + 1
		return [by]
	for spell in ["ShikigamiAttacker", "ShikigamiAttacker", "ShikigamiAttacker", "ShikigamiHealer"]:
		Shikigami.summon(world, spell, sd[spell], miko, st, caster_node, miko.position + Vector2(1, 0) * world.px)
	await get_tree().process_frame
	print("Shiki out after 3 attackers and a healer: ", out_now.call())
	var at0: Shikigami = Shikigami.active.filter(func(a): return is_instance_valid(a) and a.kind == "Attacker" and a.dismissed_at < 0.0)[0]
	print("Attacker power ", snappedf(at0.power, 0.1), " (magic ", tot.magic, "), lasts ", snappedf(at0.ends_at - at0.born_at, 0.1), " s")
	var dummy := Damageable.new()
	dummy.position = miko.position + Vector2(1.5, 0.3) * world.px
	world.things.add_child(dummy)
	dummy.setup(world, Damageable.Team.ENEMY, 5000.0, 0.35 * world.px, 1.2 * world.px)
	dummy.dummy = true
	dummy.hit_by_player = true
	var hits := []
	dummy.damaged.connect(func(amt): hits.append(snappedf(amt, 0.1)))
	var crit_shot := false
	var seen := 0
	for i in int(Shots.arg("shikiframes", "900")):
		await get_tree().process_frame
		if hits.size() > seen:
			seen = hits.size()
			if not crit_shot and float(hits[-1]) > at0.power * 1.5:
				crit_shot = true
				miko.place(dummy.position + Vector2(-1.5, 1.0) * world.px)
				for k in 8:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_crit.png")
	print("Shiki hits on the dummy: ", hits.size(), " ", hits.slice(0, 16))
