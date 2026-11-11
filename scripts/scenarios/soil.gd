extends Scenario
## Potato plots: bare, growing (watered), growing (dry), ripe; then a closer look.
## Run with --window=soil.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -1)
	for k in 4:
		world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 4)
	row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
	for k in range(1, 4):
		fm.sow(row[k], Shots.arg("crop", "Potato"))
	fm._state(row[2]).wateredAt = -1000.0
	fm._state(row[3]).grown = 999.0
	print("Soil: stages ", row.map(func(pl): return fm.stage(pl)), " dry ", row.map(func(pl): return fm.dry(pl)))
	miko.place(row[1].pos + Vector2(-1.5, 1.6) * world.px)
	camera.zoom *= float(Shots.arg("zoom", "1.6"))
	for i in 10:
		await get_tree().process_frame
