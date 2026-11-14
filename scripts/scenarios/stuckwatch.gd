extends Scenario
## Watching for villagers stuck on their way somewhere: anyone trying to walk who's barely moved in 4 seconds is
## reported (where, what they're at, where they're going, the mist here and there). Best run on a real save:
## --window=stuckwatch --slot=quick.


func run() -> void:
	var last := {}
	var told := {}
	var start := Time.get_ticks_msec()
	Engine.time_scale = 3.0
	while Time.get_ticks_msec() - start < 400000:
		for i in 60:
			await get_tree().process_frame
		var t := Villager.now()
		for v: Villager in Villager.all:
			if not is_instance_valid(v) or not v.visible:
				continue
			var id := v.get_instance_id()
			# (walking, by their pace: whatever they're at)
			if v._walk_speed_now <= 0.0 or not (v.s.walkDown as Array).has(v.shown) and not (v.s.walkUp as Array).has(v.shown):
				last.erase(id)
				continue
			if not last.has(id) or (last[id][0] as Vector2).distance_to(v.position) > 0.4 * world.px:
				last[id] = [v.position, t]
				continue
			if t - float(last[id][1]) < 4.0 or told.get(id, 0) >= 3:
				continue
			told[id] = int(told.get(id, 0)) + 1
			last[id] = [v.position, t]
			var aim := v._aim()
			print("Stuck: ", v.person.name, " ", Villager.State.keys()[v.state], " (", v.activity() if v.has_method("activity") else "", ") at ", (v.position / world.px).snapped(Vector2(0.1, 0.1)),
				" going to ", (v.target / world.px).snapped(Vector2(0.1, 0.1)), " aiming at ", (aim / world.px).snapped(Vector2(0.1, 0.1)),
				", mist here ", world.mist.tier_at(v.position) if world.mist else -1, " there ", world.mist.tier_at(v.target) if world.mist else -1,
				", ahead clear ", Villager.safe_ground(world, v.position + (aim - v.position).normalized() * 0.5 * world.px),
				", detour ", v._detour != Vector2.INF, " x", v._detours, ", route ", v.route.size() if v.route != null else -1, " leg ", v.leg,
				", vel ", v.velocity.round(), ", steer stuck ", v.steer.stuck, ", trying ", snappedf(v._trying_for, 0.1))
			shot("stuck_" + str(v.person.name))
	print("Stuck watch done")
