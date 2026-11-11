extends Scenario
## Drafts the home village from the blueprint (the one with the elder's house at the top, two houses each side, the
## storage house at the left, the bonfire and well in the middle, the farm at the right, the way in at the bottom;
## two fields, no gates or barricades), builds it in the world at E3/E4/F3/F4, saves it as
## data/villages/home_village.json, and takes pictures. The blueprint's up is the map's +x (up and right on screen),
## its right is -y, so its way in faces the road at x ≈ 0.
## Run with --window=draftvillage.

const W := 32                     ## the blueprint's width (u, rightwards) and height (v, downwards)
const H := 28
const XE := 50                    ## its top edge's x, its left edge's y
const YN := -20

var built := {"floors": 0, "walls": 0, "props": 0}


func cell(u: int, v: int) -> Vector2i:
	return Vector2i(XE - v, YN - u)


# The edge between two neighbouring cells.
func edge(a: Vector2i, b: Vector2i) -> WallMap.Edge:
	var d := b - a
	if d.x == 1: return WallMap.Edge.new(a + Vector2i(1, 0), true)
	if d.x == -1: return WallMap.Edge.new(a, true)
	if d.y == 1: return WallMap.Edge.new(a + Vector2i(0, 1), false)
	return WallMap.Edge.new(a, false)


func floor_at(u: int, v: int, fl: String) -> void:
	world.floors.paint(cell(u, v), fl)
	built.floors += 1


func prop(u: int, v: int, type: String, turn := 0) -> void:
	world.clear_cell(cell(u, v))
	world.props.remove_all(cell(u, v))
	world.props.place(cell(u, v), type, 1.0, turn)
	built.props += 1


## A house over u0..u1, v0..v1 (blueprint cells, both ends in): boards inside, walls round it, a door on [param door]
## ("down", "up", "left", "right") at blueprint cell [param at] along that side; [param broken]: wall cells shown
## broken (the attack).
func house(u0: int, v0: int, u1: int, v1: int, wall: String, boards: String, door: String, at: int, broken := []) -> Array:
	var inside := {}
	for u in range(u0, u1 + 1):
		for v in range(v0, v1 + 1):
			inside[cell(u, v)] = Vector2i(u, v)
			world.clear_cell(cell(u, v))
			world.props.remove_all(cell(u, v))
			world.floors.paint(cell(u, v), boards)
			built.floors += 1
	var dirs := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
	for c in inside:
		var b: Vector2i = inside[c]
		for side in dirs:
			var nb: Vector2i = b + dirs[side]
			if inside.has(cell(nb.x, nb.y)):
				continue
			var e := edge(c, cell(nb.x, nb.y))
			var along := b.x if side in ["up", "down"] else b.y
			var type := wall
			if side == door and along == at:
				type = "WallDoorClosed"
			elif broken.has(Vector2i(b.x, b.y)) and side in broken_sides(b, u0, v0, u1, v1):
				type = "BrokenPlankWall"
			world.walls.place(e, type)
			built.walls += 1
	return inside.keys()


func broken_sides(b: Vector2i, u0: int, v0: int, u1: int, v1: int) -> Array:
	var out := []
	if b.y == v0: out.append("up")
	if b.y == v1: out.append("down")
	if b.x == u0: out.append("left")
	if b.x == u1: out.append("right")
	return out


# A fireplace against a back wall of the house (one of its cells where it can stand), and beds and the rest.
func hearth(cells: Array) -> void:
	var bm := BuildMode.active
	cells.shuffle()
	for c in cells:
		var turn := bm.hearth_turn(c)
		if turn >= 0:
			world.props.place(c, "Fireplace", 1.0, turn)
			built.props += 1
			return


