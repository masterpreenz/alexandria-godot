extends Scenario
## A cell with a farm plot, a free flower bush on it and a fence along it: each demolish filter takes only
## its own; then a sown plot moved with Move keeps its crop.
## Run with --window=demolish.


func run() -> void:
	var bm := BuildMode.active
	var fm: Farming = miko.get_node("Farming")
	var cell := world.floors.cell_at(miko.position) + Vector2i(2, 1)
	var what := func() -> String: return "plot %s, bush %s, fence %s" % [world.props.get_prop(cell, 0) != "" or world.props.peek_top(cell) == "FarmPlot", world.props.free_props().any(func(e): return world.floors.cell_at(e.pos) == cell), world.walls.get_wall(WallMap.Edge.new(cell, false)) != ""]
	for kind in ["Walls", "Decor", "Farm"]:
		world.props.place(cell, "FarmPlot")
		world.props.place_free(world.floors.cell_centre(cell) + Vector2(10, 4), "FlowerBush")
		world.walls.place(WallMap.Edge.new(cell, false), "Fence")
		bm.set_demolish_only(kind)
		bm._clear_one(cell)
		print("Demolish ", kind, ": ", what.call())
		world.props.remove_all(cell)
		world.walls.remove(WallMap.Edge.new(cell, false))
	bm.set_demolish_only("All")
	world.props.place(cell, "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var pl: Dictionary = fm.nearest(world.floors.cell_centre(cell), world.px)
	fm.sow(pl, "Wheat")
	fm._state(pl).grown = 20.0
	bm.carried = world.props.take_top(cell)
	bm.carried.farm = fm.lift_plot(bm.carried.pos)
	var to := cell + Vector2i(3, 0)
	world.props.place(to, "FarmPlot")
	bm._set_plot(world.floors.cell_centre(to))
	bm.carried = {}
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var moved: Dictionary = fm.nearest(world.floors.cell_centre(to), world.px)
	print("Move: the plot there ", not moved.is_empty(), ", crop ", fm.crop(moved) if not moved.is_empty() else "", " grown ", fm._grown(moved) if not moved.is_empty() else -1.0, ", old spot empty ", world.props.peek_top(cell) == "")
