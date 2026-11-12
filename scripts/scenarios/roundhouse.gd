extends Scenario
## A monster with a house between it and Sera goes round the house to her, not stuck at its wall (a mutated villager,
## then a slime). The village unwarded for it (in the mist), so they hunt her alone. Run with --window=roundhouse.


func _try(kind: String) -> void:
	var houses: Array = Upkeep.active.houses()
	houses.sort_custom(func(a, b): return a.cells.size() > b.cells.size())
	var h: Dictionary = houses[0]
	var mid: Vector2 = h.middle
	var md: Dictionary = world._load_json("res://data/monsters.json")
	miko.place(mid + Vector2(-6.5, 0) * world.px)
	var m: Creature
	if kind == "slime":
		var sl := Slime.spawn(world, md.slime, false, mid + Vector2(6.5, 0) * world.px, 1.0)
		sl.angry_until = INF
		sl.home = sl.position
		sl.s.sight = 20.0   # (sees her from there, and follows her as far)
		sl.s.leash = 40.0
		m = sl
	else:
		m = MutatedVillager.spawn(world, md.mutatedVillager, mid + Vector2(6.5, 0) * world.px)
		m.s.sight = 20.0
	m.hit.unkillable = true
	var start := m.position.distance_to(miko.position) / world.px
	var t0 := Time.get_ticks_msec()
	var closest := start
	while Time.get_ticks_msec() - t0 < 40000:
		miko.stats.hp = miko.stats.stat("maxHp")   # (she stands and waits)
		closest = minf(closest, m.position.distance_to(miko.position) / world.px)
		if closest < 1.3:
			break
		await get_tree().process_frame
	print("Round the house (", kind, "): from ", snappedf(start, 0.1), " to ", snappedf(closest, 0.1), " units in ", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), "s")
	m.queue_free()
	await get_tree().process_frame


func run() -> void:
	clock.hours = float(clock.day()) * 24.0 + 22.0   # (night: the mutated villager hunts her)
	for i in 30:
		await get_tree().process_frame
	Story.active._warded = false
	world.mist.refresh(true)
	world.mist.snap()
	await _try("mutated")
	await _try("slime")
