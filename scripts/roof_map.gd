class_name RoofMap
extends Node
## Closes in every finished room (from Unity's RoofMap): cells shut in on all sides by walls (windows and doors count,
## fences don't) with a laid floor on every cell get a lid over them at the tops of their walls, made of roof tiles
## (each house's picked style, else the default look mixed with its variants cell by cell). The lid overhangs the walls
## on every side; each tile sorts by the house's front corner straight below it, so someone in front of part of the
## house still draws over that part. A chimney stands near the back corner, smoking. The lid fades out, and the walls
## nearest the camera turn see-through, while the player is inside.
##
## Not yet: snow on roofs (weather), the drop-in when a room is closed, trees under the eaves.

var world: World
var floors: FloorMap
var walls: WallMap
var data: Dictionary
var looks := {}            ## roof look name -> {whole tiles}
var roof_floors := {}      ## Vector2i -> roof look picked for that cell

var roofs := []            # [{cells: Dictionary, holders: [], tiles: [Sprite2D], front: [Edge], chimney: Vector2i, smoke, alpha}]
var _kept_smoke := {}      # Vector2i (chimney cell) -> smoke node, kept across a rebuild
var snowed := false        ## settled snow: every roof shows the snowy look (but round the chimney)
var _wall_version := -1
var _floor_version := -1
var _hearths := ""          # where the fireplaces stand (the chimneys stand over them): a change rebuilds
var _next_hearths := 0.0


func setup(w: World, f: FloorMap, wm: WallMap, d: Dictionary) -> void:
	world = w
	floors = f
	walls = wm
	data = d
	for l in d.looks:
		looks[l.name] = l


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"roof_map.process", __t)


func _process_timed(delta: float) -> void:
	if walls.rooms_version != _wall_version or floors.laid_version != _floor_version:
		rebuild()
	_chimneys()
	var inside := Vector2i(1 << 30, 0)
	if world.player != null:
		inside = floors.cell_at(world.player.position)
	for roof in roofs:
		var target := 0.0 if roof.cells.has(inside) else 1.0
		if roof.alpha < 1.0:
			_fade_front_walls(roof, lerpf(float(data.frontWallAlpha), 1.0, roof.alpha))
		if is_equal_approx(roof.alpha, target):
			continue
		roof.alpha = move_toward(roof.alpha, target, float(data.fadeSpeed) * delta)
		if roof.alpha >= 1.0:
			_fade_front_walls(roof, 1.0)
		_recolor(roof)


# ---- Reading ----

## Whether [param p] (a spot on the ground) is inside a roofed room.
func covers(p: Vector2) -> bool:
	return room_on(p) != null


## The cells of the closed room whose floor [param p] stands on, or null.
func room_on(p: Vector2) -> Variant:
	var cell := floors.cell_at(p)
	for roof in roofs:
		if roof.cells.has(cell):
			return roof.cells
	return null


## How solid the roof over [param p] is drawn now (1 shown, 0 faded away while Miko's inside), or 0 with no roof.
func alpha_over(p: Vector2) -> float:
	var cell := floors.cell_at(p)
	for roof in roofs:
		if roof.cells.has(cell):
			return float(roof.alpha)
	return 0.0


## Every closed room's cells.
func rooms() -> Array:
	return roofs.map(func(r): return r.cells)


## Turns every roof snowy (settled snow) or back.
func set_snowed(on: bool) -> void:
	if on == snowed:
		return
	snowed = on
	rebuild()


# ---- Picking a roof ----

## Roofs [param cells] with [param look]; "" goes back to the default.
func set_roof(cells: Array, look: String) -> void:
	for c in cells:
		if look == "": roof_floors.erase(c)
		else: roof_floors[c] = look
	rebuild()


func to_json() -> String:
	var out := []
	for c in roof_floors:
		out.append({"x": c.x, "y": c.y, "floor": roof_floors[c]})
	return JSON.stringify({"roofs": out})


