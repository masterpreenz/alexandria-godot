class_name WallMap
extends Node
## The world's walls (from Unity's WallMap), built along grid lines through this API by build mode, level design or
## game logic. A wall vertex sits every [member cells_per_wall] cells; a wall starts at a vertex and runs its type's
## length in edges along +x ("/") or +y ("\"), keyed by its start edge.
##
## Walls block movement along their line, except a door's opening. A door is a wall type with a toggle (its open or
## closed twin). A panel wall is one sprite standing on the wall's middle; it shows the end of its boards (its cap)
## only where no wall runs on into its start. Pieces sort at their ground centres, among everything else standing.

signal wall_changed(edge: Edge, type: String)

## A wall's place: its start vertex and whether it runs along y instead of x.
class Edge:
	var vertex: Vector2i
	var along_y: bool

	func _init(v: Vector2i, y: bool) -> void:
		vertex = v
		along_y = y

	func end() -> Vector2i:
		return vertex + (Vector2i(0, 1) if along_y else Vector2i(1, 0))

	func key() -> Vector3i:
		return Vector3i(vertex.x, vertex.y, 1 if along_y else 0)

	static func of(k: Vector3i) -> Edge:
		return Edge.new(Vector2i(k.x, k.y), k.z == 1)


var world: World
var floors: FloorMap
var types := {}            ## name -> wall type (sprites, panels, length, opening, toggle, ...)
var cells_per_wall := 1
var thickness := 7.68
## Goes up whenever any wall changes, for things that rebuild from the whole map.
var version := 0
## Goes up when walls are placed or taken away (not when a door swings): the rooms (and their roofs) change only then.
var rooms_version := 0

var walls := {}            # Vector3i (edge key) -> type name
var hp := {}               # Vector3i (edge key) -> health left, for walls that can break (barricades)
var _hit_at := {}          # key -> when it was last struck (it flashes)
const DOOR_OUTLINE_NEAR := 3.0  ## units: a door hidden behind a house is outlined only with Miko this near
var _bars: HealthBars      # the health bars over worn barricades and gates
var keep_open := {}        # Vector3i -> true: doors of houses set to stay open
var original := {}
var _drawn := {}           # Vector3i -> {holders: [Node2D], body: StaticBody2D}


func setup(w: World, f: FloorMap, data: Dictionary) -> void:
	world = w
	floors = f
	_bars = HealthBars.new()
	_bars.map = self
	w.add_child.call_deferred(_bars)
	cells_per_wall = int(data.cellsPerWall)
	thickness = data.thickness
	for t in data.types:
		types[t.name] = t
	for b in data.built:
		walls[Vector3i(int(b.x), int(b.y), 1 if b.alongY else 0)] = b.type
	original = walls.duplicate()


# ---- Geometry ----

static func _dir(along_y: bool) -> Vector2i:
	return Vector2i(0, 1) if along_y else Vector2i(1, 0)


## World position of a wall vertex, on the ground.
func vertex_position(v: Vector2i) -> Vector2:
	return floors.corner(Vector2(v * cells_per_wall))


## The vertex where a wall of [param type] starting at [param e] ends.
func span_end(e: Edge, type: String) -> Vector2i:
	return e.vertex + _dir(e.along_y) * (int(types[type].length) if types.has(type) else 1)


## The wall vertex nearest [param p].
func vertex_at(p: Vector2) -> Vector2i:
	var c := floors.fractional_cell(p) / cells_per_wall
	return Vector2i(roundi(c.x), roundi(c.y))


## The middle of a grid edge, on the ground.
func edge_middle(e: Edge) -> Vector2:
	return (vertex_position(e.vertex) + vertex_position(e.end())) / 2.0


# ---- Reading ----

## The wall covering [param e] (its own, or one that runs on through it), and the edge it starts on; "" if none.
func covering(e: Edge) -> Array:
	for back in 4:
		var start := Edge.new(e.vertex - _dir(e.along_y) * back, e.along_y)
		if walls.has(start.key()):
			var t: String = walls[start.key()]
			return [t, start] if int(types[t].length) > back else ["", e]
	return ["", e]


