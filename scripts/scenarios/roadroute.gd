extends Scenario
## Ways keep to the roads where they lead (a step on a road costs less), and a way found once is used again.
## Run with --window=roadroute.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	# From one side of the village to the other: how much of the way is on road.
	var c := world.village.centre()
	var from := c + Vector2(-9, 4) * world.px
	var to := c + Vector2(9, -4) * world.px
	var t := Time.get_ticks_usec()
	var way: Variant = VillagerRoute.find(world, from, to)
	var first := (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	VillagerRoute.find(world, from, to)
	var again := (Time.get_ticks_usec() - t) / 1000.0
	var on_road := 0
	var pts: Array = way if way != null else []
	for p in pts:
		if world.floors.get_floor(world.floors.cell_at(p.at)) != world.floors.base_floor:
			on_road += 1
	print("Road route: ", pts.size(), " points, ", on_road, " on road; first search ", snappedf(first, 0.01), " ms, again ", snappedf(again, 0.01), " ms")
