extends Scenario
## The story's opening, played through on a new game (run with --slot=new): each beat's ending done for it quickly,
## what happens as each begins checked; pictures at the start, the messenger, the village burning, the aftermath.
## Run with --window=intro --slot=new.

var st: Story
var log_beats := []


func shot(nm: String) -> void:
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + nm + ".png")


func beat_id() -> String:
	return str(st._beats()[st.beat].id) if st.beat >= 0 and st.beat < st._beats().size() else "(over)"


func wait(frames := 20) -> void:
	for i in frames:
		await get_tree().process_frame
	if log_beats.is_empty() or log_beats[-1] != beat_id():
		log_beats.append(beat_id())


func kill_near(kind: String) -> void:
	for c in Creature.all.duplicate():
		if is_instance_valid(c) and c.get_script().get_global_name() == kind and c.hit != null and c.hit.alive():
			c.hit.hurt(9999.0, true)


func run() -> void:
	st = g.get_node("Story")
	await wait(30)
	var nd: Needs = miko.get_node("Needs")
	print("Intro: beat ", beat_id(), " '", st._title.text, "'; Sera at ", world.floors.cell_at(miko.position), ", ", snappedf(clock.hour(), 0.1), "h, clock speed ", clock.speed,
		"; necklace ", miko.stats.worn_in("Necklace"), ", in her hands ", miko.stats.worn_in("LeftHand"), "; trees and rocks within 20 ", world.gatherables.filter(func(gt): return gt.position.distance_to(miko.position) < 20.0 * world.px).size(), "; mist where she is ", world.mist.tier_at(miko.position), ", at the village ", world.mist.tier_at(world.village.centre()), ", far off ", world.mist.tier_at(Vector2(-300, 100) * world.px), "; people ", people.people.map(func(p): return "%s(%s)" % [p.name, p.get("storyRole", p.get("unique", ""))]))
	shot("start")
	# Walk.
	for i in 14:
		miko.place(miko.position + Vector2(0, -0.8) * world.px)
		await get_tree().process_frame
	await wait()
	# Slimes.
	for i in 3:
		kill_near("Slime")
		await wait(10)
	# Bag, talents.
	var cp: CharacterPanel = CharacterPanel._active
	cp.toggle()
	await wait()
	cp.toggle()
	cp.toggle_talents()
	await wait()
	cp.toggle_talents()
	await wait()
	# Gather.
	miko.bag.add("Wood", 10)
	miko.bag.add("Stone", 5)
	await wait()
	var kinds := {}
	for c in Creature.all:
		if is_instance_valid(c):
			var k := str(c.get_script().get_global_name())
			kinds[k] = int(kinds.get(k, 0)) + 1
	print("Intro: after gathering, beat ", beat_id(), "; monsters about ", kinds, "; mist 40 west of the village ", world.mist.tier_at(world.village.centre() + Vector2(-40, 0) * world.px))
	kill_near("Boar")
	await wait()
	print("Intro: camp: ", snappedf(clock.hour(), 0.1), "h, clock running ", clock.speed > 0.0)
	world.props.place(world.floors.cell_at(miko.position) + Vector2i(2, 0), "Bonfire")
	world.props.place(world.floors.cell_at(miko.position) + Vector2i(0, 3), "LeafBed")
	await wait(30)
	miko.bag.add("Meal", 1)
	await wait()
	nd.lie_down()
	nd.sleep = Needs.Sleep.ASLEEP
	await wait(10)
	print("Intro: woken at ", snappedf(clock.hour(), 0.1), "h, beat ", beat_id(), "; asleep still ", nd.sleeping())
	# The messenger runs to her.
	var t0 := Time.get_ticks_msec()
	var talk: Talk = g.get_node("Hud/Talk")
	while Time.get_ticks_msec() - t0 < 15000 and not talk.visible:
		await get_tree().process_frame
	shot("messenger")
	var said := []
	while talk.visible and not talk._acts.is_empty() and said.size() < 10:
		said.append(talk._name.text + ": " + talk._line.text.left(30))
		(talk._acts[0] as Callable).call()
		await get_tree().process_frame
	talk.close()
	await wait()
	print("Intro: the messenger: ", said.size(), " lines (", said.slice(0, 2), "); beat ", beat_id(), "; mist at the village ", ["clear", "normal", "strong"][world.mist.tier_at(world.village.centre())], "; raid on ", Raids.on())
	# To the village: the pan, the attack.
	miko.place(world.village.centre() + Vector2(-14, 4) * world.px)
	await wait(40)
	shot("burning")
	print("Intro: raiders' sides (degrees round the village) ", Raids.active.raiders.filter(func(r): return is_instance_valid(r)).map(func(r): return roundi(rad_to_deg((r.position - world.village.centre()).angle()))))
	miko.place(world.village.centre() + Vector2(1, 1) * world.px)
	var alive0 := Villager.all.filter(func(v): return is_instance_valid(v) and v.hit != null and v.hit.alive()).size()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not st._doomed_left.is_empty():
		await get_tree().process_frame
	var planned0 := Construction.active.pieces.filter(func(p): return bool(p.get("wall", false))).size()
	print("Intro: before the horde's cleared, walls the monsters broke ", planned0, " (by house ", Raids.active.broken.values(), "), walls being hit ", Raids.active.wear.size())
	for r in Raids.active.raiders.duplicate():
		if is_instance_valid(r) and r.hit != null:
			r.hit.hurt(9999.0, true)
	await wait(30)
	var planned := Construction.active.pieces.filter(func(p): return bool(p.get("wall", false))).size()
	print("Intro: walls smashed and planned again ", planned, "; houses' condition ", Upkeep.active.houses().map(func(h): return roundi(h.condition)))
	shot("smashed")
	var alive := people.people.filter(func(p): return float(p.hp) > 0.0)
	print("Intro: the attack over: villagers about then ", alive0, ", alive now ", alive.map(func(p): return p.name), "; beat ", beat_id())
	# Ward it.
	world.props.place(world.floors.cell_at(world.village.centre()) + Vector2i(3, 3), "CleansingCrystal")
	await wait(40)
	print("Intro: crystal set: beat ", beat_id(), "; mist at the village ", ["clear", "normal", "strong"][world.mist.tier_at(world.village.centre())])
	# The aftermath, at the elder.
	var elder: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "elder":
			elder = v
	elder.person.erase("restUntil")
	miko.place(elder.position + Vector2(0.8, 0.3) * world.px)
	talk.open(elder)
	await get_tree().process_frame
	shot("aftermath")
	said = []
	while talk.visible and talk._acts.size() == 1 and said.size() < 12:
		said.append(talk._name.text)
		(talk._acts[0] as Callable).call()
		await get_tree().process_frame
	talk.close()
	await wait()
	print("Intro: aftermath scene, speakers ", said, "; beat ", beat_id())
	world.village.stash["Wood"] = int(world.village.stash.get("Wood", 0)) + 45
	world.village.stash["Stone"] = int(world.village.stash.get("Stone", 0)) + 15
	await wait()
	for p in Construction.active.pieces.duplicate():
		if bool(p.get("wall", false)):
			Construction.active.build(p)
	for h in Upkeep.active.houses():
		Upkeep.active.condition[h.key] = 100.0
	await wait()
	world.village.stash["Meal"] = int(world.village.stash.get("Meal", 0)) + 3
	await wait()
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "elder":
			elder = v
	talk.open(elder)
	await get_tree().process_frame
	said = []
	while talk.visible and talk._acts.size() == 1 and said.size() < 12:
		said.append(talk._line.text.left(30))
		(talk._acts[0] as Callable).call()
		await get_tree().process_frame
	talk.close()
	await wait()
	print("Intro: the elder's question: ", said.size(), " lines; beat ", beat_id(), "; J window locked ", not Chronicle.active.happened("village_given"))
	clock.hours += 14.0
	clock.hours = floorf(clock.hours / 24.0) * 24.0 + 7.0 + (24.0 if clock.hour() > 7.0 else 0.0)
	await wait(20)
	var rm: Rumors = g.get_node("Rumors")
	rm._clock = 9.0
	await wait(10)
	print("Intro: morning: beat ", beat_id(), "; intro done ", Chronicle.active.happened("intro_done"), "; rumors to tell ", rm.offers, "; newcomers allowed ", not Villagers.closed)
	print("Intro: beats seen ", log_beats)
