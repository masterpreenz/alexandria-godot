extends Scenario
## Crops grow by the hour without a pass over every plot each frame: three plots sown (one kept watered, one left dry,
## one with pests), the clock run on, how far each has grown against what it should have; then what farming costs a
## frame. Run with --window=farmhours.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	var c0 := world.floors.cell_at(miko.position) + Vector2i(2, 1)
	for k in 3:
		world.props.place(c0 + Vector2i(k * 2, 0), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 6)
	row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
	for pl in row:
		fm.sow(pl, "Potato")
	var wet: Dictionary = row[0]
	var dry: Dictionary = row[1]
	var bugs: Dictionary = row[2]
	fm._state(dry).wateredAt = -1000.0
	fm._settle(bugs)
	fm._state(bugs).pest = true
	var h0 := clock.hours
	var speed := clock.speed
	clock.speed = 600.0
	while clock.hours < h0 + 3.0:
		fm._state(wet).wateredAt = clock.hours
		var was := fm._grown(wet)
		var pd := bool(fm._state(dry).get("pest", false))
		var tended := fm._tended_at
		await get_tree().process_frame
		if fm._tended_at != tended:
			print("Farm hours: tended at ", snappedf(fm._tended_at, 0.01), " (", snappedf(fm._tended_at - tended, 0.01), " h)")
		if bool(fm._state(dry).get("pest", false)) != pd:
			print("Farm hours: pests on the dry plot ", not pd, " at ", snappedf(clock.hours, 0.01))
		if fm._grown(wet) < was - 0.0001 or fm._state(wet).get("pest", false):
			print("Farm hours: watered plot went back ", was, " -> ", fm._grown(wet), " ", fm._state(wet))
	clock.speed = speed
	var gone := clock.hours - h0
	print("Farm hours: ", snappedf(gone, 0.01), " h gone; grown watered ", snappedf(fm._grown(wet), 0.01), ", dry ", snappedf(fm._grown(dry), 0.01), " (half: ", snappedf(gone * Farming.DRY_RATE, 0.01), "), pests ", snappedf(fm._grown(bugs), 0.01))
	fm.clear_pests(bugs)
	print("Farm hours: pests cleared, growing again: ", not fm.pests(bugs), ", stage ", fm.stage(bugs), ", ", snappedf(fm.hours_left(bugs), 0.1), " h left of ", fm._grow(bugs))
	fm._state(wet).grown = fm._grow(wet) - 0.00001
	fm._state(wet).at = clock.hours
	for i in 30:
		await get_tree().process_frame
	print("Farm hours: nearly grown, a moment on: stage ", fm.stage(wet))
	var t0 := Time.get_ticks_usec()
	for i in 200:
		fm._process_timed(0.016)
	print("Farm hours: farming a frame ", snappedf((Time.get_ticks_usec() - t0) / 200.0 / 1000.0, 0.001), " ms, plots ", fm.plots.size())
