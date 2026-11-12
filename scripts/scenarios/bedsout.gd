extends Scenario
## Every bed in the village can be got out of: a way from each to the village's middle, clear of what's solid (the
## route villagers take first). Run with --window=bedsout --slot=new.


func run() -> void:
	await get_tree().process_frame
	var solid := VillagerRoute.solid_squares(world)
	var to := world.village.centre()
	var bad := 0
	for k in world.props.cells:
		var nm := str(world.props.cells[k].prop)
		if not nm.contains("Bed"):
			continue
		var at := world.floors.cell_centre(Vector2i(k.x, k.y))
		# (from beside the bed: its own square is solid)
		var ok := false
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var from: Vector2 = at + d * world.px
			if not solid.has(world.floors.cell_at(from)) and VillagerRoute._search(world, VillagerRoute.square_at(world.walls, from), VillagerRoute.square_at(world.walls, to), solid, true) != null:
				ok = true
				break
		if not ok:
			bad += 1
			print("Beds: no way out from the ", nm, " at ", Vector2i(k.x, k.y))
	print("Beds: ", bad, " with no way out")
	# The houses: how big, and whether each has a fireplace.
	for h in Upkeep.active.houses():
		var fire := []
		for c in h.cells:
			for kk in world.props.cells:
				if Vector2i(kk.x, kk.y) == c and str(world.props.cells[kk].prop) == "Fireplace":
					fire.append(c - Vector2i(2, -51))
		print("House: ", h.cells.size(), " cells, fireplace (template) ", fire)
