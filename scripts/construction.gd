class_name Construction
extends Node2D
## Blueprints (from Unity's Construction): what's planned in build mode's blueprint mode (floor tiles, walls, whole
## house presets and their furniture) but not built yet. Each piece shows shaded where it will go: blue while it's a
## draft, warm once it's ready. Villagers build only ready pieces: they take what a piece costs from the village's
## storage, go to it, and lay it (floors first, then walls, then what goes inside). Plans are saved (village.blueprints).
## (Drawing the plans comes with build mode, phase 5.)
##
## A piece (as Unity saves it): {wall, prop, free, fx, fy (a freely set prop: where, in cell coordinates), x, y,
## alongY, turned, ready, type, roof, turn, scale}.

const DRAFT := Color(0.55, 0.75, 1.0, 0.5)
const READY := Color(1.0, 0.86, 0.6, 0.55)

static var active: Construction

var world: World
var costs: Dictionary              ## build.json: floors, walls, props -> [[resource, amount]]
var pieces: Array = []
var _ghosts := {}                  ## piece (by id) -> Node2D
var _diamond: Texture2D


func setup(w: World, data: Dictionary) -> void:
	world = w
	costs = data
	active = self


func from_json(json: String) -> void:
	for p in pieces:
		_drop(p)
	pieces.clear()
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		for p in d.get("pieces", []):
			_add(p)


func to_json() -> String:
	return JSON.stringify({"pieces": pieces})


func has(p: Dictionary) -> bool:
	return pieces.has(p)


func drafts() -> int:
	return pieces.filter(func(p): return not bool(p.get("ready", false))).size()


## Marks every draft ready for the villagers to build.
func start_building() -> int:
	var n := 0
	for p in pieces:
		if not bool(p.get("ready", false)):
			p.ready = true
			n += 1
			_ghost(p)
	if n > 0:
		VillageLog.event("build-start", "Construction started: %d pieces for the villagers to build" % n)
	return n


func _add(p: Dictionary) -> void:
	pieces.append(p)
	_ghost(p)


func _drop(p: Dictionary) -> void:
	var key := _key(p)
	if _ghosts.has(key):
		if is_instance_valid(_ghosts[key]):
			_ghosts[key].queue_free()
		_ghosts.erase(key)


func _key(p: Dictionary) -> String:
	return "%s|%s|%s|%d,%d|%s|%.2f,%.2f" % [p.get("wall", false), p.get("prop", false), p.get("free", false), int(p.x), int(p.y),
		p.get("alongY", false), float(p.get("fx", 0.0)), float(p.get("fy", 0.0))]


## What a piece costs: [[resource, amount]].
func cost_of(p: Dictionary) -> Array:
	var kind := "props" if bool(p.get("prop", false)) else ("walls" if bool(p.get("wall", false)) else "floors")
	return costs.get(kind, {}).get(p.type, [])


func affordable(p: Dictionary) -> bool:
	for c in cost_of(p):
		if world.village.stored(c[0]) < int(c[1]):
			return false
	return true


## Where a piece goes, on the ground.
func position_of(p: Dictionary) -> Vector2:
	if bool(p.get("free", false)):
		return world.floors.corner(Vector2(float(p.fx), float(p.fy)))
	if bool(p.get("wall", false)):
		return world.walls.edge_middle(WallMap.Edge.new(Vector2i(int(p.x), int(p.y)), bool(p.alongY)))
	return world.floors.cell_centre(Vector2i(int(p.x), int(p.y)))


## The ready piece nearest [param near] that storage can pay for and isn't in [param taken] (floors before walls
## before furniture), or {}; says in the village's messages when ready work is waiting on materials.
func next(near: Vector2, taken: Array) -> Dictionary:
	var best := {}
	var best_score := INF
	var short_of := {}
	for p in pieces:
		if not bool(p.get("ready", false)) or taken.has(p):
			continue
		if not affordable(p):
			if short_of.is_empty():
				short_of = p
			continue
		var score := position_of(p).distance_to(near) / world.px + (2000.0 if bool(p.get("prop", false)) else (1000.0 if bool(p.get("wall", false)) else 0.0))
		if score < best_score:
			best_score = score
			best = p
	if best.is_empty() and not short_of.is_empty():
		var parts := []
		for c in cost_of(short_of):
			parts.append("%d %s" % [c[1], UiKit.resource_name(c[0]).to_lower()])
		VillageLog.problem("build-materials", "Construction is waiting on materials in storage: %s for the next piece" % ", ".join(parts))
	return best


## Pays for a piece from storage and lays it; false (nothing taken) if storage can't.
func build(p: Dictionary) -> bool:
	if not pieces.has(p) or not affordable(p):
		return false
	for c in cost_of(p):
		world.village.take_from_stash(c[0], int(c[1]))
	var scale := float(p.get("scale", 1.0))
	if scale <= 0.0:
		scale = 1.0
	if bool(p.get("prop", false)):
		var t: Dictionary = world.props.types.get(p.type, {})
		if not t.is_empty():
			var turns := maxi(1, world.props._turns(t))
			var turn := posmod(int(p.get("turn", 0)), turns) if turns > 1 else -1
			if bool(p.get("free", false)):
				world.props.place_free(position_of(p), p.type, scale, turn)
			else:
				world.props.place(Vector2i(int(p.x), int(p.y)), p.type, scale, turn)
	elif bool(p.get("wall", false)):
		world.walls.place(WallMap.Edge.new(Vector2i(int(p.x), int(p.y)), bool(p.alongY)), p.type)
	else:
		var cell := Vector2i(int(p.x), int(p.y))
		world.props.remove_all(cell)
		# Anything growing there (a tree, a rock) is cleared.
		var at := world.floors.cell_centre(cell)
		for g in Gatherable.all.duplicate():
			if g.foot.distance_to(at) < 0.6 * world.px:
				g.queue_free()
		world.floors.paint(cell, p.type, bool(p.get("turned", false)))
		if str(p.get("roof", "")) != "":
			world.roofs.set_roof([cell], p.roof)
	_drop(p)
	pieces.erase(p)
	if pieces.is_empty():
		VillageLog.event("build-done", "Construction finished")
	return true


