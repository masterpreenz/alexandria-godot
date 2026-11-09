class_name Exploration
extends Node
## What of the world Miko has seen (from Unity's Exploration): a fine grid over the whole map, cleared in a soft circle
## round her as she goes (and over the village), for the maps to lay a fog over what she hasn't (the maps come with
## phase 5). Saved with the game (world.explored).

const CELL := 0.4                  ## units per fog cell
const SIGHT := 6.5                 ## units round her the land is revealed (across the ground)

var world: World
var seen := PackedByteArray()      ## 0 unseen .. 255 fully seen, per cell
var width := 0
var height := 0
var rect := Rect2()                ## the world (units, y up as Unity's) the grid covers
var _last := Vector2(INF, 0)
var _fog: ImageTexture
var _fog_dirty := true
static var show_all := false        ## F11: the whole map without fog (only what's shown; not saved)
static var active: Exploration


func setup(w: World) -> void:
	world = w
	active = self
	# The ground's cell box, half a cell beyond (in Unity's units, y up, as the save keeps it).
	var b := world.floors.bounds
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in [b.position, Vector2i(b.end.x - 1, b.position.y), Vector2i(b.position.x, b.end.y - 1), b.end - Vector2i.ONE]:
		var p := world.floors.cell_centre(c) / world.px
		p.y = -p.y
		lo = Vector2(minf(lo.x, p.x - 0.5), minf(lo.y, p.y - 0.25))
		hi = Vector2(maxf(hi.x, p.x + 0.5), maxf(hi.y, p.y + 0.25))
	rect = Rect2(lo, hi - lo)
	width = maxi(8, ceili(rect.size.x / CELL))
	height = maxi(8, ceili(rect.size.y / CELL))
	seen.resize(width * height)
	seen.fill(0)


## The saved fog (Unity's world.explored: {width, height, seen (base64)}).
func from_json(json: String) -> void:
	_fog_dirty = true
	var d: Variant = JSON.parse_string(json)
	if not d is Dictionary or int(d.get("width", 0)) <= 0:
		return
	var bytes := Marshalls.base64_to_raw(str(d.get("seen", "")))
	var w := int(d.width)
	var h := int(d.height)
	if bytes.size() != w * h:
		return
	if w == width and h == height:
		seen = bytes
		return
	# The map grew (or shrank) round the same middle: what was seen goes over the middle of the new one.
	var ox := (width - w) / 2
	var oy := (height - h) / 2
	for y in h:
		for x in w:
			var tx := x + ox
			var ty := y + oy
			if tx >= 0 and tx < width and ty >= 0 and ty < height:
				seen[ty * width + tx] = bytes[y * w + x]


func to_json() -> String:
	return JSON.stringify({"width": width, "height": height, "seen": Marshalls.raw_to_base64(seen)})


## Clears the fog round [param at] (px) out to [param radius] units, softly at the edge.
func reveal(at: Vector2, radius: float) -> void:
	var u := Vector2(at.x, -at.y) / world.px
	var soft := minf(1.6, radius * 0.35)
	var x0 := floori((u.x - radius - rect.position.x) / CELL)
	var x1 := ceili((u.x + radius - rect.position.x) / CELL)
	var y0 := floori((u.y - radius * 0.5 - rect.position.y) / CELL)
	var y1 := ceili((u.y + radius * 0.5 - rect.position.y) / CELL)
	for y in range(maxi(0, y0), mini(height - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(width - 1, x1) + 1):
			var wx := rect.position.x + (x + 0.5) * CELL - u.x
			var wy := (rect.position.y + (y + 0.5) * CELL - u.y) * 2.0
			var d := sqrt(wx * wx + wy * wy)
			if d > radius:
				continue
			var v := roundi(255.0 * clampf((radius - d) / soft, 0.0, 1.0))
			var i := y * width + x
			if v > seen[i]:
				seen[i] = v
				_fog_dirty = true


## Whether [param at] (px) has been seen (more than half).
func is_seen(at: Vector2) -> bool:
	var u := Vector2(at.x, -at.y) / world.px
	var x := floori((u.x - rect.position.x) / CELL)
	var y := floori((u.y - rect.position.y) / CELL)
	return x >= 0 and y >= 0 and x < width and y < height and seen[y * width + x] > 128


func _process(_delta: float) -> void:
	var p := world.player
	if p == null or p.position.distance_squared_to(_last) < 0.25 * world.px * world.px:
		return
	_last = p.position
	reveal(p.position, SIGHT)
	if world.village.founded():
		reveal(world.village.centre(), world.village.half_size() + 1.0)


const FOG_COLOUR := Color8(18, 14, 12)


## The fog as a picture over [member rect] (its top row the world's top): dark where she hasn't been.
func fog() -> ImageTexture:
	if _fog != null and not _fog_dirty:
		return _fog
	_fog_dirty = false
	var bytes := PackedByteArray()
	bytes.resize(width * height * 4)
	for y in height:
		var row := (height - 1 - y) * width
		for x in width:
			var o := (row + x) * 4
			bytes[o] = 18
			bytes[o + 1] = 14
			bytes[o + 2] = 12
			bytes[o + 3] = 0 if show_all else 255 - seen[y * width + x]
	var img := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
	if _fog == null:
		_fog = ImageTexture.create_from_image(img)
	else:
		_fog.update(img)
	return _fog


## Marks the fog to be drawn again (after showing all, or loading).
func refog() -> void:
	_fog_dirty = true


## A box of the world (px) as the fog picture's texels.
func fog_region(box: Rect2) -> Rect2:
	var px := world.px
	var x0 := (box.position.x / px - rect.position.x) / CELL
	var x1 := (box.end.x / px - rect.position.x) / CELL
	var top := rect.end.y
	var y0 := (top - (-box.position.y / px)) / CELL
	var y1 := (top - (-box.end.y / px)) / CELL
	return Rect2(x0, y0, x1 - x0, y1 - y0)


## The world the fog covers, in px (Godot's y down).
func px_rect() -> Rect2:
	var px := world.px
	return Rect2(Vector2(rect.position.x * px, -rect.end.y * px), rect.size * px)
