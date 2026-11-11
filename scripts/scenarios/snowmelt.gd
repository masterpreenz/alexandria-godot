extends Scenario
## Deep winter, one bonfire and one torch burning: clear ground round them, none inside the houses.
## Run with --window=snowmelt.


func run() -> void:
	clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 9.0
	clock.forced = GameClock.Weather.CLOUDY
	snow._last_hours = -1.0
	var fr: Fires = miko.get_node("Fires")
	for i in 10:
		await get_tree().process_frame
	for f in fr.fires:
		fr.lit_until.erase(f.key)
	var bon: Dictionary = fr.fires.filter(func(f): return not bool(f.s.torch))[0]
	fr.light(bon)
	miko.place(bon.pos + Vector2(-3.0, 1.0) * world.px)
	camera.zoom *= 0.75
	for i in 90:
		await get_tree().process_frame
	print("Snow melt: snow ", snow.cover, ", lit ", fr.fires.filter(func(f): return fr.lit(f)).size(), ", houses ", world.roofs.roofs.size())
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_fire.png")
	# Into a house: its roof fades, the floor inside shows.
	var room: Dictionary = world.roofs.roofs[0].cells
	var inside: Vector2i = room.keys()[room.size() >> 1]
	miko.place(world.floors.cell_centre(inside))
	for i in 120:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_house.png")
