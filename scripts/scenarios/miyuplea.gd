extends Scenario
## The elder's plea for Miyu (the find_miyu rumor): Sera's word is the one reply, she says it aloud, and the talk
## closes. Then a look at the west village's barricades (turned to face out). Run with --window=miyuplea.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var elder: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "elder":
			elder = v
	if elder == null:
		elder = Villager.all[0]
	Rumors.active.heard.erase("find_miyu")
	Rumors.active.offers["find_miyu"] = elder.person.name
	miko.place(elder.position + Vector2(0.7, 0.2) * world.px)
	for i in 5:
		await get_tree().process_frame
	var talk: Talk = g.get_node("Hud/Talk")
	talk.open(elder)
	await get_tree().process_frame
	talk._ask_rumor()
	talk._finish_typing()
	await get_tree().process_frame
	var labels := talk._choices.get_children().filter(func(c): return not c.is_queued_for_deletion()).map(func(c): return (c as Button).text.strip_edges())
	print("Miyu plea: replies ", labels)
	shot("plea")
	talk._act_or_finish(talk._acts[0])
	for i in 10:
		await get_tree().process_frame
	var nd: Needs = miko.get_node("Needs")
	print("Miyu plea: talk still open ", talk.visible, "; Sera says '", nd._bubble_label.text if nd._bubble_label != null and nd._bubble_label.visible else "", "'")
	shot("said")
	# The west village's barricades.
	var bars := world.walls.walls.keys().filter(func(k): return str(world.walls.walls[k]) == "Barricade")
	print("Miyu plea: barricades ", bars.size(), ", turned ", bars.filter(func(k): return world.walls.turned_round.has(k)).size())
	if not bars.is_empty():
		miko.place(world.walls.wall_middle(bars[0]) + Vector2(0, 2.0) * world.px)
		camera.position = miko.position
		camera.reset_smoothing()
	for i in 30:
		await get_tree().process_frame
	shot("barricades")
