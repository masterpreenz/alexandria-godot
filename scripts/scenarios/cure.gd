extends Scenario
## A cleansing crystal among rotten trees: they're cured over hours, a few showing their bars.
## Run with --window=cure.


func run() -> void:
	var cr: Corruption = Corruption.active
	while not cr.seeded:
		await get_tree().process_frame
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 10.0
	var rm: Rumors = g.get_node("Rumors")
	var wood := rm._wood_in({"section": "F6", "corner": "upper-left", "misted": true})
	# (where the rot's thickest near there)
	var best := wood
	var best_n := -1
	for t in cr.corrupted:
		var n := cr.corrupted_near(t.foot, 5.0 * world.px)
		if n > best_n and t.foot.distance_to(wood) < 40.0 * world.px and world.mist.tier_at(t.foot) == Mist.Tier.NORMAL:
			best_n = n
			best = t.foot
	miko.place(best + Vector2(0.6, 0.9) * world.px)
	world.props.place(world.floors.cell_at(best) + Vector2i(1, 2), "CleansingCrystal")
	for i in 300:
		await get_tree().process_frame
	var rot0 := cr.corrupted_near(best, 7.0 * world.px)
	print("Cure: rotten trees round the crystal ", rot0, ", being cured ", cr.curing.size())
	clock.hours += 2.0
	for i in 40:
		await get_tree().process_frame
	print("Cure: 2 hours on: being cured ", cr.curing.size(), ", furthest along ", snappedf(cr.curing.values().max() if not cr.curing.is_empty() else 0.0, 0.01), ", bars showing ", cr._bars.bars.size(), ", rotten ", cr.corrupted_near(best, 7.0 * world.px))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_bars.png")
	for k in 3:
		clock.hours += 2.0
		for i in 20:
			await get_tree().process_frame
	print("Cure: 8 hours on: rotten ", cr.corrupted_near(best, 7.0 * world.px), " of ", rot0, ", still being cured ", cr.curing.size())
