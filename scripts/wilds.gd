class_name Wilds
## The open world outside the village, for the creatures in it (from Unity's Wilds, and Corruption's healthy forest):
## where there's open ground to stand (not in the village, a house, water or anything solid), where there's grass,
## where the trees are, and which woods are healthy (grass all round, trees close together) for the wildlife.
## (Corrupted trees come with corruption: until then every wood counts as healthy.)

const GRID := 4.0 * 128.0          ## px: trees are kept by squares this size, so "trees near here" is quick

static var _grid := {}             ## Vector2i -> [Vector2] tree feet
static var _grid_count := -1
static var _grid_at := -99.0
static var _circle: CircleShape2D


## Open ground: on the map, outside the village (and [param village_margin] tiles beyond it), not under a roof, not
## water, nothing solid within [param clearance] units.
static func open(w: World, at: Vector2, village_margin := 0.5, clearance := 0.35) -> bool:
	if not w.floors.in_bounds(w.floors.cell_at(at)):
		return false
	if w.village.contains(at, village_margin):
		return false
	if w.roofs != null and w.roofs.covers(at):
		return false
	if not dry(w, at):
		return false
	if _circle == null:
		_circle = CircleShape2D.new()
	_circle.radius = clearance * w.px
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _circle
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1  # the fixed world, not creatures or Miko
	return w.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


## No water at [param at] nor within [param margin] units round it: off the river and back from its banks.
static func dry(w: World, at: Vector2, margin := 0.7) -> bool:
	if w.water_depth(at) > 0.0:
		return false
	for i in 8:
		var a := i * TAU / 8.0
		if w.water_depth(at + Vector2(cos(a), sin(a) * 0.5) * margin * w.px) > 0.0:
			return false
	return true


## No water along the way from [param from] to [param to] (looked at every half unit): a walk that doesn't cross a river.
static func dry_way(w: World, from: Vector2, to: Vector2) -> bool:
	var steps := maxi(1, ceili(from.distance_to(to) / (0.5 * w.px)))
	for i in steps + 1:
		if w.water_depth(from.lerp(to, float(i) / steps)) > 0.0:
			return false
	return true


## On grass, with no path or floor laid over it.
static func vegetation(w: World, at: Vector2) -> bool:
	var cell := w.floors.cell_at(at)
	if w.floors.get_laid(cell) != "":
		return false
	return w.floors.get_floor(cell).contains("Grass")


## A random spot on the map passing [param ok] (a Callable taking the spot), or null.
static func find_spot(w: World, ok: Callable, tries := 80) -> Variant:
	var b: Rect2i = w.floors.bounds
	for i in tries:
		var cell := Vector2i(randi_range(b.position.x + 2, b.end.x - 3), randi_range(b.position.y + 2, b.end.y - 3))
		if not w.floors.in_bounds(cell):
			continue
		var spot := w.floors.cell_centre(cell)
		if ok.call(spot):
			return spot
	return null


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.y / GRID))


# Rebuilt when trees come or go, and now and then anyway.
static func _ensure_grid() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if Gatherable.all.size() == _grid_count and now < _grid_at + 15.0:
		return
	_grid_count = Gatherable.all.size()
	_grid_at = now
	_grid.clear()
	for g in Gatherable.all:
		if g.axe and not g.depleted():
			var k := _key(g.foot)
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(g.foot)


## The trees standing within [param radius] px of [param at].
static func trees_near(at: Vector2, radius: float) -> Array:
	_ensure_grid()
	var out := []
	var lo := _key(at - Vector2(radius, radius))
	var hi := _key(at + Vector2(radius, radius))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for t in _grid.get(Vector2i(x, y), []):
				if t.distance_squared_to(at) <= radius * radius:
					out.append(t)
	return out


## A sheltered spot in the nearest wood to [param from]: beside a tree with at least [param neighbours] others close
## round it (else beside the nearest tree); null if there are no trees in [param range] units.
static func forest(w: World, from: Vector2, neighbours := 2, reach := 25.0) -> Variant:
	var trees := trees_near(from, reach * w.px)
	var best: Variant = null
	var best_d := INF
	var fallback: Variant = null
	var fallback_d := INF
	for t in trees:
		var d: float = t.distance_to(from)
		if w.village.contains(t, 1.0):
			continue
		if d < fallback_d:
			fallback_d = d
			fallback = t
		if d >= best_d:
			continue
		if trees_near(t, 3.2 * w.px).size() - 1 >= neighbours:
			best_d = d
			best = t
	var pick: Variant = best if best != null else fallback
	if pick == null:
		return null
	# Tucked in beside the tree, somewhere it fits.
	for i in 12:
		var a := randf() * TAU
		var r := randf_range(0.6, 1.2) * w.px
		var at: Vector2 = pick + Vector2(cos(a) * r, sin(a) * r * 0.5)
		if open(w, at, 1.0, 0.3):
			return at
	return pick + Vector2(0, 0.7 * w.px)


## Forest floor: grass all round (not by a road or path), outside the village.
static func forest_floor(w: World, at: Vector2) -> bool:
	if not vegetation(w, at) or w.village.contains(at, 3.0):
		return false
	for i in 6:
		var a := i * PI / 3.0
		if not vegetation(w, at + Vector2(cos(a) * 1.6, sin(a) * 0.8) * w.px):
			return false
	return true


## Healthy forest, where the wildlife lives: forest floor with at least [param min_trees] trees within [param reach]
## units (and, once corruption comes over, few of them rotten).
static func healthy_forest(w: World, at: Vector2, min_trees := 4, reach := 4.5) -> bool:
	if not Corruption.ready() or not forest_floor(w, at):
		return false
	var trees := trees_near(at, reach * w.px).size()
	if trees < min_trees:
		return false
	var rot := Corruption.active.corrupted_near(at, reach * w.px) if Corruption.active != null else 0
	@warning_ignore("integer_division")
	return rot <= trees / 4
