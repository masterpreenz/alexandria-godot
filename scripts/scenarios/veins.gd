extends Scenario
## The corruption in the ground: open misted ground, then a crystal set by it (its edge burning back).
## Run with --window=veins.


func run() -> void:
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 11.0
	var c0 := world.floors.cell_at(world.village.centre()) + Vector2i(-20, -14)
	miko.place(world.floors.cell_centre(c0))
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_mist.png")
	world.props.place(c0 + Vector2i(6, 2), "CleansingCrystal")
	var t0 := Time.get_ticks_msec()
	var cleared_at := -1.0
	var shot := false
	while Time.get_ticks_msec() - t0 < 14000:
		await get_tree().process_frame
		var since := (Time.get_ticks_msec() - t0) / 1000.0
		if not shot and since >= 2.5:
			shot = true
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_clearing.png")
		if cleared_at < 0.0 and world.mist._moving.is_empty() and since > 1.0:
			cleared_at = since
	print("Veins: a crystal set: the clearing all shown after ", snappedf(cleared_at, 0.1), " s (the mist itself is cleared at once: ", world.mist.tier_at(miko.position) == Mist.Tier.CLEAR, ")")
