extends Scenario
## Villagers round a bit of mist: one on cleared ground sent somewhere else cleared, with mist on the straight line
## between, heads for the middle of the cleared land and on from there, instead of standing at the mist's edge. Tried
## the old way too (stopped at the edge). Run with --window=mistround.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	var v: Villager = null
	for x in Villager.all:
		if is_instance_valid(x) and x.state != Villager.State.ASLEEP and x.visible and not x._in_party():
			v = x
			break
	# A start and an end on cleared ground, mist between, each a straight walk from the middle of the cleared land.
	var middles: Array = [world.village.centre()]
	middles.append_array(Crystals.active.spots())
	var pair: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 20000:
		var m: Vector2 = middles[rng.randi() % middles.size()]
		var a: Vector2 = m + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9)) * world.px
		var b: Vector2 = m + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9)) * world.px
		if a.distance_to(b) < 5.0 * world.px or not Villager.safe_ground(world, a) or not Villager.safe_ground(world, b):
			continue
		if v._mist_free(a, b) or not v._mist_free(a, m) or not v._mist_free(m, b):
			continue
		if VillagerRoute.find(world, a, b) == null or v._clear_middle_from(a) != m:
			continue
		pair = [a, b, m]
		break
	if pair.is_empty():
		print("Mist round: no such spots found")
		return
	print("Mist round: from ", (pair[0] / world.px).round(), " to ", (pair[1] / world.px).round(), ", ", snappedf(pair[0].distance_to(pair[1]) / world.px, 0.1), " apart; middle ", (pair[2] / world.px).round())
	for old_way in [true, false]:
		v.position = pair[0]
		v.reset_physics_interpolation()
		v.velocity = Vector2.ZERO
		v.state = Villager.State.TO_WELL
		v.state_until = Villager.now() + 40.0
		v._detour = Vector2.INF
		v._set_goal(pair[1])
		v._detour_for = pair[1] if old_way else Vector2.INF
		v._detours = 2 if old_way else 0
		var start := Time.get_ticks_msec()
		var arrived := -1.0
		var into_mist := 0
		while Time.get_ticks_msec() - start < 25000:
			await get_tree().process_frame
			if not Villager.safe_ground(world, v.position):
				into_mist += 1
			if v.position.distance_to(pair[1]) < 0.3 * world.px:
				arrived = (Time.get_ticks_msec() - start) / 1000.0
				break
			if v.state != Villager.State.TO_WELL:
				break
		print("Mist round (", "old way" if old_way else "round by the middle", "): there ", arrived >= 0.0, " after ", arrived, " s; now ", Villager.State.keys()[v.state], ", ", snappedf(v.position.distance_to(pair[1]) / world.px, 0.1), " away, frames in the mist ", into_mist)
		if not old_way:
			shot("round")