func get_wall(e: Edge) -> String:
	return covering(e)[0]


## Whether the door starting at [param start] stands open.
func is_open(start: Edge) -> bool:
	var t: String = walls.get(start.key(), "")
	return t != "" and types[t].toggle != "" and float(types[t].opening) > 0.0


func kept_open(start: Edge) -> bool:
	return keep_open.has(start.key())


func set_kept_open(start: Edge, on: bool) -> void:
	if on: keep_open[start.key()] = true
	else: keep_open.erase(start.key())


## The door (a wall with a toggle) whose middle is nearest [param p], within [param range]: [edge, type] or [].
func nearest_door(p: Vector2, reach: float) -> Array:
	var best := reach
	var found := []
	var around := vertex_at(p)
	for x in range(around.x - 3, around.x + 4):
		for y in range(around.y - 3, around.y + 4):
			for k in 2:
				var e := Edge.new(Vector2i(x, y), k == 1)
				var t: String = walls.get(e.key(), "")
				if t == "" or types[t].toggle == "":
					continue
				var d := ((vertex_position(e.vertex) + vertex_position(span_end(e, t))) / 2.0).distance_to(p)
				if d < best:
					best = d
					found = [e, t]
	return found


# ---- Building ----

## Opens or closes the door starting at [param e].
func toggle(e: Edge) -> void:
	var t: String = walls.get(e.key(), "")
	if t == "" or types[t].toggle == "":
		return
	walls[e.key()] = types[t].toggle
	var rooms := rooms_version
	_changed(e)
	rooms_version = rooms  # a door swinging doesn't change the rooms


func place(e: Edge, type: String) -> void:
	if type == "":
		remove(e)
		return
	if walls.get(e.key(), "") == type:
		return
	for i in int(types[type].length):
		remove(Edge.new(e.vertex + _dir(e.along_y) * i, e.along_y))
	walls[e.key()] = type
	if max_hp(type) > 0.0:
		hp[e.key()] = max_hp(type)
	_changed(e)


# ---- Barricades: walls with health (walls.json's hp), worn down by monsters and broken when it runs out ----

## The health a wall of [param type] starts with, or 0 for one that can't be broken.
func max_hp(type: String) -> float:
	return float(types.get(type, {}).get("hp", 0.0))


## Hits the wall starting at [param k] (a key) for [param amount]; when its health runs out it breaks and is gone.
func damage(k: Vector3i, amount: float) -> void:
	if not walls.has(k) or not hp.has(k):
		return
	var e := Edge.of(k)
	var mid := wall_middle(k)
	hp[k] = float(hp[k]) - amount
	_bars.queue_redraw()
	FloatingText.spawn(world, str(roundi(amount)), mid + Vector2(0, -0.9 * world.px), Color(1.0, 0.75, 0.45))
	_hit_at[k] = Time.get_ticks_msec() / 1000.0
	for n in nodes_of(e):
		if is_instance_valid(n) and n.get_child_count() > 0:
			(n.get_child(0) as CanvasItem).self_modulate = Color(1.0, 0.7, 0.6)
	if float(hp[k]) <= 0.0:
		Puffs.burst(world, mid, 1.4, 14)
		VillageLog.event("barricade", "A %s was broken down" % str(types[walls[k]].get("display", walls[k])).to_lower())
		remove(e)


## Sets the health of the wall starting at [param k] (a repair), up to its most.
func set_hp(k: Vector3i, value: float) -> void:
	if walls.has(k) and hp.has(k):
		hp[k] = clampf(value, 0.0, max_hp(walls[k]))
		_bars.queue_redraw()


## The middle of the whole wall starting at [param k] (a key), however many cells long.
func wall_middle(k: Vector3i) -> Vector2:
	var e := Edge.of(k)
	return (vertex_position(e.vertex) + vertex_position(span_end(e, walls.get(k, "")))) / 2.0


