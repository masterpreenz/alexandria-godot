extends Scenario
## A raid sent now (at night): the horde comes at the village; where they are and who's hurt, every 5 s.
## Run with --window=raid.


func run() -> void:
	clock.hours = float(clock.day() - 1) * 24.0 + 22.0
	var rd: Raids = g.get_node("Raids")
	var n := rd.start(int(Shots.arg("raiders", "6")))
	var c := world.village.centre()
	print("Raid: ", n, " raiders, nearest ", snappedf(rd.raiders.map(func(r): return r.position.distance_to(c)).min() / world.px, 0.1), " units off")
	var vhp := func() -> int: return Villager.all.map(func(v): return roundi(v.hit.hp)).reduce(func(a, b): return a + b, 0)
	var hp0: int = vhp.call()
	var pic := false
	for i in int(Shots.arg("raidframes", "1800")):
		await get_tree().process_frame
		if i % 300 == 0:
			var alive := rd.raiders.filter(func(r): return is_instance_valid(r))
			print("Raid ", floori(i / 60.0), " s: raiders in the village ", alive.filter(func(r): return world.village.contains(r.position)).size(), "/", alive.size(), ", nearest ", snappedf(alive.map(func(r): return r.position.distance_to(c)).min() / world.px if not alive.is_empty() else -1.0, 0.1), ", villagers' HP ", vhp.call(), "/", hp0)
		if not pic and rd.raiders.any(func(r): return is_instance_valid(r) and world.village.contains(r.position)):
			pic = true
			var r0: Node2D = rd.raiders.filter(func(r): return is_instance_valid(r) and world.village.contains(r.position))[0]
			miko.place(r0.position + Vector2(-2, 1.5) * world.px)
			for k in 30:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_in.png")
	clock.hours += 10.0
	for i in 5:
		await get_tree().process_frame
	print("Raid at dawn: raiders still raiding ", rd.raiders.size())
