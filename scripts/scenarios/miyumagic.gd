extends Scenario
## Miyu's water magic: Sera gives her the Water Spell Book in a talk, she learns its spells at once; Sera dresses her
## from the bag (her own page in the Character & Bag window) and spends her talent points; then monsters come and she
## casts on her own beside Sera. Run with --window=miyumagic.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var ch := Chronicle.active
	# (the bundled save has no Miyu: someone stands in for her)
	var miyu: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			miyu = v
	if miyu == null:
		miyu = Villager.all[1]
		miyu.person["unique"] = "miyu"
		miyu.person["name"] = "Miyu"
		var trait_list: Array = miyu.person.get("traits", []).duplicate()
		trait_list.append("unique")
		miyu.person["traits"] = trait_list
	ch.events = ch.events.filter(func(e): return not str(e.what) in ["book_given:miyu", "miyu_water", "scene:miyu_water_book"])
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	miyu.person["level"] = 4   # (a few levels: talent points to spend)
	if not miko.bag.items.has("WaterTome"):
		miko.bag.items[miko.bag.free_slot()] = "WaterTome"
		miko.bag.changed.emit()
	for i in 40:
		await get_tree().process_frame
	var st := Companions.stats_for(miyu.person)
	_stats("before the book", miyu, st)
	# The talk: the book offered, and given.
	miko.place(miyu.position + Vector2(1.0, 0.6) * world.px)
	for i in 10:
		await get_tree().process_frame
	Talk.active.open(miyu)
	for i in 10:
		await get_tree().process_frame
	var offers := []
	for b in Talk.active._choices.get_children():
		offers.append((b as Button).text)
	print("Miyu magic: talk offers ", offers)
	var book := Companions.book_for(miyu.person, miko.bag)
	print("Miyu magic: book offered '", book.get("offer", ""), "'")
	Talk.active._give_book(book)
	for i in 20:
		await get_tree().process_frame
	Talk.active._finish_typing()
	for i in 5:
		await get_tree().process_frame
	shot("book")
	print("Miyu magic: book_given:miyu ", ch.happened("book_given:miyu"), ", miyu_water ", ch.happened("miyu_water"), ", rumor miyu_book done step event, tome still in bag ", miko.bag.items.has("WaterTome"))
	print("Miyu magic: learned ", st.learned, ", known ", st.known_spells(), ", offer again '", Companions.book_for(miyu.person, miko.bag).get("offer", ""), "'")
	var scene := Scenes.for_speaker(miyu.person)
	if not scene.is_empty():
		Talk.active._play(scene, (scene.get("lines", []) as Array).size())
	Talk.active.close()
	print("Miyu magic: her scene played ", ch.happened("scene:miyu_water_book"))
	_stats("with the book", miyu, st)
	# Gear: from Sera's bag onto her, on her page.
	var cp: CharacterPanel = g.get_node("Hud/CharacterPanel")
	for it in ["LinenRobe", "OakWand", "JadeRing", "CopperRing", "ShrineCharm"]:
		if not miko.bag.items.has(it) and miko.bag.free_slot() >= 0:
			miko.bag.items[miko.bag.free_slot()] = it
	miko.bag.changed.emit()
	cp.open_for(miyu.person)
	for i in 5:
		await get_tree().process_frame
	for it in ["LinenRobe", "OakWand", "JadeRing", "CopperRing"]:
		cp.clicked(miko.bag.items.find(it), true)
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	print("Miyu magic: she wears ", st.worn, ", Sera wears ", miko.stats.worn, ", Sera's bag.worn ", miko.bag.worn)
	_stats("dressed", miyu, st)
	cp.selected = -1
	cp.pick_slot("Necklace")
	cp.clicked(miko.bag.items.find("ShrineCharm"), false)
	for i in 10:
		await get_tree().process_frame
	shot("gear")
	# One back off, into Sera's bag, and on again.
	cp.pick_slot("Ring2")
	cp._do_action()
	print("Miyu magic: Ring2 taken off: in Sera's bag ", miko.bag.items.has("CopperRing"), ", she wears ", st.worn)
	for i in 3:
		await get_tree().process_frame
	cp.clicked(miko.bag.items.find("CopperRing"), true)
	print("Miyu magic: on again ", st.worn_in("Ring1"), " / ", st.worn_in("Ring2"))
	# Her talents: a path to the nearest that gives magic.
	var best := ""
	var best_cost := 99
	for t in st.character.talents:
		if float(t.perRank.get("magic", 0.0)) > 0.0 and not st.unlocked(t.id):
			var path: Variant = st.path_to(t.id)
			if path != null and (path as Array).size() < best_cost:
				best_cost = (path as Array).size()
				best = t.id
	print("Miyu magic: talent points ", st.talent_points, ", learning ", best, " (", best_cost, " on the path)")
	cp.open_for(miyu.person, true)
	cp.talents.select(best)
	cp.talents._learn_selected()
	for i in 15:
		await get_tree().process_frame
	shot("talents")
	print("Miyu magic: after learning: points ", st.talent_points, ", ", st.talent(best).get("name", ""), " rank ", st.rank(best), ", talents window shows '", cp.talents.owner_name(), "'")
	_stats("with a talent", miyu, st)
	cp.talents.visible = false
	cp.show_for({})
	print("Miyu magic: Sera's page again: panel stats are Sera's ", cp.stats == miko.stats, ", talents' ", cp.talents.stats == miko.stats)
	var pw: PartyWindow = g.get_node("Hud/PartyWindow")
	pw.open()
	for i in 15:
		await get_tree().process_frame
	shot("party")
	pw.close()
	# A fight: slimes and a wolf come at Sera, Miyu beside her.
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var magic := CompanionMagic.give(miyu)
	magic.cast.connect(func(sp, at): print("Miyu magic: cast ", sp, " at ", (at / world.px).round(), ", her mana ", snappedf(st.mana, 0.1)))
	var foes: Array = []
	for k in 3:
		foes.append(Slime.spawn(world, md.slime, false, miko.position + Vector2(4.0 + k * 0.8, 1.0 - k) * world.px, 1.0))
	miyu.hit.hp = miyu.hit.max_hp * 0.5   # (hurt already: a heal's called for)
	for second in 14:
		for i in 60:
			await get_tree().physics_frame
		var hps := []
		for f in foes:
			hps.append(snappedf((f as Creature).hit.hp, 0.1) if is_instance_valid(f) and (f as Creature).hit != null and is_instance_valid((f as Creature).hit) else "gone")
		print("Miyu magic: ", second + 1, "s: monsters HP ", hps, ", Miyu HP ", snappedf(miyu.hit.hp, 0.1), "/", miyu.hit.max_hp, " mana ", snappedf(st.mana, 0.1), ", Sera HP ", snappedf(miko.stats.hp, 0.1), ", casting ", Villager.now() < miyu.cast_until)
		if second == 1 or second == 5 or second == 9:
			shot("fight%d" % second)
		if second == 5:
			foes.append(MutatedWolf.spawn(world, md.mutatedWolf, miyu.position + Vector2(-2.5, 1.0) * world.px))
		if second == 7:
			miyu.hit.hurt(6.0)   # (struck: a barrier's called for)
	print("Miyu magic: casts ", magic.casts.map(func(c): return c[0]))
	# Saved and loaded again: her stats with her.
	var saved: String = people.to_json()
	var again: Dictionary = (JSON.parse_string(saved).people as Array).filter(func(p): return str(p.get("unique", "")) == "miyu")[0]
	print("Miyu magic: saved companion ", (again.get("companion", {}) as Dictionary).keys(), ", maxHp ", again.maxHp, ", atk ", again.atk, ", maxMana ", again.get("maxMana", "-"))
	var back := CharacterStats.new()
	back.setup(Companions._character(again.companion.natural), Companions.combat().items)
	back.from_json(again.companion.stats)
	print("Miyu magic: loaded back: level ", back.level, ", points ", back.talent_points, ", worn ", back.worn, ", learned ", back.learned.keys(), ", magic ", back.stat("magic"))
	back.free()


func _stats(when: String, v: Villager, st: CharacterStats) -> void:
	var t := st.total()
	print("Miyu magic: %s: Lv %d, points %d, HP %s/%s (body %s/%s), attack %s (person atk %s), defense %s, magic %s, mana %s/%s, spells %s" % [when, st.level, st.talent_points,
		CharacterStats.fmt(st.hp), CharacterStats.fmt(float(t.get("maxHp", 0))), CharacterStats.fmt(v.hit.hp), CharacterStats.fmt(v.hit.max_hp),
		CharacterStats.fmt(float(t.get("attack", 0))), CharacterStats.fmt(float(v.person.atk)), CharacterStats.fmt(float(t.get("defense", 0))),
		CharacterStats.fmt(float(t.get("magic", 0))), CharacterStats.fmt(st.mana), CharacterStats.fmt(float(t.get("maxMana", 0))), st.known_spells()])