## The barricade (a wall with health) in the way from [param from] to [param to], or within [param near] px of
## [param from] facing that way: [key, the nearest point on it], or [].
func barricade_in_way(from: Vector2, to: Vector2, near: float) -> Array:
	var best := []
	var best_d := INF
	for k in hp:
		if not walls.has(k) or is_open(Edge.of(k)):   # (an open gate: through it)
			continue
		var e := Edge.of(k)
		var a := vertex_position(e.vertex)
		var b := vertex_position(span_end(e, walls[k]))
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, a, b)
		var p: Vector2 = hit if hit != null else Geometry2D.get_closest_point_to_segment(from, a, b)
		var d := from.distance_to(p)
		if hit == null and (d > near or (to - from).dot(p - from) < 0.0):
			continue
		if d < best_d:
			best_d = d
			best = [k, p]
	return best


# The walls struck lately flash back to their colour.
func _process(_delta: float) -> void:
	if _hit_at.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for k in _hit_at.keys():
		if now - float(_hit_at[k]) < 0.15:
			continue
		_hit_at.erase(k)
		if walls.has(k):
			for n in nodes_of(Edge.of(k)):
				if is_instance_valid(n) and n.get_child_count() > 0:
					(n.get_child(0) as CanvasItem).self_modulate = Color.WHITE


## Removes the wall covering [param e].
func remove(e: Edge) -> void:
	var c := covering(e)
	if c[0] == "":
		return
	var start: Edge = c[1]
	var end := span_end(start, c[0])
	walls.erase(start.key())
	hp.erase(start.key())
	_bars.queue_redraw()
	_changed(start, end)


func _changed(e: Edge, end: Variant = null) -> void:
	version += 1
	rooms_version += 1
	var t := get_wall(e)
	var stop: Vector2i = end if end != null else span_end(e, t if t != "" else "")
	_sync(e)
	for v in [e.vertex, stop]:
		for other in _at(v):
			_sync(other)
	wall_changed.emit(e, get_wall(e))


## The four grid lines that meet at a vertex.
static func _at(v: Vector2i) -> Array:
	return [Edge.new(v, false), Edge.new(v - Vector2i(1, 0), false), Edge.new(v, true), Edge.new(v - Vector2i(0, 1), true)]


# ---- Saving ----

func to_json() -> String:
	var out := []
	for k in walls:
		out.append({"x": k.x, "y": k.y, "alongY": k.z == 1, "type": walls[k]})
	var open := []
	for k in keep_open:
		if walls.has(k):
			open.append({"x": k.x, "y": k.y, "alongY": k.z == 1})
	var worn := []
	for k in hp:
		if walls.has(k) and float(hp[k]) < max_hp(walls[k]):
			worn.append({"x": k.x, "y": k.y, "alongY": k.z == 1, "hp": hp[k]})
	return JSON.stringify({"walls": out, "world": FloorMap.WORLD_VERSION, "keepOpen": open, "worn": worn})


func from_json(json: String) -> void:
	var data: Dictionary = JSON.parse_string(json)
	walls.clear()
	hp.clear()
	for w in data.get("walls", []):
		if types.has(w.type):
			var k := Vector3i(int(w.x), int(w.y), 1 if w.alongY else 0)
			walls[k] = w.type
			if max_hp(w.type) > 0.0:
				hp[k] = max_hp(w.type)
	for w in data.get("worn", []):
		var k := Vector3i(int(w.x), int(w.y), 1 if w.alongY else 0)
		if hp.has(k):
			hp[k] = float(w.hp)
	_bars.queue_redraw()
	keep_open.clear()
	for k in data.get("keepOpen", []):
		keep_open[Vector3i(int(k.x), int(k.y), 1 if k.alongY else 0)] = true
	# Walls the scene has gained since this save was made (the ruined farmhouse): put in.
	var w := int(data.get("world", 0))
	for k in original:
		if FloorMap.added_since(Vector2i(k.x, k.y) * cells_per_wall, w):
			walls[k] = original[k]
	rebuild()


