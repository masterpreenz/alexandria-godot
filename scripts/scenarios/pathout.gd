extends Scenario
## A cobble path laid out of the village (and into the river, which mustn't take): which cells took it.
## Run with --window=pathout.


func run() -> void:
	var bm := BuildMode.active
	bm.set_open(true)
	for it in bm.items:
		if it.name == "PathCobble": bm.select(it)
	miko.bag.add("Stone", 50)
	var spot := Vector2.ZERO
	for k in 400:
		var p := world.village.centre() + Vector2.from_angle(randf() * TAU) * randf_range(18.0, 30.0) * world.px
		if not world.village.contains(p, 2.0) and not world.wet(p) and world.floors.get_laid(world.floors.cell_at(p)) == "":
			spot = p
			break
	var c := world.floors.cell_at(spot)
	var took := []
	for i in 3:
		bm._paint(c + Vector2i(i, 0), "PathCobble", false)
		took.append(world.floors.get_laid(c + Vector2i(i, 0)))
	print("Path outside the village: ", took)
	var wet_cell := Vector2i(999999, 0)
	for k in 2000:
		var p := spot + Vector2.from_angle(randf() * TAU) * randf_range(1.0, 60.0) * world.px
		if world.water_depth(p) > 0.5:
			wet_cell = world.floors.cell_at(p)
			break
	bm._paint(wet_cell, "PathCobble", false)
	print("Path in the water: '", world.floors.get_laid(wet_cell), "'")
	bm.set_open(false)
