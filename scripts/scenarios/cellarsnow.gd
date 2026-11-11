extends Scenario
## Deep winter: a chest down in the cellar, no snow on it.
## Run with --window=cellarsnow.


func run() -> void:
	clock.forced = -1
	clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 10.0
	snow._last_hours = -1.0
	world.props.place(Cellars.AT + Vector2i(2, 3), "Chest")
	world.props.place(Cellars.AT + Vector2i(3, 3), "Chest")
	miko.place(world.floors.cell_centre(Cellars.AT + Vector2i(2, 1)))
	camera.zoom *= 1.5
	for i in 90:
		await get_tree().process_frame
	print("Cellar snow: snow lying ", snow.cover)
