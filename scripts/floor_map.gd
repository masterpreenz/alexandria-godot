class_name FloorMap
extends Node
## The world's floors (from Unity's FloorMap): one floor type per grid cell, painted and erased through this API by
## build mode, level design or game logic.
##
## Cells that aren't painted show the base floor (grass). Each other ground floor (dirt, stone) draws on its own layer,
## shifted half a cell so every drawn tile's four corners sit on four cell centres (a dual grid); the tile is the corner
## case of which of those cells it covers, so a painted cell blends into its neighbours on its own. A floor also covers
## cells of higher floors, filling in beneath them, so different floors meet without a gap. Laid floors (boards, brick
## and cobble paths) sit on top of the ground, one whole tile per cell, with a side face along each front edge where
## they end, and can be turned a quarter.
##
## Grid: Unity's isometric grid, 1 x 0.5 units a cell (128 x 64 px). Cell (x, y) runs +x down-right... in corner
## units: corner (x, y) is at origin + ex * x + ey * y.

signal floor_changed(cell: Vector2i, floor: String)

const CHUNK := 16  ## cells a side per drawn chunk

## The world version: saves stamped with it (or later) cover the area they record; older ones only the old map.
const WORLD_VERSION := 9
const OLD_AREA := Rect2i(-100, -100, 200, 200)
const REWORKED4 := [Rect2i(-98, -82, 40, 40), Rect2i(-74, -60, 40, 38), Rect2i(-54, -150, 40, 48)]
const REWORKED5 := Rect2i(-54, -150, 32, 300)
const REWORKED6 := [Rect2i(-90, -50, 54, 38), Rect2i(-98, -82, 40, 40)]
const REWORKED7 := [Rect2i(-70, 30, 20, 20)]
const ROAD_HALF_WIDTH := 2

var world: World
var base_floor := "Grass"
var types := {}            ## name -> {name, display, layer, tiles[16], whole[], turned[]}
var origin := Vector2.ZERO ## corner (0, 0), px
var ex := Vector2(64, -32)
var ey := Vector2(-64, -32)
var centre := Vector2(0, -32)
var lift := 32.0
var bounds := Rect2i()
var order := -10000
## Goes up whenever any floor changes, for things that rebuild from the whole map.
var version := 0
## Goes up when a laid floor (boards, paving) goes down or comes up: rooms (and their roofs) care only about those, not
## the ground painted under them (grass, dirt, tilled soil).
var laid_version := 0

var cells := {}            # Vector2i -> floor name (ground floors other than the base)
var laid := {}             # Vector2i -> floor name (whole floors on top)
var turned := {}           # Vector2i -> true
var original := {}
var original_laid := {}
var original_turned := {}
var _layers := {}          # floor name -> FloorLayer
var _ground: FloorLayer


func setup(w: World, data: Dictionary) -> void:
	world = w
	origin = _v(data.origin)
	ex = _v(data.ex)
	ey = _v(data.ey)
	centre = _v(data.centre)
	lift = data.lift
	order = int(data.order)
	bounds = Rect2i(int(data.bounds[0]), int(data.bounds[1]), int(data.bounds[2]), int(data.bounds[3]))
	base_floor = data.base
	for t in data.types:
		types[t.name] = t
	for p in data.painted:
		var at := Vector2i(int(p.x), int(p.y))
		if is_whole(p.floor):
			laid[at] = p.floor
			if p.turned:
				turned[at] = true
		else:
			cells[at] = p.floor
	original = cells.duplicate()
	original_laid = laid.duplicate()
	original_turned = turned.duplicate()
	# The ground (one layer), then each other floor's layer above it, by its layer number.
	_ground = FloorLayer.new(self, "Floor_" + base_floor)
	for n in types:
		if n != base_floor:
			_layers[n] = FloorLayer.new(self, "Floor_" + n)


## The layers to draw, each with its Unity sorting order (the world interleaves them with the water by order).
func layer_nodes() -> Array:
	var out := [[order, _ground]]
	for n in _layers:
		out.append([_layer_order(n), _layers[n]])
	return out


static func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


