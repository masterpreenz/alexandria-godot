extends Scenario
## Drafts the next village (X8, across the river, up the road north): already overrun. A street running north
## from the road, houses either side with walls fallen in and gaps where the rest stood (so no roofs), beds and chests
## left as they were, a cold fire, a well, barricades broken down at the edge. Nobody's left: only monsters. Saved as
## data/villages/west_village.json (added to games already going, too), with pictures.
## Run with --window=draftwest.

const STREET_X := -250
var rng := RandomNumberGenerator.new()


func paint(c: Vector2i, fl: String) -> void:
	world.clear_cell(c)
	world.props.remove_all(c)
	world.floors.paint(c, fl)


func prop(c: Vector2i, type: String, turn := 0) -> void:
	world.clear_cell(c)
	world.props.remove_all(c)
	world.props.place(c, type, 1.0, turn)


func edge(a: Vector2i, b: Vector2i) -> WallMap.Edge:
	var d := b - a
	if d.x == 1: return WallMap.Edge.new(a + Vector2i(1, 0), true)
	if d.x == -1: return WallMap.Edge.new(a, true)
	if d.y == 1: return WallMap.Edge.new(a + Vector2i(0, 1), false)
	return WallMap.Edge.new(a, false)


## A ruined house over [param lo]..[param hi] (cells): boards, about half its walls standing (some of those broken),
## the rest fallen; a bed or two and a chest left in it.
func ruin(lo: Vector2i, hi: Vector2i, beds: int) -> void:
	var inside := {}
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			inside[Vector2i(x, y)] = true
			paint(Vector2i(x, y), "WornBoards")
	for c in inside:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if inside.has(c + d):
				continue
			var roll := rng.randf()
			if roll < 0.45:
				continue   # (fallen)
			world.walls.place(edge(c, c + d), "BrokenPlankWall" if roll < 0.7 else "PlankWall")
	var cells := inside.keys()
	cells.shuffle()
	for i in beds:
		prop(cells[i], "WoodenBed", rng.randi_range(0, 3))
	prop(cells[beds], "Chest", rng.randi_range(0, 3))


func run() -> void:
	rng.seed = 7741
	seed(7741)
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day()) * 24.0 + 11.0
	var area := Wildlands.WEST_VILLAGE
	# The street, north from the road; a lane across.
	for y in range(area.position.y, area.end.y - 2):
		for x in range(STREET_X - 2, STREET_X + 3):
			paint(Vector2i(x, y), "Dirt")
	for x in range(area.position.x + 3, area.end.x - 3):
		for y in range(109, 112):
			paint(Vector2i(x, y), "Dirt")
	# The houses either side.
	for h in [[Vector2i(-262, 96), 2], [Vector2i(-262, 114), 1], [Vector2i(-262, 120), 2], [Vector2i(-243, 95), 1], [Vector2i(-243, 101), 2], [Vector2i(-243, 116), 2], [Vector2i(-270, 102), 1]]:
		var lo: Vector2i = h[0]
		ruin(lo, lo + Vector2i(4, 4), int(h[1]))
	# The square: a fire long out, the well.
	prop(Vector2i(-247, 112), "Bonfire")
	prop(Vector2i(-254, 107), "Well")
	# Barricades broken down along the south edge, where they came in.
	for x in range(area.position.x + 2, area.end.x - 2, 2):
		if absi(x - STREET_X) <= 3:
			continue
		var e := WallMap.Edge.new(Vector2i(x, area.position.y + 1), false)
		if rng.randf() < 0.55:
			world.walls.place(e, "Barricade")
			world.walls.hp[e.key()] = world.walls.max_hp("Barricade") * rng.randf_range(0.1, 0.35)
	# Rubble about.
	for i in 24:
		var c := Vector2i(rng.randi_range(area.position.x + 2, area.end.x - 3), rng.randi_range(area.position.y + 2, area.end.y - 3))
		if world.floors.laid.has(c) or world.props.cells.has(Vector3i(c.x, c.y, 0)) or absi(c.x - STREET_X) <= 2:
			continue
		world.props.place(c, ["Rocks", "Pebble", "TallGrass", "Bush"][i % 4], 1.0, -1)
	await get_tree().process_frame
	await get_tree().process_frame
	var t := VillageTemplate.capture(world, area, "west_village")
	t["addToSaves"] = true
	for r in t.props:
		if str(r.type) == "Bonfire":
			r["out"] = true   # (long gone out)
	print("West village: ", t.width, "×", t.height, " at ", t.at, ": ", t.floors.size(), " floors, ", t.walls.size(), " walls, ", t.props.size(), " props; roofed rooms ",
		world.props_named("WoodenBed").filter(func(b): return area.has_point(world.floors.cell_at(b)) and world.roofs.room_on(b) != null).size(), "; saved ", VillageTemplate.save(t))
	miko.place(world.floors.cell_centre(Vector2i(STREET_X, 104)))
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_near.png")
	camera.zoom *= 0.45
	miko.place(world.floors.cell_centre(Vector2i(STREET_X, 110)))
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_whole.png")