func run() -> void:
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day()) * 24.0 + 11.0
	# The ground first: the plaza round the fire and the well, the paths, the way in to the road.
	for u in range(10, 22):
		for v in range(9, 16):
			floor_at(u, v, "Dirt")
	for u in range(2, 30):
		for v in [9, 10]:
			floor_at(u, v, "Dirt")
	for u in range(5, 25):
		for v in [17, 18]:
			floor_at(u, v, "Dirt")
	for u in range(14, 17):
		for v in range(15, H):
			floor_at(u, v, "Dirt")
	for u in [4, 27]:
		for v in range(8, 9):
			floor_at(u, v, "Dirt")
	for v in range(11, 14):
		floor_at(5, v, "Dirt")
	# (and on out to the road at x ≈ 0)
	var gate := cell(15, H - 1)
	for x in range(2, gate.x):
		for y in range(gate.y - 1, gate.y + 2):
			world.floors.paint(Vector2i(x, y), "Dirt")
			built.floors += 1
	# The houses.
	var elder := house(12, 1, 18, 7, "PlasterWall", "OakBoards", "down", 15)
	var tl := house(2, 3, 6, 7, "PlankWall", "WornBoards", "down", 4, [Vector2i(2, 5)])
	var tright := house(25, 3, 29, 7, "PlankWall", "WornBoards", "down", 27)
	house(1, 11, 4, 14, "DarkPlankWall", "LongBoards", "right", 12)
	var bl := house(6, 19, 10, 23, "PlankWall", "WornBoards", "up", 8)
	var br := house(19, 19, 23, 23, "PlankWall", "WornBoards", "up", 21, [Vector2i(23, 21)])
	for h in [elder, tl, tright, bl, br]:
		hearth(h)
	# Beds: three in the elder's house (the elders, and Miyu), two in each of the others; chests in the store.
	for b in [[13, 2], [17, 2], [17, 6]]:
		prop(b[0], b[1], "WoodenBed", 0)
	for h in [[2, 3], [25, 3], [6, 19], [19, 19]]:
		prop(h[0], h[1] + 1, "WoodenBed", 0)
		prop(h[0] + 3, h[1] + 1, "WoodenBed", 0)
	for c in [[1, 11], [2, 11], [1, 14]]:
		prop(c[0], c[1], "Chest", 0)
	# The middle: the fire, the well, the banner.
	prop(13, 12, "Bonfire")
	prop(18, 12, "Well")
	prop(15, 14, "TownBanner")
	# Two fields at the right.
	for u in range(25, 29):
		for v in range(12, 16):
			prop(u, v, "FarmPlot")
		for v in range(17, 21):
			prop(u, v, "FarmPlot")
	# Torches along the ways.
	for t in [[10, 8], [21, 8], [9, 16], [22, 16], [13, 24], [17, 24], [1, 9], [30, 9], [24, 11], [24, 21]]:
		prop(t[0], t[1], "TallTorch")
	world.village.tier = 2
	await get_tree().process_frame
	await get_tree().process_frame
	# Saved: everything over the blueprint's area, and the way out to the road.
	var lo := Vector2i(2, cell(W - 1, 0).y)
	var hi := Vector2i(XE, cell(0, 0).y)
	var area := Rect2i(lo, hi - lo + Vector2i.ONE)
	var t := VillageTemplate.capture(world, area, "home_village")
	t["tier"] = 2
	print("Draft village: built ", built, "; template ", t.width, "×", t.height, " at ", t.at, ": ", t.floors.size(), " floors, ", t.walls.size(), " walls, ", t.props.size(), " props; saved ", VillageTemplate.save(t))
	# Each house a home (roofed, beds in it)?
	var homes := 0
	var beds := 0
	for b in world.props_named("WoodenBed"):
		if area.has_point(world.floors.cell_at(b)):
			beds += 1
			if world.roofs.room_on(b) != null and world.village.contains(b):
				homes += 1
	print("Draft village: beds ", beds, ", in a roofed room in the village ", homes, "; fireplaces ", world.props_named("Fireplace").filter(func(a): return area.has_point(world.floors.cell_at(a))).size(), "; village contains its corners ", world.village.contains(world.floors.cell_centre(cell(0, 0))), " ", world.village.contains(world.floors.cell_centre(cell(W - 1, H - 1))))
	miko.place(world.floors.cell_centre(cell(15, 16)))
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_near.png")
	camera.zoom *= 0.42
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_whole.png")
