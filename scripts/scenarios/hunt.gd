extends Scenario
## Hunting: only the men can be set to it, and "any work" never takes it in. A man set to hunt goes after a boar found
## by a crystal: he shoots it with his bow from a distance, steps out of its charge, and brings the meat home.
## Run with --window=hunt.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	clock.hours = floorf(clock.hours / 24.0) * 24.0 + 9.0   # (morning: hunting's by day)
	var man: Villager = null
	var woman: Villager = null
	for v in Villager.all:
		if not is_instance_valid(v) or v.person.has("unique"):
			continue
		if Villager.male(v.person) and man == null:
			man = v
		elif not Villager.male(v.person) and woman == null:
			woman = v
	print("Hunt: man ", man.person.name if man != null else "-", ", woman ", woman.person.name if woman != null else "-")
	if woman != null:
		print("Hunt: a woman can hunt: ", Villager.able(woman.person, Villager.Job.HUNTING))
	if man == null:
		return
	print("Hunt: before he's set to it, he hunts: ", man.hunts(), " (his work: ", JobsWindow.jobs_text(man.person), ")")
	Villager.only(man.person, [Villager.Job.HUNTING])
	print("Hunt: set to hunt only: hunts ", man.hunts(), ", jobs ", JobsWindow.jobs_text(man.person))
	# A boar by a crystal outside the village.
	var spots := Crystals.active.spots()
	print("Hunt: crystals ", spots.size())
	var md: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var at := Vector2.INF
	for c in spots:
		if world.village.contains(c, 6.0):
			continue
		for i in 24:
			var spot: Vector2 = c + Vector2.from_angle(i * TAU / 24.0) * Vector2(1.0, 0.5) * 5.0 * world.px
			if Wilds.dry(world, spot, 0.6) and not world.village.contains(spot, 2.0) and Villager.safe_ground(world, spot):
				at = spot
				break
		if at != Vector2.INF:
			break
	if at == Vector2.INF:
		print("Hunt: no crystal outside the village to hunt by")
		return
	var boar := Boar.spawn(world, md.boar, at)
	boar.hit.max_hp = 60.0
	boar.hit.hp = 60.0
	# He's near it; Sera watching from a way off.
	man.position = at + Vector2(-9.0, 2.0) * world.px
	miko.position = at + Vector2(-4.0, 5.0) * world.px
	man.state = Villager.State.STAND
	man.state_until = 0.0
	await _secs(0.5)
	print("Hunt: why not? night ", man._night(), ", able ", Villager.able(man.person, Villager.Job.HUNTING), ", carrying ", man.carrying, ", party ", man._in_party(), ", boar in village ", world.village.contains(boar.position, 1.0), ", safe ", Villager.safe_ground(world, boar.position), ", by crystal ", man._by_crystal(boar.position, spots), ", in Creature.all ", Creature.all.has(boar), ", hour ", clock.hour())
	var went := man._go_hunt(true)
	print("Hunt: off hunting ", went, ", after a ", man._prey_name(), ", state ", Villager.State.keys()[man.state])
	var dodges := 0
	var was_dodging := false
	var hurt0 := man.hit.hp
	var start := Time.get_ticks_msec()
	var pictured := 0
	while Time.get_ticks_msec() - start < 40000:
		await get_tree().process_frame
		var dodging := man.dodge_until > Villager.now()
		if dodging and not was_dodging:
			dodges += 1
		was_dodging = dodging
		if pictured == 0 and man._shot_from > 0.0 and Villager.now() - man._shot_from > 0.7:
			pictured = 1
			shot("aim")
		if pictured == 1 and boar != null and is_instance_valid(boar) and boar.state == Boar.State.WIND_UP:
			pictured = 2
			shot("charge")
		if not is_instance_valid(boar) or not boar.hit.alive():
			break
		if Engine.get_process_frames() % 300 == 0:
			print("Hunt: ... ", Villager.State.keys()[man.state], " ", man.activity(), ", boar ", Boar.State.keys()[boar.state], " HP ", roundi(boar.hit.hp), ", apart ", snappedf(man.position.distance_to(boar.position) / world.px, 0.1), ", boar from crystal ", snappedf(boar.position.distance_to(at) / world.px, 0.1))
	print("Hunt: after ", (Time.get_ticks_msec() - start) / 1000.0, " s: boar ", ("down" if not is_instance_valid(boar) or not boar.hit.alive() else "HP %d" % roundi(boar.hit.hp)), ", dodges ", dodges, ", his HP ", roundi(hurt0), " -> ", roundi(man.hit.hp), ", state ", Villager.State.keys()[man.state], ", activity: ", man.activity())
	var meat := 0
	for pk in Pickup.all:
		if is_instance_valid(pk) and pk.resource == "Food" and pk.position.distance_to(at) < 8.0 * world.px:
			meat += pk.amount
	print("Hunt: meat on the ground from the boar ", meat)
	for i in 4:
		await _secs(2.0)
		print("Hunt: then: ", Villager.State.keys()[man.state], " carrying ", man.carrying, " ", man.carry_kind, " (", man.activity(), ")")
	shot("after")
	# A boar lost comes back a few hours later (game hours), one at a time.
	var sp: Spawners = g.find_children("*", "Spawners", true, false)[0]
	var before := sp.boars.size()
	print("Hunt: boars about the world ", before, " (of ", sp.d.boarSpawner.count, "), forest spots for them ", Wilds.find_spot(world, sp._boar_fits, 160) != null)
	if before == 0:
		return
	sp.boars[0].queue_free()
	await _secs(1.5)
	clock.hours += 4.1
	await _secs(2.5)
	print("Hunt: boars ", before, ", one taken away, 4 game hours on: ", sp.boars.size())
	# The maps: whoever can be played shown standing.
	shot("minimap")
