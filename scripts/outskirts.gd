class_name Outskirts
extends Node
## The land past the map's edges, for looks only: the map is a diamond, and beyond it there was nothing (black). The
## ground carries on [constant MARGIN] cells further every way (FloorMap draws it), the river runs on through it
## (World stretches its mesh and banks), the mist lies over it (Mist), and this scatters forest and undergrowth across
## it: trees in clumps, bushes, grass and flowers between. Nothing there can be reached, gathered or walked on (the
## map's own bounds stop her). Laid out the same every time (a fixed seed), not saved.

const MARGIN := 57                ## cells past each edge (a fifth of the map's 284)
const TREES := ["tree_1", "tree_2", "tree_2", "tree_3"]
const UNDERGROWTH := ["grass_1", "grass_1", "grass_1", "bush", "bush", "berry_bush", "flower_mix", "flower_bush", "single_rock"]
const TREE_CHANCE := 0.13         ## a cell in a forest clump
const SPARSE_TREE := 0.006        ## a cell outside one
const GROWTH_CHANCE := 0.035
const RIVER := [-43, -34]         ## the river's cells across (x): kept clear


func setup(world: World) -> void:
	var by_name := {}
	for i in world.sprites.size():
		var n := str(world.sprites[i].name)
		if not by_name.has(n):
			by_name[n] = i
	var trees := TREES.filter(func(n): return by_name.has(n)).map(func(n): return int(by_name[n]))
	var growth := UNDERGROWTH.filter(func(n): return by_name.has(n)).map(func(n): return int(by_name[n]))
	if trees.is_empty():
		return
	var holder := Node2D.new()
	holder.name = "Outskirts"
	holder.y_sort_enabled = true
	world.things.add_child(holder)
	var noise := FastNoiseLite.new()
	noise.seed = 7723
	noise.frequency = 0.045
	var rng := RandomNumberGenerator.new()
	rng.seed = 7723
	var inner := world.floors.bounds
	var outer := inner.grow(MARGIN)
	var snow := world.snow_material(0)
	# (nothing on a road carried on past the edge, nor close by it: further on the side below it on screen, where a
	# tree's crown would stand up over it)
	var by_road := {}
	for c: Vector2i in world.floors.beyond:
		for dx in range(-8, 4):
			for dy in range(-8, 4):
				by_road[c + Vector2i(dx, dy)] = true
	for x in range(outer.position.x, outer.end.x):
		for y in range(outer.position.y, outer.end.y):
			if inner.has_point(Vector2i(x, y)) or (x >= RIVER[0] and x <= RIVER[1]):
				continue
			# (the mountains stand along and past the north-east edge)
			if x >= inner.end.x - Mountains.DEPTH and x < inner.end.x + 22 and y >= inner.position.y - 8 and y < inner.end.y + 8:
				continue
			var roll := rng.randf()
			var wooded := noise.get_noise_2d(x, y) > 0.08
			var id := -1
			var size := 1.0
			if roll < (TREE_CHANCE if wooded else SPARSE_TREE):
				id = trees[rng.randi() % trees.size()]
				size = rng.randf_range(0.85, 1.15)
			elif roll < (TREE_CHANCE if wooded else SPARSE_TREE) + GROWTH_CHANCE and not growth.is_empty():
				id = growth[rng.randi() % growth.size()]
				size = rng.randf_range(0.8, 1.15)
			if id < 0 or by_road.has(Vector2i(x, y)):
				continue
			var sp := Sprite2D.new()
			world.show_frame(sp, id, Vector2(-size if rng.randf() < 0.5 else size, size))
			sp.material = snow
			sp.position = world.floors.corner(Vector2(x + rng.randf(), y + rng.randf()))
			holder.add_child(sp)
			Culler.still(world, sp, sp.position)
