class_name PropMap
extends Node
## The world's decorations and furniture (from Unity's PropMap), placed and removed through this API by build mode,
## level design or game logic. A cell holds one prop per slot (ground, tall), so a tree can stand over the flowers at
## its base. Each prop stands at its cell's centre, sorted by height on screen like the characters (a ground prop just
## in front of a tall one on the same cell), kept behind any wall standing in front of it, with a rounded footprint if
## its type is solid. Free props stand anywhere, off the grid and any number per cell.
##
## Not yet: what a prop brings along (a bonfire's flames, a bed's sleeper spot, a chest's storage): phase 3.

signal prop_changed(cell: Vector2i, slot: int, prop: String)

enum Slot { GROUND, TALL }

var world: World
var floors: FloorMap
var types := {}          ## name -> prop type
var version := 0
## The props that sway in the wind (World.tree_material).
const SWAYING := ["Pine", "Oak", "Willow", "Bush", "BerryBush", "FlowerBush"]

var cells := {}          # Vector3i (x, y, slot) -> {prop, flipped, turn, scale}
var free := []           # [{pos (px), prop, flipped, turn, scale}]
var original := {}
var original_free := []
var _drawn := {}         # Vector3i -> holder
var _free_drawn := []


func setup(w: World, f: FloorMap, data: Dictionary) -> void:
	world = w
	floors = f
	for t in data.types:
		types[t.name] = t
	for p in data.placed:
		if types.has(p.prop):
			cells[Vector3i(int(p.x), int(p.y), int(types[p.prop].slot))] = _entry(p)
	for p in data.free:
		if types.has(p.prop):
			free.append(_free_entry(p))
	original = cells.duplicate()
	original_free = free.duplicate()


func _entry(p: Dictionary) -> Dictionary:
	return {"prop": p.prop, "flipped": p.get("flipped", false), "turn": int(p.get("turn", 0)), "scale": float(p.get("scale", 1.0))}


# Free props are saved in Unity units (as the game's saves have them).
func _free_entry(p: Dictionary) -> Dictionary:
	var e := _entry(p)
	e["pos"] = Vector2(float(p.x) * world.px, -float(p.y) * world.px)
	return e


static func _scale(saved: float) -> float:
	return saved if saved > 0.0 else 1.0


# ---- Reading ----

func get_prop(cell: Vector2i, slot: int) -> String:
	return cells.get(Vector3i(cell.x, cell.y, slot), {}).get("prop", "")


## Every prop on [param cell]: [{prop, turn, scale}].
func at(cell: Vector2i) -> Array:
	var out := []
	for slot in Slot.values():
		var e: Dictionary = cells.get(Vector3i(cell.x, cell.y, slot), {})
		if not e.is_empty():
			out.append(e)
	return out


## Whether a prop named [param name] (its asset or display name) stands anywhere.
func has(nm: String) -> bool:
	return not cached("has", nm, _has_list).is_empty()


func _has_list(nm: String) -> Array:
	return [true] if _has(nm) else []


func _has(nm: String) -> bool:
	for e in cells.values() + free:
		if e.prop == nm or types[e.prop].display == nm:
			return true
	return false


# ---- Placing ----

## Puts [param prop] on [param cell] at [param scale], replacing whatever was in its slot ([param turn] -1: as it
## comes, flipped at random if its type allows).
func place(cell: Vector2i, prop: String, scale := 1.0, turn := -1) -> void:
	if not types.has(prop) or not floors.in_bounds(cell):
		return
	var k := Vector3i(cell.x, cell.y, int(types[prop].slot))
	var here: Dictionary = cells.get(k, {})
	if not here.is_empty() and here.prop == prop and _scale(here.scale) == scale and (turn < 0 or here.turn == turn):
		return
	cells[k] = {"prop": prop, "flipped": turn < 0 and types[prop].randomFlip and randf() < 0.5, "turn": maxi(0, turn), "scale": scale}
	_changed(k)