func from_json(json: String) -> void:
	roof_floors.clear()
	var d: Dictionary = JSON.parse_string(json)
	for r in d.get("roofs", []):
		if looks.has(r.floor):
			roof_floors[Vector2i(int(r.x), int(r.y))] = r.floor
	rebuild()


# ---- Building ----

# A house's chimney stands over its fireplace, and smokes only while a fire burns in the house: looked at twice a
# second (a fireplace put in, moved or taken out rebuilds the roofs).
func _chimneys() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_hearths or world.props == null:
		return
	_next_hearths = now + 0.5
	var key := str(_hearth_cells())
	if key != _hearths:
		_hearths = key
		rebuild()
	var fires: Fires = world.player.get_node_or_null("Fires") if world.player != null else null
	for roof in roofs:
		if roof.smoke != null and is_instance_valid(roof.smoke):
			var p := roof.smoke.get_child(0) as CPUParticles2D
			var burning := fires != null and fires.warm_room(roof.cells)
			if p != null and p.emitting != burning:
				p.emitting = burning


# The cells the fireplaces stand on.
func _hearth_cells() -> Array:
	var out := []
	for at in world.props_named("Fireplace"):
		out.append(floors.cell_at(at))
	out.sort()
	return out


func rebuild() -> void:
	var __t := Time.get_ticks_usec()
	_rebuild_untimed()
	Perf.add(&"roofs: rebuild", __t)


func _rebuild_untimed() -> void:
	_wall_version = walls.rooms_version
	_floor_version = floors.laid_version
	# Keep how faded each roof was, so rebuilding while inside doesn't flash; and keep its chimney's smoke going.
	var faded := {}
	for roof in roofs:
		for c in roof.cells:
			faded[c] = roof.alpha
	_clear()
	for room in _find_rooms():
		var roof := _build(room)
		for c in room:
			if faded.has(c):
				roof.alpha = faded[c]
		_recolor(roof)
		roofs.append(roof)
	for s in _kept_smoke.values():
		s.queue_free()
	_kept_smoke.clear()


func _clear() -> void:
	for roof in roofs:
		if roof.alpha < 1.0:
			_fade_front_walls(roof, 1.0)
		if roof.smoke != null:
			roof.smoke.get_parent().remove_child(roof.smoke)
			_kept_smoke[roof.chimney] = roof.smoke
		for h in roof.holders:
			# The smoke is kept for the rebuilt roof (it goes on puffing); everything else goes.
			if h != roof.smoke and is_instance_valid(h):
				h.queue_free()
	roofs.clear()


# The rooms: cells closed in by walls with a laid floor on every cell, big enough to live in. (Fences don't close a
# room, so the search starts only from real walls, and checks a set of their edges made once, not each wall's length.)
func _find_rooms() -> Array:
	var blocked := _blocked_edges()
	var found := []
	var seen := {}
	for e in blocked:
		var v := Vector2i(e.x, e.y)
		var sides := [Vector2i(v.x - 1, v.y), v] if e.z == 1 else [Vector2i(v.x, v.y - 1), v]
		for start in sides:
			if seen.has(start):
				continue
			var room := _fill(start, seen, blocked)
			if room.is_empty() or not _floored(room):
				continue
			var size := _size(room)
			if size.x >= int(data.minRoomSize) and size.y >= int(data.minRoomSize):
				found.append(room)
	return found


# The edges (Vector3i keys) every wall but a fence covers, its whole length.
func _blocked_edges() -> Dictionary:
	var blocked := {}
	for k in walls.walls:
		var t: Dictionary = walls.types[walls.walls[k]]
		if t.fence:
			continue
		var step := WallMap._dir(k.z == 1)
		for i in int(t.length):
			blocked[Vector3i(k.x + step.x * i, k.y + step.y * i, k.z)] = true
	return blocked


