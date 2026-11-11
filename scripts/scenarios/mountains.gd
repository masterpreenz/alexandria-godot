extends Scenario
## The cave's mouth at the mountains' foot; then into it, and out again.
## Run with --window=mountains.


func run() -> void:
	var foot := Mountains.EDGE + 1 - Mountains.DEPTH
	miko.place(world.floors.corner(Vector2(foot - 3.0, 0.5)))
	camera.zoom *= float(Shots.arg("zoom", "0.45"))
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_range.png")
	print("Mountains: build on the rock ", not Mountains.covers(Vector2i(foot + 2, 20)), ", mist at the mouth ", world.mist.tier_at(miko.position))
	miko.place(world.floors.corner(Vector2(foot + 2.0, 0.0)))
	for i in 90:
		await get_tree().process_frame
	print("Mountains: in the cave ", Mountains.in_cave(miko.position), ", mist there ", world.mist.tier_at(miko.position))
	camera.zoom /= float(Shots.arg("zoom", "0.45"))
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_cave.png")
	miko.place(Mountains.active._exit())
	for i in 90:
		await get_tree().process_frame
	print("Mountains: out again, in the cave ", Mountains.in_cave(miko.position), ", at cell ", world.floors.cell_at(miko.position))
