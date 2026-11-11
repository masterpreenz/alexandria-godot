extends Scenario
## Three plots of potatoes: normal, left dry, and with pests; their growth over 10 game hours; Miko waters
## the dry one; a villager clears the pests (the emote showing).
## Run with --window=tend.


func run() -> void:
	seed(7)
	var fm: Farming = miko.get_node("Farming")
	clock.hours = 12.0
	var c0 := world.floors.cell_at(miko.position) + Vector2i(2, 1)
	for k in 3:
		world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 3)
	row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
	for pl in row:
		fm.sow(pl, "Potato")
	fm._state(row[1]).wateredAt = -1000.0
	fm._state(row[2]).pest = true
	for k in 10:
		clock.hours += 1.0
		for i in 2:
			await get_tree().process_frame
	print("Tend: grown after 10 h (normal, dry, pests): ", row.map(func(pl): return snappedf(fm._grown(pl), 0.1)), " dry ", row.map(func(pl): return fm.dry(pl)), " pests ", row.map(func(pl): return fm.pests(pl)))
	fm.water(row[1])
	print("Tend: watered, dry now ", fm.dry(row[1]))
	clock.hours += 14.0   # the next midday (at 22:00 they're off to bed)
	fm._state(row[2]).pest = true
	for i in 3:
		await get_tree().process_frame
	var v: Villager = Villager.all[0]
	v.position = row[2].pos + Vector2(2.5, 1.0) * world.px
	v.carrying = 0
	v.farm_task = "pests"
	v.planting = false
	v._go_to_plot(row[2])
	var seen_emote := false
	for i in 600:
		await get_tree().process_frame
		if v.emote != null and v.emote.visible and not seen_emote:
			seen_emote = true
			miko.place(row[1].pos + Vector2(-1.5, 1.2) * world.px)
			for k in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_emote.png")
		if not fm.pests(row[2]):
			break
	print("Tend: villager cleared the pests ", not fm.pests(row[2]), ", saw the emote ", seen_emote, ", status '", v.activity(), "'")
	fm._state(row[0]).pest = true
	fm._state(row[0]).wateredAt = -1000.0
	miko.place(row[1].pos + Vector2(0, 1.6) * world.px)
