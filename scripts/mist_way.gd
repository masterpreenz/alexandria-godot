class_name MistWay
## A way between two spots on cleared ground that keeps out of the mist: over the mist's own map, round every misty
## bit, the corners cut wherever the straight line between stays clear. What a villager walks when the mist lies
## between them and where they're going (a hunter home from a crystal's clearing, a hauler round a tongue of mist).

const AROUND := 20.0               ## units round the two spots the way may wander to
const MOST_CELLS := 40000          ## past this the search isn't tried (far too far apart)


## The points to walk through, the last of them [param to]; empty when there's no way on cleared ground.
static func find(w: World, from: Vector2, to: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var mist := w.mist
	if mist == null:
		return out
	var __t := Time.get_ticks_usec()
	var cs := mist.cell
	var box := Rect2(from, Vector2.ZERO).expand(to).grow(AROUND * w.px)
	var x0 := floori((box.position.x - mist.rect.position.x) / cs)
	var y0 := floori((box.position.y - mist.rect.position.y) / cs)
	var x1 := ceili((box.end.x - mist.rect.position.x) / cs)
	var y1 := ceili((box.end.y - mist.rect.position.y) / cs)
	if (x1 - x0) * (y1 - y0) > MOST_CELLS:
		return out
	var g := AStarGrid2D.new()
	g.region = Rect2i(x0, y0, x1 - x0, y1 - y0)
	g.cell_size = Vector2(cs, cs)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	var start := _cell_of(mist, from)
	var end := _cell_of(mist, to)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := Vector2i(x, y)
			if c != start and c != end and mist.tier_at(_middle(mist, c)) != Mist.Tier.CLEAR:
				g.set_point_solid(c, true)
	if not g.region.has_point(start) or not g.region.has_point(end):
		return out
	var cells := g.get_id_path(start, end)
	if cells.is_empty():
		Perf.add(&"villager: a way round the mist", __t)
		return out
	# The corners cut: on from each point to the furthest one still in a straight, clear line.
	var pts: Array[Vector2] = [from]
	for i in range(1, cells.size() - 1):
		pts.append(_middle(mist, cells[i]))
	pts.append(to)
	var at := 0
	while at < pts.size() - 1:
		var next := at + 1
		for j in range(pts.size() - 1, at + 1, -1):
			if _clear_line(w, pts[at], pts[j]):
				next = j
				break
		out.append(pts[next])
		at = next
	Perf.add(&"villager: a way round the mist", __t)
	return out


static func _cell_of(mist: Mist, p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - mist.rect.position.x) / mist.cell), floori((p.y - mist.rect.position.y) / mist.cell))


static func _middle(mist: Mist, c: Vector2i) -> Vector2:
	return mist.rect.position + (Vector2(c) + Vector2(0.5, 0.5)) * mist.cell


static func _clear_line(w: World, a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / (0.3 * w.px)))
	for k in range(1, steps):
		if not Villager.safe_ground(w, a.lerp(b, k / float(steps))):
			return false
	return true
