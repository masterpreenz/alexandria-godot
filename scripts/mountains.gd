class_name Mountains
extends Node
## The mountains closing off the map's north-east edge (its highest x), all along sections H1 to H8, and the cave in
## them where H4 meets H5 (from Unity's MountainBorder and CaveEntrance).
## - Rows of rock pieces (assets/Art/Environment/Mountains), small and low at the foot and towering at the back and
##   past the edge. Nothing can be walked or built on them: a collider runs along their foot, build mode asks
##   [method covers], and whatever grew there (trees, bushes, stones) is hidden under the rock. Laid out the same every
##   time (a fixed seed), not saved.
## - The cave: its mouth opens in the foot of the range; walking in fades to black and out again inside the cave
##   dungeon. For now that's a stand-in: one plain chamber off the map (dummy textures), free of mist, with its way
##   out at the bottom, which fades back out to the cave's mouth.

const EDGE := 141                 ## the map's highest x (cells)
const FROM := -142                ## the stretch along y: the whole edge
const TO := 141
const DEPTH := 10                 ## tiles in from the edge the mountains' foot reaches
## The rows from the back: how far in from the edge (tiles; less than 0 is past it), how big their pieces are (tiles
## across the base), how much taller than drawn they stand.
const ROWS := [[-16.0, 15.0, 1.6], [-8.0, 12.0, 1.5], [-1.5, 9.0, 1.4], [3.5, 6.5, 1.25], [7.3, 4.2, 1.1]]
## Each piece's art: its ground's middle in it (share across, share up from the bottom) and its px to a unit.
const PIECES := [["mountain_1", 0.4996, 0.3302, 290.25], ["mountain_2", 0.4996, 0.427, 298.75], ["mountain_3", 0.4996, 0.2852, 286.75], ["mountain_4", 0.4996, 0.2894, 283.75]]
const ART := "res://assets/Art/Environment/Mountains/%s.png"

const CAVE_CENTRE := Vector2(135.5, 1.6)   ## the cave's ground diamond, centred on this cell (fractional)
const CAVE_SIZE := 7.0                     ## tiles across
const CAVE_ART := ["cave_entrance", 0.5, 0.2515, 176.57]
const MOUTH_FROM := -2            ## the mouth: these cells along the foot (y)...
const MOUTH_TO := 1
const MOUTH_DEPTH := 3            ## ...open this many tiles in from it
## The chamber, in units, well off the map (below it).
const ROOM := Rect2(-9.0, 161.0, 18.0, 11.0)
const RIM := 0.8

static var active: Mountains

var world: World
var miko: Miko
var _holder: Node2D
var _fade: ColorRect
var _busy := false
var _hide_at := [0.5, 3.0]        ## seconds on: what's under the rock is hidden (after the save has laid the world out)
var _age := 0.0


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	active = self
	_holder = Node2D.new()
	_holder.name = "Mountains"
	_holder.y_sort_enabled = true
	world.things.add_child(_holder)
	_rocks()
	_cave()
	_wall()
	_room()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	_fade.z_index = 100
	hud.add_child(_fade)


## Whether [param cell] lies under the mountains (nothing can be built there).
static func covers(cell: Vector2i) -> bool:
	return active != null and cell.x > EDGE - DEPTH and cell.y >= FROM and cell.y <= TO


## Whether [param at] (px) is inside the cave dungeon (underground: out of the mist).
static func in_cave(at: Vector2) -> bool:
	return active != null and (ROOM.grow(RIM)).has_point(at / active.world.px)


# The rows of rock, back to front.
func _rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4151
	var textures := []
	for p in PIECES:
		textures.append(load(ART % p[0]))
	for row in ROWS:
		var depth: float = row[0]
		var size: float = row[1]
		var tall: float = row[2]
		# Along the edge, a little past each end so the corners are closed off.
		var along := FROM - size * 0.6
		while along <= TO + 0.5 - size * 0.25:
			var s := size * rng.randf_range(0.85, 1.15)
			var cell := Vector2(EDGE + 0.5 - depth + rng.randf_range(-0.4, 0.4) * size * 0.15, along + 0.5)
			var which := rng.randi() % PIECES.size()
			var stretch := tall * rng.randf_range(0.92, 1.08)
			var flip := rng.randi() % 2 == 0
			along += size * 0.62 * rng.randf_range(0.85, 1.15)
			# The cave stands in the front rows: no rock in front of it or through it.
			if cell.x < CAVE_CENTRE.x + CAVE_SIZE / 2.0 and absf(cell.y - CAVE_CENTRE.y) < (CAVE_SIZE + s) / 2.0:
				continue
			_place(textures[which], PIECES[which], cell, s / 4.0, stretch, flip)


# A piece with its ground diamond centred on the (fractional) cell, its base [param k] x 4 tiles across, stretched
# [param tall] times upwards from its ground's middle. Sorted by where its ground sits, as everything else is.
func _place(tex: Texture2D, piece: Array, cell: Vector2, k: float, tall: float, flip: bool) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = false
	var size := tex.get_size()
	sp.offset = Vector2(-size.x * float(piece[1]), -size.y * (1.0 - float(piece[2])))
	var to_px := world.px / float(piece[3]) * k
	sp.scale = Vector2(-to_px if flip else to_px, to_px * tall)
	sp.position = world.floors.corner(cell)
	_holder.add_child(sp)
	return sp


