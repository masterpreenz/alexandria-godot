class_name VillageBorder
extends MeshInstance2D
## The village's edge on the ground (from Unity's VillageBorder): a soft dark band along it, darkest on the line and
## fading out a little way outside and further inside, round each loop of its outline (the square and the blocks added
## on). Redrawn only when the village's shape changes.

const INSIDE := 1.4                         ## tiles in the shading fades over
const OUTSIDE := 0.35                       ## and out
const SHADE := Color(0.05, 0.03, 0.02, 0.5)

var world: World
var _shown := ""


func setup(w: World) -> void:
	world = w
	world.add_ground_layer(self, -9968)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"village_border.process", __t)


func _process_timed(_delta: float) -> void:
	var key := world.village.shape_key()
	if key == _shown:
		return
	_shown = key
	visible = world.village.founded()
	if visible:
		_build()


# The village's tiles, from the banner's tile.
func _cells() -> Dictionary:
	var v := world.village
	var set := {}
	var r := roundi(float(v.radii[clampi(v.tier, 0, v.radii.size() - 1)]))
	var rects: Array = [Rect2i(-r, -r, 2 * r + 1, 2 * r + 1)]
	rects.append_array(v.blocks)
	for rc in rects:
		for x in range(rc.position.x, rc.end.x):
			for y in range(rc.position.y, rc.end.y):
				set[Vector2i(x, y)] = true
	return set


# The loops round the tiles' edges, as their turning corners (Unity's Village.Loops).
static func loops(cells: Dictionary) -> Array:
	var nxt := {}
	var edge := func(a: Vector2i, b: Vector2i):
		if not nxt.has(a): nxt[a] = []
		nxt[a].append(b)
	for c in cells:
		if not cells.has(c + Vector2i(0, -1)): edge.call(c, c + Vector2i(1, 0))
		if not cells.has(c + Vector2i(1, 0)): edge.call(c + Vector2i(1, 0), c + Vector2i(1, 1))
		if not cells.has(c + Vector2i(0, 1)): edge.call(c + Vector2i(1, 1), c + Vector2i(0, 1))
		if not cells.has(c + Vector2i(-1, 0)): edge.call(c + Vector2i(0, 1), c)
	var out := []
	while not nxt.is_empty():
		var start: Vector2i = nxt.keys()[0]
		var loop := []
		var at := start
		while true:
			loop.append(at)
			var outs: Array = nxt[at]
			var to: Vector2i = outs.pop_back()
			if outs.is_empty():
				nxt.erase(at)
			at = to
			if at == start or not nxt.has(at):
				break
		var corners := []
		for i in loop.size():
			var prev: Vector2i = loop[(i + loop.size() - 1) % loop.size()]
			var here: Vector2i = loop[i]
			var after: Vector2i = loop[(i + 1) % loop.size()]
			if here - prev != after - here:
				corners.append(here)
		if corners.size() >= 4:
			out.append(corners)
	return out


# A loop moved out (or, negative, in) by [param by] tiles: the village is on its left.
static func offset(loop: Array, by: float) -> Array:
	var out := []
	for i in loop.size():
		var prev := Vector2(loop[(i + loop.size() - 1) % loop.size()])
		var here := Vector2(loop[i])
		var after := Vector2(loop[(i + 1) % loop.size()])
		var d1 := (here - prev).normalized()
		var d2 := (after - here).normalized()
		out.append(here + (Vector2(d1.y, -d1.x) + Vector2(d2.y, -d2.x)) * by)
	return out


func _build() -> void:
	var banner := world.floors.cell_at(world.village.centre())
	var verts := PackedVector2Array()
	var colours := PackedColorArray()
	var tris := PackedInt32Array()
	var alpha := [0.0, SHADE.a, 0.0]
	var by := [OUTSIDE, 0.0, -INSIDE]
	for loop in loops(_cells()):
		var n: int = loop.size()
		var start := verts.size()
		for r in 3:
			for p in offset(loop, by[r]):
				verts.append(world.floors.corner(Vector2(banner) + p))
				colours.append(Color(SHADE, alpha[r]))
		for band in 2:
			for i in n:
				var j := (i + 1) % n
				var a := start + band * n + i
				var b := start + band * n + j
				var c := start + (band + 1) * n + j
				var d := start + (band + 1) * n + i
				tris.append_array([a, b, c, a, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = tris
	var m := ArrayMesh.new()
	if not tris.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = m
