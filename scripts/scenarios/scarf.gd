extends Scenario
## Winter, snowing: a villager out in the open, cold; a scarf put in storage; they take it.
## Run with --window=scarf.


func run() -> void:
	clock.forced = -1
	clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4)) * 24.0 + 10.0
	while Villager.all.is_empty():
		await get_tree().process_frame
	var fr: Fires = miko.get_node("Fires")
	for f in fr.fires:
		fr.lit_until[f.key] = -1.0
	var vl: Villager = Villager.all[0]
	vl.position = world.village.centre() + Vector2(6.0, 5.0) * world.px
	for i in 30:
		await get_tree().process_frame
	print("Scarf: ", GameClock.WEATHER_NAMES[clock.weather()], ", ", vl.person.name, " chill ", vl.chill(), ", work pace ", snappedf(vl._tool_pace(), 0.01), ", greets '", (g.get_node("Hud/Talk") as Talk)._greeting(vl) if g.has_node("Hud/Talk") else "", "'")
	print("Scarf: recipe at the tool workbench ", world._load_json("res://data/build.json").workbenches.ToolWorkbench.recipes.filter(func(r): return r.item == "Scarf").size() if world._load_json("res://data/build.json").has("workbenches") else "?", ", item ", UiKit.item("Scarf").get("name", "?"))
	world.village.items.append("Scarf")
	for i in 400:
		await get_tree().process_frame
	print("Scarf: wearing one ", vl.person.get("scarf", false), ", chill ", vl.chill(), ", work pace ", snappedf(vl._tool_pace(), 0.01), ", scarves left in storage ", world.village.items.count("Scarf"))
