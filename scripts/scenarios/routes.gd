extends Scenario
## Ways across the village: how many squares something solid stands on, and whether any planned way
## steps on one (other than where it ends). Then every villager sent across it: who gets stuck.
## Run with --window=routes.


func run() -> void:
	var solid := VillagerRoute.solid_squares(world)
	var c := world.village.centre()
	var h := world.village.half_size() * world.px * 0.8
	var ways := 0
	var none := 0
	var on_solid := 0
	for i in 200:
		var from_at := c + Vector2(randf_range(-h, h), randf_range(-h, h) * 0.5)
		var to_at := c + Vector2(randf_range(-h, h), randf_range(-h, h) * 0.5)
		var way: Variant = VillagerRoute.find(world, from_at, to_at)
		if way == null:
			none += 1
			continue
		ways += 1
		for k in (way as Array).size() - 1:
			if solid.has(world.floors.cell_at(way[k].at)) and world.floors.cell_at(way[k].at) != world.floors.cell_at(from_at):
				on_solid += 1
				break
	print("Routes: ", solid.size(), " solid squares; of 200 ways ", ways, " found, ", none, " none, ", on_solid, " stepping on something solid")
