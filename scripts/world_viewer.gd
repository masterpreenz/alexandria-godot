extends Node2D
## Phase 0 world viewer: draws the world exported from Unity (data/world.json, data/sprites.json): the ground and
## floor tiles, the water meshes, and every placed sprite, y-sorted the way Unity sorted them. Pan with WASD / arrow
## keys or by dragging with the middle or right mouse button; zoom with the wheel. See GODOT_MIGRATION.md.

const GROUND_ORDER := -9000  ## Unity sorting orders at or below this are ground level (drawn under everything standing)
const CHUNK := 2048.0        ## ground tiles are drawn in chunks this many px across

var sprites: Array = []           ## the sprite table: tex, rect, pivot, ppu
var textures := {}                ## res path -> Texture2D
var px := 128.0

@onready var camera: Camera2D = $Camera
@onready var ground: Node2D = $Ground
@onready var things: Node2D = $Things


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	sprites = _load_json("res://data/sprites.json")
	var world: Dictionary = _load_json("res://data/world.json")
	px = world.get("px", 128.0)
	var layers := []  # [order, node] for everything drawn at ground level
	for map in world.tilemaps:
		layers.append([map.order, _tile_layer(map)])
	for mesh in world.meshes:
		layers.append([mesh.order, _mesh(mesh)])
	var placed := 0
	for s in world.sprites:
		var order: float = s.sort / px * 100.0
		if order <= GROUND_ORDER:
			layers.append([order, _sprite_node(s, false)])
		else:
			things.add_child(_sprite_node(s, true))
		placed += 1
	layers.sort_custom(func(a, b): return a[0] < b[0])
	for l in layers:
		ground.add_child(l[1])
	_screenshot_if_asked()
	print("World viewer: %d tile layers, %d meshes, %d sprites, %d textures in %d ms" % [
		world.tilemaps.size(), world.meshes.size(), placed, textures.size(), Time.get_ticks_msec() - t0])


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


func _process(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	if Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_S): dir.y += 1
	camera.position += dir.limit_length(1.0) * 1600.0 * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
		camera.position -= event.relative / camera.zoom
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.15).clamp(Vector2(0.03, 0.03), Vector2(4, 4))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.15).clamp(Vector2(0.03, 0.03), Vector2(4, 4))


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


## Run with [code]-- --shot=path.png [--at=x,y] [--zoom=z][/code]: frames the view there, saves a screenshot and quits
## (for checking the port without the editor).
func _screenshot_if_asked() -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot = arg.substr(7)
		elif arg.begins_with("--at="):
			var p := arg.substr(5).split(",")
			camera.position = Vector2(float(p[0]), float(p[1]))
		elif arg.begins_with("--zoom="): camera.zoom = Vector2.ONE * float(arg.substr(7))
	if shot == "":
		return
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	print("Saved ", shot)
	get_tree().quit()
