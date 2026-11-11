extends Scenario
## Water: a well in the village; Sera drinks there and fills a bucket; waters a dry crop with it (and can't without);
## a drink from a mug; thirst; a villager thirsty goes to drink, and a farmer fetches water before watering.
## Run with --window=water.


func run() -> void:
	clock.forced = GameClock.Weather.CLEAR   # (rain would water the plots)
	var v := world.village
	var c0 := world.floors.cell_at(v.centre())
	var spot := c0 + Vector2i(3, -3)
	var bm := BuildMode.active
	for r in range(2, 8):
		for dx in range(-r, r + 1):
			var cc := c0 + Vector2i(dx, -r)
			if spot == c0 + Vector2i(3, -3) and bm.why_not(bm.item_for("Prop", "Well"), world.floors.cell_centre(cc)) == "" and not bm.no_build(cc):
				spot = cc
	world.props.place(spot, "Well", 1.0, 0)
	await get_tree().process_frame
	var wells: Wells = g.get_node("Wells")
	var well_at := world.floors.cell_centre(spot)
	print("Water: wells ", wells.all().size(), ", in the village ", wells.village().size())
	var nd: Needs = miko.get_node("Needs")
	nd.thirst = 20.0
	miko.place(well_at + Vector2(0.9, 0.5) * world.px)
	for i in 30:
		await get_tree().process_frame
	print("Water: at the well, no bucket: '", wells.prompt.text, "'; thirsty ", nd.thirsty(), ", effects ", nd.effects().map(func(e): return e[0]))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_well.png")
	miko.bag.items[miko.bag.free_slot()] = "Bucket"
	miko.bag.items[miko.bag.free_slot()] = "Mug"
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	for i in 4:
		await get_tree().process_frame
	print("Water: E: thirst ", nd.thirst, ", water carried ", miko.bag.count("Water"))
	nd.thirst = 50.0
	print("Water: G (a mug, water carried): drinks ", nd.drink(), ", thirst ", nd.thirst, ", water left ", miko.bag.count("Water"))
	# A dry plot: watered with it, then not without.
	var farm: Farming = miko.get_node("Farming")
	var plot: Dictionary = {}
	for p in farm.plots:
		if farm.stage(p) == 1:
			plot = p
	if not plot.is_empty():
		for p in farm.plots:
			if farm.stage(p) == 1:
				farm._state(p).wateredAt = -INF
				farm._state(p).pest = false
		miko.place(plot.pos)
		for i in 10:
			await get_tree().process_frame
		var before := miko.bag.count("Water")
		Input.parse_input_event(key)
		for i in 4:
			await get_tree().process_frame
		print("Water: a dry plot, E: dry plots after ", farm.plots.filter(func(p): return farm.dry(p)).size(), ", water ", before, " -> ", miko.bag.count("Water"))
		for p in farm.plots:
			if farm.stage(p) == 1:
				farm._state(p).wateredAt = -INF
		miko.bag.counts["Water"] = 0
		for i in 10:
			await get_tree().process_frame
		print("Water: no water: '", farm.prompt.text if farm.get("prompt") != null else "?", "'")
	# A thirsty villager, and a farmer with dry plots and an empty bucket.
	clock.hours = float(clock.day()) * 24.0 + 9.0
	var a: Villager = Villager.all[0]
	var b: Villager = Villager.all[1]
	a.person["thirst"] = 10.0
	a.person.hunger = 90.0
	a._stand(Villager.now(), 0.0)
	Villager.only(b.person, [Villager.Job.FARMING])
	b.person.hunger = 90.0
	b.person["thirst"] = 90.0
	b._bucket = 0
	for p in farm.plots:
		if farm.stage(p) == 1:
			farm._state(p).wateredAt = -INF
			farm._state(p).pest = false
	b._stand(Villager.now(), 0.0)
	var seen_a := []
	var seen_b := []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
		for pair in [[a, seen_a], [b, seen_b]]:
			var what: String = Villager.State.keys()[pair[0].state]
			if pair[1].is_empty() or pair[1][-1] != what:
				pair[1].append(what)
		if float(a.person.thirst) > 90.0 and seen_b.has("FARM"):
			break
	print("Water: thirsty ", a.person.name, " went ", seen_a, ", thirst now ", a.person.thirst)
	print("Water: farmer ", b.person.name, " went ", seen_b, " (", b.farm_task, "), bucket ", b._bucket, "; dry plots now ", farm.plots.filter(func(p): return farm.dry(p)).size())