# ---- Drawing ----

func rebuild() -> void:
	version += 1
	rooms_version += 1
	for k in _drawn.keys():
		_clear(k)
	for k in walls:
		_sync(Edge.of(k))


func _clear(k: Vector3i) -> void:
	var d: Dictionary = _drawn.get(k, {})
	for h in d.get("holders", []):
		h.queue_free()
	if d.has("body"):
		d.body.queue_free()
	_drawn.erase(k)


func _sync(e: Edge) -> void:
	var k := e.key()
	_clear(k)
	var t: String = walls.get(k, "")
	if t == "":
		return
	var type: Dictionary = types[t]
	var a := vertex_position(e.vertex)
	var b := vertex_position(span_end(e, t))
	var mid := (a + b) / 2.0
	# Along x the art's left half runs to the start vertex; along y the art is mirrored (unless it has its own y art).
	var own_y: bool = e.along_y and int(type.leftY) >= 0
	var starts := get_wall(Edge.new(e.vertex - _dir(e.along_y), e.along_y)) == ""
	var cap_art := int(type.capY if own_y else type.cap)
	var panels: bool = type.panels
	var start_art: int = cap_art if panels and starts and cap_art >= 0 else int(type.leftY if own_y else type.left)
	var holders := []
	if not type.invisible:
		_half(holders, start_art, e.along_y and not own_y, mid if panels else (a + mid) / 2.0, mid, panels)
		if not panels:
			_half(holders, int(type.rightY if own_y else type.right), e.along_y and not own_y, (b + mid) / 2.0, mid, false)
	# A door: findable when the house hides it (an outline over what's in front, as for a character behind something).
	if str(type.get("toggle", "")) != "":
		for h in holders:
			var art: Sprite2D = h.get_child(0)
			var o := OccludedOutline.new()
			o.name = "DoorOutline"
			o.fade_covers = false
			h.add_child(o)
			# Hidden when the room in front of it (lower on screen) has its roof showing (a door in a house's back wall),
			# and unless Miko is near it.
			var front_cell := _front_cell(e)
			var door_at: Vector2 = mid
			o.hidden_when = func() -> bool: return (world.player == null or world.player.position.distance_to(door_at) > DOOR_OUTLINE_NEAR * world.px) \
					or (world.roofs != null and world.roofs.alpha_over(world.floors.cell_centre(front_cell)) > 0.5)
			o.setup(world, art, Color(1.0, 0.86, 0.55, 1))
	var drawn := {"holders": holders}
	if float(type.opening) < 1.0:
		# The blocking line; with an opening, two pieces either side of it.
		var body := StaticBody2D.new()
		body.name = "Wall"
		var gap := clampf(float(type.opening), 0.0, 1.0)
		var half := (b - a) / 2.0
		var pieces := [[-half, half]] if gap <= 0.0 else [[-half, -half * gap], [half * gap, half]]
		for p in pieces:
			var shape := CollisionShape2D.new()
			var cap := CapsuleShape2D.new()
			var along: Vector2 = p[1] - p[0]
			cap.radius = thickness
			cap.height = along.length() + thickness * 2.0
			shape.shape = cap
			shape.position = mid + (p[0] + p[1]) / 2.0
			shape.rotation = along.angle() - PI / 2.0
			body.add_child(shape)
		world.add_child(body)
		drawn["body"] = body
	_drawn[k] = drawn


