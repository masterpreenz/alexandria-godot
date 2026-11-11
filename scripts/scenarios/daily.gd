extends Scenario
## Seed kept back; the meals of a day; a torch out by a crystal lit; waking and off.
## Run with --window=daily.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day()) * 24.0 + 5.0
	for i in 150:
		await get_tree().process_frame
	var v := world.village
	print("Daily: plots in the village ", fm.plots.filter(func(q): return v.contains(q.pos, 3.0)).size(), ", a plot's crop ", fm._field_crop(fm.plots[0], func(_s: String) -> bool: return true))
	print("Daily: kept for planting ", v.reserve, "; potatoes ", v.stored("Potato"), ", spare ", v.spare("Potato"), "; plots ", fm.plots.size())
	v.stash["Potato"] = int(v.reserve.get("Potato", 0)) + 1
	v.stash["Potato"] = int(v.reserve.get("Potato", 0))
	print("Daily: at the reserve exactly, spare ", v.spare("Potato"), ", potato dish ", Kitchen.next(v).has("Potato"))
	v.put_in_stash("BakedPotato", 30)
	# A torch out by a crystal, well outside the village.
	var out := world.floors.cell_at(v.centre()) + Vector2i(ceili(v.half_size()) + 6, 0)
	world.props.place(out, "CleansingCrystal")
	world.props.place(out + Vector2i(2, 1), "Torch")
	var fr: Fires = miko.get_node("Fires")
	for i in 10:
		await get_tree().process_frame
	var far: Dictionary = fr.fires.filter(func(f): return world.floors.cell_at(f.pos) == out + Vector2i(2, 1))[0]
	fr.lit_until.erase(far.key)
	print("Daily: the torch by the crystal, outside the village: in the village ", v.contains(far.pos, 2.0), ", tended ", fr.tended(far))
	var eaten := {}
	for start in [6.9, 11.9, 17.6]:
		clock.hours = floorf(clock.hours / 24.0) * 24.0 + start
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 50000:
			await get_tree().process_frame
			for vl in Villager.all:
				if vl.state == Villager.State.EATING and vl.get_meta("ate_at", -9.0) < clock.hours - 0.5:
					vl.set_meta("ate_at", clock.hours)
					eaten[vl.person.name] = (eaten.get(vl.person.name, []) as Array) + [snappedf(clock.hour(), 0.1)]
	print("Daily: by ", snappedf(clock.hour(), 0.1), " h, sat down to eat at ", eaten, "; hunger ", Villager.all.map(func(q): return roundi(q.person.hunger)), "; torch by the crystal lit ", fr.lit(far))
