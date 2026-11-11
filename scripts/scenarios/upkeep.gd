extends Scenario
## Three days of weather on the houses; then one worn right down, and the villagers at it.
## Run with --window=upkeep.


func run() -> void:
	var up := Upkeep.active
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 8.0
	for i in 5:
		await get_tree().process_frame
	print("Upkeep: houses ", up.houses().map(func(h): return "%d cells %d%% cost %s" % [h.cells.size(), roundi(h.condition), Upkeep.cost(h.cells)]))
	for d in 3:
		clock.hours += 24.0
		for i in 3:
			await get_tree().process_frame
	print("Upkeep: after 3 fair days ", up.houses().map(func(h): return roundi(h.condition)))
	for h in up.houses():
		up.condition[h.key] = 100.0
	var first: Dictionary = up.houses()[0]
	up.condition[first.key] = 20.0
	clock.hours = float(clock.day() - 1) * 24.0 + 9.0
	world.village.put_in_stash("Wood", 40)
	world.village.put_in_stash("Stone", 40)
	var wood0 := world.village.stored("Wood")
	var stone0 := world.village.stored("Stone")
	miko.place((first.middle as Vector2) + Vector2(-3.0, 2.5) * world.px)
	for i in int(Shots.arg("upframes", "2400")):
		await get_tree().process_frame
		if i % 300 == 0:
			print("Upkeep ", floori(i / 60.0), ": house ", roundi(up.condition[first.key]), "%, at it ", Villager.all.filter(func(v): return v.mend == first.key).map(func(v): return v.person.name + " " + Villager.State.keys()[v.state]))
		if i == 30:
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_worn.png")
	print("Upkeep end: house ", roundi(up.condition[first.key]), "%, wood ", wood0, " -> ", world.village.stored("Wood"), ", stone ", stone0, " -> ", world.village.stored("Stone"), ", saved ", up.to_json().left(80))
