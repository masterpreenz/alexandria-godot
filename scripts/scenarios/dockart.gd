extends Scenario
## The dock's two views, side by side by the river.
## Run with --window=dockart.


func run() -> void:
	var bm := BuildMode.active
	var dock_item := bm.item_for("Prop", "FishingDock")
	var c0 := world.floors.cell_at(world.village.centre())
	var spot := c0
	for r in range(1, 60):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var cc := c0 + Vector2i(dx, dy)
				if spot == c0 and maxi(absi(dx), absi(dy)) == r and not bm.no_build(cc) and bm.why_not(dock_item, world.floors.cell_centre(cc)) == "":
					spot = cc
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 11.0
	world.props.place(spot, "FishingDock", 1.0, 0)
	world.props.place(spot + Vector2i(4, -4), "FishingDock", 1.0, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var fz: Fishing = g.get_node("Fishing")
	for d in fz.docks():
		var on := 0
		var blocked := 0
		for i in 400:
			var q := Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5))
			if absf(q.x) + absf(q.y) * 2.0 > 1.0:
				continue
			if fz.on_planks(d + q * world.px): on += 1
			else: blocked += 1
		print("Dock deck: turned ", fz._turn_of(d), ": open planks ", snappedf(float(on) / float(on + blocked), 0.01), " of the deck; they stand ", Fishing.deck_stand(fz._turn_of(d)), " on planks ", fz.on_planks(fz.stand_at(d)), "; colliders ", fz._shapes.size())
	world.props.place(spot + Vector2i(1, -1), "CleansingCrystal")
	miko.place(world.floors.cell_centre(spot + Vector2i(3, -1)))
	for i in 240:
		await get_tree().process_frame
