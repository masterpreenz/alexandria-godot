class_name Wildlands
## The western wilds: the land added past the old south-west edge (x below [constant FROM_X], out to the map's new edge),
## across the river from the village. Grown, not drawn: the same every time (seeded), so nothing of it needs saving.
## Forest in clumps, thickening to the north-west (+y); rocks here and there; undergrowth between. The road west from
## the bridge, and the way north up to the next village, are kept clear, and so is the village's own ground.
## Trees and rocks are real (Gatherables: chopped, mined, felled, grown back), made from gather.json's own trees and
## rocks moved here; the undergrowth is only to look at.

const FROM_X := -143               ## the first column of the wilds (the old map ended at -142)
const TO_X := -430                 ## its last (the new edge)
const SEED := 4417
const TREE_CHANCE := 0.06          ## a cell in a forest clump
const SPARSE_TREE := 0.004         ## a cell outside one
const ROCK_CHANCE := 0.0025
const GROWTH_CHANCE := 0.02
const UNDERGROWTH := ["grass_1", "grass_1", "bush", "bush", "berry_bush", "flower_mix", "flower_bush", "single_rock"]
## The road west from the bridge (along y ≈ 0), and up north to the next village (along x ≈ ROAD_NORTH_X).
const ROAD_HALF := 4
const ROAD_NORTH_X := -250
const ROAD_TURN_Y := 0
## Where the next village stands (cells): kept clear for it.
const WEST_VILLAGE := Rect2i(-272, 92, 44, 36)


## Whether [param c] is on the road west, or the way north to the next village.
static func on_road(c: Vector2i) -> bool:
	if c.x <= -40 and c.x >= ROAD_NORTH_X - ROAD_HALF and absi(c.y - ROAD_TURN_Y) <= ROAD_HALF:
		return true
	return absi(c.x - ROAD_NORTH_X) <= ROAD_HALF and c.y >= ROAD_TURN_Y and c.y <= WEST_VILLAGE.position.y + 4


## Grows the wilds into [param w]: its trees and rocks, and its undergrowth. Called as the world loads.
static func grow(w: World, gather: Dictionary) -> void:
	var b := w.floors.bounds
	if b.position.x > FROM_X:
		return   # (the map hasn't the wilds in it)
	var trees: Array = gather.spots.filter(func(s): return str(s.resource) == "Wood" and int(s.get("planted", 0)) == 0 and int(s.s) in [623, 625])
	var rocks: Array = gather.spots.filter(func(s): return str(s.resource) == "Stone")
	if trees.is_empty():
		return
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.frequency = 0.04
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var holder := Node2D.new()
	holder.name = "WildGrowth"
	w.things.add_child(holder)
	var wood := int(gather.miner.treeWood)
	var f := w.floors
	for x in range(TO_X, FROM_X + 1):
		for y in range(b.position.y, b.end.y):
			var c := Vector2i(x, y)
			var roll := rng.randf()
			var pick := rng.randf()
			var jx := rng.randf_range(0.2, 0.8)
			var jy := rng.randf_range(0.2, 0.8)
			if on_road(c) or WEST_VILLAGE.has_point(c):
				continue
			# (thicker towards the north-west, the higher the y)
			var north := clampf((float(y) - b.position.y) / float(b.size.y), 0.0, 1.0)
			var wooded := noise.get_noise_2d(x, y) > 0.15 - 0.35 * north
			var at := f.corner(Vector2(x + jx, y + jy))
			if roll < (TREE_CHANCE if wooded else SPARSE_TREE):
				_spot(w, trees[int(pick * trees.size()) % trees.size()], at, wood)
			elif roll < (TREE_CHANCE if wooded else SPARSE_TREE) + ROCK_CHANCE and not rocks.is_empty():
				_spot(w, rocks[int(pick * rocks.size()) % rocks.size()], at, wood)
			elif roll < 0.2 + GROWTH_CHANCE and roll >= 0.2:
				var nm: String = UNDERGROWTH[int(pick * UNDERGROWTH.size()) % UNDERGROWTH.size()]
				var id := _sprite_named(w, nm)
				if id >= 0:
					var sp := Sprite2D.new()
					var size := rng.randf_range(0.8, 1.1)
					w.show_frame(sp, id, Vector2(size if pick < 0.5 else -size, size))
					sp.position = at
					holder.add_child(sp)


# One of gather.json's trees or rocks, moved to [param at] (its collider with it).
static func _spot(w: World, template: Dictionary, at: Vector2, wood: int) -> void:
	var d: Dictionary = template.duplicate(true)
	var off := at - Vector2(float(template.x), float(template.y))
	d.x = at.x
	d.y = at.y
	d.sort = float(template.sort) + off.y
	var col: Dictionary = d.get("collider", {})
	if col.has("c"):
		col.c = [float(col.c[0]) + off.x, float(col.c[1]) + off.y]
	if col.has("p"):
		var p: Array = col.p
		for i in range(0, p.size(), 2):
			p[i] = float(p[i]) + off.x
			p[i + 1] = float(p[i + 1]) + off.y
	var g := Gatherable.new()
	w.things.add_child(g)
	g.setup(w, d, wood)
	w.gatherables.append(g)


static var _ids := {}


static func _sprite_named(w: World, nm: String) -> int:
	if _ids.is_empty():
		for i in w.sprites.size():
			_ids[str(w.sprites[i].name)] = i
	return int(_ids.get(nm, -1))
