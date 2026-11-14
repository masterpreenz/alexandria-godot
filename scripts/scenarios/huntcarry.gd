extends Scenario
## A hunter's catch home in one go: a boar he's hunting falls by him, and he gathers up all of it (the meat, and the
## hide with it in his bag) and takes it to storage in one trip. Run with --window=huntcarry.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	var man: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and Villager.male(v.person) and v.visible:
			man = v
			break
	Villager.only(man.person, [Villager.Job.HUNTING])
	man.person["hunger"] = 100.0
	man.person["thirst"] = 100.0
	man.person["lastMeal"] = 999999
	var c := world.village.centre()
	man.position = c + Vector2(3.0, 2.0) * world.px
	man.reset_physics_interpolation()
	miko.place(c + Vector2(-14.0, 8.0) * world.px)   # (well away: what lies near her drifts into her bag)
	var boar := Boar.spawn(world, world._load_json("res://data/monsters.json").boar, man.position + Vector2(1.5, 0.0) * world.px)
	await _secs(0.3)
	man.prey = boar
	man.state = Villager.State.HUNT
	man.state_until = Villager.now() + 60.0
	var hide0 := world.village.stored("Hide")
	boar.hit.hurt(9999.0)
	print("Hunt carry: ", man.person.name, " carries at most ", man._carry_most())
	var trips := 0
	var last := -1
	for i in 80:
		await _secs(0.5)
		if man.state != last:
			last = man.state
			if man.state == Villager.State.TO_STORE:
				trips += 1
				for p in Pickup.all:
					if is_instance_valid(p) and Villager.GAME_DROPS.has(p.resource):
						print("   lying: ", p.resource, " x", p.amount, " ", snappedf(p.ground.distance_to(man.position) / world.px, 0.1), " away, settled ", p.settled(), ", thrown ", p.thrown, ", claimed ", Villager.gathering.has(p), ", reachable ", man._game_reachable(p.ground), "; he hunts ", man.hunts())
			print("Hunt carry: ", snappedf(i * 0.5, 0.1), "s ", Villager.State.keys()[man.state], " carrying ", man.carrying, " ", man.carry_kind, " and ", man.side_load)
	print("Hunt carry: trips to storage ", trips, "; hide stored ", world.village.stored("Hide") - hide0, "; game left lying by the kill ", Pickup.all.filter(func(p): return is_instance_valid(p) and Villager.GAME_DROPS.has(p.resource) and p.ground.distance_to(man.position) < 30.0 * world.px).size())
