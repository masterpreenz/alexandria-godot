class_name World
extends Node2D
## The world exported from Unity (data/world.json, data/sprites.json): the ground and floor tiles, the water meshes,
## every placed sprite (y-sorted the way Unity sorted them, under [member things]) and what blocks walking
## ([member solids]). Characters go under [member things] so they sort among the trees and props.

signal built

const GROUND_ORDER := -9000  ## Unity sorting orders at or below this are ground level (drawn under everything standing)
const CHUNK := 2048.0        ## ground tiles are drawn in chunks this many px across

var sprites: Array = []           ## the sprite table: tex, rect, pivot, ppu
var textures := {}                ## res path -> Texture2D
var px := 128.0

var ground: Node2D  ## everything at ground level, drawn under the rest
var things: Node2D  ## everything standing, y-sorted
var solids: StaticBody2D  ## the colliders
## What can hide someone standing behind it (trees, walls, big props; not bushes, flowers or grass): sprites by area.
var occluders := {}  # Vector2i (OCC_CELL px squares) -> Array[Sprite2D]
const OCC_CELL := 512.0
## Floor cells laid over the grass (paths, stone, boards): for footsteps and the like.
var _floor_cells := {}
var _cell_offset := Vector2.ZERO
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
	for map in world.tilemaps:
		layers.append([map.order, _tile_layer(map)])
		if map.name != "Ground":
			_note_floor(map)
	for mesh in world.meshes:
		layers.append([mesh.order, _mesh(mesh)])
	var placed := 0
	for s in world.sprites:
		var order: float = s.sort / px * 100.0
		if order <= GROUND_ORDER:
			layers.append([order, _sprite_node(s, false)])
		else:
			var holder := _sprite_node(s, true)
			things.add_child(holder)
			if _hides(s):
				_add_occluder(holder.get_child(0))
		placed += 1
	layers.sort_custom(func(a, b): return a[0] < b[0])
	for l in layers:
		ground.add_child(l[1])
	for c in world.get("colliders", []):
		_collider(c)
	print("World: %d tile layers, %d meshes, %d sprites, %d textures in %d ms" % [
		world.tilemaps.size(), world.meshes.size(), placed, textures.size(), Time.get_ticks_msec() - t0])
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


## A tilemap layer, cut into chunks that each draw their tiles in one go (and are culled when off screen).
func _tile_layer(map: Dictionary) -> Node2D:
	var layer := Node2D.new()
	layer.name = map.name
	if map.has("color"):
		layer.modulate = Color(map.color[0], map.color[1], map.color[2], map.color[3])
	var chunks := {}
	var tiles: Array = map.tiles
	for i in range(0, tiles.size(), 4):
		var key := Vector2i(floori(tiles[i] / CHUNK), floori(tiles[i + 1] / CHUNK))
		if not chunks.has(key):
			var c := TileChunk.new()
			c.viewer = self
			chunks[key] = c
		(chunks[key] as TileChunk).add(tiles[i], tiles[i + 1], int(tiles[i + 2]), int(tiles[i + 3]))
	for c in chunks.values():
		layer.add_child(c)
	return layer


## A water (or other) mesh, plain-coloured for now (its shader comes over in phase 2).
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
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(m.t)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance2D.new()
	node.name = m.name
	node.mesh = mesh
	node.modulate = Color(0.32, 0.58, 0.72, 0.95) if m.material != "Waterfall" else Color(0.75, 0.9, 1.0, 0.85)
	return node


## A chunk of one tile layer: its tiles drawn straight from the sprite table.
class TileChunk extends Node2D:
	var viewer
	var entries := PackedFloat32Array()  # x, y, sprite, flip

	func add(x: float, y: float, s: int, flip: int) -> void:
		entries.append_array([x, y, s, flip])

	func _draw() -> void:
		for i in range(0, entries.size(), 4):
			var info: Dictionary = viewer.sprites[int(entries[i + 2])]
			var tex: Texture2D = viewer._texture(info.tex)
			if tex == null:
				continue
			var k: float = viewer.px / info.ppu
			var size := Vector2(info.rect[2], info.rect[3]) * k
			var at := Vector2(entries[i], entries[i + 1]) - Vector2(info.pivot[0], info.pivot[1]) * k
			var flip := int(entries[i + 3])
			if flip == 0:
				draw_texture_rect_region(tex, Rect2(at, size), Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3]))
			else:
				# Mirrored about its pivot.
				var sx := -1.0 if flip & 1 else 1.0
				var sy := -1.0 if flip & 2 else 1.0
				draw_set_transform(Vector2(entries[i], entries[i + 1]), 0.0, Vector2(sx, sy))
				draw_texture_rect_region(tex, Rect2(-Vector2(info.pivot[0], info.pivot[1]) * k, size), Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3]))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


func _add_occluder(sprite: Sprite2D) -> void:
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
			for sprite in occluders.get(Vector2i(x, y), []):
				found[sprite] = true
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


func _note_floor(map: Dictionary) -> void:
	var tiles: Array = map.tiles
	for i in range(0, tiles.size(), 4):
		var p := Vector2(tiles[i], tiles[i + 1])
		if _floor_cells.is_empty() and _cell_offset == Vector2.ZERO:
			var uv := _iso(p)
			_cell_offset = uv - uv.round()
		_floor_cells[Vector2i((_iso(p) - _cell_offset).round())] = true


## Iso cell coordinates of a world point (cells are 1 x 0.5 units: px wide, px/2 tall).
func _iso(p: Vector2) -> Vector2:
	return Vector2(p.x / px + p.y / (px * 0.5), p.y / (px * 0.5) - p.x / px)


## Whether something's laid over the grass at [param p] (a path, stone, boards).
func on_floor(p: Vector2) -> bool:
	return _floor_cells.has(Vector2i((_iso(p) - _cell_offset).round()))
