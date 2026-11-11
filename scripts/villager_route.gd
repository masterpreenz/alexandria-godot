class_name VillagerRoute
## A villager's way round walls (from Unity's VillagerRoute): a breadth-first search over the squares between wall
## vertices, crossing only where there's no wall, a doorway, or a door (which they open), and going round the squares
## something solid stands on (furniture, chests, fires, crystals, the cellar's doors, standing trees and rocks), so the
## way planned is one that can be walked, not one that runs them into things for Steer to get them out of. Where
## there's no way that keeps clear of everything, the way through the walls alone is given (and Steer does what it
## can). The way comes back as points to walk through; the ones at doors are kept exactly, so they go straight through
## the opening.
##
## A point: {at (px), exact (walk to it exactly, no cutting the corner), door (a door just ahead: opened here if
## shut), door_edge (its starting edge)}.

const MARGIN := 10
const MOST_SQUARES := 4000
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## The square (between wall vertices) [param p] stands in.
static func square_at(walls: WallMap, p: Vector2) -> Vector2i:
	var c := walls.floors.fractional_cell(p) / float(walls.cells_per_wall)
	return Vector2i(floori(c.x), floori(c.y))


static func square_centre(walls: WallMap, sq: Vector2i) -> Vector2:
	return walls.floors.corner((Vector2(sq) + Vector2(0.5, 0.5)) * walls.cells_per_wall)


## The way from [param from] to [param to] as points (ending at [param to]), or null when walls leave no way through.
static func find(w: World, from: Vector2, to: Vector2) -> Variant:
	var t := Time.get_ticks_usec()
	var r: Variant = _find(w, from, to)
	Perf.add(&"AI: route finding", t)
	return r


static var _wet_squares := {}    ## square -> whether it's water (the rivers and ponds don't move)


# Whether a square is water: no way through (the route goes round, to a bridge or the bank).
static func _wet(w: World, c: Vector2i) -> bool:
	var known: Variant = _wet_squares.get(c)
	if known == null:
		known = w.water_depth(w.floors.cell_centre(c)) > 0.05
		_wet_squares[c] = known
	return known


static var _solid := {}          ## squares something solid stands on
static var _solid_key := ""


## The squares something solid stands on (worked out again when the props, or the trees and rocks, change).
static func solid_squares(w: World) -> Dictionary:
	var key := "%d %d" % [w.props.version, Gatherable.version]
	if key == _solid_key:
		return _solid
	_solid_key = key
	_solid = {}
	var f := w.floors
	for k in w.props.cells:
		var t: Dictionary = w.props.types.get(w.props.cells[k].prop, {})
		if bool(t.get("solid", false)):
			_cover(f, f.cell_centre(Vector2i(k.x, k.y)), float(t.get("footprint", 0.0)) * PropMap._scale(float(w.props.cells[k].scale)))
	for e in w.props.free:
		var t: Dictionary = w.props.types.get(e.prop, {})
		if bool(t.get("solid", false)):
			_cover(f, e.pos, float(t.get("footprint", 0.0)) * PropMap._scale(float(e.get("scale", 1.0))))
	for g in Gatherable.all:
		if is_instance_valid(g) and not g.depleted():
			_solid[f.cell_at(g.foot)] = true
	return _solid


# The squares a solid thing at [param at] with a footprint [param radius] px wide covers: its own, and (a big one)
# those whose middles it reaches.
static func _cover(f: FloorMap, at: Vector2, radius: float) -> void:
	var c := f.cell_at(at)
	_solid[c] = true
	if radius < 70.0:
		return
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			var d: Vector2 = f.cell_centre(n) - at
			if Vector2(d.x, d.y * 2.0).length() < radius:
				_solid[n] = true


static func _find(w: World, from: Vector2, to: Vector2) -> Variant:
	if w.walls == null:
		return null
	# Clear of everything solid if there's such a way; else through the walls alone.
	var way: Variant = _search(w, from, to, solid_squares(w), true)
	return way if way != null else _search(w, from, to, {})