func _process(_delta: float) -> void:
	if drafts() > 0:
		VillageLog.problem("drafts", "Blueprints drawn: \"Start building\" in build mode when they're ready", VillageLog.Kind.NEWS)


# ---- The shaded pieces in the world ----

func _ghost(p: Dictionary) -> void:
	_drop(p)
	var tint := READY if bool(p.get("ready", false)) else DRAFT
	var holder := Node2D.new()
	var sprite := Sprite2D.new()
	holder.add_child(sprite)
	sprite.modulate = tint
	var at := position_of(p)
	holder.position = at
	if bool(p.get("prop", false)):
		var t: Dictionary = world.props.types.get(p.type, {})
		if t.is_empty():
			return
		var turns := maxi(1, world.props._turns(t))
		var turn := posmod(int(p.get("turn", 0)), turns)
		var id := world.props.sprite_for(p.type, turn)
		var flipped: bool = (t.turnSprites as Array).is_empty() and turns > 1 and turn % 2 == 1
		var k := float(p.get("scale", 1.0))
		world.show_frame(sprite, id, Vector2(-k if flipped else k, k))
		holder.position.y += 2.0
		world.things.add_child(holder)
	elif bool(p.get("wall", false)):
		var t: Dictionary = world.walls.types.get(p.type, {})
		if t.is_empty():
			return
		var own_y: bool = bool(p.alongY) and int(t.leftY) >= 0
		var art := int(t.leftY if own_y else t.left)
		if art >= 0:
			world.show_frame(sprite, art, Vector2(-1.0 if bool(p.alongY) and not own_y else 1.0, 1.0))
		holder.position.y += 3.0
		world.things.add_child(holder)
	else:
		sprite.texture = _tile_diamond()
		sprite.scale = Vector2.ONE * world.px / 64.0
		world.add_ground_layer(holder, -9989)
	_ghosts[_key(p)] = holder


# A tile-shaped diamond, for a planned floor tile.
func _tile_diamond() -> Texture2D:
	if _diamond != null:
		return _diamond
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dd := absf(x + 0.5 - w / 2.0) / (w / 2.0) + absf(y + 0.5 - h / 2.0) / (h / 2.0)
			var a := 0.55 if dd <= 0.92 else (1.0 if dd <= 1.0 else 0.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_diamond = ImageTexture.create_from_image(img)
	return _diamond


# ---- Planning (build mode's blueprint mode) ----

func _remove_where(test: Callable) -> bool:
	var gone := false
	for p in pieces.duplicate():
		if test.call(p):
			_drop(p)
			pieces.erase(p)
			gone = true
	return gone


## A planned floor tile on [param cell] (replacing any plan there).
func plan_floor(cell: Vector2i, floor: String, turned: bool) -> void:
	_remove_where(func(p): return not bool(p.get("wall", false)) and not bool(p.get("prop", false)) and int(p.x) == cell.x and int(p.y) == cell.y)
	_add({"wall": false, "prop": false, "free": false, "x": cell.x, "y": cell.y, "type": floor, "turned": turned, "ready": false, "scale": 1.0})


## A planned wall on [param edge].
func plan_wall(edge: WallMap.Edge, type: String) -> void:
	_remove_where(func(p): return bool(p.get("wall", false)) and int(p.x) == edge.vertex.x and int(p.y) == edge.vertex.y and bool(p.get("alongY", false)) == edge.along_y)
	_add({"wall": true, "prop": false, "free": false, "x": edge.vertex.x, "y": edge.vertex.y, "alongY": edge.along_y, "type": type, "ready": false, "scale": 1.0})


## Takes away one plan at [param cell]: furniture first, then a wall on one of [param edges], then the floor.
func remove_at(cell: Vector2i, edges: Array) -> bool:
	for p in pieces:
		if bool(p.get("prop", false)) and int(p.x) == cell.x and int(p.y) == cell.y:
			_drop(p)
			pieces.erase(p)
			return true
	for e in edges:
		for p in pieces:
			if bool(p.get("wall", false)) and int(p.x) == e.vertex.x and int(p.y) == e.vertex.y and bool(p.get("alongY", false)) == e.along_y:
				_drop(p)
				pieces.erase(p)
				return true
	for p in pieces:
		if not bool(p.get("wall", false)) and not bool(p.get("prop", false)) and int(p.x) == cell.x and int(p.y) == cell.y:
			_drop(p)
			pieces.erase(p)
			return true
	return false


## Drops every draft (ready pieces stay).
func clear_drafts() -> int:
	var n := drafts()
	_remove_where(func(p): return not bool(p.get("ready", false)))
	return n
