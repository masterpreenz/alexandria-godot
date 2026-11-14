extends Scenario
## Prey into the mist: a hunter after a boar that goes off into the mist, out of bow range, lets it be within a few
## seconds (before, he ran on the spot at the mist's edge till the hunt ran out). Run with --window=mistprey.
## (Set up as hunt.gd.) Hunting: only the men can be set to it, and "any work" never takes it in. A man set to hunt goes after a boar found
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
	await _secs(2.0)
	# The boar off into the mist, out of range.
	var into := Vector2.INF
	for r in range(6, 30):
		for a in 24:
			var p: Vector2 = man.position + Vector2.from_angle(a * TAU / 24.0) * r * 0.5 * world.px
			if into == Vector2.INF and not Villager.safe_ground(world, p) and p.distance_to(man.position) > Villager.BOW_RANGE * 1.6 * world.px:
				into = p
	boar.position = into
	boar.state = Boar.State.GRAZE
	boar.reset_physics_interpolation()
	var t0 := Villager.now()
	var ended := -1.0
	while Villager.now() - t0 < 15.0:
		await get_tree().process_frame
		if man.state != Villager.State.HUNT and ended < 0.0:
			ended = Villager.now() - t0
	print("Mist prey: boar put in the mist ", snappedf(into.distance_to(man.position) / world.px, 0.1), " away; hunt given up after ", snappedf(ended, 0.1), " s, now ", Villager.State.keys()[man.state], " (", man.activity(), ")")
