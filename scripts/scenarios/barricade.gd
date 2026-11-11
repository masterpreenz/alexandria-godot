extends Scenario
## Barricades: three along x and three along y, a fence row beside them to compare.
## Run with --window=barricade.


func run() -> void:
	var c0 := world.floors.cell_at(miko.position) + Vector2i(2, -2)
	for i in 3:
		world.walls.place(WallMap.Edge.new(c0 + Vector2i(i * 2, 0), false), Shots.arg("wall", "Barricade"))
		world.walls.place(WallMap.Edge.new(c0 + Vector2i(7, i * 2 + 1), true), Shots.arg("wall", "Barricade"))
		world.walls.place(WallMap.Edge.new(c0 + Vector2i(i, -2), false), "Fence")
	miko.place(world.floors.cell_centre(c0 + Vector2i(1, 2)))
	camera.zoom *= float(Shots.arg("zoom", "1.4"))
	for i in 10:
		await get_tree().process_frame
