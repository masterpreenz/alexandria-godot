class_name Mist
extends Node
## The purple mist over the wild (from Unity's Mist and MistLayer): a grid over the whole world holding how thick the
## mist is in each spot: clear, normal, or strong (everything far from the middle of the map). Monsters come out of it
## and are stronger in it. It's cleared, softly and over a moment, round the middle of the map until a village is
## founded, inside the village and a little way past its edge, round every teleport crystal and every cleansing
## crystal; strong mist isn't cleared by those. Trees and rocks part it: the wisps curl round them.
##
## Drawn twice: the ground under it darkened and violet (under everything standing), and the drifting smoke over
## everything, Miko, trees and rocks included (shaders/mist.gdshader).

enum Tier { CLEAR, NORMAL, STRONG }

const NORMAL_POWER := 1.15   ## how much stronger monsters are in normal mist
const STRONG_POWER := 1.4

var world: World
var data: Dictionary
var rect := Rect2()          ## the world it covers, px
var cell := 64.0             ## px a mist cell
var width := 0
var height := 0

var _base := PackedByteArray()      # the mist where nothing clears it
var target := PackedByteArray()     # what it should be now (Tier)
var _shown := PackedFloat32Array()  # what's drawn, easing towards target (0..2)
var _near := PackedByteArray()      # how near a tree or rock each cell is (0..255)
var _moving := PackedInt32Array()   # cells still easing
var _image: Image
var texture: ImageTexture
var _sources := ""
var _next_refresh := 0.0
var ground_layer: Node2D
var veil_layer: Node2D


func setup(w: World, d: Dictionary) -> void:
	world = w
	data = d
	rect = Rect2(d.world[0], d.world[1], d.world[2], d.world[3])
	cell = d.cellSize
	width = maxi(8, ceili(rect.size.x / cell))
	height = maxi(8, ceili(rect.size.y / cell))
	var n := width * height
	_base.resize(n)
	target.resize(n)
	_shown.resize(n)
	_near.resize(n)
	# Strong mist far from the map's middle (in cells): the cell coordinates are linear in the position, so step them.
	var strong2: float = float(d.strongFrom) * float(d.strongFrom)
	var f0 := world.floors.fractional_cell(_centre(0, 0))
	var fx := world.floors.fractional_cell(_centre(1, 0)) - f0
	var fy := world.floors.fractional_cell(_centre(0, 1)) - f0
	var normal := PackedByteArray()
	normal.resize(width)
	for y in height:
		var row := f0 + fy * y
		var i0 := y * width
		for x in width:
			_base[i0 + x] = Tier.STRONG if (row + fx * x).length_squared() > strong2 else Tier.NORMAL
	_note_obstacles(d.obstacles)
	_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	refresh(true)
	# At first, show it as it is (no clearing animation as the game starts).
	for i in n:
		_shown[i] = target[i]
	_moving.clear()
	_upload_all()
	ground_layer = _layer("MistGround", 1, data.get("groundNormal", 0.75), data.get("groundStrong", 1.0))
	veil_layer = _layer("MistVeil", 2, data.get("veilNormal", 0.7), data.get("veilStrong", 0.9))
	veil_layer.z_as_relative = false
	veil_layer.z_index = 4050  # over everything, the outline included


func _centre(x: int, y: int) -> Vector2:
	return rect.position + Vector2((x + 0.5) * cell, (y + 0.5) * cell)


## How thick the mist is at [param p].
func tier_at(p: Vector2) -> int:
	var x := floori((p.x - rect.position.x) / cell)
	var y := floori((p.y - rect.position.y) / cell)
	if x < 0 or y < 0 or x >= width or y >= height:
		return Tier.STRONG
	return target[y * width + x]


## How much stronger a monster is at [param p] (1 on clear ground).
func power(p: Vector2) -> float:
	match tier_at(p):
		Tier.NORMAL: return NORMAL_POWER
		Tier.STRONG: return STRONG_POWER
	return 1.0


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_refresh:
		_next_refresh = now + 0.5
		refresh()
	_settle(delta)


# ---- What clears it ----

# Everything that clears mist, as a string: when it changes, the mist is worked out again.
func _source_key() -> String:
	var s := "V" + world.village.shape_key()
	for p in world.props_named("TeleportCrystal"):
		s += "|%.0f,%.0f" % [p.x, p.y]
	for p in world.props_named("CleansingCrystal"):
		s += "|W%.0f,%.0f" % [p.x, p.y]
	return s


## Works out the mist again if the village or the crystals have changed (cheap when nothing has).
func refresh(force := false) -> void:
	var key := _source_key()
	if key == _sources and not force:
		return
	_sources = key
	var before := target.duplicate()
	target = _base.duplicate()
	var village: Village = world.village
	if not village.founded():
		# A clearing round the middle of the map to start from, until there's a village to clear its own ground.
		_clear_circle(Vector2.ZERO, data.homeRadius, Tier.NORMAL)
	else:
		var margin: float = data.villageMargin
		var box := village.bounds(margin)
		_for_cells(box, func(i: int, at: Vector2) -> void:
			if target[i] == Tier.NORMAL and village.contains(at, margin):
				target[i] = Tier.CLEAR)
	for p in world.props_named("TeleportCrystal"):
		_clear_circle(p, data.crystalRadius, Tier.NORMAL)
	for p in world.props_named("CleansingCrystal"):
		_clear_circle(p, data.wardRadius, Tier.NORMAL)
	# Ease only what changed.
	for i in target.size():
		if before.size() == target.size() and before[i] != target[i]:
			_moving.append(i)