# Every cell reachable from [param start] without crossing a wall in [param blocked], or {} if that runs off the map or
# past the most a room can be (not closed in).
func _fill(start: Vector2i, seen: Dictionary, blocked: Dictionary) -> Dictionary:
	var room := {start: true}
	var open := [start]
	seen[start] = true
	var most := int(data.maxRoomCells)
	var head := 0
	while head < open.size():
		var cell: Vector2i = open[head]
		head += 1
		if not floors.in_bounds(cell) or room.size() > most:
			return {}
		# Right and left cross edges along y (at x+1 and x); up and down, edges along x (at y+1 and y).
		var n := cell + Vector2i(1, 0)
		if not room.has(n) and not blocked.has(Vector3i(cell.x + 1, cell.y, 1)):
			room[n] = true; seen[n] = true; open.append(n)
		n = cell + Vector2i(-1, 0)
		if not room.has(n) and not blocked.has(Vector3i(cell.x, cell.y, 1)):
			room[n] = true; seen[n] = true; open.append(n)
		n = cell + Vector2i(0, 1)
		if not room.has(n) and not blocked.has(Vector3i(cell.x, cell.y + 1, 0)):
			room[n] = true; seen[n] = true; open.append(n)
		n = cell + Vector2i(0, -1)
		if not room.has(n) and not blocked.has(Vector3i(cell.x, cell.y, 0)):
			room[n] = true; seen[n] = true; open.append(n)
	return room


func _floored(room: Dictionary) -> bool:
	for c in room:
		if floors.get_laid(c) == "":
			return false
	return true


static func _size(room: Dictionary) -> Vector2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for c in room:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return hi - lo + Vector2i.ONE


func _build(cells: Dictionary) -> Dictionary:
	var roof := {"cells": cells, "holders": [], "tiles": [], "front": [], "chimney": Vector2i.ZERO, "smoke": null, "alpha": 1.0}
	var height: float = data.height
	var overhang: float = data.overhang
	# The lid is centred on the room, so growing it overhangs every side alike.
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c in cells:
		var p := floors.cell_centre(c)
		lo = lo.min(p)
		hi = hi.max(p)
	var root := (lo + hi) / 2.0 + Vector2(0, -height)
	var chimney := _chimney_spot(cells)
	# Over the fireplace, when the house has one.
	for c in _hearth_cells():
		if cells.has(c):
			# (a cell in from the wall it backs onto, so the chimney stands on the roof, not off its edge)
			chimney = c
			if not cells.has(c + Vector2i(1, 0)) and cells.has(c - Vector2i(1, 0)):
				chimney = c - Vector2i(1, 0)
			elif not cells.has(c + Vector2i(0, 1)) and cells.has(c - Vector2i(0, 1)):
				chimney = c - Vector2i(0, 1)
			break
	for c in cells:
		var left: bool = not cells.has(c + Vector2i(-1, 0))
		var front: bool = not cells.has(c + Vector2i(0, -1))
		# Side faces only along the lid's front edges, as a laid patch shows.
		var edges := (1 if left else 0) | (2 if front else 0)
		if left: roof.front.append(WallMap.Edge.new(c, true))
		if front: roof.front.append(WallMap.Edge.new(c, false))
		var at := root + (floors.cell_centre(c) + Vector2(0, -height) - root) * overhang
		# The warm chimney melts the snow off a small patch round its base: the cell it stands on.
		var tile := _tile(roof, _tile_sprite(c, edges, c == chimney), at, _lid_order(c, cells), overhang)
		if not (snowed and c != chimney):
			tile.material = world.snow_material(2)
	_add_chimney(roof, cells, chimney, root)
	return roof


# A roof piece drawn at [param at], sorting at [param sort] among everything standing.
func _tile(roof: Dictionary, sprite_id: int, at: Vector2, sort: float, scale: float) -> Sprite2D:
	var holder := Node2D.new()
	holder.position = Vector2(at.x, sort)
	var sprite := Sprite2D.new()
	if sprite_id >= 0:
		world.show_frame(sprite, sprite_id, Vector2(scale, scale))
	sprite.position = Vector2(0, at.y - sort)
	holder.add_child(sprite)
	world.things.add_child(holder)
	world.add_occluder(sprite)
	roof.holders.append(holder)
	roof.tiles.append(sprite)
	return sprite


