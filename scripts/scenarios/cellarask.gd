extends Scenario
## The village asks for a cellar: no cellar and the chests full of food, so a villager asks; Sera says she'll build
## one; a cellar put in the village settles it, for thanks and gold. Run with --window=cellarask.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var req := Requests.active
	var cellars := Cellars.active
	for at in cellars.all():
		world.props.remove_one_where(world.floors.cell_at(at), func(n): return n == "Cellar")
	await get_tree().process_frame
	req.asks.clear()   # (one whole-village ask at a time: the others set aside, as done)
	for id in ["pouches_all", "scarves_all"]:
		req.asks[id] = {"id": id, "state": "done", "by": "", "since": 0.0, "took": 0.0}
	for r in Spoilage.PER_DAY:
		world.village.stash[r] = 0
	print("Cellar ask: cellars ", cellars.all().size(), ", food in storage ", cellars.food_stored())
	req._hourly()
	print("Cellar ask: with little food, asked ", req.asks.has("cellar"))
	world.village.stash["Food"] = 30
	world.village.stash["Potato"] = 30
	print("Cellar ask: food in storage now ", cellars.food_stored())
	req._hourly()
	print("Cellar ask: founded ", world.village.founded(), ", wanting ", req._counts(req.by_id["cellar"]), ", asks now ", req.asks.keys().map(func(k): return [k, req.asks[k].state]))
	print("Cellar ask: asked ", req.asks.has("cellar"), " by ", req.asks.get("cellar", {}).get("by", ""), ": \"", req.said("cellar") if req.asks.has("cellar") else "", "\"")
	if not req.asks.has("cellar"):
		return
	req.accept("cellar")
	var key := "cellar"
	print("Cellar ask: journal ", req.lines(key))
	var v := req._villager(str(req.asks[key].by))
	print("Cellar ask: something to hand over ", not req.find_thing(req.by_id["cellar"]).is_empty(), ", open for the asker ", req.open_for(v))
	var gold0 := miko.bag.count("Gold")
	var spot := world.floors.cell_at(world.village.centre()) + Vector2i(4, -5)
	world.props.place(spot, "Cellar", 1.0, 0)
	await get_tree().process_frame
	req._hourly()
	print("Cellar ask: cellar built (", cellars.all().size(), "), now ", req.asks[key].state, ", gold ", gold0, " -> ", miko.bag.count("Gold"))
	print("Cellar ask: journal ", req.lines(key))