static func _search(w: World, from: Vector2, to: Vector2, solid: Dictionary, dry := false) -> Variant:
	var walls := w.walls
	var a := square_at(walls, from)
	var b := square_at(walls, to)
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y)) - Vector2i.ONE * MARGIN
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) + Vector2i.ONE * MARGIN
	var came := {a: a}
	var open: Array[Vector2i] = [a]
	var head := 0
	var found := a == b
	while head < open.size() and not found and came.size() < MOST_SQUARES:
		var at: Vector2i = open[head]
		head += 1
		for step in STEPS:
			var nxt: Vector2i = at + step
			if nxt.x < lo.x or nxt.y < lo.y or nxt.x > hi.x or nxt.y > hi.y or came.has(nxt):
				continue
			if not passable(walls, crossing(at, step)):
				continue
			# (round what's solid: but where they're going may be right by, or on, such a square)
			if nxt != b and (solid.has(nxt) or (dry and _wet(w, nxt))):
				continue
			came[nxt] = at
			if nxt == b:
				found = true
				break
			open.append(nxt)
	if not found:
		return null
	var squares := []
	var s := b
	while true:
		squares.append(s)
		if s == a:
			break
		s = came[s]
	squares.reverse()
	var points := []
	for i in range(1, squares.size()):
		var step: Vector2i = squares[i] - squares[i - 1]
		var edge := crossing(squares[i - 1], step)
		var cover: Array = walls.covering(edge)
		if cover[0] != "":
			# A doorway: just before it, through its middle, just past it.
			var mid := walls.edge_middle(edge)
			var before := square_centre(walls, squares[i - 1])
			var after := square_centre(walls, squares[i])
			var is_door: bool = walls.types[cover[0]].toggle != ""
			points.append({"at": mid.lerp(before, 0.45), "exact": true, "door": is_door, "door_edge": cover[1]})
			points.append({"at": mid, "exact": true, "door": false})
			points.append({"at": mid.lerp(after, 0.45), "exact": true, "door": false})
		elif i < squares.size() - 1:
			points.append({"at": square_centre(walls, squares[i]), "exact": false, "door": false})
	points.append({"at": to, "exact": true, "door": false})
	return points


## The grid edge crossed going from [param square] by [param step].
static func crossing(square: Vector2i, step: Vector2i) -> WallMap.Edge:
	if step.x > 0: return WallMap.Edge.new(square + Vector2i(1, 0), true)
	if step.x < 0: return WallMap.Edge.new(square, true)
	if step.y > 0: return WallMap.Edge.new(square + Vector2i(0, 1), false)
	return WallMap.Edge.new(square, false)


## No wall, a doorway (an opening), or a door they can open.
static func passable(walls: WallMap, edge: WallMap.Edge) -> bool:
	var t: String = walls.get_wall(edge)
	if t == "":
		return true
	var type: Dictionary = walls.types[t]
	if float(type.opening) > 0.0:
		return true
	var toggled: String = type.toggle
	return toggled != "" and walls.types.has(toggled) and float(walls.types[toggled].opening) > 0.0


## Whether the door starting at [param edge] is shut (and can be opened).
static func is_closed_door(walls: WallMap, edge: WallMap.Edge) -> bool:
	var t: String = walls.walls.get(edge.key(), "")
	if t == "":
		return false
	var type: Dictionary = walls.types[t]
	var toggled: String = type.toggle
	return float(type.opening) <= 0.0 and toggled != "" and walls.types.has(toggled) and float(walls.types[toggled].opening) > 0.0


## Whether the door starting at [param edge] stands open (and can be shut).
static func is_open_door(walls: WallMap, edge: WallMap.Edge) -> bool:
	var t: String = walls.walls.get(edge.key(), "")
	if t == "":
		return false
	var type: Dictionary = walls.types[t]
	var toggled: String = type.toggle
	return float(type.opening) > 0.0 and toggled != "" and walls.types.has(toggled) and float(walls.types[toggled].opening) <= 0.0


## The doors of a room (its cells): [Edge] starting edges.
static func doors_of(walls: WallMap, cells: Dictionary) -> Array:
	var out := []
	var seen := {}
	for c in cells:
		for step in STEPS:
			if cells.has(c + step):
				continue
			var e := crossing(c, step)
			var cover: Array = walls.covering(e)
			if cover[0] == "" or walls.types[cover[0]].toggle == "":
				continue
			var start: WallMap.Edge = cover[1]
			if not seen.has(start.key()):
				seen[start.key()] = true
				out.append(start)
	return out
