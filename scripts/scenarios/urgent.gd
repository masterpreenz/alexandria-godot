extends Scenario
## Only raw fish and jelly in storage, evening, nobody set to cook: someone cooks anyway, and they eat.
## Run with --window=urgent.


func run() -> void:
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 18.6
	var v := world.village
	for f in Villager.FOODS:
		v.stash[f[0]] = 0
	v.stash["Fish"] = 10
	v.stash["Jelly"] = 5
	v.stash["Wood"] = maxi(40, v.stored("Wood"))
	v.stash["Stone"] = maxi(40, v.stored("Stone"))
	for vl in Villager.all:
		Villager.only(vl.person, [])
		vl.person.hunger = 20.0
		vl.person.energy = 90.0
		vl._stand(Villager.now(), 0.0)
	Villager._short_at = -1.0
	await get_tree().process_frame
	print("Urgent: hour ", snappedf(clock.hour(), 0.1), ", work hours ", Villager.all[0]._work_hours(), ", food short ", Villager.food_short(world), ", raw to cook ", Villager.raw_to_cook(world), ", everyone's set to no work; cooks here ", Villager.all.filter(func(x): return x._cook_skill() > 0).map(func(x): return x.person.name))
	var seen := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 100000 and v.stored("GrilledFish") + v.stored("Candy") <= 0:
		await get_tree().process_frame
		for vl in Villager.all:
			var what: String = "%s %s" % [vl.person.name, Villager.State.keys()[vl.state]]
			if not seen.has(what):
				seen[what] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	print("Urgent: after ", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 1.0), " s: grilled fish ", v.stored("GrilledFish"), ", candy ", v.stored("Candy"), ", raw fish ", v.stored("Fish"), "; seen ", seen.keys().filter(func(k): return k.contains("COOK") or k.contains("STORE") or k.contains("EAT")))
