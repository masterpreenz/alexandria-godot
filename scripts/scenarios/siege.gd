extends Scenario
## In the mist, a row of barricades between Miko and a mutated villager and an angry slime: they break it
## down first, then come for her.
## Run with --window=siege.


func run() -> void:
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var home_at := miko.position
	for k in 400:
		var spot := home_at + Vector2.from_angle(randf() * TAU) * randf_range(14.0, 30.0) * world.px
		if world.mist.tier_at(spot) != Mist.Tier.CLEAR and Wilds.dry(world, spot, 6.0):
			miko.place(spot)
			break
	var c := world.floors.cell_at(miko.position)
	for i in range(-3, 4, 2):
		world.walls.place(WallMap.Edge.new(c + Vector2i(2, i), true), "Barricade")
	var east := world.floors.cell_centre(c + Vector2i(4, 0))
	var mv := MutatedVillager.spawn(world, md.mutatedVillager, east)
	var sl: Slime = Slime.spawn(world, md.slime, false, east + Vector2(0, 0.6 * world.px), 1.0)
	sl.angry_until = Creature.now() + 999.0
	var hp_of := func() -> Array: return world.walls.hp.keys().filter(func(k): return world.walls.walls.has(k) and world.walls.walls[k] == "Barricade").map(func(k): return roundi(world.walls.hp[k]))
	var hp0: float = miko.stats.hp
	var pic := false
	for i in int(Shots.arg("siegeframes", "900")):
		await get_tree().process_frame
		if i % 150 == 0:
			print("Siege ", floori(i / 60.0), " s: barricades ", hp_of.call(), ", villager ", MutatedVillager.State.keys()[mv.state], ", her HP ", roundi(miko.stats.hp))
		if not pic and mv.state == MutatedVillager.State.ATTACK and mv._bar_key != null:
			pic = true
			for k in 8:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
	print("Siege end: barricades ", hp_of.call(), ", her HP ", hp0, " -> ", miko.stats.hp)
