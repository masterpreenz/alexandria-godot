extends Scenario
## Walls just past the village's edge: a plank wall can't go there, a barricade or gate can (up to 2 tiles).
## Run with --window=margin.


func run() -> void:
	for i in 3:
		await get_tree().process_frame
	var bm := BuildMode.active
	var edge_cell := world.floors.cell_at(world.village.centre()) + Vector2i(0, ceili(world.village.half_size()))
	for off in [0, 1, 2, 3, 4]:
		var e := WallMap.Edge.new(edge_cell + Vector2i(0, off), false)
		print("Margin +", off, ": PlankWall out ", bm._wall_outside(e, "PlankWall", false), ", Barricade out ", bm._wall_outside(e, "Barricade", false), ", Gate out ", bm._wall_outside(e, "Gate", false))
