extends Scenario
## Miyu's own tree of ice and water: given the Water Spell Book she knows Ice Shard only, her tree open to her points
## (pictures of its left and right ends); the Advanced Ice group locked till someone helps her (the lock's words, a
## picture), then learnt; every core skill to rank 5 and the rest; then each spell cast by her among monsters, what it
## did printed (Ice Shard and its twin, Healing Blanket mending Sera only, Frost Armor on Sera and Miyu bursting,
## Ice Blast with frozen ground and a Cold Snap freeze, Blizzard's shards landing), and her casting on her own. Last,
## an old save where the book taught all four spells at once, carried over. Run with --window=miyuice.

var md: Dictionary


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(s: float) -> void:
	await get_tree().create_timer(s).timeout


func run() -> void:
	await _frames(30)
	md = world._load_json("res://data/monsters.json")
	var ch := Chronicle.active
	# (the bundled save has no Miyu: someone stands in for her)
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	var trait_list: Array = miyu.person.get("traits", []).duplicate()
	trait_list.append("unique")
	miyu.person["traits"] = trait_list
	ch.events = ch.events.filter(func(e): return not str(e.what) in ["book_given:miyu", "miyu_water", "scene:miyu_water_book", "miyu_advanced_ice"])
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	miyu.person["level"] = 4
	if not miko.bag.items.has("WaterTome"):
		miko.bag.items[miko.bag.free_slot()] = "WaterTome"
		miko.bag.changed.emit()
	await _frames(20)
	var st := Companions.stats_for(miyu.person)
	print("Miyu ice: before the book: tree ", st.tree_id(), ", known ", st.known_spells(), ", points ", st.talent_points, ", Ice Shard can be bought ", st.path_to("is") != null, " (barred '", st.barred("is"), "')")
	# The book, given in a talk.
	miko.place(miyu.position + Vector2(1.0, 0.6) * world.px)
	await _frames(10)
	Talk.active.open(miyu)
	await _frames(10)
	var book := Companions.book_for(miyu.person, miko.bag)
	Talk.active._give_book(book)
	await _frames(20)
	Talk.active.close()
	await _frames(5)
	print("Miyu ice: after the book: known ", st.known_spells(), ", Ice Shard rank ", st.rank("is"), " (gifted ", st.gifted_rank("is"), "), learned ", st.learned, ", points ", st.talent_points)
	var groups := []
	for gr in st.character.groups:
		groups.append("%s Lv%d" % [gr.name, int(gr.level)])
	print("Miyu ice: her tree's groups ", groups, ", rows ", st.character.rows, ", talents ", st.character.talents.size())
	for gi in st.character.groups.size():
		var nodes := []
		for t in st.character.talents:
			if int(t.group) == gi:
				nodes.append("%s %s (%s, %s, max %d)" % [t.id, t.name, t.row, t.kind, int(t.get("maxRank", 1))])
		print("Miyu ice: group ", gi, ": ", ", ".join(nodes))
	var lb: Array = st.character.talents.filter(func(t): return int(t.group) < 0)
	print("Miyu ice: Life & Body talents shared ", lb.size(), ", same as Sera's ", lb.size() == miko.stats.character.talents.filter(func(t): return int(t.group) < 0).size())
	print("Miyu ice: Sera's tree still hers: ", miko.stats.tree_id(), ", first talent ", miko.stats.character.talents[0].id)
	# Her talents window.
	var cp: CharacterPanel = g.get_node("Hud/CharacterPanel")
	cp.open_for(miyu.person, true)
	var tw: TalentsWindow = cp.talents
	await _frames(15)
	tw.web.fit()
	tw.web.scroll_to(0.0)
	await _frames(10)
	print("Miyu ice: window shows '", tw.owner_name(), "', its stats Miyu's ", tw.stats == st, ", web laid out for her tree ", tw.web._pos.has("is"), ", has Sera's s2 ", tw.web._pos.has("s2"))
	shot("tree_left")
	tw.web.scroll_to(1.0)
	await _frames(10)
	shot("tree_right")
	# The locked group: can't be learnt at any level.
	st.level = 25
	miyu.person["level"] = 25
	st.talent_points = 80
	st.changed.emit()
	tw.select("ibz")
	await _frames(5)
	print("Miyu ice: Blizzard locked: learn ", st.learn_path("ibz"), ", path ", st.path_to("ibz"), ", barred '", st.barred("ibz"), "', panel says '", tw._path.text, "', button '", tw._learn.text, "' disabled ", tw._learn.disabled)
	print("Miyu ice: Glacial Spikes locked ", st.path_to("igs") == null, ", Ice Pillar ", st.path_to("ipl") == null, ", Rime (behind Blizzard) says '", st.lock_text(st.barred_on_path("iri")), "'")
	var tip := tw.describe("igs")
	print("Miyu ice: hover card ends '", tip.substr(tip.rfind("\n") + 1), "'")
	tw.show_tip(tip)
	await _frames(5)
	shot("locked")
	tw.hide_tip()
	# Every core skill to rank 5, and the rest.
	var plan := ["is", "is", "is", "is", "its", "ifb", "ifb", "ifb", "iks", "iks", "iks", "iqc", "iqc", "ids", "ids",
		"ihc", "ihc", "ihc", "ihc", "ihc", "ice", "igw", "igw", "igw", "ilt", "ilt", "iwp", "iwp",
		"ifa", "ifa", "ifa", "ifa", "ifa", "ish", "ish", "ish", "ibs", "iti", "iti", "iti", "ilf", "ilf",
		"iib", "iib", "iib", "iib", "iib", "ifg", "ics", "iwb", "iwb", "iqf", "iqf"]
	var failed := []
	for id in plan:
		if not st.learn_path(id):
			failed.append(id)
	print("Miyu ice: learnt all but Advanced Ice, failed ", failed, ", points left ", st.talent_points)
	ch.record("miyu_advanced_ice")
	print("Miyu ice: someone helped her (miyu_advanced_ice): Blizzard learnable ", st.path_to("ibz") != null)
	failed = []
	for id in ["ibz", "ibz", "ibz", "ibz", "ibz", "iso", "iso", "iri", "ils", "ils", "iws", "iws", "igs", "ipl"]:
		if not st.learn_path(id):
			failed.append(id)
	print("Miyu ice: Advanced Ice learnt, failed ", failed, ", points left ", st.talent_points)
	var shown := []
	for t in st.character.talents:
		if int(t.group) >= 0:
			shown.append("%s %d/%d" % [t.id, st.rank(t.id), st.max_rank(t.id)])
	print("Miyu ice: ranks ", ", ".join(shown))
	print("Miyu ice: known ", st.known_spells())
	var tot := st.total()
	var keys := ["shardDamage", "twinShard", "frostbiteDamage", "castSpeed", "maxMana", "manaRegen", "poolHeal", "poolSeconds", "poolSize",
		"poolChill", "armorStrength", "armorSeconds", "armorBurst", "armorFrost", "blastDamage", "blastArea", "blastCooldown",
		"blastFrozenGround", "coldSnap", "stormDamage", "stormShards", "stormSeconds", "stormArea", "rime", "magic"]
	var line := []
	for k in keys:
		line.append("%s %s" % [k, CharacterStats.fmt(float(tot.get(k, 0.0)))])
	print("Miyu ice: stats ", ", ".join(line))
	for sp in ["IceShard", "HealingCircle", "FrostArmor", "IceBlast", "Blizzard"]:
		var s := SpellEffects.tuned(Companions.spell(sp), st)
		print("Miyu ice: %s tuned: damage %s, area %s, heal %s, time %s, shield %s, shards %s, extra %s, chill %s, frozen ground %s, frostbite x%s, cold snap %s%%, no frostbite %s, cooldown %ss, cast %ss, mana %s" % [sp,
			CharacterStats.fmt(SpellEffects.damage(s, st)), CharacterStats.fmt(float(s.aoeRadius)), CharacterStats.fmt(SpellEffects.by_magic(float(s.get("heal", 0.0)), st)),
			CharacterStats.fmt(float(s.get("healTime", s.get("shieldTime", s.get("stormTime", 0.0))))), CharacterStats.fmt(float(s.get("shield", 0.0))), s.get("shards", 0), s.get("extra", 0),
			CharacterStats.fmt(float(s.get("chill", 0.0))), CharacterStats.fmt(float(s.get("frozenGround", 0.0))), snappedf(float(s.get("statusBite", 1.0)), 0.01),
			CharacterStats.fmt(float(s.get("coldSnap", 0.0))), s.get("noStatus", false), snappedf(SpellEffects.cooldown(Companions.spell(sp), st), 0.01), s.castTime, s.manaCost])
	tw.web.scroll_to(0.55)
	await _frames(10)
	shot("tree_learnt")
	cp.visible = false
	await _frames(5)
	# Out by the village, a fight.
	var here := miko.position + Vector2(-6.0, 8.0) * world.px
	miko.place(here)
	miyu.position = here + Vector2(-1.2, 0.4) * world.px
	miyu.reset_physics_interpolation()
	await _frames(20)
	# (her own casting held back while each spell's tried by hand)
	var own: CompanionMagic = miyu.get_node_or_null("Magic")
	if own != null:
		own.set_physics_process(false)
	st.mana = 999.0
	miko.stats.set_guard("test", 90.0)   # (Sera kept on her feet through the tests)
	# Ice Shard, two of them.
	var sl := Slime.spawn(world, md.slime, false, here + Vector2(3.2, 0.0) * world.px, 1.0)
	await _frames(5)
	_tough(sl, 500.0)
	var hp0 := sl.hit.hp
	_cast("IceShard", miyu, st, sl.position)
	var seen := {}
	var most := 0
	for i in 40:
		await get_tree().process_frame
		var n := 0
		for c in world.get_children():
			if c is SpellEffects.Projectile:
				seen[c.get_instance_id()] = true
				n += 1
		most = maxi(most, n)
		if i == 12:
			shot("shard")
	await _secs(0.5)
	print("Miyu ice: Ice Shard: shards thrown ", seen.size(), ", at most ", most, " in the air at once; slime HP ", snappedf(hp0, 0.1), " -> ", str(snappedf(sl.hit.hp, 0.1)) if is_instance_valid(sl) and sl.hit != null else "gone", ", frostbitten ", is_instance_valid(sl) and StatusEffects.has_effect(sl.hit, "Frostbite"))
	if is_instance_valid(sl):
		sl.queue_free()
	# Frost Armor on both (Miyu held still at Sera's side meanwhile), a slime beside each: nothing happens to them while
	# the shells hold; Sera's broken, it bursts on the one beside her only.
	miyu.set_physics_process(false)
	miyu.position = miko.position + Vector2(-0.9, -0.3) * world.px
	miyu.reset_physics_interpolation()
	var by_sera := Slime.spawn(world, md.slime, false, miko.position + Vector2(0.9, 0.3) * world.px, 1.0)
	var by_miyu := Slime.spawn(world, md.slime, false, miyu.position + Vector2(-2.6, -0.6) * world.px, 1.0)
	await _frames(3)
	_tough(by_sera, 400.0)
	_tough(by_miyu, 400.0)
	_cast("FrostArmor", miyu, st, miyu.position)
	await _frames(10)
	print("Miyu ice: Frost Armor: Sera's shield ", snappedf(miko.stats.shield(), 0.1), " (on ", SpellEffects.FrostArmor.on(miko), "), Miyu's ", snappedf(st.shield(), 0.1), " body ", snappedf(miyu.hit.shields.values().reduce(func(a, b): return a + b, 0.0), 0.1), " (on ", SpellEffects.FrostArmor.on(miyu), ")")
	shot("armor")
	await _secs(2.0)
	print("Miyu ice: Frost Armor held 2s: slime by Sera HP ", by_sera.hit.hp, " frostbitten ", StatusEffects.has_effect(by_sera.hit, "Frostbite"), ", slowed x", StatusEffects.speed_of(by_sera.hit),
		"; slime by Miyu HP ", by_miyu.hit.hp, " frostbitten ", StatusEffects.has_effect(by_miyu.hit, "Frostbite"), ", bursts ", SpellEffects.FrostArmor.bursts)
	print("Miyu ice: slimes from Sera: by her ", snappedf(by_sera.hit.ground_distance(miko.position), 1), "px, by Miyu ", snappedf(by_miyu.hit.ground_distance(miko.position), 1), "px (the burst reaches ", Companions.spell("FrostArmor").aoeRadius, ")")
	var hp_before := miko.stats.hp
	miko.stats.set_guard("test", 0.0)
	miko.stats.damage(miko.stats.shield() * 1.6 + 20.0)
	await _frames(10)
	print("Miyu ice: Sera struck through her armour: bursts ", SpellEffects.FrostArmor.bursts, ", Sera HP ", snappedf(hp_before, 0.1), " -> ", snappedf(miko.stats.hp, 0.1), ", her armour on ", SpellEffects.FrostArmor.on(miko),
		"; slime by Sera HP ", snappedf(by_sera.hit.hp, 0.1), " frostbitten ", StatusEffects.has_effect(by_sera.hit, "Frostbite"), "; slime by Miyu HP ", snappedf(by_miyu.hit.hp, 0.1),
		" frostbitten ", StatusEffects.has_effect(by_miyu.hit, "Frostbite"), ", Miyu's armour on ", SpellEffects.FrostArmor.on(miyu))
	shot("burst")
	miko.stats.set_hp(miko.stats.stat("maxHp"))   # (whole again: the test's blow was a big one)
	by_sera.queue_free()
	by_miyu.queue_free()
	# Healing Blanket on Sera (hurt): only she mends; Miyu (hurt too) and a slime beside Sera untouched. (Shared Warmth
	# held back for this.)
	miko.place(miko.position + Vector2(-2.7, 1.0) * world.px)   # (out from under the willow, on open grass)
	miyu.position = miko.position + Vector2(-0.9, -0.3) * world.px
	miyu.reset_physics_interpolation()
	await _frames(10)
	miko.stats.set_hp(miko.stats.stat("maxHp") * 0.4)
	miyu.hit.hp = miyu.hit.max_hp * 0.5
	var near := Slime.spawn(world, md.slime, false, miko.position + Vector2(0.9, 0.3) * world.px, 1.0)
	await _frames(3)
	_tough(near, 400.0)
	st.set_buff("test_share", {"blanketShare": -st.stat("blanketShare")})
	var sera0 := miko.stats.hp
	var miyu0 := miyu.hit.hp
	clock.set_hour(12.0)
	_cast("HealingCircle", miyu, st, miko.position + Vector2(0.3, -0.2) * world.px)
	await _secs(0.8)
	var bl := SpellEffects.WaterBlanket.of(miko)
	print("Miyu ice: Healing Blanket on Sera ", bl != null, ", on Miyu ", SpellEffects.WaterBlanket.on(miyu), ", lasts ", snappedf(bl.time, 0.1) if bl != null else 0.0,
		"s, per mend (0.5s) ", snappedf(bl.per_tick, 0.01) if bl != null else 0.0, ", Cold Comfort bite ", snappedf(bl.frost, 0.01) if bl != null else 0.0)
	shot("blanket_sera_day")
	await _secs(2.6)
	print("Miyu ice: after 3.4s: Sera HP ", snappedf(sera0, 0.1), " -> ", snappedf(miko.stats.hp, 0.1), ", Miyu HP ", snappedf(miyu0, 0.1), " -> ", snappedf(miyu.hit.hp, 0.1),
		"; slime beside Sera HP ", near.hit.hp, " frostbitten ", StatusEffects.has_effect(near.hit, "Frostbite"), " speed x", StatusEffects.speed_of(near.hit))
	clock.set_hour(23.0)
	await _secs(1.2)
	shot("blanket_sera_night")
	# Cold Comfort: Sera, wrapped, strikes the slime.
	SpellEffects.WaterBlanket.struck(miko, near.hit)
	await _frames(2)
	print("Miyu ice: Cold Comfort: Sera strikes the slime: frostbitten ", StatusEffects.has_effect(near.hit, "Frostbite"))
	near.queue_free()
	# On Miyu herself (aimed at her), by night then day; and recast on Sera starts hers afresh.
	var m0 := miyu.hit.hp
	_cast("HealingCircle", miyu, st, miyu.position)
	await _secs(1.0)
	shot("blanket_miyu_night")
	clock.set_hour(12.0)
	await _secs(1.0)
	shot("blanket_miyu_day")
	print("Miyu ice: Healing Blanket on Miyu ", SpellEffects.WaterBlanket.on(miyu), ", her HP ", snappedf(m0, 0.1), " -> ", snappedf(miyu.hit.hp, 0.1), ", Sera's still on ", SpellEffects.WaterBlanket.on(miko))
	var age0 := SpellEffects.WaterBlanket.of(miko).age if SpellEffects.WaterBlanket.on(miko) else -1.0
	_cast("HealingCircle", miyu, st, miko.position)
	await _frames(2)
	print("Miyu ice: recast on Sera: her blanket's age ", snappedf(age0, 0.1), " -> ", snappedf(SpellEffects.WaterBlanket.of(miko).age, 0.1) if SpellEffects.WaterBlanket.on(miko) else -1.0)
	# Shared Warmth: Sera wrapped, the most hurt near her (Miyu) wrapped too, more weakly.
	st.set_buff("test_share", null)
	await _secs(15.5)   # (both blankets gone first)
	miyu.hit.hp = miyu.hit.max_hp * 0.4
	_cast("HealingCircle", miyu, st, miko.position)
	await _frames(3)
	var bs := SpellEffects.WaterBlanket.of(miko)
	var bm := SpellEffects.WaterBlanket.of(miyu)
	print("Miyu ice: Shared Warmth (", st.stat("blanketShare"), "%): Sera's per mend ", snappedf(bs.per_tick, 0.01) if bs != null else -1.0, ", Miyu's ", snappedf(bm.per_tick, 0.01) if bm != null else -1.0)
	var wolf := MutatedWolf.spawn(world, md.mutatedWolf, miyu.position + Vector2(1.5, 0.3) * world.px)
	await _frames(5)
	_tough(wolf, 3000.0)
	miko.stats.set_guard("test", 90.0)
	miyu.set_physics_process(true)
	# Ice Blast on a pack, frozen ground left, and (Cold Snap made sure of) a freeze.
	var pack := []
	for k in 3:
		pack.append(Slime.spawn(world, md.slime, false, here + Vector2(2.6 + k * 0.6, -1.0 + k * 0.7) * world.px, 1.0))
		await _frames(2)
		_tough(pack[k], 300.0)
	if is_instance_valid(wolf):
		wolf.position = here + Vector2(3.2, 0.4) * world.px
	await _frames(5)
	var at := here + Vector2(3.2, 0.0) * world.px
	var hps := pack.map(func(s): return snappedf(s.hit.hp, 0.1))
	st.set_buff("test", {"coldSnap": 100.0})
	var blasts0 := SpellEffects.IceBlastArea.blasts
	var freezes0 := StatusEffects.freezes
	_cast("IceBlast", miyu, st, at)
	# (the spell's area drawn over it, to see the animation's ring matches)
	var area := float(SpellEffects.tuned(Companions.spell("IceBlast"), st).aoeRadius)
	var guide := Node2D.new()
	guide.z_as_relative = false
	guide.z_index = 4090
	guide.position = at
	guide.draw.connect(func():
		guide.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		guide.draw_arc(Vector2.ZERO, area, 0.0, TAU, 96, Color(1, 0.3, 0.3, 0.9), 4.0, true))
	world.add_child(guide)
	await _secs(0.35)
	shot("blast_ring")
	await _secs(0.15)
	print("Miyu ice: Ice Blast at 0.5s: landed ", SpellEffects.IceBlastArea.blasts - blasts0, ", slimes ", pack.map(func(s): return str(snappedf(s.hit.hp, 0.1)) if is_instance_valid(s) else "gone"))
	await _secs(0.4)
	st.set_buff("test", null)
	print("Miyu ice: Ice Blast at 0.9s: landed ", SpellEffects.IceBlastArea.blasts - blasts0, ", slimes ", hps, " -> ", pack.map(func(s): return str(snappedf(s.hit.hp, 0.1)) if is_instance_valid(s) and s.hit != null else "gone"),
		", frozen ground ", _count(SpellEffects.FrozenGround), ", frozen solid ", StatusEffects.freezes - freezes0, ", wolf frozen ", is_instance_valid(wolf) and StatusEffects.frozen(wolf.hit))
	shot("blast")
	if is_instance_valid(wolf):
		var p0 := wolf.position
		await _secs(0.5)
		print("Miyu ice: wolf held: moved ", snappedf(wolf.position.distance_to(p0), 0.1), "px in 0.5s while frozen ", StatusEffects.frozen(wolf.hit))
		shot("frozen")
	guide.queue_free()
	if is_instance_valid(wolf):
		# Freezes again and again: shorter each time, then shaken off.
		var lasts := []
		for i in 4:
			await _secs(1.3)
			var t0 := Time.get_ticks_msec() / 1000.0
			var ok := StatusEffects.freeze(wolf.hit)
			var s: StatusEffects = wolf.hit.get_node("Status")
			lasts.append(str(snappedf(float(s.effects.get(&"Frozen", {}).get("until", t0)) - t0, 0.01)) if ok else "shaken off")
		print("Miyu ice: Cold Snap again and again: ", lasts)
	# Blizzard over the pack.
	var more := []
	for k in 4:
		more.append(Slime.spawn(world, md.slime, false, here + Vector2(2.2 + k * 0.7, 1.5 - k * 0.5) * world.px, 1.0))
		await _frames(2)
		_tough(more[k], 300.0)
	await _frames(5)
	var landed0 := SpellEffects.Blizzard.landed
	var bhits0 := SpellEffects.Blizzard.hits
	_cast("Blizzard", miyu, st, here + Vector2(3.2, 0.6) * world.px)
	await _secs(1.6)
	shot("blizzard")
	await _secs(4.0)
	print("Miyu ice: Blizzard: shards landed ", SpellEffects.Blizzard.landed - landed0, ", monsters hit ", SpellEffects.Blizzard.hits - bhits0, ", slimes now ", (more + pack).map(func(s): return str(snappedf(s.hit.hp, 0.1)) if is_instance_valid(s) and s.hit != null else "gone"))
	for s in more + pack:
		if is_instance_valid(s):
			s.queue_free()
	if is_instance_valid(wolf):
		wolf.queue_free()
	# Frozen ground alone, beside Sera on the grass: by day, then by night.
	var hour0 := clock.hour()
	clock.set_hour(12.0)
	var sheet := SpellEffects.FrozenGround.make(world, {"frozenGround": 30.0}, miko.position + Vector2(2.2, 0.6) * world.px, 288.0, 20.0, true)
	await _secs(1.2)
	shot("ice_day")
	clock.set_hour(23.0)
	await _secs(1.5)
	shot("ice_night")
	sheet.age = sheet.life - 0.4   # (melting back)
	await _secs(0.2)
	shot("ice_melt")
	clock.set_hour(hour0)
	await _frames(10)
	miko.stats.set_guard("test", 0.0)
	# On her own: a pack comes, she casts as she sees fit.
	await _frames(10)
	st.mana = st.stat("maxMana")
	miko.stats.set_hp(miko.stats.stat("maxHp") * 0.7)
	var magic := CompanionMagic.give(miyu)
	magic.set_physics_process(true)
	magic.cast.connect(func(sp, wh): print("Miyu ice: she casts ", sp, " at ", (wh / world.px).round(), ", mana ", snappedf(st.mana, 0.1)))
	var foes := []
	for k in 4:
		foes.append(Slime.spawn(world, md.slime, false, miko.position + Vector2(4.0 + k * 0.6, 1.0 - k * 0.6) * world.px, 1.0))
	foes.append(MutatedWolf.spawn(world, md.mutatedWolf, miko.position + Vector2(-3.0, 1.0) * world.px))
	for second in 16:
		await _secs(1.0)
		if second == 3:
			shot("own")
		if second == 6:
			miko.stats.damage(4.0)   # (Sera struck: armour's called for)
	print("Miyu ice: on her own she cast ", magic.casts.map(func(c): return c[0]))
	for f in foes:
		if is_instance_valid(f):
			f.queue_free()
	# Saved and loaded: her tree and ranks with her.
	var json := st.to_json()
	var back := CharacterStats.new()
	back.setup(Companions._character({"maxHp": 40.0, "atk": 6.0}, "miyu"), Companions.combat().items)
	back.from_json(json)
	print("Miyu ice: saved and loaded: tree ", back.tree_id(), ", points ", back.talent_points, " (were ", st.talent_points, "), Ice Blast rank ", back.rank("iib"), ", gifted ", back.gifted, ", known ", back.known_spells())
	back.free()
	_old_save(8)
	_old_save(16)


