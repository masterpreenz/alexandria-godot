class_name UseSpots
## Each bed and chest has its own way in (from Unity's UseSpots): one tile beside it where villagers stand to use it. A
## bed's is on its right, as it lies (else another side with no wall or anything solid in the way); a chest's is in
## front of it (the side its lock faces), always.


# A grid step for each way a bed can face (its foot's diagonal on screen): turn 0 down-left, 1 down-right, 2 up-right,
# 3 up-left.
static func _along(turn: int) -> Vector2i:
	match turn:
		0: return Vector2i(-1, 0)
		1: return Vector2i(0, -1)
		2: return Vector2i(1, 0)
	return Vector2i(0, 1)


static func _right_of(a: Vector2i) -> Vector2i:
	return Vector2i(a.y, -a.x)


# Something solid standing at [param p] (the fixed world's colliders).
static func _solid(w: World, p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = 0.15 * w.px
	q.shape = c
	q.transform = Transform2D(0.0, p)
	q.collision_mask = 1
	return not w.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


# The grid edge between two side-by-side tiles, or null.
static func _between(a: Vector2i, b: Vector2i) -> Variant:
	var d := b - a
	if d == Vector2i(1, 0): return WallMap.Edge.new(b, true)
	if d == Vector2i(-1, 0): return WallMap.Edge.new(a, true)
	if d == Vector2i(0, 1): return WallMap.Edge.new(b, false)
	if d == Vector2i(0, -1): return WallMap.Edge.new(a, false)
	return null


# The first of the sides with no wall between it and [param on] and nothing solid on it; the first if none is.
static func _pick(w: World, on: Vector2i, sides: Array) -> Vector2i:
	for d in sides:
		var cell: Vector2i = on + d
		var e: Variant = _between(on, cell)
		if w.walls != null and e != null:
			var t: String = w.walls.get_wall(e)
			if t != "" and float(w.walls.types[t].opening) < 1.0:
				continue
		if _solid(w, w.floors.cell_centre(cell)):
			continue
		return cell
	return on + sides[0]


## The tile a bed (Needs.all_beds' entry) is used from.
static func bed_cell(w: World, bed: Dictionary) -> Vector2i:
	var on := w.floors.cell_at(bed.pos)
	var along := _along(int(bed.e.turn))
	var right := _right_of(along)
	return _pick(w, on, [right, -right, along, -along])


## Where to stand to use a bed: the middle of its way-in tile, or null if that can't be stood on.
static func bed_spot(w: World, bed: Dictionary) -> Variant:
	var p := w.floors.cell_centre(bed_cell(w, bed))
	return null if _solid(w, p) else p


## The tile a chest at [param at] (set down at [param turn]) is used from: in front of it, where its lock faces.
static func chest_cell(w: World, at: Vector2, turn: int) -> Vector2i:
	return w.floors.cell_at(at) + (Vector2i(-1, 0) if turn % 2 == 0 else Vector2i(0, -1))


## Where to stand at the nearest chest in the village to [param from] (its way in, else beside it), or null.
static func nearest_chest_spot(w: World, from: Vector2) -> Variant:
	var best: Variant = null
	var best_d := INF
	for c in w.props.entries_named("Chest"):
		if not w.village.contains(c.pos):
			continue
		var dd: float = c.pos.distance_to(from)
		if dd >= best_d:
			continue
		var p := w.floors.cell_centre(chest_cell(w, c.pos, int(c.e.turn)))
		if _solid(w, p):
			p = c.pos + Vector2(0, 0.5 * w.px)
		best_d = dd
		best = p
	return best
