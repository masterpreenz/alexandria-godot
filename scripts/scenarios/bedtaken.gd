extends Scenario
## Miko beside a villager's bed: free, the sleep prompt shows; with the villager in it, it doesn't.
## Run with --window=bedtaken.


func run() -> void:
	while Villager.all.is_empty():
		await get_tree().process_frame
	var nd: Needs = miko.get_node("Needs")
	var sleeper: Villager = null
	for v in Villager.all:
		if not v.home.is_empty():
			sleeper = v
			break
	if sleeper == null:
		print("Bed taken: no villager with a bed")
	else:
		var bed_at: Vector2 = sleeper.home.pos
		miko.place(bed_at + Vector2(0.5, 0.4) * world.px)
		for i in 20:
			await get_tree().process_frame
		print("Bed taken: free bed, prompt '", nd.prompt.text, "' showing ", nd.prompt.visible)
		Needs.occupants[Needs.bed_key(bed_at)] = sleeper
		for i in 20:
			await get_tree().process_frame
		var found: Dictionary = nd.nearest_bed(miko.position, float(nd.s.bedRange) * world.px)
		print("Bed taken: with ", sleeper.person.name, " in it, prompt showing ", nd.prompt.visible, ", still marked taken ", Needs.occupants.has(Needs.bed_key(bed_at)), ", bed found for her ", "none" if found.is_empty() else ("the same one" if found.pos.distance_to(bed_at) < 1.0 else "another, %.1f units from it" % (found.pos.distance_to(bed_at) / world.px)))
