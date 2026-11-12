class_name World
extends Node2D
## The world exported from Unity (data/world.json, data/sprites.json): the ground and floor tiles, the water meshes,
## every placed sprite (y-sorted the way Unity sorted them, under [member things]) and what blocks walking
## ([member solids]). Characters go under [member things] so they sort among the trees and props.

signal built

## Every person's body on screen, one scale for all of them (Miko, the villagers, the mutated villagers, and anyone
## drawn like them): their sheets are drawn at the same size, so this alone sets how big people are in the world.
const BODY_SCALE := 0.7
const GROUND_ORDER := -9000  ## Unity sorting orders at or below this are ground level (drawn under everything standing)

var sprites: Array = []           ## the sprite table: tex, rect, pivot, ppu
var textures := {}                ## res path -> Texture2D
var px := 128.0

var ground: Node2D  ## everything at ground level, drawn under the rest
var things: Node2D  ## everything standing, y-sorted
var solids: StaticBody2D  ## the colliders
var floors: FloorMap      ## the floors (ground, paths, boards)
var walls: WallMap        ## the walls, doors and fences
var props: PropMap        ## furniture, decorations, crops, the grass and bushes
var roofs: RoofMap        ## the roofs over closed, floored rooms
var player: Node2D        ## who the roofs fade for (set by the game)
var clock: GameClock      ## the time of day (set by the game)
var village: Village      ## the village's extent (its banner, square and blocks)
var mist: Mist            ## the purple mist over the wild
var gatherables: Array[Gatherable] = []  ## every tree and rock to gather from
var stamped_villages: Array = []   ## the village templates built into this game (saved)
var cleared := {}                ## cells cleared of trees and rocks to build on (saved: they don't grow back on loading)
var _wet := {}            # Vector2i (half-cell) -> true: under a water or bank mesh, edges and all (wet())
var _depths := {}         # Vector2i (half-cell corner) -> how deep the water is there, cells in from its edge
## The rivers' flow, vertex by vertex: [position, one cell downstream (px), one cell across (px), speed (cells/s)],
## bucketed by area for finding the nearest.
var _flow_points := {}
const FLOW_CELL := 256.0
## What live maps draw themselves: the exported snapshot's sprites and colliders of these kinds are left out.
const LIVE_KINDS := ["Walls", "Props"]
## What can hide someone standing behind it (trees, walls, big props; not bushes, flowers or grass): sprites by area.
var occluders := {}  # Vector2i (OCC_CELL px squares) -> Array[Sprite2D]
const OCC_CELL := 512.0
var _images := {}  # Texture2D -> Image, read back for pixel tests


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	ground = Node2D.new()
	ground.name = "Ground"
	add_child(ground)
	things = Node2D.new()
	things.name = "Things"
	things.y_sort_enabled = true
	add_child(things)
	solids = StaticBody2D.new()
	solids.name = "Solids"
	add_child(solids)
	sprites = _load_json("res://data/sprites.json")
	var world: Dictionary = _load_json("res://data/world.json")
	px = world.get("px", 128.0)
	var layers := []  # [order, node] for everything drawn at ground level
	floors = FloorMap.new()
	floors.name = "Floors"
	add_child(floors)
	floors.setup(self, _load_json("res://data/floors.json"))
	layers.append_array(floors.layer_nodes())
	_run_river_on(world.meshes)
	for mesh in world.meshes:
		layers.append([mesh.order, _mesh(mesh)])
	var placed := 0
	for s in world.sprites:
		if s.get("kind", "") in LIVE_KINDS or s.has("gather"):
			continue
		var order: float = s.sort / px * 100.0
		if order <= GROUND_ORDER:
			layers.append([order, _sprite_node(s, false)])
		else:
			var holder := _sprite_node(s, true)
			things.add_child(holder)
			if _hides(s):
				add_occluder(holder.get_child(0))
		placed += 1
	layers.sort_custom(func(a, b): return a[0] < b[0])
	for l in layers:
		l[1].set_meta("order", l[0])
		ground.add_child(l[1])
	for c in world.get("colliders", []):
		if c.get("kind", "") not in LIVE_KINDS and not c.has("gather"):
			_collider(c)
	# The trees and rocks, live: they can be chopped, mined, felled, and grow back.
	if FileAccess.file_exists("res://data/gather.json"):
		var gd: Dictionary = _load_json("res://data/gather.json")
		for d in gd.spots:
			var g := Gatherable.new()
			things.add_child(g)
			g.setup(self, d, int(gd.miner.treeWood))
			gatherables.append(g)
		# The wilds west of the river: grown, the same every time.
		Wildlands.grow(self, gd)
	walls = WallMap.new()
	walls.name = "Walls"
	add_child(walls)
	walls.setup(self, floors, _load_json("res://data/walls.json"))
	props = PropMap.new()
	props.name = "Props"
	add_child(props)
	props.setup(self, floors, _load_json("res://data/props.json"))
	roofs = RoofMap.new()
	roofs.name = "Roofs"
	add_child(roofs)
	roofs.setup(self, floors, walls, _load_json("res://data/roofs.json"))
	if FileAccess.file_exists("res://data/water.json"):
		var water: Dictionary = _load_json("res://data/water.json")
		for k in water.depth:
			var xy: PackedStringArray = k.split(",")
			_depths[Vector2i(int(xy[0]), int(xy[1]))] = float(water.depth[k])
		# The river splitting round the bridge's pilings.
		for wk in water.get("wakes", []):
			var wake := WaterWake.make(self, null, Vector2(wk.x, wk.y), wk.width)
			wake.flow_lift = wk.flowLift
			wake.foam_lift = wk.foamLift
	# The saved game's world over the scene's (the village as it stands).
	# The save this run starts from (the latest, one asked for, or the start bundled with the game).
	var sections: Dictionary = SaveSystem.start_sections(self)
	if sections.has("world.floors"):
		floors.from_json(sections["world.floors"])
	else:
		floors.redraw()
	if sections.has("world.walls"):
		walls.from_json(sections["world.walls"])
	else:
		walls.rebuild()
	# Props after the walls: they sort against them.
	if sections.has("world.props"):
		props.from_json(sections["world.props"])
	else:
		props.rebuild()
	if sections.has("world.roofs"):
		roofs.from_json(sections["world.roofs"])
	else:
		roofs.rebuild()
	village = Village.new(self)
	if sections.has("village"):
		village.from_json(sections["village"])
	# The woods round the home village (once the save's own ground, walls, props and the water are in, to keep clear of
	# them; before the cleared ground's taken out of them).
	if FileAccess.file_exists("res://data/gather.json"):
		Wildlands.village_woods(self, _load_json("res://data/gather.json"))
	# Cleared ground stays clear.
	if sections.has("world.cleared"):
		var cl: Variant = JSON.parse_string(sections["world.cleared"])
		for c in (cl if cl is Array else []):
			clear_cell(Vector2i(int(c[0]), int(c[1])))
	# A new game: the village as it stands when the story begins (data/villages/home_village.json), and the other
	# places built ahead (the next village, overrun); a game already going gets those it hasn't had yet.
	var stamped: Array = JSON.parse_string(sections.get("world.stamped", "[]")) if sections.has("world.stamped") else []
	for nm in VillageTemplate.all_names():
		var t := VillageTemplate.load_named(nm)
		if stamped.has(nm) or (sections.has("world.props") and not bool(t.get("addToSaves", false))):
			continue
		VillageTemplate.stamp(self, t)
		stamped.append(nm)
	stamped_villages = stamped
	# The mist, once the village and the crystals stand.
	if FileAccess.file_exists("res://data/mist.json"):
		var md: Dictionary = _load_json("res://data/mist.json")
		village.radii = md.get("villageRadii", village.radii)
		mist = Mist.new()
		mist.name = "Mist"
		add_child(mist)
		mist.setup(self, md)
		add_ground_layer(mist.ground_layer, -9994)
		add_child(mist.veil_layer)
	print("World: %d floor types, %d walls, %d props, %d roofs, %d meshes, %d sprites, %d textures in %d ms" % [
		floors.types.size(), walls.walls.size(), props.cells.size() + props.free.size(), roofs.roofs.size(), world.meshes.size(), placed, textures.size(), Time.get_ticks_msec() - t0])
	built.emit()