func _cave() -> void:
	var sp := _place(load(ART % CAVE_ART[0]), CAVE_ART, CAVE_CENTRE, 1.0, 1.0, false)
	sp.name = "Cave"


# The foot: walked into, not through. Along the inner side, in round the cave's mouth, closed at its ends.
func _wall() -> void:
	var f := world.floors
	var inner := EDGE + 1 - DEPTH
	var pts: Array[Vector2] = [
		f.corner(Vector2(EDGE + 1, FROM)), f.corner(Vector2(inner, FROM)),
		f.corner(Vector2(inner, MOUTH_FROM)), f.corner(Vector2(inner + MOUTH_DEPTH, MOUTH_FROM)),
		f.corner(Vector2(inner + MOUTH_DEPTH, MOUTH_TO + 1)), f.corner(Vector2(inner, MOUTH_TO + 1)),
		f.corner(Vector2(inner, TO + 1)), f.corner(Vector2(EDGE + 1, TO + 1)),
	]
	_segments(pts)


func _segments(pts: Array[Vector2]) -> void:
	for i in pts.size() - 1:
		var shape := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = pts[i]
		seg.b = pts[i + 1]
		shape.shape = seg
		world.solids.add_child(shape)


# The stand-in chamber: a dark stone floor, a rim of rock round it (walls you can't pass), and the way out.
func _room() -> void:
	var px := world.px
	var room := Node2D.new()
	room.name = "CaveRoom"
	room.z_as_relative = false
	room.z_index = -100
	world.add_child(room)
	var r := Rect2(ROOM.position * px, ROOM.size * px)
	var rim := RIM * px
	var rock := _checker(Color(0.36, 0.34, 0.4), Color(0.31, 0.29, 0.35))
	# (the dark all round it, so nothing of the world's emptiness shows)
	_quad(room, r.grow(40.0 * px), _checker(Color(0.05, 0.05, 0.07), Color(0.05, 0.05, 0.07)))
	_quad(room, r.grow(rim), rock)
	_quad(room, Rect2(r.position + Vector2(0, rim), r.size - Vector2(0, rim)), _checker(Color(0.24, 0.23, 0.27), Color(0.2, 0.19, 0.23)))
	# The way out: a pale patch of daylight at the bottom.
	var out := _exit()
	_quad(room, Rect2(out.x - 0.8 * px, r.end.y - 0.8 * px, 1.6 * px, 0.9 * px), _checker(Color(0.78, 0.74, 0.62), Color(0.72, 0.68, 0.56)))
	var pts: Array[Vector2] = [r.end, Vector2(r.position.x, r.end.y), r.position + Vector2(0, rim), Vector2(r.end.x, r.position.y + rim), r.end]
	_segments(pts)


func _exit() -> Vector2:
	return Vector2(ROOM.get_center().x, ROOM.end.y - 0.6) * world.px


func _quad(parent: Node2D, rect: Rect2, tex: Texture2D) -> void:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sp.region_enabled = true
	# (a check to a unit)
	sp.region_rect = Rect2(Vector2.ZERO, rect.size / world.px * 8.0)
	sp.scale = Vector2.ONE * world.px / 8.0
	sp.centered = false
	sp.position = rect.position
	parent.add_child(sp)


# A dummy texture: soft checks.
static func _checker(a: Color, b: Color) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			@warning_ignore("integer_division")
			img.set_pixel(x, y, a if (x / 4 + y / 4) % 2 == 0 else b)
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_age += delta
	if not _hide_at.is_empty() and _age >= float(_hide_at[0]):
		_hide_at.pop_front()
		_hide_under()
	if _busy or miko == null:
		return
	var p := miko.position
	if in_cave(p):
		if p.distance_to(_exit()) < 0.7 * world.px:
			_go(false)
		return
	# In the mouth: past the foot of the mountains, between its sides.
	var cell := world.floors.fractional_cell(p)
	var foot := EDGE + 1 - DEPTH
	if cell.x > foot + 1.6 and cell.y > MOUTH_FROM and cell.y < MOUTH_TO + 1:
		_go(true)


# Fade to black, move, fade back in.
func _go(inside: bool) -> void:
	_busy = true
	var was_locked := miko.locked
	miko.locked = true
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	await tw.finished
	var to := _exit() + Vector2(0, -1.6 * world.px) if inside \
		else world.floors.corner(Vector2(EDGE + 1 - DEPTH - 1.5, (MOUTH_FROM + MOUTH_TO + 1) / 2.0))
	miko.place(to)
	miko.velocity = Vector2.ZERO
	await get_tree().create_timer(0.15).timeout
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.35)
	await tw.finished
	_fade.visible = false
	miko.locked = was_locked
	_busy = false


# Whatever grows or stands where the rock is (trees, bushes, stones) is hidden: the rock covers it.
func _hide_under() -> void:
	for n in world.things.get_children():
		if n == _holder or n is CharacterBody2D or not (n is Node2D):
			continue
		if (n as Node2D).visible and covers(world.floors.cell_at((n as Node2D).position)):
			(n as Node2D).visible = false
