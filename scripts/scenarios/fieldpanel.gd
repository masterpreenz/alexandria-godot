extends Scenario
## A field of four carrots part grown (one dry, one with pests), and its panel opened (R).
## Run with --window=fieldpanel.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	fm.rotation = ["Potato", "Carrot", "Wheat", "Cotton"]
	var c0 := world.floors.cell_at(miko.position) + Vector2i(1, 1)
	for k in 4:
		world.props.place(c0 + Vector2i(k % 2, floori(k / 2.0)), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var field := fm.field_of(fm.nearest(world.floors.cell_centre(c0), world.px))
	for pl in field:
		fm.sow(pl, "Carrot")
		fm._state(pl).grown = 22.0
	fm._state(field[1]).wateredAt = -1000.0
	fm._state(field[2]).pest = true
	miko.place(field[0].pos + Vector2(0, 0.4) * world.px)
	await get_tree().process_frame
	fm.panel.open(field[0])
	for i in 10:
		await get_tree().process_frame
	if Shots.arg("winter") != "":
		# Late autumn (a day and a half to winter): the panel's warning; then into winter: the frost.
		var dps: int = clock.days_per_season
		var autumn_day := posmod(GameClock.Season.AUTUMN - clock.start_season, 4) * dps
		clock.hours = float(autumn_day + dps - 2) * 24.0 + 12.0
		for i in 5:
			await get_tree().process_frame
		fm.panel._refresh()
		print("Winter: in ", snappedf(fm.hours_to_winter(), 0.1), " h; panel: ", fm.panel._lines.text.replace("
", " | "))
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_autumn.png")
		clock.hours += 40.0
		for i in 5:
			await get_tree().process_frame
		fm.panel._refresh()
		print("Winter: season ", clock.season(), " stages ", field.map(func(pl): return fm.stage(pl)), " plantable ", fm.plantable(field[0]), "; panel: ", fm.panel._lines.text.replace("
", " | "))