## The art a wall of [param type] would stand at edge [param e] with, for a ghost of it while placing: [[sprite, mirrored,
## where its pivot goes (px)]]. Nothing for an invisible wall.
func ghost_pieces(e: Edge, type_name: String) -> Array:
	if not types.has(type_name):
		return []
	var type: Dictionary = types[type_name]
	if type.invisible:
		return []
	var mid := (vertex_position(e.vertex) + vertex_position(span_end(e, type_name))) / 2.0
	var own_y: bool = e.along_y and int(type.leftY) >= 0
	var flip: bool = e.along_y and not own_y
	var panels: bool = type.panels
	var cap_art := int(type.capY if own_y else type.cap)
	var starts := get_wall(Edge.new(e.vertex - _dir(e.along_y), e.along_y)) == ""
	var out := [[cap_art if panels and starts and cap_art >= 0 else int(type.leftY if own_y else type.left), flip, mid]]
	if not panels:
		out.append([int(type.rightY if own_y else type.right), flip, mid])
	return out.filter(func(p): return int(p[0]) >= 0)


# Of the two cells a wall at [param e] stands between, the one in front (lower on screen).
func _front_cell(e: Edge) -> Vector2i:
	var v := e.vertex
	var a := Vector2i(v.x - 1, v.y) if e.along_y else Vector2i(v.x, v.y - 1)
	return a if floors.cell_centre(a).y > floors.cell_centre(v).y else v


# A piece of wall art: at the wall's middle (a whole wall's halves pivot there; a panel stands on its own centre),
# sorting at its ground centre among everything standing.
func _half(into: Array, sprite_id: int, flip: bool, ground_centre: Vector2, mid: Vector2, centred: bool) -> void:
	if sprite_id < 0:
		return
	var holder := Node2D.new()
	holder.position = ground_centre
	var sprite := Sprite2D.new()
	world.show_frame(sprite, sprite_id, Vector2(-1 if flip else 1, 1))
	sprite.material = world.snow_material(0)
	sprite.position = (ground_centre if centred else mid) - ground_centre
	holder.add_child(sprite)
	world.things.add_child(holder)
	world.add_occluder(sprite)
	into.append(holder)


## Where something standing at [param foot], [param half_width] wide on screen, should sort (from Unity's
## SortAgainstWalls): over any wall it stands in front of and under any wall it stands behind. A wall is long and
## sloped, so sorting by one point of it goes wrong near its ends; this asks which side of the wall's line it's on.
func sort_against_walls(foot: Vector2, half_width: float, sort_y: float) -> float:
	var above := -INF
	var below := INF
	var around := vertex_at(foot)
	for x in range(around.x - 3, around.x + 4):
		for y in range(around.y - 3, around.y + 4):
			for k in 2:
				var e := Edge.new(Vector2i(x, y), k == 1)
				var t: String = walls.get(e.key(), "")
				if t == "":
					continue
				var a := vertex_position(e.vertex)
				var b := vertex_position(span_end(e, t))
				if a.x > b.x:
					var swap := a
					a = b
					b = swap
				if foot.x + half_width <= a.x or foot.x - half_width >= b.x:
					continue
				var line_y := lerpf(a.y, b.y, inverse_lerp(a.x, b.x, foot.x)) if b.x != a.x else (a.y + b.y) / 2.0
				# Its pieces sort at their ground centres: one panel, or two halves.
				var mid := (a + b) / 2.0
				var front: float = mid.y if types[t].panels else maxf((a.y + mid.y) / 2.0, (b.y + mid.y) / 2.0)
				var back: float = mid.y if types[t].panels else minf((a.y + mid.y) / 2.0, (b.y + mid.y) / 2.0)
				if foot.y > line_y:
					above = maxf(above, front + 1.28)
				else:
					below = minf(below, back - 1.28)
	# Where both can't hold (a narrow room), hiding behind the nearer wall wins.
	if above > below:
		return below
	return clampf(sort_y, above, below)


## How see-through the wall covering [param e] is drawn (1 solid), e.g. to show what's inside a room.
func set_alpha(e: Edge, alpha: float) -> void:
	var c := covering(e)
	if c[0] == "":
		return
	for h in _drawn.get((c[1] as Edge).key(), {}).get("holders", []):
		for s in h.get_children():
			if s is Sprite2D and not is_equal_approx(s.modulate.a, alpha):
				s.modulate.a = alpha


# ---- Building (build mode) ----

