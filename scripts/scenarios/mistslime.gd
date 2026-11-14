extends Scenario
## A slime in the mist where the village's square reaches into it: a fighter doesn't take it on (before, set on it
## after it hit him, he ran at it and stood running on the spot at the mist's edge for good). And one he can't get nearer: let be after 4 seconds.
## Best on a real save: --window=mistslime --slot=quick.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	var spot := Vector2.INF
	var c := world.village.centre()
	var best := INF
	for x in range(-60, 61):
		for y in range(-60, 61):
			var at := c + Vector2(x, y) * 0.5 * world.px
			if not Villager.safe_ground(world, at) and at.distance_to(c) < best:
				best = at.distance_to(c)
				spot = at
	if spot == Vector2.INF:
		print("Mist slime: no mist inside the village here")
		return
	var sl := Slime.spawn(world, world._load_json("res://data/monsters.json").slime, false, spot, 1.0)
	var fighter: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and v.visible and not v._in_party() and not (v.s.stabDown as Array).is_empty() and v.state != Villager.State.ASLEEP:
			fighter = v
			break
	# him on cleared ground beside it
	var near := spot
	for r in range(1, 20):
		var found := false
		for a in 16:
			var at := spot + Vector2.from_angle(a * TAU / 16.0) * r * 0.5 * world.px
			if Villager.safe_ground(world, at):
				near = at
				found = true
				break
		if found:
			break
	fighter.position = near
	fighter.reset_physics_interpolation()
	fighter._stand(Villager.now(), 0.1)
	miko.place(near + Vector2(2, 1) * world.px)
	print("Mist slime: slime at ", (spot / world.px).round(), " in the mist, ", fighter.person.name, " ", snappedf(near.distance_to(spot) / world.px, 0.1), " away on cleared ground")
	await _secs(0.3)
	fighter._fight(sl.hit)
	var fought := 0
	var start := fighter.position
	for i in 10:
		await _secs(1.0)
		if fighter.state == Villager.State.FIGHT:
			fought += 1
	print("Mist slime: seconds of the last 10 spent fighting it ", fought, ", now ", Villager.State.keys()[fighter.state], ", moved ", snappedf(fighter.position.distance_to(start) / world.px, 0.1), ", slime alive ", is_instance_valid(sl))
	shot("after")