## Stands [param prop] at [param pos] (px), off the grid, alongside whatever is there.
func place_free(pos: Vector2, prop: String, scale := 1.0, turn := -1) -> void:
	if not types.has(prop) or not floors.in_bounds(floors.cell_at(pos)):
		return
	free.append({"pos": pos, "prop": prop, "flipped": turn < 0 and types[prop].randomFlip and randf() < 0.5, "turn": maxi(0, turn), "scale": scale})
	_sync_free(free.size() - 1)
	version += 1


func remove(cell: Vector2i, slot: int) -> void:
	var k := Vector3i(cell.x, cell.y, slot)
	if cells.erase(k):
		_changed(k)


## Removes everything standing on [param cell], free props included.
func remove_all(cell: Vector2i) -> void:
	for slot in Slot.values():
		remove(cell, slot)
	var before := free.size()
	free = free.filter(func(e): return floors.cell_at(e.pos) != cell)
	if free.size() != before:
		_rebuild_free()
		version += 1


func _changed(k: Vector3i) -> void:
	_sync(k)
	version += 1
	prop_changed.emit(Vector2i(k.x, k.y), k.z, cells.get(k, {}).get("prop", ""))


# ---- Saving ----

func to_json() -> String:
	var props := []
	for k in cells:
		var e: Dictionary = cells[k]
		props.append({"x": k.x, "y": k.y, "prop": e.prop, "flipped": e.flipped, "turn": e.turn, "scale": _scale(e.scale)})
	var frees := []
	for e in free:
		frees.append({"x": e.pos.x / world.px, "y": -e.pos.y / world.px, "prop": e.prop, "flipped": e.flipped, "turn": e.turn, "scale": _scale(e.scale)})
	var b := floors.bounds
	return JSON.stringify({"props": props, "free": frees, "areaX": b.position.x, "areaY": b.position.y, "areaW": b.size.x,
		"areaH": b.size.y, "world": FloorMap.WORLD_VERSION})


## Replaces every placed prop with those saved; land the save never covered comes from the scene, as in Unity.
func from_json(json: String) -> void:
	var data: Dictionary = JSON.parse_string(json)
	cells.clear()
	for p in data.get("props", []):
		if types.has(p.prop):
			cells[Vector3i(int(p.x), int(p.y), int(types[p.prop].slot))] = _entry(p)
	free.clear()
	for p in data.get("free", []):
		if types.has(p.prop):
			free.append(_free_entry(p))
	var w := int(data.get("world", 0))
	var area := FloorMap._saved_area(int(data.get("areaX", 0)), int(data.get("areaY", 0)), int(data.get("areaW", 0)), int(data.get("areaH", 0)), w)
	for k in cells.keys():
		if FloorMap.from_scene(Vector2i(k.x, k.y), area, w): cells.erase(k)
	free = free.filter(func(e): return not FloorMap.from_scene(floors.cell_at(e.pos), area, w))
	for k in original:
		if FloorMap.from_scene(Vector2i(k.x, k.y), area, w): cells[k] = original[k]
	for e in original_free:
		if FloorMap.from_scene(floors.cell_at(e.pos), area, w): free.append(e)
	rebuild()


# ---- Drawing ----

func rebuild() -> void:
	version += 1
	for k in _drawn.keys():
		_drawn[k].queue_free()
	_drawn.clear()
	for k in cells:
		_sync(k)
	_rebuild_free()


func _rebuild_free() -> void:
	for h in _free_drawn:
		h.queue_free()
	_free_drawn.clear()
	for i in free.size():
		_sync_free(i)


func _sync(k: Vector3i) -> void:
	if _drawn.has(k):
		_drawn[k].queue_free()
		_drawn.erase(k)
	var e: Dictionary = cells.get(k, {})
	if e.is_empty():
		return
	# A ground prop draws just in front of a tall one on its cell.
	_drawn[k] = _show(floors.cell_centre(Vector2i(k.x, k.y)), e, 1.28 if k.z == Slot.GROUND else 0.0)


func _sync_free(i: int) -> void:
	while _free_drawn.size() <= i:
		_free_drawn.append(null)
	if _free_drawn[i] != null:
		_free_drawn[i].queue_free()
	_free_drawn[i] = _show(free[i].pos, free[i], 0.0)


## Every placed [param name]: where it stands (px, as it's drawn), and its entry (flipped, turn, scale).
## Lookups by name, kept until the props change (many systems ask every frame; scanning every prop each time cost
## milliseconds a frame).
var _named := {}
var _named_version := -1