func _layer_order(n: String) -> int:
	return order + 1 + clampi(int(types[n].layer), 0, 8)


func is_whole(n: String) -> bool:
	return types.has(n) and (types[n].whole as Array).size() > 0


func can_turn(n: String) -> bool:
	return types.has(n) and (types[n].turned as Array).size() > 0


# ---- Geometry ----

## A corner (or fractional corner coordinates) in the world.
func corner(c: Vector2) -> Vector2:
	return origin + ex * c.x + ey * c.y


func cell_centre(cell: Vector2i) -> Vector2:
	return corner(Vector2(cell)) + centre


## Cell coordinates of [param p] before rounding to a cell, in corner units.
func fractional_cell(p: Vector2) -> Vector2:
	var d := p - origin
	var u := d.x / ex.x
	var v := d.y / ex.y  # ex.y is negative: up the screen is up the grid
	return Vector2((u + v) / 2.0, (v - u) / 2.0)


func cell_at(p: Vector2) -> Vector2i:
	var f := fractional_cell(p)
	return Vector2i(floori(f.x), floori(f.y))


func in_bounds(cell: Vector2i) -> bool:
	return bounds.has_point(cell)


# ---- Reading ----

## The ground on [param cell], under anything laid on it.
func get_floor(cell: Vector2i) -> String:
	return cells.get(cell, base_floor)


## The floor laid on top of [param cell]'s ground, or "".
func get_laid(cell: Vector2i) -> String:
	return laid.get(cell, "")


func is_turned(cell: Vector2i) -> bool:
	return turned.has(cell)


## Whether anything's on [param p] besides the base grass (a path, stone, boards).
func on_floor(p: Vector2) -> bool:
	var c := cell_at(p)
	return get_floor(c) != base_floor or get_laid(c) != ""


# ---- Painting ----

## Paints ground on [param cell], or lays a laid floor on top (turned a quarter if [param turn] and it can turn); the
## base floor (or "") erases the ground.
func paint(cell: Vector2i, floor_name: String, turn := false) -> void:
	if not in_bounds(cell):
		return
	if floor_name != "" and is_whole(floor_name):
		turn = turn and can_turn(floor_name)
		if get_laid(cell) == floor_name and is_turned(cell) == turn:
			return
		laid[cell] = floor_name
		laid_version += 1
		if turn: turned[cell] = true
		else: turned.erase(cell)
		_changed(cell)
		return
	if floor_name == "" or floor_name == base_floor:
		erase(cell)
		return
	if get_floor(cell) == floor_name:
		return
	cells[cell] = floor_name
	_changed(cell)


func erase(cell: Vector2i) -> void:
	if cells.erase(cell):
		_changed(cell)


## Lifts the laid floor off [param cell], leaving its ground.
func unlay(cell: Vector2i) -> void:
	turned.erase(cell)
	if laid.erase(cell):
		laid_version += 1
		_changed(cell)


## Puts [param cell]'s ground and laid floor back to how the map loaded.
func restore(cell: Vector2i) -> void:
	paint(cell, original.get(cell, base_floor))
	if original_laid.has(cell):
		paint(cell, original_laid[cell], original_turned.has(cell))
	else:
		unlay(cell)


func _changed(cell: Vector2i) -> void:
	version += 1
	for n in _layers:
		if is_whole(n):
			# This cell and the two behind it, whose front edges it may now hide or show.
			_draw_whole(n, cell)
			_draw_whole(n, cell + Vector2i.RIGHT)
			_draw_whole(n, cell + Vector2i(0, 1))
		else:
			for dx in [-1, 0]:
				for dy in [-1, 0]:
					_draw_tile(n, cell + Vector2i(dx, dy))
	floor_changed.emit(cell, get_floor(cell))


# ---- Saving ----

## The painted cells, for save games (as Unity's SaveData).
func to_json() -> String:
	var out := []
	for c in cells:
		out.append({"x": c.x, "y": c.y, "floor": cells[c], "turned": false})
	for c in laid:
		out.append({"x": c.x, "y": c.y, "floor": laid[c], "turned": turned.has(c)})
	return JSON.stringify({"cells": out, "areaX": bounds.position.x, "areaY": bounds.position.y,
		"areaW": bounds.size.x, "areaH": bounds.size.y, "world": WORLD_VERSION})


