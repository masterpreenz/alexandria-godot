extends Scenario
## A new game (run with --slot=new): the home village stamped in: is it a village, are its houses homes, who comes
## to live there; pictures near and far.
## Run with --window=newgame --slot=new.


func run() -> void:
	var v := world.village
	print("New game: founded ", v.founded(), ", centre cell ", world.floors.cell_at(v.centre()), ", tier ", v.tier, " (half size ", v.half_size(), "), banners ", world.props_named("TownBanner").size())
	for i in 60:
		await get_tree().process_frame
	var beds := world.props_named("WoodenBed")
	var homes := beds.filter(func(b): return world.roofs.room_on(b) != null and v.contains(b))
	print("New game: beds ", beds.size(), ", homes (roofed, in the village) ", homes.size(), "; wells ", world.props_named("Well").size(), ", fields ", world.props_named("FarmPlot").size(), "; trees left standing on built cells ", Gatherable.all.filter(func(tree): return world.floors.laid.has(world.floors.cell_at(tree.foot))).size())
	clock.hours = float(clock.day() - 1) * 24.0 + 10.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and Villager.all.size() < 3:
		await get_tree().process_frame
	print("New game: villagers after ", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), " s: ", Villager.all.map(func(x): return x.person.name))
	miko.place(v.centre() + Vector2(0, 1.0) * world.px)
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_near.png")
	camera.zoom *= 0.4
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_whole.png")
