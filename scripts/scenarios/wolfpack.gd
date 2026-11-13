extends Scenario
## Night: a pack of mutated wolves comes out to the north or east (three, more as Sera levels), one howls once as
## they near her, they run at her with their feet loud on the ground. By day: none come. Run with --window=wolfpack.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var sp: Spawners = get_tree().current_scene.find_child("Spawners", true, false)
	var b := world.village.banner_cell()
	# By day: none.
	clock.hours = float(clock.day() - 1) * 24.0 + 13.0
	sp.restock_wolves()
	print("Wolf pack: by day ", sp.wolves.size(), " wolves")
	# Night, Sera out to the north-east.
	clock.hours = float(clock.day() - 1) * 24.0 + 22.0
	miko.place(world.floors.cell_centre(b + Vector2i(26, 26)))
	for i in 10:
		await get_tree().process_frame
	sp.restock_wolves()
	var ok := sp.wolves.all(func(wv): var off: Vector2i = world.floors.cell_at(wv.position) - b; return off.x >= 20 or off.y >= 20)
	print("Wolf pack: at night ", sp.wolves.size(), " wolves (Sera level ", miko.stats.level, "), packs ", sp.wolves.map(func(wv): return wv.pack), ", howlers ", sp.wolves.filter(func(wv): return wv.howler).size(), ", all north or east ", ok)
	if sp.wolves.is_empty():
		return
	var lead: MutatedWolf = sp.wolves.filter(func(wv): return wv.howler)[0]
	# Walked up to them.
	var to: Vector2 = lead.position + (miko.position - lead.position).normalized() * 6.0 * world.px
	miko.place(to)
	var running := false
	for i in 240:
		await get_tree().process_frame
		for wv in sp.wolves:
			if is_instance_valid(wv) and wv._run_grass != null and (wv._run_grass.playing and not wv._run_grass.stream_paused or wv._run_solid.playing and not wv._run_solid.stream_paused):
				running = true
		if i == 60:
			shot("pack")
	print("Wolf pack: howled ", lead._howled, " (only the one: ", sp.wolves.filter(func(wv): return is_instance_valid(wv) and wv._howled).size(), "), running feet heard ", running, ", states ", sp.wolves.filter(func(wv): return is_instance_valid(wv)).map(func(wv): return MutatedWolf.State.keys()[wv.state]))
