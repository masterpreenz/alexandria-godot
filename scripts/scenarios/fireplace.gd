extends Scenario
## Winter evening: a fireplace put in one house; villagers light it; then who sleeps cold and who warm.
## Run with --window=fireplace.


func run() -> void:
	clock.forced = -1
	clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 17.6
	var fr: Fires = miko.get_node("Fires")
	var room: Dictionary = world.roofs.roofs[0].cells
	var spot := Vector2i.ZERO
	for c in room:
		if world.props.peek_where(c, func(_n): return true) == "" and not BuildMode.active._use_cells().has(c):
			spot = c
	world.props.place(spot, "Fireplace")
	world.village.put_in_stash("Wood", 30)
	for i in 10:
		await get_tree().process_frame
	var hearth: Dictionary = fr.fires.filter(func(f): return bool(f.s.get("hearth", false)))[0]
	fr.lit_until.erase(hearth.key)
	var wood0 := world.village.stored("Wood")
	miko.place(world.floors.cell_centre(spot) + Vector2(0.8, 0.6) * world.px)
	for i in 1500:
		await get_tree().process_frame
		if fr.lit(hearth):
			break
	print("Fireplace: lit by a villager ", fr.lit(hearth), " (hour ", snappedf(clock.hour(), 0.1), "), burns ", snappedf(float(fr.lit_until.get(hearth.key, 0.0)) - clock.hours, 0.1), " h, wood ", wood0, " -> ", world.village.stored("Wood"), ", warm room ", fr.warm_room(room))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_lit.png")
	clock.hours = floorf(clock.hours / 24.0) * 24.0 + 23.0
	for i in 400:
		await get_tree().process_frame
	for v in Villager.all:
		if not v.home.is_empty():
			print("  ", v.person.name, ": in bed ", v.in_bed, ", sleeping cold ", v._sleeping_cold())