# Clears mist up to [param up_to] within a circle across the ground (the screen's y counts double).
func _clear_circle(centre: Vector2, radius: float, up_to: int) -> void:
	var box := Rect2(centre - Vector2(radius, radius * 0.5), Vector2(radius * 2.0, radius))
	_for_cells(box, func(i: int, at: Vector2) -> void:
		var d := Vector2(at.x - centre.x, (at.y - centre.y) * 2.0)
		if d.length_squared() <= radius * radius and target[i] <= up_to:
			target[i] = Tier.CLEAR)


func _for_cells(box: Rect2, each: Callable) -> void:
	var x0 := maxi(0, floori((box.position.x - rect.position.x) / cell))
	var x1 := mini(width - 1, ceili((box.end.x - rect.position.x) / cell))
	var y0 := maxi(0, floori((box.position.y - rect.position.y) / cell))
	var y1 := mini(height - 1, ceili((box.end.y - rect.position.y) / cell))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			each.call(y * width + x, _centre(x, y))


# Marks round every tree and rock, so the mist flows about them.
func _note_obstacles(list: Array) -> void:
	var r0: float = data.obstacleRadius
	for k in range(0, list.size(), 3):
		var c := Vector2(list[k], list[k + 1])
		var r := r0 * (1.0 if int(list[k + 2]) == 1 else 0.8)
		_for_cells(Rect2(c - Vector2(r, r * 0.5), Vector2(r * 2.0, r)), func(i: int, at: Vector2) -> void:
			var d := Vector2(at.x - c.x, (at.y - c.y) * 2.0).length() / r
			if d < 1.0:
				_near[i] = maxi(_near[i], int(255.0 * smoothstep(0.0, 1.0, 1.0 - d))))


# ---- Showing it ----

# Eases what's drawn towards what the mist now is (about a second and a bit to clear).
func _settle(delta: float) -> void:
	if _moving.is_empty():
		return
	var step := delta * 0.8
	var still := PackedInt32Array()
	for i in _moving:
		_shown[i] = move_toward(_shown[i], target[i], step)
		_put(i)
		if not is_equal_approx(_shown[i], target[i]):
			still.append(i)
	_moving = still
	texture.update(_image)


func _put(i: int) -> void:
	var v := _shown[i]
	_image.set_pixel(i % width, i / width, Color(clampf(v, 0.0, 1.0), clampf(v - 1.0, 0.0, 1.0), _near[i] / 255.0, 1.0))


func _upload_all() -> void:
	for i in _shown.size():
		_put(i)
	texture = ImageTexture.create_from_image(_image)


# One of the two layers: a rectangle over the whole world, drawn by the mist shader.
func _layer(n: String, part: int, normal: float, strong: float) -> Node2D:
	var layer := MistQuad.new()
	layer.name = n
	layer.rect = rect
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/mist.gdshader")
	mat.set_shader_parameter("mist", texture)
	mat.set_shader_parameter("texel", Vector2(1.0 / width, 1.0 / height))
	mat.set_shader_parameter("part", part)
	mat.set_shader_parameter("normal_amount", normal)
	mat.set_shader_parameter("strong_amount", strong)
	mat.set_shader_parameter("unit", world.px)
	var unity: Dictionary = world.material_settings(data.material)
	var c: Dictionary = unity.get("colors", {})
	var f: Dictionary = unity.get("floats", {})
	var tex: Dictionary = unity.get("textures", {})
	if tex.has("_Wisps"): mat.set_shader_parameter("wisps", load(tex._Wisps))
	for pair in [["_Color", "color"], ["_Deep", "deep"], ["_Ground", "ground"]]:
		if c.has(pair[0]):
			mat.set_shader_parameter(pair[1], Color(c[pair[0]][0], c[pair[0]][1], c[pair[0]][2], 1.0))
	for pair in [["_DriftA", "drift_a"], ["_DriftB", "drift_b"]]:
		if c.has(pair[0]):
			mat.set_shader_parameter(pair[1], Vector2(c[pair[0]][0], c[pair[0]][1]))
	for pair in [["_Scale", "scale"], ["_GroundAmount", "ground_amount"], ["_Swirl", "swirl"]]:
		if f.has(pair[0]):
			mat.set_shader_parameter(pair[1], float(f[pair[0]]))
	layer.material = mat
	return layer


## A rectangle over the world, for the mist shader to fill.
class MistQuad extends Node2D:
	var rect := Rect2()

	func _draw() -> void:
		draw_rect(rect, Color.WHITE)
