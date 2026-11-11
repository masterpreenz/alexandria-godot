extends Scenario
## A field of six growing plots, all with pests, by day: who goes to clear them, over a game hour or two.
## Run with --window=pestwatch.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	clock.hours = float(clock.day() - 1) * 24.0 + 9.0
	var c0 := world.floors.cell_at(world.village.centre()) + Vector2i(3, 3)
	for k in 6:
		world.props.place(c0 + Vector2i(k % 3, floori(k / 3.0)), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var field := fm.field_of(fm.nearest(world.floors.cell_centre(c0), world.px))
	for pl in field:
		fm.sow(pl, "Wheat")
		fm._state(pl).pest = true
	print("Pests: field of ", field.size(), " in the village ", world.village.contains(field[0].pos, 3.0), "; villagers ", Villager.all.map(func(v): return [v.person.name, v.person.get("job", 0)]))
	for sec in int(Shots.arg("pestsecs", "60")):
		for i in 60:
			await get_tree().process_frame
		if sec % 10 == 0:
			print("Pests ", sec, " s: left ", field.filter(func(pl): return fm.pests(pl)).size(), "; doing ", Villager.all.map(func(v): return v.activity()))
