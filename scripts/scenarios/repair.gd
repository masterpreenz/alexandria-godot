extends Scenario
## A worn barricade in the village in the morning: someone comes with wood to mend it.
## Run with --window=repair.


func run() -> void:
	clock.hours = float(clock.day() - 1) * 24.0 + 9.0
	world.village.put_in_stash("Wood", 5)
	var cv := world.floors.cell_at(world.village.centre()) + Vector2i(3, 3)
	var ek := WallMap.Edge.new(cv, false)
	world.walls.place(ek, "Barricade")
	world.walls.damage(ek.key(), 110.0)
	miko.place(world.walls.wall_middle(ek.key()) + Vector2(-2.5, 1.5) * world.px)
	var pic := false
	var wood0 := world.village.stored("Wood")
	for i in int(Shots.arg("repairframes", "1800")):
		await get_tree().process_frame
		var who: Array = Villager.all.filter(func(v): return v.mend == ek.key())
		if i == 30:
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_worn.png")
		if i % 120 == 0:
			print("Repair ", floori(i / 60.0), " s: HP ", roundi(world.walls.hp.get(ek.key(), -1.0)), ", ", (who[0].person.name + " " + Villager.State.keys()[who[0].state]) if not who.is_empty() else "nobody on it")
		if not pic and not who.is_empty() and who[0].state == Villager.State.REPAIR:
			pic = true
			miko.place(who[0].position + Vector2(-1.5, 1.0) * world.px)
			for k in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_mend.png")
		if float(world.walls.hp.get(ek.key(), 0.0)) >= 150.0 and who.is_empty():
			break
	print("Repair end: HP ", world.walls.hp.get(ek.key(), -1.0), ", wood ", wood0, " -> ", world.village.stored("Wood"))
