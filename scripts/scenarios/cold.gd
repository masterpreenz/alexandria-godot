extends Scenario
## Winter: out in the open, in the snow, by a lit fire; what she suffers each time. And a villager
## lighting a fire by day.
## Run with --window=cold.


func run() -> void:
	var nd: Needs = miko.get_node("Needs")
	var fr: Fires = miko.get_node("Fires")
	clock.forced = -1
	clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 10.0
	var names := func() -> Array: return nd.effects().map(func(x): return x[0])
	miko.place(world.village.centre() + Vector2(9.0, 6.0) * world.px)
	for f in fr.fires:
		fr.lit_until.erase(f.key)
	for w in [GameClock.Weather.CLEAR, GameClock.Weather.SNOW]:
		clock.forced = w
		for i in 20:
			await get_tree().process_frame
		print("Cold: ", GameClock.WEATHER_NAMES[w], " out in the open -> ", nd.cold(), " ", names.call(), ", move speed ", miko.stats.stat("moveSpeed"))
	var bon: Dictionary = fr.fires.filter(func(f): return not bool(f.s.torch))[0]
	miko.place(bon.pos + Vector2(1.2, 0.6) * world.px)
	for i in 20:
		await get_tree().process_frame
	print("Cold: by an unlit fire -> ", nd.cold())
	fr.light(bon)
	for i in 20:
		await get_tree().process_frame
	print("Cold: by it lit -> ", nd.cold(), ", it burns ", snappedf(float(fr.lit_until[bon.key]) - clock.hours, 0.1), " h")
	fr.lit_until.erase(bon.key)
	world.village.put_in_stash("Wood", 20)
	world.village.put_in_stash("Stone", 20)
	for i in int(Shots.arg("coldframes", "1500")):
		await get_tree().process_frame
	print("Cold: villagers lit by day ", fr.fires.filter(func(f): return fr.lit(f)).size(), " of ", fr.fires.size(), " fires and torches (hour ", snappedf(clock.hour(), 0.1), ")")
