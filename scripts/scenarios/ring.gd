extends Scenario
## A ring of barricades just round the village: their spikes should point out on every side.
## Run with --window=ring.


func run() -> void:
	for i in 5:
		await get_tree().process_frame
	var cc := world.floors.cell_at(world.village.centre())
	var h := ceili(world.village.half_size()) + 1
	for x in range(cc.x - h, cc.x + h, 2):
		world.walls.place(WallMap.Edge.new(Vector2i(x, cc.y - h), false), "Barricade")
		world.walls.place(WallMap.Edge.new(Vector2i(x, cc.y + h), false), "Barricade")
	for y in range(cc.y - h, cc.y + h, 2):
		world.walls.place(WallMap.Edge.new(Vector2i(cc.x - h, y), true), "Barricade")
		world.walls.place(WallMap.Edge.new(Vector2i(cc.x + h, y), true), "Barricade")
	for side in [["south", Vector2i(cc.x + h, cc.y + h)], ["north", Vector2i(cc.x - h, cc.y - h)], ["east", Vector2i(cc.x + h, cc.y - h)], ["west", Vector2i(cc.x - h, cc.y + h)]]:
		miko.place(world.floors.cell_centre(side[1]))
		for i in 90:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + side[0] + ".png")
