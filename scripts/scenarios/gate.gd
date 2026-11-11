extends Scenario
## A barricade row with a gate in it each way: shut, then open as Miko comes up to it.
## Run with --window=gate.


func run() -> void:
	var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -1)
	for i in [-4, -2, 2, 4]:
		world.walls.place(WallMap.Edge.new(c0 + Vector2i(i, 0), false), "Barricade")
		world.walls.place(WallMap.Edge.new(c0 + Vector2i(7, i + 3), true), "Barricade")
	var gx := WallMap.Edge.new(c0, false)
	var gy := WallMap.Edge.new(c0 + Vector2i(7, 3), true)
	world.walls.place(gx, Shots.arg("gate", "Gate"))
	world.walls.place(gy, "PlankGate" if Shots.arg("gate", "Gate") == "Gate" else "Gate")
	miko.place(world.floors.cell_centre(c0 + Vector2i(3, 4)))
	camera.zoom *= float(Shots.arg("zoom", "1.2"))
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_shut.png")
	miko.place(world.walls.wall_middle(gx.key()) + Vector2(0, 0.5 * world.px))
	for i in 30:
		await get_tree().process_frame
	print("Gate open by her: ", world.walls.is_open(gx), " (", world.walls.walls.get(gx.key()), "), HP ", world.walls.hp.get(gx.key()))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_open.png")
	miko.place(world.floors.cell_centre(c0 + Vector2i(3, 5)))
	for i in 240:
		await get_tree().process_frame
	print("Gate after she left: open ", world.walls.is_open(gx))
