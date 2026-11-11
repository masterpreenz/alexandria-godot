extends Scenario
## Two fields of three plots, planted plot by plot as the villagers do: one crop a field; then the
## first harvested and planted again, moving on to the next crop together.
## Run with --window=rotation.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	fm.rotation = ["Potato", "Carrot", "Wheat", "Cotton"]
	var base := world.floors.cell_at(miko.position) + Vector2i(2, 1)
	for k in 3:
		world.props.place(base + Vector2i(k, 0), "FarmPlot")
		world.props.place(base + Vector2i(k, 3), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var fields := [[], []]
	for pl in fm.plots:
		var c := world.floors.cell_at(pl.pos)
		if c.x >= base.x and c.x < base.x + 3 and (c.y == base.y or c.y == base.y + 3):
			fields[0 if c.y == base.y else 1].append(pl)
	var any_seed := func(_s: String) -> bool: return true
	for f in fields:
		for pl in f:
			fm.sow(pl, fm._field_crop(pl, any_seed)[1])
	print("Rotation planted: A ", fields[0].map(func(pl): return fm.crop(pl)), "  B ", fields[1].map(func(pl): return fm.crop(pl)))
	for pl in fields[0]:
		fm._state(pl).sownAt = -10000.0
		fm.harvest(pl)
	for pl in fields[0]:
		fm.sow(pl, fm._field_crop(pl, any_seed)[1])
	print("Rotation next season: A ", fields[0].map(func(pl): return fm.crop(pl)), "  B ", fields[1].map(func(pl): return fm.crop(pl)))
	miko.place(fields[0][1].pos + Vector2(0, 0.45) * world.px)
	for i in 20:
		await get_tree().process_frame