# A chimney a cell in from the back corner (the top on screen), on its tile, always smoking.
func _add_chimney(roof: Dictionary, cells: Dictionary, spot: Vector2i, root: Vector2) -> void:
	var size := _size(cells)
	var big := size.x >= int(data.bigChimneyFrom) and size.y >= int(data.bigChimneyFrom)
	var art := int(data.chimneyBig if big and int(data.chimneyBig) >= 0 else data.chimneySmall)
	if art < 0:
		return
	var overhang: float = data.overhang
	var at := root + (floors.cell_centre(spot) + Vector2(0, -float(data.height)) - root) * overhang
	var sort := _lid_order(spot, cells) + 1.28
	var _sprite := _tile(roof, art, at, sort, overhang)
	roof.chimney = spot
	var info: Dictionary = world.sprites[art]
	var top := at + Vector2(0, -(info.pivot[1] * world.px / info.ppu) * overhang + 0.08 * world.px)
	var smoke: Node2D = _kept_smoke.get(spot)
	if smoke != null:
		_kept_smoke.erase(spot)
	else:
		smoke = Smoke.make()
		(smoke.get_child(0) as CPUParticles2D).emitting = false   # (till a fire's seen burning under it)
	smoke.position = Vector2(top.x, sort + 1.28)
	smoke.set_meta("top", top)
	smoke.get_child(0).position = Vector2(0, top.y - smoke.position.y)
	world.things.add_child(smoke)
	roof.holders.append(smoke)
	roof.smoke = smoke


# The roof look over [param cell]: the house's picked style, else the default look or one of its variants (by a hash
# of the cell, so it never changes); with front faces on the given edges.
func _tile_sprite(cell: Vector2i, edges: int, melted := false) -> int:
	var look: String = roof_floors.get(cell, "")
	if snowed and not melted and looks.has(data.snowRoof):
		look = data.snowRoof
		var snow: Array = looks[look].whole
		return FloorMap._sprite_for(snow[mini(edges, snow.size() - 1)], cell)
	if look == "" or not (data.styles as Array).has(look):
		look = _default_look(cell)
	var seen: Array = looks[look].whole
	return FloorMap._sprite_for(seen[mini(edges, seen.size() - 1)], cell)


func _default_look(cell: Vector2i) -> String:
	var variants: Array = data.variants
	var count := 1 + variants.size()
	# As Unity: each product wraps to 32 bits, then the two are xor'd as unsigned.
	var h := ((cell.x * 73856093) & 0xFFFFFFFF) ^ ((cell.y * 19349663) & 0xFFFFFFFF)
	var pick := h % count
	return data.defaultRoof if pick == 0 else variants[pick - 1]


# A roof tile's sort: by the front corner of its cell, a step in front of the walls round it.
func _tile_order(cell: Vector2i) -> float:
	return floors.corner(Vector2(cell)).y + 1.28


# A lid tile's sort: over every wall of the house below it on screen. Walk straight down the screen (a cell back on
# both axes) to the house's front, then take the front-most of that cell and its two front neighbours.
func _lid_order(cell: Vector2i, cells: Dictionary) -> float:
	var front := cell
	while cells.has(front - Vector2i.ONE):
		front -= Vector2i.ONE
	var sort := _tile_order(front)
	if cells.has(front + Vector2i(-1, 0)): sort = maxf(sort, _tile_order(front + Vector2i(-1, 0)))
	if cells.has(front + Vector2i(0, -1)): sort = maxf(sort, _tile_order(front + Vector2i(0, -1)))
	return sort


static func _chimney_spot(cells: Dictionary) -> Vector2i:
	var back: Vector2i = cells.keys()[0]
	for c in cells:
		if c.x + c.y > back.x + back.y or (c.x + c.y == back.x + back.y and c.x > back.x):
			back = c
	return back - Vector2i.ONE if cells.has(back - Vector2i.ONE) else back