## Replaces every painted cell with those saved; land the save never covered (the map has grown or been reshaped
## since) is taken from the scene, as Unity did.
func from_json(json: String) -> void:
	var data: Dictionary = JSON.parse_string(json)
	cells.clear()
	laid.clear()
	laid_version += 1
	turned.clear()
	for c in data.get("cells", []):
		if not types.has(c.floor):
			continue
		var at := Vector2i(int(c.x), int(c.y))
		if is_whole(c.floor):
			laid[at] = c.floor
			if c.get("turned", false):
				turned[at] = true
		else:
			cells[at] = c.floor
	var w := int(data.get("world", 0))
	var area := _saved_area(int(data.get("areaX", 0)), int(data.get("areaY", 0)), int(data.get("areaW", 0)), int(data.get("areaH", 0)), w)
	for c in cells.keys():
		if from_scene(c, area, w): cells.erase(c)
	for c in laid.keys():
		if from_scene(c, area, w):
			laid.erase(c)
			turned.erase(c)
	for c in original:
		if from_scene(c, area, w): cells[c] = original[c]
	# Saves from before the main roads were widened: the roads' new cells, where the save has nothing painted.
	if w < 3:
		for c in original:
			if (absi(c.x) <= ROAD_HALF_WIDTH or absi(c.y) <= ROAD_HALF_WIDTH) and not cells.has(c) and not laid.has(c):
				cells[c] = original[c]
	for c in original_laid:
		if from_scene(c, area, w):
			laid[c] = original_laid[c]
			if original_turned.has(c): turned[c] = true
	redraw()


static func _saved_area(x: int, y: int, w: int, h: int, world_version: int) -> Rect2i:
	return Rect2i(x, y, w, h) if world_version >= 2 and w > 0 and h > 0 else OLD_AREA


static func added_since(cell: Vector2i, w: int) -> bool:
	if w < 9:
		for r in REWORKED7:
			if r.has_point(cell): return true
	return false


## Whether a save stamped [param w], covering [param area], leaves [param cell] to the scene.
static func from_scene(cell: Vector2i, area: Rect2i, w: int) -> bool:
	if not area.has_point(cell): return true
	if w < 4:
		for r in REWORKED4:
			if r.has_point(cell): return true
	if w < 5 and REWORKED5.has_point(cell): return true
	if w < 6:
		for r in REWORKED6:
			if r.has_point(cell): return true
	return added_since(cell, w)


# ---- Drawing ----

func redraw() -> void:
	version += 1
	_ground.clear()
	var base: Dictionary = types[base_floor]
	# (and on past the map's edges, for looks: Outskirts)
	var drawn := bounds.grow(Outskirts.MARGIN)
	for x in range(drawn.position.x, drawn.end.x):
		for y in range(drawn.position.y, drawn.end.y):
			var c := Vector2i(x, y)
			_ground.put(c, cell_centre(c), _sprite_for(base.tiles[15], c))
	# Only round what's painted: a drawn tile has a painted cell at one of its corners; a laid tile is its own cell.
	for n in _layers:
		_layers[n].clear()
	var around := {}
	for c in cells:
		for dx in [-1, 0]:
			for dy in [-1, 0]:
				around[c + Vector2i(dx, dy)] = true
	for n in _layers:
		if is_whole(n):
			for c in laid:
				if laid[c] == n: _draw_whole(n, c)
		else:
			for at in around:
				_draw_tile(n, at)
	for l in [_ground] + _layers.values():
		l.refresh()


## The sprite a tile shows at [param at]: a plain tile's sprite, or a periodic tile's piece for that position.
static func _sprite_for(tile: Variant, at: Vector2i) -> int:
	if tile == null:
		return -1
	if tile.has("sprite"):
		return int(tile.sprite)
	var period: Array = tile.period
	var u := posmod(at.x - at.y, int(period[0]))
	var v := posmod(at.x + at.y, int(period[1]))
	var i := u * int(period[1]) + v
	var pieces: Array = tile.pieces
	return int(pieces[i]) if i < pieces.size() else -1


