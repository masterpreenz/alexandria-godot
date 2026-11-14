extends Scenario
## A hunter with nothing to hunt clears monsters round the village: no game about, a slime in the mist just outside;
## he goes after it, into the mist, growing mist sick there, and kills it. Then a second slime, with him already
## near sick enough: he turns for home, and won't go out again till it's worn off. Run with --window=mistclear.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _mist_spot(deeper: float) -> Vector2:
	var c := world.village.centre()
	var spot := Vector2.INF
	var best := INF
	for x in range(-60, 61):
		for y in range(-60, 61):
			var at := c + Vector2(x, y) * 0.5 * world.px
			if not Villager.safe_ground(world, at) and at.distance_to(c) < best:
				best = at.distance_to(c)
				spot = at
	return spot + (spot - c).normalized() * deeper * world.px if spot != Vector2.INF else spot


func run() -> void:
	await _secs(1.0)
	clock.hours = floorf(clock.hours / 24.0) * 24.0 + 9.0
	for c in Creature.all.duplicate():
		if is_instance_valid(c) and (c is Boar or c is Rabbit or c is Slime or c is MutatedWolf or c is MutatedVillager):
			c.queue_free()
	await _secs(0.3)
	var man: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and not v.person.has("unique") and Villager.male(v.person) and v.visible:
			man = v
			break
	if man == null:
		print("Clear: no man to hunt")
		return
	Villager.only(man.person, [Villager.Job.HUNTING])
	man.person["hunger"] = 100.0
	man.person["thirst"] = 100.0
	man.person["lastMeal"] = 999999
	var spot := _mist_spot(5.0)
	print("Clear: ", man.person.name, " hunts ", man.hunts(), "; slime at ", (spot / world.px).round(), " in the mist ", not Villager.safe_ground(world, spot), ", outside the village ", not world.village.contains(spot, 2.0), ", within reach of the village ", world.village.contains(spot, Villager.CLEAR_REACH))
	var cells_off: Vector2 = world.floors.fractional_cell(spot) - world.floors.fractional_cell(world.village.centre())
	print("Clear: slime ", cells_off.round(), " cells from the village's middle; its half size ", world.village.half_size(), "; from him ", snappedf(spot.distance_to(man.position) / world.px, 0.1), " units")
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var sl: Slime = Slime.spawn(world, md.slime, false, spot, 1.0)
	miko.place(man.position + Vector2(-3, 2) * world.px)
	# His day: idle hunting finds nothing, so he goes after the slime.
	var went := false
	for i in 40:
		await _secs(0.5)
		if man.state == Villager.State.HUNT and man.prey == sl:
			went = true
			break
	print("Clear: went after it by himself ", went, " (", Villager.State.keys()[man.state], ", ", man.activity(), ")")
	if not went:
		man._stand(Villager.now(), 0.0)
		print("Clear: sent: ", man._go_clear())
	var most_sick := 0.0
	var in_mist := false
	var until := Time.get_ticks_msec() + 60000
	var next_say := 0
	while Time.get_ticks_msec() < until and is_instance_valid(sl) and sl.hit.alive():
		await get_tree().process_frame
		if Time.get_ticks_msec() >= next_say:
			next_say = Time.get_ticks_msec() + 3000
			print("Clear trace: ", Villager.State.keys()[man.state], " clearing ", man._clearing, ", ", snappedf(man.position.distance_to(sl.position) / world.px, 0.1), " units off, slime hp ", snappedf(sl.hit.hp, 0.1), ", he's in the mist ", not Villager.safe_ground(world, man.position), ", slime in it ", not Villager.safe_ground(world, sl.position), ", sick ", roundi(man.mist_sick * 50.0), "%, vel ", snappedf(man.velocity.length() / world.px, 0.1))
		most_sick = maxf(most_sick, man.mist_sick)
		in_mist = in_mist or not Villager.safe_ground(world, man.position)
	print("Clear: slime killed ", not (is_instance_valid(sl) and sl.hit.alive()), ", he went into the mist ", in_mist, ", mist sick at most ", roundi(most_sick * 50.0), "%")
	shot("killed")
	# A second, with him nearly sick enough already.
	await _secs(4.0)
	var sl2: Slime = Slime.spawn(world, md.slime, false, _mist_spot(6.0), 1.0)
	if man.state == Villager.State.HUNT:
		man._end_hunt(Villager.now(), false)
	man._stand(Villager.now(), 0.0)
	man.mist_sick = 0.0
	print("Clear: second slime: sent ", man._go_clear())
	for i in 400:
		await _secs(0.05)
		if not Villager.safe_ground(world, man.position):
			break
	print("Clear: in the mist after it ", not Villager.safe_ground(world, man.position), ", ", Villager.State.keys()[man.state])
	man.mist_sick = 0.97
	var home := false
	var seen := {}
	until = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		seen[Villager.State.keys()[man.state] + (" sick %d%%" % roundi(man.mist_sick * 50.0)) + (" mist" if not Villager.safe_ground(world, man.position) else "")] = true
		if seen.size() > 12:
			seen.clear()
		if man.state == Villager.State.HOME:
			home = true
			break
	print("Clear: turned for home ", home, " at mist sick ", roundi(man.mist_sick * 50.0), "%; slime still alive ", is_instance_valid(sl2) and sl2.hit.alive())
	print("Clear: straight out again while sick: ", man._go_clear())
	await _secs(8.0)
	print("Clear: after 8 s out of the mist, sick ", roundi(man.mist_sick * 50.0), "%")
	shot("home")