# ---- Fading ----

func _recolor(roof: Dictionary) -> void:
	var t: Array = data.tint
	for s in roof.tiles:
		s.modulate = Color(t[0], t[1], t[2], roof.alpha)
	# The chimney's smoke goes with the roof: hidden while it's faded out (Miko inside).
	if roof.smoke != null:
		roof.smoke.visible = roof.alpha > 0.5


# The walls on the room's sides facing the camera, which hide whoever is inside.
func _fade_front_walls(roof: Dictionary, alpha: float) -> void:
	for e in roof.front:
		walls.set_alpha(e, alpha)


## Chimney smoke: round puffs, one at a time, that rise, swell and fade.
class Smoke:
	static var _tex: Texture2D

	static func make() -> Node2D:
		var holder := Node2D.new()
		holder.name = "Smoke"
		var p := CPUParticles2D.new()
		p.amount = 6
		p.lifetime = 2.5
		p.texture = _puff()
		p.direction = Vector2(0.15, -1)
		p.spread = 8.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = 40.0
		p.initial_velocity_max = 56.0
		p.scale_amount_min = 0.42
		p.scale_amount_max = 0.58
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(0.6, 1.0))
		curve.add_point(Vector2(1, 1.2))
		p.scale_amount_curve = curve
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.0))
		g.set_color(1, Color(0.9, 0.9, 0.93, 0.0))
		g.add_point(0.15, Color(1, 1, 1, 0.9))
		g.add_point(0.75, Color(0.95, 0.95, 0.97, 0.7))
		p.color_ramp = g
		holder.add_child(p)
		return holder

	# A round, softly outlined puff.
	static func _puff() -> Texture2D:
		if _tex != null:
			return _tex
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in s:
			for x in s:
				var d := Vector2(x + 0.5 - s / 2.0, y + 0.5 - s / 2.0).length() / (s / 2.0)
				var a := clampf((1.0 - d) * 6.0, 0.0, 1.0)
				var shade := 0.72 if d > 0.82 else lerpf(1.0, 0.9, d)
				img.set_pixel(x, y, Color(shade, shade, shade * 1.02, a))
		_tex = ImageTexture.create_from_image(img)
		return _tex


# ---- Build mode ----

var _missing: Array = []
var _missing_key := ""


## The bare cells in walled-in rooms that are mostly floored (so a missed tile is easy to find).
func missing_floor() -> Array:
	var key := "%d|%d" % [walls.rooms_version, floors.laid_version]
	if key == _missing_key:
		return _missing
	_missing_key = key
	_missing = []
	var seen := {}
	var blocked := _blocked_edges()
	for e in blocked:
		var v := Vector2i(e.x, e.y)
		for start2 in ([Vector2i(v.x - 1, v.y), v] if e.z == 1 else [Vector2i(v.x, v.y - 1), v]):
			if seen.has(start2):
				continue
			var room := _fill(start2, seen, blocked)
			if room.is_empty():
				continue
			var bare := []
			for c in room:
				if floors.get_laid(c) == "":
					bare.append(c)
			if not bare.is_empty() and bare.size() * 2 < room.size():
				_missing.append_array(bare)
	return _missing


## The roof look picked for [param cells] (the first one's), or the default.
func look_of(cells: Dictionary) -> String:
	for c in cells:
		if roof_floors.has(c):
			return roof_floors[c]
		break
	return str(data.get("defaultRoof", ""))


## The looks a house can be given: [[name, display]].
func styles() -> Array:
	return data.get("styles", []).map(func(n): return [n, str(looks.get(n, {}).get("display", n))])


## Every drawn roof piece (for hiding them while building).
func all_nodes() -> Array:
	var out := []
	for r in roofs:
		out.append_array(r.holders)
		if r.smoke != null and is_instance_valid(r.smoke):
			out.append(r.smoke)
	return out
