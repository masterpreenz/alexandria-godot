extends Scenario
## Sundown with every torch and fire in the village out and everyone at work: the nearest free villager to each goes
## and lights it, till all are lit. A hurt villager mends over a game hour, awake and out of a fight. Sera's card
## shows her thirst. Run with --window=dusk.


func _unlit(fires: Fires) -> Array:
	return fires.fires.filter(func(f): return fires.tended(f) and not fires.lit(f))


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var fires: Fires = miko.get_node("Fires")
	clock.hours = float(clock.day() - 1) * 24.0 + 17.6
	fires.lit_until.clear()
	for r in ["Wood", "Stone"]:
		world.village.put_in_stash(r, 200)
	var hurt: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and v.hit.alive() and not v._in_party():
			hurt = v
			break
	hurt.hit.hp = hurt.hit.max_hp * 0.5
	var hp0 := hurt.hit.hp
	var h0 := clock.hours
	print("Dusk: ", _unlit(fires).size(), " torches and fires out at ", clock.time_text(), ", villagers ", Villager.all.size(), ", ", hurt.person.name, " at ", roundi(hp0), "/", roundi(hurt.hit.max_hp))
	miko.place(world.village.centre())
	var took := -1.0
	for i in 1800:
		await get_tree().process_frame
		if i % 120 == 0:
			var going := Villager.all.filter(func(v): return is_instance_valid(v) and v.state == Villager.State.TO_LIGHT).size()
			print("Dusk: ", clock.time_text(), " out ", _unlit(fires).size(), ", on the way to light one ", going)
		if _unlit(fires).is_empty() and took < 0.0:
			took = clock.hours - h0
			shot("lit")
			break
	print("Dusk: all lit ", _unlit(fires).is_empty(), " after ", snappedf(took * 60.0, 1.0), " game minutes")
	shot("card")
	# An hour on, calm.
	while clock.hours < h0 + 1.0:
		await get_tree().process_frame
	print("Dusk: ", hurt.person.name, " mended ", roundi(hp0), " -> ", roundi(hurt.hit.hp), " in ", snappedf(clock.hours - h0, 0.01), " h (state ", hurt.state, ")")
