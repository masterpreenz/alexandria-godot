extends Scenario
## The bookshelves (one cell, two cells) and the street lamp, each way they turn, at night; the waysides on the road
## west; and a game from before the west village's barricades were turned (they're turned as it loads).
## Run with --window=newprops.


func _look_at(at: Vector2, nm: String, zoom := 0.7) -> void:
	miko.place(at + Vector2(2.6, 0.4) * world.px)   # (the camera follows her: she stands just beside)
	camera.zoom = Vector2(zoom, zoom)
	for i in 30:
		camera.position = at
		camera.reset_smoothing()
		await get_tree().process_frame
	shot(nm)


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	world.clock.hours = floorf(world.clock.hours / 24.0) * 24.0 + 21.0
	var f := world.floors
	var c0 := Vector2i(int(Shots.arg("cx", "-200")), int(Shots.arg("cy", "-30")))
	for x in range(-8, 18):
		for y in range(-8, 16):
			world.props.remove_all(c0 + Vector2i(x, y))
			world.clear_cell(c0 + Vector2i(x, y))
	var row := 0
	for kind in [["Bookshelf", 2], ["WideBookshelf", 2], ["StreetLamp", 4]]:
		for t in int(kind[1]):
			var c := c0 + Vector2i(t * 3, row * 3)
			world.props.remove_all(c)
			world.clear_cell(c)
			world.props.place(c, str(kind[0]), 1.0, t)
		row += 1
	world.props.place(c0 + Vector2i(13, 6), "TallTorch", 1.0, 0)   # (beside the lamps, to compare their light)
	for i in 30:
		await get_tree().process_frame
	var fires: Fires = miko.get_node("Fires")
	var lamps := fires.fires.filter(func(x): return str(x.type) == "StreetLamp")
	print("New props: lamps lit ", lamps.filter(func(x): return fires.lit(x)).size(), " of ", lamps.size(), ", their turns ", lamps.map(func(x): return x.turn),
		", lights ", lamps.map(func(x):
			if x.light == null:
				return null
			return [x.light.visible, snappedf(x.light.energy, 0.01)]),
		"; torch ", fires.fires.filter(func(x): return str(x.type) == "TallTorch").map(func(x): return [fires.lit(x), x.light.visible if x.light != null else null, snappedf(x.light.energy, 0.01) if x.light != null else 0.0]))
	var lamp_at := Vector2.ZERO
	for e in world.props.drawn_named("StreetLamp"):
		lamp_at += e.pos / 4.0
	var shelf_at := Vector2.ZERO
	var shelves: Array = world.props.drawn_named("Bookshelf") + world.props.drawn_named("WideBookshelf")
	for e in shelves:
		shelf_at += e.pos / float(shelves.size())
	await _look_at(lamp_at, "lamps", 1.1)
	var lm: LightMap = g.find_children("*", "LightMap", true, false)[0] if not g.find_children("*", "LightMap", true, false).is_empty() else null
	if lm == null:
		for n in get_tree().root.find_children("LightMap", "", true, false):
			lm = n as LightMap
	print("New props: light pass ", lm != null and lm._rect.visible, ", lights in it ", lm._mat.get_shader_parameter("count") if lm != null else -1, ", daylight ", str(lm.daylight.color) if lm != null and lm.daylight != null else "?")
	await _look_at(shelf_at, "shelves", 1.1)
	world.clock.hours = floorf(world.clock.hours / 24.0) * 24.0 + 12.0
	await _look_at(lamp_at, "lamps_day", 1.1)
	await _look_at(shelf_at, "shelves_day", 1.1)
	# The waysides.
	for w in ["wayside_hut", "wayside_camp", "wayside_post", "wayside_well"]:
		var t := VillageTemplate.load_named(w)
		var mid := Vector2i(int(t.at[0]) + int(t.width / 2.0), int(t.at[1]) + int(t.height / 2.0))
		await _look_at(f.cell_centre(mid), w, 0.6)
	# An old game's west village: its barricades still standing, then as it loads (taken out).
	var west := VillageTemplate.load_named("west_village")
	var lo := Vector2i(int(west.at[0]), int(west.at[1]))
	var edges := []
	for r in west.walls:
		if str(r.type) == "Barricade":
			var e := WallMap.Edge.new(lo + Vector2i(int(r.x), int(r.y)), bool(r.alongY))
			edges.append(e)
			world.walls.place(e, "Barricade")
	var before := edges.filter(func(e): return world.walls.get_wall(e) == "Barricade").size()
	VillageTemplate.keep_up(world, west)
	print("New props: west village barricades, an old game's ", before, ", once loaded ", edges.filter(func(e): return world.walls.get_wall(e) == "Barricade").size(), " of ", edges.size())
	camera.zoom = Vector2.ONE
