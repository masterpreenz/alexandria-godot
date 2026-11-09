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

var walls := {}            # Vector3i (edge key) -> type name
var keep_open := {}        # Vector3i -> true: doors of houses set to stay open
var original := {}
var _drawn := {}           # Vector3i -> {holders: [Node2D], body: StaticBody2D}


func setup(w: World, f: FloorMap, data: Dictionary) -> void:
	world = w
	floors = f
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
func nearest_door(p: Vector2, range: float) -> Array:
	var best := range
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
	_changed(e)


func place(e: Edge, type: String) -> void:
	if type == "":
		remove(e)
		return
	if walls.get(e.key(), "") == type:
		return
	for i in int(types[type].length):
		remove(Edge.new(e.vertex + _dir(e.along_y) * i, e.along_y))
	walls[e.key()] = type
	_changed(e)


## Removes the wall covering [param e].
func remove(e: Edge) -> void:
	var c := covering(e)
	if c[0] == "":
		return
	var start: Edge = c[1]
	var end := span_end(start, c[0])
	walls.erase(start.key())
	_changed(start, end)


func _changed(e: Edge, end: Variant = null) -> void:
	version += 1
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
	return JSON.stringify({"walls": out, "world": FloorMap.WORLD_VERSION, "keepOpen": open})


func from_json(json: String) -> void:
	var data: Dictionary = JSON.parse_string(json)
	walls.clear()
	for w in data.get("walls", []):
		if types.has(w.type):
			walls[Vector3i(int(w.x), int(w.y), 1 if w.alongY else 0)] = w.type
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


# A piece of wall art: at the wall's middle (a whole wall's halves pivot there; a panel stands on its own centre),
# sorting at its ground centre among everything standing.
func _half(into: Array, sprite_id: int, flip: bool, ground_centre: Vector2, mid: Vector2, centred: bool) -> void:
	if sprite_id < 0:
		return
	var holder := Node2D.new()
	holder.position = ground_centre
	var sprite := Sprite2D.new()
	world.show_frame(sprite, sprite_id, Vector2(-1 if flip else 1, 1))
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
