class_name World
extends Node2D
## The world exported from Unity (data/world.json, data/sprites.json): the ground and floor tiles, the water meshes,
## every placed sprite (y-sorted the way Unity sorted them, under [member things]) and what blocks walking
## ([member solids]). Characters go under [member things] so they sort among the trees and props.

signal built

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
var _depths := {}         # Vector2i (half-cell corner) -> how deep the water is there, cells in from its edge
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
	for mesh in world.meshes:
		layers.append([mesh.order, _mesh(mesh)])
	var placed := 0
	for s in world.sprites:
		if s.get("kind", "") in LIVE_KINDS:
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
		ground.add_child(l[1])
	for c in world.get("colliders", []):
		if c.get("kind", "") not in LIVE_KINDS:
			_collider(c)
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
	# The saved game's world over the scene's (the village as it stands).
	var save: Dictionary = _load_json("res://data/save.json") if FileAccess.file_exists("res://data/save.json") else {}
	var sections: Dictionary = save.get("sections", {})
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
	print("World: %d floor types, %d walls, %d props, %d roofs, %d meshes, %d sprites, %d textures in %d ms" % [
		floors.types.size(), walls.walls.size(), props.cells.size() + props.free.size(), roofs.roofs.size(), world.meshes.size(), placed, textures.size(), Time.get_ticks_msec() - t0])
	built.emit()


## A blocker: a circle, a closed polygon, or a chain of segments (a wall, a shore).
func _collider(c: Dictionary) -> void:
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
			solids.add_child(shape)
		"poly":
			var poly := CollisionPolygon2D.new()
			poly.polygon = pts
			solids.add_child(poly)
		"chain":
			for i in pts.size() - 1:
				var shape := CollisionShape2D.new()
				var seg := SegmentShape2D.new()
				seg.a = pts[i]
				seg.b = pts[i + 1]
				shape.shape = seg
				solids.add_child(shape)


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
	if not sorted:
		sprite.position = Vector2(s.x, s.y)
		return sprite
	var holder := Node2D.new()
	holder.position = Vector2(s.x, s.sort)
	sprite.position = Vector2(0, s.y - s.sort)
	holder.add_child(sprite)
	return holder


## A water mesh (the river, lake, ponds), a bank's earth wall, or the waterfall, each with its Godot shader and the
## colours and numbers its Unity material had.
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
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(m.t)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance2D.new()
	node.name = m.name if m.get("parent", "") in ["", "World"] else m.parent + " " + m.name
	node.mesh = mesh
	node.material = _water_material(m)
	if m.material == "Waterfall":
		node.add_child(Waterfall.spray(verts, uvs))
	return node


## Which way the water runs at each vertex (where UV.x, cells along the river, grows), averaged over the triangles
## round it so it turns smoothly round bends: packed into the vertex colour (rg: direction * 0.5 + 0.5; b: 1 where it
## runs at all). Still water (UV.x all 0) gets none.
static func _flow_directions(verts: PackedVector2Array, uvs: PackedVector2Array, tris: PackedInt32Array) -> PackedColorArray:
	var sum := []
	sum.resize(verts.size())
	sum.fill(Vector2.ZERO)
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var e1 := verts[b] - verts[a]
		var e2 := verts[c] - verts[a]
		var du1 := uvs[b].x - uvs[a].x
		var du2 := uvs[c].x - uvs[a].x
		var det := e1.x * e2.y - e1.y * e2.x
		if absf(det) < 1e-6:
			continue
		# The gradient of u over the triangle: solves grad . e1 = du1, grad . e2 = du2.
		var grad := Vector2((du1 * e2.y - du2 * e1.y) / det, (du2 * e1.x - du1 * e2.x) / det)
		for v in [a, b, c]:
			sum[v] += grad
	var out := PackedColorArray()
	for v in sum:
		var d: Vector2 = v.normalized() if v.length() > 1e-9 else Vector2.ZERO
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
func show_frame(sprite: Sprite2D, id: int, scale: Vector2 = Vector2.ONE) -> void:
	var info: Dictionary = sprites[id]
	sprite.texture = _texture(info.tex)
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	sprite.offset = Vector2(-info.pivot[0], -info.pivot[1])
	sprite.scale = scale * (px / info.ppu)


## Whether a placed sprite can hide someone (as OccludedOutline decided): not the ground clutter under Props (bushes,
## flowers, grass, small rocks), except trees among them; not a bridge's railings.
func _hides(s: Dictionary) -> bool:
	var name: String = sprites[int(s.s)].name
	if s.kind == "Props" and not name.contains("tree"):
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


## Whether something's laid over the grass at [param p] (a path, stone, boards).
func on_floor(p: Vector2) -> bool:
	return floors.on_floor(p)


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
