extends Scenario
## A look at some map sections (--names=F5,F6,F8): each one's cells, its laid ground (roads) and trees, and the world
## map (F6) zoomed in on the first. Run with --window=sections --names=F5,F6,F8.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var names := Shots.arg("names", "F5,F6,F8").split(",")
	var f := world.floors
	var first := Rect2i()
	for nm in names:
		var cr: Array = MapMarks.section_of(nm)
		if cr.is_empty():
			continue
		var b := MapMarks.section_bounds(cr[0], cr[1])
		if first.size == Vector2i.ZERO:
			first = b
		var laid := {}
		var road_cells := []
		for x in range(b.position.x, b.end.x):
			for y in range(b.position.y, b.end.y):
				var c := Vector2i(x, y)
				var fl: String = f.get_floor(c)
				if fl != f.base_floor and fl != "":
					laid[fl] = int(laid.get(fl, 0)) + 1
					road_cells.append(c)
		var trees := 0
		for gth in Gatherable.all:
			if gth.axe and b.has_point(f.cell_at(gth.foot)):
				trees += 1
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := -lo
		for c in road_cells:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		print("Section ", nm, ": cells ", b, ", ground laid ", laid, " (from ", lo, " to ", hi, "), trees ", trees)
	# The ground itself, zoomed out, over each named point (--at_cells=x,y;x,y).
	for spot in Shots.arg("at_cells", "").split(";", false):
		var xy := spot.split(",")
		var at := f.cell_centre(Vector2i(int(xy[0]), int(xy[1])))
		miko.place(at)
		camera.zoom = Vector2(0.35, 0.35)
		camera.position = at
		camera.reset_smoothing()
		for i in 40:
			camera.position = at
			await get_tree().process_frame
		shot("ground_%s_%s" % [xy[0], xy[1]])
	camera.zoom = Vector2.ONE
	var wm := g.get_node("Hud/WorldMap") as WorldMap
	wm.open()
	wm.centre = f.cell_centre(first.get_center())
	for i in int(Shots.arg("mapzoom", "2")):
		wm._step(1, null)
	for i in 20:
		await get_tree().process_frame
	shot("map")
