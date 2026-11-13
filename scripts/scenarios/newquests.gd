extends Scenario
## After Miyu's home: the elder shows a "?" while his handing-over scene waits; once the village is Sera's, he has
## "Room for more" (grow the village) and someone tells of the river to the west (go to its bank, catch a fish). Both
## heard and done here. Run with --window=newquests.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var ch := Chronicle.active
	var r := Rumors.active
	var elder: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "elder":
			elder = v
	if elder == null:
		# (the bundled save has no elder yet: someone stands in for him)
		elder = Villager.all[0]
		elder.person["unique"] = "elder"
		elder.person["name"] = "Genzo"
	print("New quests: the elder's ", elder.person.name)
	# Miyu home, the elder's scene not yet played.
	ch.events = ch.events.filter(func(e): return not str(e.what) in ["village_given", "scene:elders_thanks", "village_grown", "fish_caught"])
	if not ch.happened("miyu_home"):
		ch.record("miyu_home")
	for i in 20:
		await get_tree().process_frame
	if elder != null:
		print("New quests: his scene waiting ", elder._scene_waiting(), ", his emote '", elder._rumor_emote(), "', showing ", elder.emote != null and elder.emote.visible, " (state ", elder.state, ")")
		miko.place(elder.position + Vector2(1.5, 1.0) * world.px)
		camera.zoom = Vector2(1.6, 1.6)
		for i in 20:
			await get_tree().process_frame
		shot("elder")
		camera.zoom = Vector2.ONE
	# The village given a day and a half ago.
	ch.events.append({"h": ch.now() - 36.0, "what": "village_given", "data": {}})
	ch.events.append({"h": ch.now() - 36.0, "what": "scene:elders_thanks", "data": {}})
	for id in ["village_room", "river_fish"]:
		r.heard.erase(id)
	for i in 90:
		await get_tree().process_frame
	print("New quests: offered ", r.offers.get("village_room", "-"), " / ", r.offers.get("river_fish", "-"), ", the elder's '?' now ", elder._rumor_emote() if elder != null else "")
	for id in ["village_room", "river_fish"]:
		var who: Villager = null
		for v in Villager.all:
			if is_instance_valid(v) and v.person.name == r.offers.get(id, ""):
				who = v
		if who != null:
			r.hear(id, who)
	print("New quests: heard ", r.heard.has("village_room"), " ", r.heard.has("river_fish"))
	# Growing the village.
	for res in [["Wood", 40], ["Stone", 30], ["Gold", 400]]:
		miko.bag.add(res[0], res[1])
	print("New quests: to pay ", world.village.next_upgrade(), " have ", ["Wood", "Stone", "Gold"].map(func(x): return world.village.have(miko.bag, miko, x)))
	var wood0 := world.village.stored("Wood") + miko.bag.count("Wood")
	var rect: Rect2i = vd.growth._fit(Vector2i(40, 0))[0]
	print("New quests: grow ", rect, " '", world.village.cant_add(rect), "' -> ", world.village.grow(miko.bag, miko, rect))
	for i in 90:
		await get_tree().process_frame
	print("New quests: room for more done ", ch.happened("done:village_room"), ", wood ", wood0, " -> ", world.village.stored("Wood") + miko.bag.count("Wood"))
	# Down to the river.
	var bank := r.place_of(r.heard.river_fish, r.by_id.river_fish, 0)
	print("New quests: the river step's at ", world.floors.cell_at(bank), ", water within 6 cells ", Fishing.water_near(world, bank, 6.0))
	miko.place(world.floors.cell_centre(Vector2i(-32, -32)))
	for i in 240:
		await get_tree().process_frame
	print("New quests: at the bank, step now ", r.heard.river_fish.get("step", ""))
	camera.zoom = Vector2(0.8, 0.8)
	for i in 10:
		await get_tree().process_frame
	shot("river")
	camera.zoom = Vector2.ONE
	var fish0 := world.village.stored("Fish") + miko.bag.count("Fish")
	ch.record("fish_caught")
	for i in 90:
		await get_tree().process_frame
	print("New quests: river done ", ch.happened("done:river_fish"), ", fish ", fish0, " -> ", world.village.stored("Fish") + miko.bag.count("Fish"))
