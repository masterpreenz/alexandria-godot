extends Scenario
## Two barricades side by side, one turned round (R); then saved and loaded back, and the ghost's art.
## Run with --window=turnbar.


func run() -> void:
	for i in 5:
		await get_tree().process_frame
	var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -2)
	var ea := WallMap.Edge.new(c0, false)
	var eb := WallMap.Edge.new(c0 + Vector2i(2, 0), false)
	world.walls.place(ea, "Barricade")
	world.walls.place(eb, "Barricade", true)
	var ec := WallMap.Edge.new(c0 + Vector2i(5, -1), true)
	world.walls.place(ec, "Barricade", true)
	var saved_walls := world.walls.to_json()
	world.walls.from_json(saved_walls)
	world.walls.rebuild()
	print("Turned: plain ", world.walls.is_turned(ea), ", turned ", world.walls.is_turned(eb), ", turned along y ", world.walls.is_turned(ec))
	print("Ghost art: usual ", world.walls.ghost_pieces(ea, "Barricade")[0][0], ", turned ", world.walls.ghost_pieces(ea, "Barricade", true)[0][0])
	world.walls.place(ea, "Barricade", true)
	print("Placed again turned: ", world.walls.is_turned(ea))
	world.walls.place(ea, "Barricade", false)
	miko.place(world.floors.cell_centre(c0 + Vector2i(2, 2)))
	for i in 20:
		await get_tree().process_frame
