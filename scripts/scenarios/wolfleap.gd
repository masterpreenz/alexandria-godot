extends Scenario
## A mutated wolf in the mist: it comes for Sera, crouches with a strip on the ground showing where it'll land (pale
## red, filling dark red), leaps along it and hits her if she's still on it. Then a boar's charge, shown the same way
## while it paws. Run with --window=wolfleap.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var md: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	# Somewhere misted and open (no trees or bushes over the ground), out of the village.
	var spot := world.floors.cell_centre(Vector2i(56, 55))
	var c0 := world.village.banner_cell()
	var found := false
	for r in range(8, 60, 2):
		for k in 24:
			var a := k * TAU / 24.0
			var c := c0 + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			var at := world.floors.cell_centre(c)
			if world.mist.tier_at(at) != Mist.Tier.CLEAR and world.water_depth(at) <= 0.0 and Wilds.open(world, at, 3.0, 0.3) and Wilds.open(world, at + Vector2(-4.0, 1.0) * world.px, 2.0, 0.3):
				spot = at
				found = true
				break
		if found:
			break
	print("Wolf: open misted ground found ", found, " at ", world.floors.cell_at(spot))
	miko.place(spot)
	for i in 20:
		await get_tree().process_frame
	var hp0 := miko.stats.hp
	var wolf := MutatedWolf.spawn(world, md.mutatedWolf, spot + Vector2(-4.0, 1.0) * world.px)
	print("Wolf: in the mist ", world.mist.tier_at(spot) != Mist.Tier.CLEAR, ", ", snappedf(wolf.position.distance_to(miko.position) / world.px, 0.1), " units off")
	var seen := {}
	var shot_crouch := false
	for i in 400:
		await get_tree().process_frame
		var st: String = MutatedWolf.State.keys()[wolf.state]
		if not seen.has(st):
			seen[st] = true
			print("Wolf: ", st, " at frame ", i, (", strip " + str(snappedf(wolf.warn.length / world.px, 0.1)) + " units, fill " + str(snappedf(wolf.warn.fill, 0.01))) if wolf.warn != null else "")
		if wolf.state == MutatedWolf.State.CROUCH and wolf.warn != null and wolf.warn.fill > 0.6 and not shot_crouch:
			shot_crouch = true
			shot("crouch")
		if seen.has("LAND"):
			break
	print("Wolf: Sera's HP ", roundi(hp0), " -> ", roundi(miko.stats.hp), ", strip gone ", wolf.warn == null)
	wolf.queue_free()
	miko.stats.hp = hp0
	# A boar pawing the ground.
	var boar := Boar.spawn(world, md.boar, spot + Vector2(-3.5, 0.8) * world.px)
	for i in 5:
		await get_tree().process_frame
	boar._begin_wind_up()
	for i in 30:
		await get_tree().process_frame
		if boar.state == Boar.State.WIND_UP and boar.warn != null and boar.warn.fill > 0.5:
			print("Boar: pawing, strip ", snappedf(boar.warn.length / world.px, 0.1), " units, fill ", snappedf(boar.warn.fill, 0.01))
			shot("boar")
			break
	for i in 60:
		await get_tree().process_frame
	print("Boar: charged, strip gone ", boar.warn == null, ", state ", Boar.State.keys()[boar.state])