## A blocker: a circle, a closed polygon, or a chain of segments (a wall, a shore).
func _collider(c: Dictionary) -> void:
	_collider_into(solids, c)


## The shapes of collider [param c] (world coordinates), added to [param into].
func _collider_into(into: Node, c: Dictionary) -> void:
	var p: Array = c.get("p", [])
	var pts := PackedVector2Array()
	for i in range(0, p.size(), 2):
		pts.append(Vector2(p[i], p[i + 1]))
	match c.type:
		"circle":
			var shape := CollisionShape2D.new()
			var circle := CircleShape2D.new()
			circle.radius = c.r
			shape.shape = circle
			shape.position = Vector2(c.c[0], c.c[1])
			into.add_child(shape)
		"poly":
			var poly := CollisionPolygon2D.new()
			poly.polygon = pts
			into.add_child(poly)
		"chain":
			for i in pts.size() - 1:
				var shape := CollisionShape2D.new()
				var seg := SegmentShape2D.new()
				seg.a = pts[i]
				seg.b = pts[i + 1]
				shape.shape = seg
				into.add_child(shape)


func _load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	return JSON.parse_string(text)


func _texture(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = load(path) if ResourceLoader.exists(path) else null
		if textures[path] == null:
			push_warning("Missing texture " + path)
	return textures[path]


## A placed sprite. With [param sorted], a node at its sort point (for the y-sort) holding the art at its true place.
func _sprite_node(s: Dictionary, sorted: bool) -> Node2D:
	var info: Dictionary = sprites[int(s.s)]
	var sprite := Sprite2D.new()
	sprite.texture = _texture(info.tex)
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	sprite.offset = Vector2(-info.pivot[0], -info.pivot[1])
	var k: float = px / info.ppu
	sprite.scale = Vector2(s.sx * k, s.sy * k)
	if s.has("rot"):
		sprite.rotation_degrees = s.rot
	if s.has("color"):
		sprite.modulate = Color(s.color[0], s.color[1], s.color[2], s.color[3])
	sprite.set_meta("sprite", int(s.s))
	if not sorted:
		sprite.position = Vector2(s.x, s.y)
		return sprite
	sprite.material = snow_material(0)
	var holder := Node2D.new()
	holder.position = Vector2(s.x, s.sort)
	sprite.position = Vector2(0, s.y - s.sort)
	holder.add_child(sprite)
	return holder


## A water mesh (the river, lake, ponds), a bank's earth wall, or the waterfall, each with its Godot shader and the
## colours and numbers its Unity material had.
# The river runs the map's whole length and stopped dead at its edges: its ribbon and its banks (strips of vertex
# pairs, a row every half cell) are carried on past both ends, as far as the outskirts go.
func _run_river_on(meshes: Array) -> void:
	var river: Dictionary = {}
	for m in meshes:
		if str(m.name) == "River":
			river = m
	if river.is_empty():
		return
	var rows := Outskirts.MARGIN * 2 + 8
	var n: int = (river.v as Array).size() >> 1
	_stretch_strip(river, 0, 2, rows)
	_stretch_strip(river, n - 2, n - 4, rows)
	for m in meshes:
		# Its banks: the cliffs mesh that starts where the river does, two strips as long as it.
		if str(m.name) != "Cliffs" or (m.v as Array).size() != n * 4 or not is_equal_approx(float(m.v[0]), float(river.v[0])):
			continue
		for from in [0, n]:
			_stretch_strip(m, from, from + 2, rows)
			_stretch_strip(m, from + n - 2, from + n - 4, rows)


# Carries a strip on from its end pair of vertices ([param end], end + 1) by [param rows] more rows, each the step
# from the pair before ([param before]) to it: one long piece, its uvs running on too.
func _stretch_strip(m: Dictionary, end: int, before: int, rows: int) -> void:
	var first: int = (m.v as Array).size() >> 1
	for k in 2:
		for key in ["v", "uv", "uv2"]:
			if not m.has(key) or (m[key] as Array).size() < (first + k) * 2:
				continue
			var a: Array = m[key]
			for c in 2:
				var at := float(a[(end + k) * 2 + c])
				a.append(at + (at - float(a[(before + k) * 2 + c])) * rows)
	(m.t as Array).append_array([end, first, end + 1, end + 1, first, first + 1])


func _mesh(m: Dictionary) -> Node2D:
	var verts := PackedVector2Array()
	var v: Array = m.v
	for i in range(0, v.size(), 2):
		verts.append(Vector2(v[i], v[i + 1]))
	var uvs := PackedVector2Array()
	var uv: Array = m.uv
	for i in range(0, uv.size(), 2):
		uvs.append(Vector2(uv[i], uv[i + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if uvs.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	# A bank's height (world units) rides in the vertex colour's red, for its shader (canvas shaders have one UV set).
	var uv2: Array = m.get("uv2", [])
	if m.material == "Cliff" and uv2.size() == verts.size() * 2:
		var colors := PackedColorArray()
		for i in verts.size():
			colors.append(Color(clampf(uv2[i * 2 + 1] / 4.0, 0.0, 1.0), 0, 0, 1))
		arrays[Mesh.ARRAY_COLOR] = colors
	if m.material == "River" and uvs.size() == verts.size():
		arrays[Mesh.ARRAY_COLOR] = _flow_directions(verts, uvs, PackedInt32Array(m.t))
		if float(m.get("flow", 0.0)) > 0.3:
			_note_flow(verts, uvs, PackedInt32Array(m.t), float(m.flow))
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(m.t)
	if m.material in ["River", "Cliff", "Waterfall"]:
		_mark_wet(verts, PackedInt32Array(m.t))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance2D.new()
	node.name = m.name if m.get("parent", "") in ["", "World"] else m.parent + " " + m.name
	node.mesh = mesh
	node.material = _water_material(m)
	if m.material == "Waterfall":
		node.add_child(Waterfall.spray(verts, uvs))
	return node


## Which way the water runs at each vertex, a cell's length downstream in the grid's own (square) cell space: where
## UV.x (cells along the river) grows, averaged over the triangles round the vertex so it turns smoothly round bends.
## On screen the iso grid is squashed, so this has to be worked out in cell space, not from the screen. Still water
## (UV.x all 0) gets none.
func _along_cells(verts: PackedVector2Array, uvs: PackedVector2Array, tris: PackedInt32Array) -> Array:
	var to_cells := Transform2D(floors.ex, floors.ey, Vector2.ZERO).affine_inverse()
	var sum := []
	sum.resize(verts.size())
	sum.fill(Vector2.ZERO)
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var e1 := to_cells.basis_xform(verts[b] - verts[a])
		var e2 := to_cells.basis_xform(verts[c] - verts[a])
		var du1 := uvs[b].x - uvs[a].x
		var du2 := uvs[c].x - uvs[a].x
		var det := e1.x * e2.y - e1.y * e2.x
		if absf(det) < 1e-9:
			continue
		# The gradient of u over the triangle: solves grad . e1 = du1, grad . e2 = du2.
		var grad := Vector2((du1 * e2.y - du2 * e1.y) / det, (du2 * e1.x - du1 * e2.x) / det)
		for v in [a, b, c]:
			sum[v] += grad
	return sum.map(func(g): return g.normalized() if g.length() > 1e-9 else Vector2.ZERO)


## The flow on screen at each vertex, for the water shader: packed into the vertex colour (rg: direction * 0.5 + 0.5;
## b: 1 where it runs at all).
func _flow_directions(verts: PackedVector2Array, uvs: PackedVector2Array, tris: PackedInt32Array) -> PackedColorArray:
	var basis := Transform2D(floors.ex, floors.ey, Vector2.ZERO)
	var out := PackedColorArray()
	for along in _along_cells(verts, uvs, tris):
		var d: Vector2 = basis.basis_xform(along).normalized() if along != Vector2.ZERO else Vector2.ZERO
		out.append(Color(d.x * 0.5 + 0.5, d.y * 0.5 + 0.5, 1.0 if d != Vector2.ZERO else 0.0, 1.0))
	return out


var _materials := {}

func _water_material(m: Dictionary) -> ShaderMaterial:
	if _materials.is_empty():
		_materials = _load_json("res://data/materials.json") if FileAccess.file_exists("res://data/materials.json") else {}
	var unity: Dictionary = _materials.get(m.material, {"colors": {}, "floats": {}, "textures": {}})
	var c: Dictionary = unity.colors
	var f: Dictionary = unity.floats
	var mat := ShaderMaterial.new()
	var col := func(n: String, fallback: Color) -> Color:
		return Color(c[n][0], c[n][1], c[n][2], c[n][3]) if c.has(n) else fallback
	match m.material:
		"River":
			mat.shader = preload("res://shaders/water.gdshader")
			mat.set_shader_parameter("deep", col.call("_Deep", Color(0.15, 0.39, 0.48)))
			mat.set_shader_parameter("shallow", col.call("_Shallow", Color(0.42, 0.7, 0.67)))
			mat.set_shader_parameter("foam", col.call("_Foam", Color(0.88, 0.93, 0.88)))
			mat.set_shader_parameter("flow", float(m.get("flow", f.get("_Flow", 0.7))))
			mat.set_shader_parameter("ripple_scale", float(f.get("_RippleScale", 1.4)))
			mat.set_shader_parameter("foam_width", float(f.get("_FoamWidth", 0.14)))
			mat.set_shader_parameter("cell_px", px)
		"Cliff":
			mat.shader = preload("res://shaders/bank.gdshader")
			var tex: String = unity.textures.get("_MainTex", "")
			if tex != "":
				mat.set_shader_parameter("stone", load(tex))
			mat.set_shader_parameter("tile_size", float(f.get("_TileSize", 1.6)))
			mat.set_shader_parameter("cell_length", float(f.get("_CellLength", 0.559)))
			mat.set_shader_parameter("grass", col.call("_Grass", Color(0.36, 0.52, 0.25)))
			mat.set_shader_parameter("grass_light", col.call("_GrassLight", Color(0.41, 0.6, 0.27)))
			mat.set_shader_parameter("wet", col.call("_Wet", Color(0.16, 0.18, 0.19)))
			mat.set_shader_parameter("waterline", col.call("_Waterline", Color(0.42, 0.55, 0.55)))
		"Waterfall":
			mat.shader = preload("res://shaders/waterfall.gdshader")
			mat.set_shader_parameter("deep", col.call("_Deep", Color(0.15, 0.39, 0.48)))
			mat.set_shader_parameter("water", col.call("_Water", Color(0.28, 0.55, 0.58)))
			mat.set_shader_parameter("pale", col.call("_Light2", Color(0.42, 0.7, 0.67)))
			mat.set_shader_parameter("foam", col.call("_Foam", Color(0.88, 0.93, 0.88)))
			mat.set_shader_parameter("edge_fade", float(f.get("_EdgeFade", 0.14)))
			mat.set_shader_parameter("speed", float(f.get("_Speed", 2.4)))
	return mat


## Shows sprite [param id] from the table on [param sprite] (its image, slice and pivot), at [param scale] on top of the
## world's pixels-per-unit; a negative x scale mirrors it about its pivot.
func show_frame(sprite: Sprite2D, id: int, sc: Vector2 = Vector2.ONE) -> void:
	var info: Dictionary = sprites[id]
	sprite.set_meta("sprite", id)
	sprite.texture = _texture(info.tex)
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	sprite.offset = Vector2(-info.pivot[0], -info.pivot[1])
	sprite.scale = sc * (px / info.ppu)


## Whether a placed sprite can hide someone (as OccludedOutline decided): not the ground clutter under Props (bushes,
## flowers, grass, small rocks), except trees among them; not a bridge's railings.
func _hides(s: Dictionary) -> bool:
	var nm: String = sprites[int(s.s)].name
	if s.kind == "Props" and not nm.contains("tree"):
		return false
	return s.kind != "River"


func add_occluder(sprite: Sprite2D) -> void:
	var r := sprite_rect(sprite)
	for x in range(floori(r.position.x / OCC_CELL), floori(r.end.x / OCC_CELL) + 1):
		for y in range(floori(r.position.y / OCC_CELL), floori(r.end.y / OCC_CELL) + 1):
			var k := Vector2i(x, y)
			if not occluders.has(k):
				occluders[k] = []
			occluders[k].append(sprite)


## The sprites that might hide something within [param rect].
func occluders_near(rect: Rect2) -> Array:
	var found := {}
	for x in range(floori(rect.position.x / OCC_CELL), floori(rect.end.x / OCC_CELL) + 1):
		for y in range(floori(rect.position.y / OCC_CELL), floori(rect.end.y / OCC_CELL) + 1):
			var here: Array = occluders.get(Vector2i(x, y), [])
			# Gone ones (a wall taken down) drop out as they're met.
			for i in range(here.size() - 1, -1, -1):
				if not is_instance_valid(here[i]):
					here.remove_at(i)
				else:
					found[here[i]] = true
	return found.keys()


static var _view := Rect2()
static var _view_frame := -1


## What's on screen now (in the world, px), with [param margin] units round it: worked out once a frame. Things off it
## needn't be kept up (a wake, someone wading): the map grows as it's played, nothing's unloaded, so this keeps
## the far side of it from costing.
func on_screen(p: Vector2, margin := 4.0) -> bool:
	var f := Engine.get_process_frames()
	if f != _view_frame:
		_view_frame = f
		var vp := get_viewport()
		_view = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	return _view.grow(margin * px).has_point(p)


## A sprite's box in the world.
static func sprite_rect(sprite: Sprite2D) -> Rect2:
	var t := sprite.get_global_transform()
	var local := Rect2(sprite.offset, sprite.region_rect.size)
	var r := Rect2(t * local.position, Vector2.ZERO)
	for c in [local.position + Vector2(local.size.x, 0), local.position + Vector2(0, local.size.y), local.end]:
		r = r.expand(t * c)
	return r


## Whether [param sprite] draws a (mostly solid) pixel at world point [param p].
func drawn_at(sprite: Sprite2D, p: Vector2) -> bool:
	if sprite.texture == null:
		return false
	var local := sprite.get_global_transform().affine_inverse() * p - sprite.offset
	var region := sprite.region_rect
	if local.x < 0 or local.y < 0 or local.x >= region.size.x or local.y >= region.size.y:
		return false
	var img: Image = _images.get(sprite.texture)
	if img == null:
		img = sprite.texture.get_image()
		if img == null:
			return true
		if img.is_compressed():
			img.decompress()
		_images[sprite.texture] = img
	var px_at := Vector2i(region.position + local)
	if px_at.x >= img.get_width() or px_at.y >= img.get_height():
		return false
	return img.get_pixel(px_at.x, px_at.y).a > 0.4


## Clears the trees and rocks standing on [param cell] for good (to build there): they're gone, and stay gone in the
## save.
func clear_cell(cell: Vector2i) -> void:
	cleared[cell] = true
	var at := floors.cell_centre(cell)
	for g in Gatherable.all.duplicate():
		if is_instance_valid(g) and floors.cell_at(g.foot) == cell or (is_instance_valid(g) and g.foot.distance_to(at) < 0.6 * px):
			Gatherable.all.erase(g)
			gatherables.erase(g)
			g.queue_free()


func cleared_json() -> String:
	return JSON.stringify(cleared.keys().map(func(c): return [c.x, c.y]))


## Whether something's laid over the grass at [param p] (a path, stone, boards).
func on_floor(p: Vector2) -> bool:
	return floors.on_floor(p)


## Whether [param p] is in the water or on its banks: anywhere a water or bank mesh is drawn, right to its edge. (The
## depth map below only starts some way in from the edge, so on its own it takes the water's margins for dry land.)
func wet(p: Vector2) -> bool:
	var g := floors.fractional_cell(p) * 2.0
	return _wet.has(Vector2i(floori(g.x), floori(g.y))) or water_depth(p) > 0.0


# Every half-cell a water or bank mesh's triangles cover (sampled every quarter of a cell's width and height).
func _mark_wet(verts: PackedVector2Array, tris: PackedInt32Array) -> void:
	var step := Vector2(floors.ex.x, -floors.ex.y) / 2.0
	for k in range(0, tris.size(), 3):
		var a := verts[tris[k]]
		var b := verts[tris[k + 1]]
		var c := verts[tris[k + 2]]
		var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
		var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
		var y := lo.y
		while y <= hi.y + step.y:
			var x := lo.x
			while x <= hi.x + step.x:
				var q := Vector2(minf(x, hi.x), minf(y, hi.y))
				if Geometry2D.point_is_inside_triangle(q, a, b, c) or q.distance_to(a) < 1.0:
					var g := floors.fractional_cell(q) * 2.0
					_wet[Vector2i(floori(g.x), floori(g.y))] = true
				x += step.x
			y += step.y
		# Thin triangles (a bank's slivers) can fall between those samples: along their edges too.
		for e in [[a, b], [b, c], [c, a]]:
			var n := maxi(1, ceili((e[0] as Vector2).distance_to(e[1]) / 16.0))
			for i in n + 1:
				var g := floors.fractional_cell((e[0] as Vector2).lerp(e[1], float(i) / n)) * 2.0
				_wet[Vector2i(floori(g.x), floori(g.y))] = true


## How far into the water [param p] is, in cells in from its edge (0 on dry land): blended between the depth map's
## half-cell samples.
func water_depth(p: Vector2) -> float:
	var g := floors.fractional_cell(p) * 2.0
	var i := Vector2i(floori(g.x), floori(g.y))
	var f := g - Vector2(i)
	var d00: float = _depths.get(i, 0.0)
	var d10: float = _depths.get(i + Vector2i(1, 0), 0.0)
	var d01: float = _depths.get(i + Vector2i(0, 1), 0.0)
	var d11: float = _depths.get(i + Vector2i(1, 1), 0.0)
	return lerpf(lerpf(d00, d10, f.x), lerpf(d01, d11, f.x), f.y)


## The layer drawing on the water (ripples, wakes): over the water and its banks, under everything standing.
func water_fx() -> Node2D:
	var fx: Node2D = get_node_or_null("WaterFx")
	if fx == null:
		fx = Node2D.new()
		fx.name = "WaterFx"
		add_child(fx)
		move_child(fx, things.get_index())
	return fx


# Each river vertex's flow, as Unity's River.FlowAt gives it: one cell downstream and one cell across (normalised in
# cell space, then into the world), from the way UV.x (cells along) grows over the triangles round it.
func _note_flow(verts: PackedVector2Array, uvs: PackedVector2Array, tris: PackedInt32Array, speed: float) -> void:
	var basis := Transform2D(floors.ex, floors.ey, Vector2.ZERO)
	var alongs := _along_cells(verts, uvs, tris)
	for i in verts.size():
		var along: Vector2 = alongs[i]
		if along == Vector2.ZERO:
			continue
		# Downstream a cell long, and across it a cell long (in cell space), both into the world.
		var down := basis.basis_xform(along)
		var side := basis.basis_xform(Vector2(-along.y, along.x))
		var key := Vector2i(floori(verts[i].x / FLOW_CELL), floori(verts[i].y / FLOW_CELL))
		if not _flow_points.has(key):
			_flow_points[key] = []
		_flow_points[key].append([verts[i], down, side, speed])


## The river's flow at [param p]: {down, side (px: a cell downstream, a cell across), speed (cells/s)}, or {} where
## there's no running water (a pond, dry land).
func flow_at(p: Vector2) -> Dictionary:
	var k := Vector2i(floori(p.x / FLOW_CELL), floori(p.y / FLOW_CELL))
	var best: Array = []
	var best_d := 1.5 * px
	for x in range(k.x - 1, k.x + 2):
		for y in range(k.y - 1, k.y + 2):
			for pt in _flow_points.get(Vector2i(x, y), []):
				var d: float = (pt[0] as Vector2).distance_to(p)
				if d < best_d:
					best_d = d
					best = pt
	if best.is_empty():
		return {}
	return {"down": best[1], "side": best[2], "speed": best[3]}


## Puts [param node] among the ground layers by its Unity sorting [param order].
func add_ground_layer(node: Node2D, order: float) -> void:
	node.set_meta("order", order)
	var at := ground.get_child_count()
	for i in ground.get_child_count():
		if float(ground.get_child(i).get_meta("order", -1e9)) > order:
			at = i
			break
	ground.add_child(node)
	ground.move_child(node, at)


## Where every prop of the type [param name] stands (on cells and free), px.
func props_named(nm: String) -> Array:
	if props == null:
		return []
	return props.cached("positions", nm, _props_named)


func _props_named(nm: String) -> Array:
	var out := []
	for k in props.cells:
		if props.cells[k].prop == nm:
			out.append(floors.cell_centre(Vector2i(k.x, k.y)))
	for e in props.free:
		if e.prop == nm:
			out.append(e.pos)
	return out


## A Unity material's colours, numbers and textures (data/materials.json).
func material_settings(nm: String) -> Dictionary:
	if _materials.is_empty():
		_materials = _load_json("res://data/materials.json") if FileAccess.file_exists("res://data/materials.json") else {}
	return _materials.get(nm, {})


var _snow_mats := {}

## The snow material for [param mode]: 0 caps on things standing, 1 ground patches, 2 roofs (shaders/snow.gdshader).
func snow_material(mode: int) -> ShaderMaterial:
	if not _snow_mats.has(mode):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/snow.gdshader")
		m.set_shader_parameter("mode", mode)
		m.set_shader_parameter("unit", px)
		if mode == 4 or mode == 5:
			m.set_shader_parameter("sway", 0.045)
		if mode == 3:
			m.set_shader_parameter("variety", grass_variety())
			m.set_shader_parameter("grass_variety", 1.0 if Settings.varied_grass else 0.0)
		for k in _snow_params:
			m.set_shader_parameter(k, _snow_params[k])
		_snow_mats[mode] = m
	return _snow_mats[mode]


var _snow_params := {}

## Sets [param key] on every snow material (the ones made later too).
func set_snow_param(key: String, value: Variant) -> void:
	_snow_params[key] = value
	for m in _snow_mats.values():
		(m as ShaderMaterial).set_shader_parameter(key, value)


static var _variety: Texture2D

## The noise the grass is varied by (snow.gdshader mode 3): Godot's FastNoiseLite, simplex with a few octaves, made
## once into a seamless 512 x 512 picture that the ground's shader samples across the world.
static func grass_variety() -> Texture2D:
	if _variety == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = 7
		n.frequency = 0.008
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		_variety = ImageTexture.create_from_image(n.get_seamless_image(512, 512))
	return _variety


## Keeps [param n] as drawn whatever the hour (words, numbers, bars, speech bubbles: not things in the world): the
## night's tint undone on it each frame (its self_modulate; its own fading through modulate goes on as it was).
static func keep_lit(n: CanvasItem) -> void:
	n.add_to_group(&"unlit")


func _process(_delta: float) -> void:
	var lit := get_tree().get_nodes_in_group(&"unlit")
	if lit.is_empty():
		return
	var undo := daylight_undo()
	for n in lit:
		(n as CanvasItem).self_modulate = Color(undo, (n as CanvasItem).self_modulate.a)


## The colour that undoes the day's light on something that shouldn't be dimmed by it (emotes: speech-bubble art,
## always shown as drawn): the night's tint (Daylight) inverted, to multiply it by.
func daylight_undo() -> Color:
	var daylight := get_tree().current_scene.get_node_or_null("Daylight") as CanvasModulate
	if daylight == null:
		return Color.WHITE
	var c := daylight.color
	return Color(1.0 / maxf(c.r, 0.05), 1.0 / maxf(c.g, 0.05), 1.0 / maxf(c.b, 0.05), 1.0)


## The trees' material: swaying, with snow settling on them (or, [param snowy] art with its snow drawn, without).
func tree_material(snowy := false) -> ShaderMaterial:
	if Shots.arg("nosway") != "":
		return snow_material(0)
	return snow_material(5 if snowy else 4)


## A wind gust's front (px across the world) and strength (0 to 1): the trees it passes lean over.
func set_gust(front_x: float, strength: float) -> void:
	for mode in [4, 5]:
		var m := snow_material(mode)
		m.set_shader_parameter("gust_x", front_x)
		m.set_shader_parameter("gust", strength)


## Grass varied (Settings) or plain: the ground's shader, at once.
func set_grass_variety(on: bool) -> void:
	snow_material(3).set_shader_parameter("grass_variety", 1.0 if on else 0.0)
