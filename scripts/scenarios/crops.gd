extends Scenario
## Five farm plots in a row beside her, one of each crop: growing, then (--ripe) ripe.
## Run with --window=crops.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	var c0 := world.floors.cell_at(miko.position) + Vector2i(2, 1)
	for k in 5:
		world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 5)
	row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
	for k in row.size():
		fm.sow(row[k], Farming.ORDER[k % Farming.ORDER.size()])
		if Shots.arg("ripe") != "":
			fm._state(row[k]).sownAt = -10000.0
	print("Crops: ", row.size(), " plots: ", row.map(func(pl): return [fm.crop(pl), fm.stage(pl), fm._art(pl, fm.stage(pl))]))
	miko.place(row[2].pos + Vector2(0, 2.0) * world.px if row.size() > 2 else miko.position)
	for i in 20:
		await get_tree().process_frame