# A save from before: the book taught her all four spells at once, and her points went on Sera's tree.
func _old_save(lv: int) -> void:
	var old := {"level": lv, "xp": 0, "talentPoints": 2, "hp": 40, "mana": 20, "tree": 3, "talentIds": ["s2", "a1", "b0", "h1"], "talentRanks": [2, 1, 2, 1],
		"equipped": [], "wear": {}, "learned": {"IceSpikes": "Water Spell Book", "IceBlast": "Water Spell Book", "WaterHeal": "Water Spell Book", "IceBarrier": "Water Spell Book"}}
	var st := CharacterStats.new()
	st.setup(Companions._character({"maxHp": 40.0, "atk": 6.0}, "miyu"), Companions.combat().items)
	st.from_json(JSON.stringify(old))
	print("Miyu ice: old save Lv%d: ranks %s, gifted %s, points %d (of %d for the level), learned %s, known %s" % [lv, str(st.ranks), str(st.gifted), st.talent_points, (lv - 1) * st.points_per_level(), str(st.learned), str(st.known_spells())])
	var again := CharacterStats.new()
	again.setup(Companions._character({"maxHp": 40.0, "atk": 6.0}, "miyu"), Companions.combat().items)
	again.from_json(st.to_json())
	print("Miyu ice: old save Lv%d loaded again: points %d, ranks %s (the same: done once)" % [lv, again.talent_points, str(again.ranks)])
	st.free()
	again.free()


# Miyu casts [param id] at [param target] (her mana spent as in a fight).
func _cast(id: String, who: Villager, st: CharacterStats, target: Vector2) -> void:
	var s := Companions.spell(id)
	st.spend_mana(float(s.get("manaCost", 0.0)))
	var origin := target
	var ground := target
	if str(s.delivery) == "Directional":
		ground = who.position
		origin = who.position + Vector2(0, -0.45 * world.px)
	SpellEffects.begin(world, s, st, origin, ground, target, who)
	print("Miyu ice: cast ", id)


# Makes [param c] last long enough for the numbers to read.
func _tough(c: Creature, hp: float) -> void:
	c.hit.max_hp = hp
	c.hit.hp = hp


func _count(kind) -> int:
	var n := 0
	for c in world.get_children():
		if is_instance_of(c, kind):
			n += 1
	for c in world.things.get_children() + world.ground.get_children():
		if is_instance_of(c, kind):
			n += 1
	return n
