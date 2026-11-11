extends Scenario
## A cook with raw food in storage: to storage first, then the fire; what's cooked.
## Run with --window=cookfetch.


func run() -> void:
	var v := world.village
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 9.5
	for r in Spoilage.PER_DAY:
		v.stash[r] = 0
	v.stash["Potato"] = 40
	v.reserve = {}
	var cook: Villager = null
	while Villager.all.size() < 2:
		await get_tree().process_frame
	for q in Villager.all:
		q.person.hunger = 100.0
		if q._cook_skill() > 0 and cook == null:
			cook = q
	print("Cook fetch: cook ", cook.person.name if cook != null else "none", ", goes ", cook._go_cook() if cook != null else false, ", '", cook.activity() if cook != null else "", "'")
	var seen := []
	var t0 := Time.get_ticks_msec()
	while cook != null and Time.get_ticks_msec() - t0 < 70000:
		await get_tree().process_frame
		var what := "%s%s" % [Villager.State.keys()[cook.state], " (holding %d %s)" % [cook._raw_left, cook._raw_kind] if cook._raw_left > 0 else ""]
		if seen.is_empty() or str(seen[-1]).split(" ")[0] != what.split(" ")[0]:
			seen.append(what)
		if cook.state == Villager.State.TO_COOK:
			cook.set_meta("dbg", "%.1f units from the fire, stuck %s, %.0f s left, leg %d of %d, goal %.1f from the fire" % [cook.position.distance_to(cook.stove.pos) / world.px, cook.steer.stuck, cook.state_until - Villager.now(), cook.leg, (cook.route as Array).size() if cook.route != null else -1, cook.target.distance_to(cook.stove.pos) / world.px])
		elif cook.has_meta("dbg"):
			print("Cook fetch: left TO_COOK for ", Villager.State.keys()[cook.state], " at ", cook.get_meta("dbg"))
			cook.remove_meta("dbg")
		if cook.state == Villager.State.STAND and seen.size() > 3:
			break
	print("Cook fetch: went ", seen)
	print("Cook fetch: potatoes ", v.stored("Potato"), ", baked ", v.stored("BakedPotato"))
