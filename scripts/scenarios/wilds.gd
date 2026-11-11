extends Scenario
## The western wilds: how big the map is now, how many trees and rocks grew there, the mist there, the road west and
## north to the next village, the sections; pictures along the way and of the world map.
## Run with --window=wilds.


func run() -> void:
	var b := world.floors.bounds
	var wild := Gatherable.all.filter(func(tree): return world.floors.cell_at(tree.foot).x < Wildlands.FROM_X + 1)
	var tiers := [0, 0, 0]
	for c in [Vector2i(-200, 0), Vector2i(-250, 60), Vector2i(-250, 110), Vector2i(-300, -100), Vector2i(-420, 0), Vector2i(-100, 0), Vector2i(-130, 100)]:
		tiers[world.mist.tier_at(world.floors.cell_centre(c))] += 1
	print("Wilds: bounds ", b, "; trees and rocks there ", wild.size(), " (all ", Gatherable.all.size(), "); road at (-200, 0) ", world.floors.original.get(Vector2i(-200, 0), "none"), ", at (-250, 60) ", world.floors.original.get(Vector2i(-250, 60), "none"))
	for c in [Vector2i(-200, 0), Vector2i(-250, 60), Vector2i(-250, 110), Vector2i(-300, -100), Vector2i(-420, 0), Vector2i(-100, 0), Vector2i(-130, 100)]:
		print("Wilds: mist at ", c, " ", ["clear", "normal", "strong"][world.mist.tier_at(world.floors.cell_centre(c))], ", section ", _section(c))
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day()) * 24.0 + 11.0
	for spot in [[Vector2i(-150, 0), "edge"], [Vector2i(-230, 2), "road"], [Vector2i(-250, 70), "north"], [Vector2i(-300, 80), "forest"]]:
		miko.place(world.floors.cell_centre(spot[0]))
		var t0 := Time.get_ticks_msec()
		for i in 40:
			await get_tree().process_frame
		print("Wilds: at ", spot[1], " ", spot[0], ": ", snappedf(40000.0 / maxf(1.0, Time.get_ticks_msec() - t0), 0.1), " fps")
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + str(spot[1]) + ".png")
	# Walking the edge: she can't leave the map.
	miko.place(world.floors.cell_centre(Vector2i(-428, 0)))
	for i in 60:
		miko.velocity = Vector2(-1, 0.5).normalized() * 600.0
		await get_tree().physics_frame
	print("Wilds: pushed past the west edge from (-428, 0): now at cell ", world.floors.cell_at(miko.position))
	var wm: WorldMap = g.get_node("Hud/WorldMap")
	miko.place(world.floors.cell_centre(Vector2i(-150, 0)))
	wm.open()
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_map.png")
	wm.close()


func _section(c: Vector2i) -> String:
	for col in MapMarks.columns():
		for row in MapMarks.SECTIONS:
			if MapMarks.section_bounds(col, row).has_point(c):
				return MapMarks.section_name(col, row)
	return "?"