func _covers(n: String, x: int, y: int) -> bool:
	var there: String = cells.get(Vector2i(x, y), "")
	return there != "" and int(types[there].layer) >= int(types[n].layer)


# Drawn tile (x, y)'s corners are the centres of cells left (x, y+1), bottom (x, y), right (x+1, y) and top (x+1, y+1).
func _draw_tile(n: String, at: Vector2i) -> void:
	var corners := (1 if _covers(n, at.x, at.y + 1) else 0) | (2 if _covers(n, at.x, at.y) else 0) \
		| (4 if _covers(n, at.x + 1, at.y) else 0) | (8 if _covers(n, at.x + 1, at.y + 1) else 0)
	var sprite := -1 if corners == 0 else _sprite_for(types[n].tiles[corners], at)
	_layers[n].put(at, cell_centre(at) + Vector2(0, -lift), sprite)


# A laid floor covers its whole cell and shows a side face along each front edge where it ends: left where the cell
# down-left (x-1) isn't laid with it, right where the cell down-right (y-1) isn't.
func _draw_whole(n: String, cell: Vector2i) -> void:
	var sprite := -1
	if get_laid(cell) == n:
		var edges := (1 if get_laid(cell - Vector2i.RIGHT) != n else 0) | (2 if get_laid(cell - Vector2i(0, 1)) != n else 0)
		var seen: Array = types[n].turned if is_turned(cell) and can_turn(n) else types[n].whole
		sprite = _sprite_for(seen[mini(edges, seen.size() - 1)], cell)
	_layers[n].put(cell, cell_centre(cell), sprite)


## One floor's tiles, in chunks that each draw their tiles in one go (back to front) and are culled off screen.
class FloorLayer extends Node2D:
	var map: FloorMap
	var chunks := {}  # Vector2i -> Chunk
	var _dirty := {}

	func _init(m: FloorMap, n: String) -> void:
		map = m
		name = n
		# The ground and ground floors settle snow; boards (mostly indoors) don't.
		if not m.is_whole(n.trim_prefix("Floor_")):
			# The grass gets its own: snow as the other ground, and the noise that varies it.
			material = m.world.snow_material(3 if n == "Floor_" + m.base_floor else 1)

	func clear() -> void:
		for c in chunks.values():
			c.tiles.clear()
			_dirty[c] = true

	func put(cell: Vector2i, at: Vector2, sprite: int) -> void:
		var key := Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))
		var chunk: Chunk = chunks.get(key)
		if chunk == null:
			if sprite < 0:
				return
			chunk = Chunk.new()
			chunk.layer = self
			chunk.use_parent_material = true
			chunks[key] = chunk
			add_child(chunk)
		if sprite < 0:
			if chunk.tiles.erase(cell): _mark(chunk)
		elif chunk.tiles.get(cell, [-1])[0] != sprite:
			chunk.tiles[cell] = [sprite, at]
			_mark(chunk)

	func _mark(chunk: Chunk) -> void:
		if not _dirty.has(chunk):
			_dirty[chunk] = true
			refresh.call_deferred()

	func refresh() -> void:
		for c in _dirty:
			c.queue_redraw()
		_dirty.clear()


class Chunk extends Node2D:
	var layer
	var tiles := {}  # Vector2i -> [sprite, position]

	func _draw() -> void:
		var world: World = layer.map.world
		# Back cells first (higher on screen), so a laid tile's front edge overlaps the one behind it.
		var keys := tiles.keys()
		keys.sort_custom(func(a, b): return tiles[a][1].y < tiles[b][1].y)
		for k in keys:
			var info: Dictionary = world.sprites[tiles[k][0]]
			var tex: Texture2D = world._texture(info.tex)
			if tex == null:
				continue
			var s: float = world.px / info.ppu
			var at: Vector2 = tiles[k][1] - Vector2(info.pivot[0], info.pivot[1]) * s
			draw_texture_rect_region(tex, Rect2(at, Vector2(info.rect[2], info.rect[3]) * s), Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3]))