func cached(kind: String, nm: String, build: Callable) -> Array:
	if _named_version != version:
		_named_version = version
		_named.clear()
	var key := kind + ":" + nm
	if not _named.has(key):
		_named[key] = build.call(nm)
	return (_named[key] as Array).duplicate()


func entries_named(nm: String) -> Array:
	return cached("entries", nm, _entries_named)


func _entries_named(nm: String) -> Array:
	var out := []
	for k in cells:
		if cells[k].prop == nm:
			out.append({"pos": floors.cell_centre(Vector2i(k.x, k.y)), "e": cells[k]})
	for e in free:
		if e.prop == nm:
			out.append({"pos": e.pos, "e": e})
	return out


## Every placed [param name] with the node it's drawn as: [{pos, e, node}] (a holder whose first child is its sprite).
func drawn_named(nm: String) -> Array:
	return cached("drawn", nm, _drawn_named)


func _drawn_named(nm: String) -> Array:
	var out := []
	for k in cells:
		if cells[k].prop == nm and _drawn.has(k):
			out.append({"pos": floors.cell_centre(Vector2i(k.x, k.y)), "e": cells[k], "node": _drawn[k]})
	for i in free.size():
		if free[i].prop == nm and i < _free_drawn.size() and _free_drawn[i] != null:
			out.append({"pos": free[i].pos, "e": free[i], "node": _free_drawn[i]})
	return out


## Whether a placed prop shows mirrored (a turning prop without turned art mirrors on odd turns).
func shown_flipped(e: Dictionary) -> bool:
	var t: Dictionary = types[e.prop]
	if _turns(t) > 1:
		return (t.turnSprites as Array).is_empty() and e.turn % 2 == 1
	return e.flipped


## A prop's sprite for [param turn]: its turned art, or its one sprite (mirrored on odd turns if it turns).
func sprite_for(prop: String, turn: int) -> int:
	var t: Dictionary = types[prop]
	var turned: Array = t.turnSprites
	return int(turned[posmod(turn, turned.size())]) if turned.size() > 0 else int(t.sprite)


func _turns(t: Dictionary) -> int:
	return (t.turnSprites as Array).size() if (t.turnSprites as Array).size() > 0 else maxi(1, int(t.turns))


func _show(where: Vector2, e: Dictionary, bias: float) -> Node2D:
	var t: Dictionary = types[e.prop]
	var flipped: bool = e.flipped
	if _turns(t) > 1:
		flipped = (t.turnSprites as Array).is_empty() and e.turn % 2 == 1
	var scale := _scale(e.scale)
	var sort := where.y + bias
	# Kept behind any wall standing in front of it (a wide bed set against a wall would otherwise draw over it).
	if world.walls != null:
		var sorted: float = world.walls.sort_against_walls(where, 0.1 * world.px, sort)
		sort = sorted - 1.28 if sorted < sort else sorted
	var holder := Node2D.new()
	holder.position = Vector2(where.x, sort)
	var sprite := Sprite2D.new()
	var id := sprite_for(e.prop, e.turn)
	if id >= 0:
		world.show_frame(sprite, id, Vector2(-scale if flipped else scale, scale))
		# Trees and bushes sway (the taller, the more); everything else stands still.
		if SWAYING.has(e.prop):
			sprite.material = world.tree_material()
			sprite.set_meta("sway", true)
		else:
			sprite.material = world.snow_material(0)
	sprite.position = Vector2(0, where.y - sort)
	holder.add_child(sprite)
	if t.solid:
		# A rounded footprint at its base: much flatter and characters slide round it instead of stopping.
		var body := StaticBody2D.new()
		# (furniture, a bed or a fireplace, on a layer of its own: the villagers pass through it; Sera and the
		# monsters don't)
		if str(t.get("category", "")) == "Furniture":
			body.collision_layer = FURNITURE_LAYER
		var shape := CollisionShape2D.new()
		var cap := CapsuleShape2D.new()
		var r: float = t.footprint * scale
		cap.radius = r * 0.75
		cap.height = r * 2.0
		shape.shape = cap
		shape.rotation = PI / 2.0
		shape.position = Vector2(0, -r * 0.25)
		body.add_child(shape)
		body.position = Vector2(0, where.y - sort)
		holder.add_child(body)
	world.things.add_child(holder)
	if String(world.sprites[id].name).contains("tree") if id >= 0 else false:
		world.add_occluder(sprite)
	return holder


