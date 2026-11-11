extends Scenario
## A 2x2 field of wheat, part grown, lifted whole with Move; its ghost under the cursor; set down 3 cells on.
## Run with --window=movefield.


func run() -> void:
	var bm := BuildMode.active
	var fm: Farming = miko.get_node("Farming")
	var cell := world.floors.cell_at(miko.position) + Vector2i(1, 1)
	for k in 4:
		world.props.place(cell + Vector2i(k % 2, floori(k / 2.0)), "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	fm._look()
	for pl in fm.field_of(fm.nearest(world.floors.cell_centre(cell), world.px)):
		fm.sow(pl, "Wheat")
		fm._state(pl).grown = 20.0
	bm.set_open(true)
	bm.set_tool("Move")
	bm._lift_field(cell)
	print("Move field: lifted ", bm.carried.group.size(), " plots, left on the ground ", [0, 1, 2, 3].filter(func(k): return world.props.peek_top(cell + Vector2i(k % 2, floori(k / 2.0))) != "").size())
	var to := cell + Vector2i(3, 0)
	get_viewport().warp_mouse(get_viewport().get_canvas_transform() * world.floors.cell_centre(to))
	for i in 6:
		await get_tree().process_frame
	print("Move field: ghosts ", bm._group_ghost.size(), " tool ", bm.tool, " open ", BuildMode.is_open(), " hover ", bm.hover.get("title", ""))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_carry.png")
	bm._set_field_down(to)
	bm.carried = {}
	for i in 3:
		await get_tree().process_frame
	fm._look()
	var moved := fm.field_of(fm.nearest(world.floors.cell_centre(to), world.px))
	print("Move field: set down ", moved.size(), " plots, crops ", moved.map(func(pl): return fm.crop(pl)), " grown ", moved.map(func(pl): return snappedf(fm._grown(pl), 1.0)))
	bm.set_open(false)
