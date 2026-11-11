extends Scenario
## Walks her round a wide loop (through the village and out into the wilds) at running pace, then reports.
## Run with --window=walk.


func run() -> void:
	var centre := miko.position
	var radius := float(Shots.arg("radius", "18")) * world.px
	var frames := int(Shots.arg("walkframes", "1200"))
	var wet_ever := {}
	for i in frames:
		var a := TAU * i / 600.0
		miko.place(centre + Vector2(cos(a) * radius, sin(a) * radius * 0.5) - Vector2(radius, 0))
		if i % 10 == 0:
			for c in Creature.all:
				if is_instance_valid(c) and not Wilds.dry(world, c.position, 0.5):
					wet_ever[c.get_instance_id()] = true
		await get_tree().process_frame
	print(Perf.active.summary())
	print("Creatures in water at some point: ", wet_ever.size(), " (of ", Creature.all.size(), " now)")