## The physics layer furniture stands on (not the fixed world's: villagers don't bump into it).
const FURNITURE_LAYER := 16


## What [method remove_one] would take off [param cell]: the latest free prop there, else the tallest placed one; "".
func peek_top(cell: Vector2i) -> String:
	for i in range(free.size() - 1, -1, -1):
		if floors.cell_at(free[i].pos) == cell:
			return free[i].prop
	for slot in [Slot.TALL, Slot.GROUND]:
		var p := get_prop(cell, slot)
		if p != "":
			return p
	return ""


## The prop on [param cell] the next [method remove_one_where] would take: as [method peek_top], counting only those
## [param want] (a prop name -> bool) says yes to; "" when none.
func peek_where(cell: Vector2i, want: Callable) -> String:
	for i in range(free.size() - 1, -1, -1):
		if floors.cell_at(free[i].pos) == cell and want.call(free[i].prop):
			return free[i].prop
	for slot in [Slot.TALL, Slot.GROUND]:
		var p := get_prop(cell, slot)
		if p != "" and want.call(p):
			return p
	return ""


## Removes one thing on [param cell] that [param want] says yes to (as [method remove_one]); false when none.
func remove_one_where(cell: Vector2i, want: Callable) -> bool:
	for i in range(free.size() - 1, -1, -1):
		if floors.cell_at(free[i].pos) == cell and want.call(free[i].prop):
			free.remove_at(i)
			_rebuild_free()
			version += 1
			return true
	for slot in [Slot.TALL, Slot.GROUND]:
		var p := get_prop(cell, slot)
		if p != "" and want.call(p):
			remove(cell, slot)
			return true
	return false


## Removes one thing standing on [param cell]: the free prop placed there last, else the tallest slot's prop. False
## when there was nothing.
func remove_one(cell: Vector2i) -> bool:
	for i in range(free.size() - 1, -1, -1):
		if floors.cell_at(free[i].pos) == cell:
			free.remove_at(i)
			_rebuild_free()
			version += 1
			return true
	for slot in [Slot.TALL, Slot.GROUND]:
		if get_prop(cell, slot) != "":
			remove(cell, slot)
			return true
	return false


## Lifts the top thing off [param cell] (as [method remove_one] would): {prop, turn, scale, free, pos}, or {}.
func take_top(cell: Vector2i) -> Dictionary:
	for i in range(free.size() - 1, -1, -1):
		if floors.cell_at(free[i].pos) == cell:
			var e: Dictionary = free[i]
			free.remove_at(i)
			_rebuild_free()
			version += 1
			return {"prop": e.prop, "turn": int(e.get("turn", 0)), "scale": _scale(float(e.get("scale", 1.0))), "free": true, "pos": e.pos}
	for slot in [Slot.TALL, Slot.GROUND]:
		var k := Vector3i(cell.x, cell.y, slot)
		if cells.has(k):
			var e: Dictionary = cells[k]
			remove(cell, slot)
			return {"prop": e.prop, "turn": int(e.get("turn", 0)), "scale": _scale(float(e.get("scale", 1.0))), "free": false, "pos": floors.cell_centre(cell)}
	return {}


## What's set down freely: [{pos, prop, turn, scale}].
func free_props() -> Array:
	return free


## The drawn node of the prop on [param cell]'s [param slot], or null.
func node_at(cell: Vector2i, slot: int) -> Node2D:
	return _drawn.get(Vector3i(cell.x, cell.y, slot), null)


## The drawn node of the free prop placed last, or null.
func last_free_node() -> Node2D:
	return _free_drawn[free.size() - 1] if not free.is_empty() and free.size() <= _free_drawn.size() else null


## Every drawn prop node (for hiding or showing).
func drawn_nodes() -> Array:
	return _drawn.values() + _free_drawn.filter(func(n): return n != null)
