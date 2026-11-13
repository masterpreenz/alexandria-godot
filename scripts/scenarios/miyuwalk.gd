extends Scenario
## Miyu walking both ways with her redrawn run (8 frames to the front, 13 to the back, one pace): frames shown over
## a stretch of walking, and pictures mid-stride. Run with --window=miyuwalk.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	miyu.person["look"] = 5
	miyu.look = miyu.people._look_for(miyu.person)
	miyu.s = miyu.look.settings
	for way in [[Vector2(4.0, 2.0), "down"], [Vector2(-4.0, -2.0), "up"]]:
		var from := miko.position + Vector2(1.5, 1.0) * world.px
		miyu.position = from
		miyu.state = Villager.State.WALK
		miyu.target = from + (way[0] as Vector2) * world.px
		miyu.state_until = Villager.now() + 6.0
		var seen := {}
		var t0 := Time.get_ticks_msec()
		for i in 60:
			await get_tree().process_frame
			seen[miyu.art.region_rect] = true
			if i == 30:
				shot("walk_" + str(way[1]))
		print("Miyu walk: ", way[1], " facing up ", miyu.facing_up, ", distinct frames in 1 s ", seen.size(), ", fps ", miyu._walk_fps(), ", moved ", snappedf(miyu.position.distance_to(from) / world.px, 0.01), " units in ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
