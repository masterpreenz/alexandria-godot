extends Scenario
## Where Miyu's found: on the road north, short of the overrun village (she collapsed on her way home). The rumor heard,
## Sera comes up the road to her: the rumor's on to carrying her, she lies there, and E's offered by her.
## Run with --window=miyuroad.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var rescue: Rescue = Rescue.active
	Rumors.active.heard.erase("find_miyu")
	Rumors.active.offers["find_miyu"] = "x"
	Rumors.active.hear("find_miyu", Villager.all[0])
	var at := world.floors.cell_centre(Rescue.LIES_AT)
	print("Miyu road: she lies ", Rescue.LIES_AT, ", on the road ", Wildlands.on_road(Rescue.LIES_AT), ", ", Rescue.LIES_AT.y - Wildlands.WEST_VILLAGE.position.y, " cells from the village")
	miko.place(at + Vector2(0, 5) * world.px)
	for i in 30:
		await get_tree().process_frame
	miko.place(at + Vector2(0.6, 0.4) * world.px)
	for i in 30:
		await get_tree().process_frame
	print("Miyu road: the rumor's step ", Rumors.active.heard.find_miyu.step, ", she's ", rescue.state, ", prompt '", rescue.prompt.text, "' showing ", rescue.prompt.visible)
	camera.zoom = Vector2(0.7, 0.7)
	for i in 10:
		await get_tree().process_frame
	shot("road")
	camera.zoom = Vector2.ONE
