extends Scenario
## A field of three plots and a lone plot beside it planted mixed (an old save); evened out to one crop;
## two harvested: the field waits; the last harvested: planted again together, the next crop.
## Run with --window=fields.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	fm.rotation = ["Potato", "Carrot", "Wheat", "Cotton"]
	var c0 := world.floors.cell_at(miko.position) + Vector2i(2, 1)
	for k in 3:
		world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 3)
	row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
	var mixed := ["Carrot", "Carrot", "Wheat"]
	for k in 3:
		fm.sow(row[k], mixed[k])
		fm._state(row[k]).grown = 999.0
	fm._even_fields()
	print("Fields: evened out ", row.map(func(pl): return fm.crop(pl)))
	var any_seed := func(_s: String) -> bool: return true
	fm.harvest(row[0])
	fm.harvest(row[1])
	print("Fields: two harvested, plantable ", row.map(func(pl): return fm.plantable(pl)), ", still growing ", fm.still_growing(row[0]))
	fm.harvest(row[2])
	print("Fields: all harvested, plantable ", row.map(func(pl): return fm.plantable(pl)))
	for pl in row:
		fm.sow(pl, fm._field_crop(pl, any_seed)[1])
	print("Fields: replanted together ", row.map(func(pl): return fm.crop(pl)))
