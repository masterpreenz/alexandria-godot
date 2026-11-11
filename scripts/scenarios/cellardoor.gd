extends Scenario
## The doors used three times in quick succession, then left: opened once, shut once.
## Run with --window=cellardoor.


func run() -> void:
	var cl: Cellars = g.get_node("Cellars")
	if Shots.arg("winter") != "":
		clock.forced = -1
		clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 10.0
		snow._last_hours = -1.0
	var door_at := world.floors.cell_centre(world.floors.cell_at(world.village.centre()) + Vector2i(4, -5))
	world.props.place(world.floors.cell_at(door_at), "Cellar", 1.0, 0)
	for i in 5:
		await get_tree().process_frame
	print("Cellar door: sounds ", snappedf(Sfx.stream(Cellars.OPEN_SOUND).get_length(), 0.1), " s open, ", snappedf(Sfx.stream(Cellars.CLOSE_SOUND).get_length(), 0.1), " s close")
	world.props.place(world.floors.cell_at(door_at) + Vector2i(4, 0), "Cellar", 1.0, 1)
	# One placed freely (off the grid), as with Alt held.
	var free_at := door_at + Vector2(-3.3, 1.7) * world.px
	world.props.place_free(free_at, "Cellar", 1.0, 0)
	for i in 5:
		await get_tree().process_frame
	cl.use_doors(free_at)
	var fn: Node2D = world.props.last_free_node()
	print("Cellar door: one placed freely shows ", world.sprites[int((fn.get_child(0) as Sprite2D).get_meta("sprite", 0))].name)
	miko.place(door_at + Vector2(2.0, 2.5) * world.px)
	for i in 5:
		await get_tree().process_frame
	cl.use_doors(world.floors.cell_centre(world.floors.cell_at(door_at) + Vector2i(4, 0)))
	var states := []
	for n in 3:
		cl.use_doors(door_at + Vector2(20, 30))
		if n == 1:
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_open.png")
		states.append(cl._open_until.size())
		for i in 60:
			await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while not cl._open_until.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	print("Cellar door: open after each use ", states, "; shut by itself after ", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), " s more")
