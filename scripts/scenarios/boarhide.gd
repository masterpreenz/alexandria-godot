extends Scenario
## A boar's drops: killed ten times over, what lands each time (meat and hide), and where the hide lies (in the mist,
## in water). Run with --window=boarhide.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var c := world.village.centre()
	for i in 10:
		var at := c + Vector2(randf_range(-6, 6), randf_range(-6, 6)) * world.px
		var before := {}
		for p in Pickup.all:
			before[p] = true
		var boar := Boar.spawn(world, md.boar, at)
		await _secs(0.3)
		boar.hit.hurt(9999.0)
		await _secs(2.0)
		var got := {}
		var hide_where := ""
		for p in Pickup.all:
			if is_instance_valid(p) and not before.has(p):
				got[p.resource] = int(got.get(p.resource, 0)) + p.amount
				if p.resource == "Hide":
					hide_where = "%s, clear %s" % [(p.ground / world.px).round(), Villager.safe_ground(world, p.ground)]
		print("Boar hide: kill ", i, ": ", got, ", hide at ", hide_where)