## The grid edge nearest [param p]; with [param keep_along_y] (true or false) it keeps that way until the other line
## is clearly nearer by [param padding] cells.
func edge_at(p: Vector2, keep_along_y: Variant = null, padding := 0.0) -> Edge:
	var c := floors.fractional_cell(p) / cells_per_wall
	var to_x_line := absf(c.y - roundf(c.y))
	var to_y_line := absf(c.x - roundf(c.x))
	var on_x: bool
	if keep_along_y == null: on_x = to_x_line <= to_y_line
	elif keep_along_y: on_x = to_x_line + padding < to_y_line
	else: on_x = to_x_line <= to_y_line + padding
	if on_x:
		return Edge.new(Vector2i(floori(c.x), roundi(c.y)), false)
	return Edge.new(Vector2i(roundi(c.x), floori(c.y)), true)


func in_bounds(e: Edge) -> bool:
	return floors.in_bounds(floors.cell_at(edge_middle(e) + Vector2(0, -0.05 * world.px)))


## Whether [param type] may go on [param e]: in bounds, and no door or window would end up at a corner or junction.
func can_place(e: Edge, type: String) -> bool:
	if not types.has(type):
		return false
	var n := int(types[type].length)
	for i in n:
		if not in_bounds(Edge.new(e.vertex + _dir(e.along_y) * i, e.along_y)):
			return false
	for v in [e.vertex, span_end(e, type)]:
		for other in _at(v):
			var there: String = covering(other)[0]
			if there == "" or other.along_y == e.along_y:
				continue
			if bool(types[type].keepOffCorners) or bool(types[there].keepOffCorners):
				return false
	return true


## The walls whose middle lies in [param cell].
func edges_in(cell: Vector2i) -> Array:
	var out := []
	var lo := Vector2i(floori((cell.x - 1.0) / cells_per_wall), floori((cell.y - 1.0) / cells_per_wall))
	for x in range(lo.x, lo.x + 3):
		for y in range(lo.y, lo.y + 3):
			for along_y in [false, true]:
				var e := Edge.new(Vector2i(x, y), along_y)
				if floors.cell_at(edge_middle(e) + Vector2(0, -0.05 * world.px)) == cell:
					out.append(e)
	return out


## Puts the wall on [param e] back to how the map loaded.
func restore(e: Edge) -> void:
	if original.has(e.key()):
		place(e, original[e.key()])
		return
	var c := covering(e)
	if c[0] != "" and not original.has((c[1] as Edge).key()):
		remove(e)


## The drawn pieces of the wall starting on [param e] (for the drop-in), or [].
func nodes_of(e: Edge) -> Array:
	return _drawn.get(e.key(), {}).get("holders", [])


## Every drawn wall piece (for hiding them while building).
func all_nodes() -> Array:
	var out := []
	for d in _drawn.values():
		out.append_array(d.get("holders", []))
	return out


## A bar over each barricade or gate that's been worn down (none over one at full health): how much is left of it.
## Bright whatever the hour.
class HealthBars extends Node2D:
	var map: WallMap

	func _init() -> void:
		z_as_relative = false
		z_index = 3990
		World.keep_lit(self)

	func _draw() -> void:
		var px := map.world.px
		for k in map.hp:
			if not map.walls.has(k):
				continue
			var top := map.max_hp(map.walls[k])
			var left := float(map.hp[k])
			if top <= 0.0 or left >= top:
				continue
			var w := 64.0
			var at := map.wall_middle(k) + Vector2(-w / 2.0, -1.2 * px)
			var share := clampf(left / top, 0.0, 1.0)
			var fill := Color(0.92, 0.3, 0.2).lerp(Color(0.95, 0.75, 0.3), clampf((share - 0.25) / 0.5, 0.0, 1.0))
			draw_rect(Rect2(at, Vector2(w, 8)), Color(0.1, 0.06, 0.05, 0.85))
			draw_rect(Rect2(at + Vector2(1, 1), Vector2((w - 2) * share, 6)), fill)
