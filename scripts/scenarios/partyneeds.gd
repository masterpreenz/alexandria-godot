extends Scenario
## A hungry, thirsty companion: they say so, the party window shows it, and Sera gives them food from her bag and a
## drink from her pouch. Sera drinks from her pouch (G), then fills it again at the river's edge (E).
## Run with --window=partyneeds.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	var trait_list: Array = miyu.person.get("traits", []).duplicate()
	trait_list.append("unique")
	miyu.person["traits"] = trait_list
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	miyu.person["hunger"] = 20.0
	miyu.person["thirst"] = 20.0
	var needs: Needs = miko.get_node("Needs")
	needs.pouch = 100.0
	if not miko.bag.items.has("WaterPouch"):
		miko.bag.items[miko.bag.free_slot()] = "WaterPouch"
	miko.bag.add("GrilledFish", 2)
	miyu._next_need_bark = 0.0
	for i in 20:
		await get_tree().process_frame
	print("Party needs: Miyu says '", miyu._bark.text if miyu._bark != null and "text" in miyu._bark else "?", "', bubble showing ", miyu._bark != null and miyu._bark.visible)
	var pw: PartyWindow = get_tree().current_scene.get_node("Hud/PartyWindow")
	pw.open()
	for i in 20:
		await get_tree().process_frame
	shot("window")
	var fish0 := miko.bag.count("GrilledFish")
	print("Party needs: fed ", Party.active.feed(miyu.person), ", hunger ", miyu.person.hunger, ", fish ", fish0, " -> ", miko.bag.count("GrilledFish"))
	print("Party needs: a drink ", Party.active.give_drink(miyu.person), ", thirst ", miyu.person.thirst, ", pouch ", needs.pouch)
	pw.close()
	# Sera's own drinks.
	needs.thirst = 30.0
	needs.drink()
	print("Party needs: Sera drank, thirst ", needs.thirst, ", pouch ", needs.pouch)
	needs.thirst = 30.0
	# (the last dry cell before the river, along the row west of the village)
	var edge := Vector2i(-30, -32)
	for x in range(-30, -50, -1):
		if world.water_depth(world.floors.cell_centre(Vector2i(x, -32))) > 0.0:
			break
		edge = Vector2i(x, -32)
	print("Party needs: the river's edge at ", edge)
	miko.place(world.floors.cell_centre(edge))
	for i in 40:
		await get_tree().process_frame
	var wells: Wells = Wells.active
	print("Party needs: by the river: prompt '", wells.prompt.text, "' showing ", wells.prompt.visible)
	shot("river")
	wells._pressed = true
	for i in 5:
		await get_tree().process_frame
	print("Party needs: after E, thirst ", needs.thirst, ", pouch ", needs.pouch)
