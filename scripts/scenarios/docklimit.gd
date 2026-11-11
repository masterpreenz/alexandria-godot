extends Scenario
## One fishing dock to begin with; one more each time the village grows.
## Run with --window=docklimit.


func run() -> void:
	var bm := BuildMode.active
	var dock_item := bm.item_for("Prop", "FishingDock")
	var c0 := world.floors.cell_at(world.village.centre())
	var free := []
	for r in range(1, 60):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var cc := c0 + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and free.size() < 6 and not bm.no_build(cc) and bm.why_not(dock_item, world.floors.cell_centre(cc)) == "" 										and free.all(func(o): return maxi(absi(o.x - cc.x), absi(o.y - cc.y)) > 3):
					free.append(cc)
	print("Dock limit: village grown ", world.village.growths(), " times, limit ", bm.limit_of(dock_item), ", ", free.size(), " places by the water found")
	for i in free.size():
		var why := bm.why_not(dock_item, world.floors.cell_centre(free[i]))
		print("Dock limit: dock ", i + 1, ": '", why, "'")
		if why == "":
			world.props.place(free[i], "FishingDock")
			await get_tree().process_frame
		elif world.village.tier < 3:
			world.village.tier += 1
			print("Dock limit: the village grows (", world.village.growths(), "): limit ", bm.limit_of(dock_item), ", now '", bm.why_not(dock_item, world.floors.cell_centre(free[i])), "'")
