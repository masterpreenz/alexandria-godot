extends Scenario
## After dark, a villager by an unlit torch when a slime comes: they light the torch first, then fight.
## Run with --window=torchfight.


func run() -> void:
	while Villager.all.size() < 2:
		await get_tree().process_frame
	clock.hours = float(clock.day()) * 24.0 + 20.0
	var fires: Fires = miko.get_node("Fires")
	# A torch in the village, put out; a villager by it, awake and at nothing.
	var torch := {}
	for f in fires.fires:
		if bool(f.s.get("torch", false)) and world.village.contains(f.pos):
			torch = f
			break
	fires.lit_until.erase(torch.key)
	Villager.lighting.erase(torch.key)   # (nobody else already on their way to it)
	var v: Villager = null
	for x in Villager.all:
		if is_instance_valid(x) and x.hit.alive() and not str(x.person.get("unique", "")) in ["elder", "elder_wife"]:
			v = x
			break
	v.person.erase("restUntil")
	v.position = torch.pos + Vector2(2.0, 0.5) * world.px
	v._stand(Creature.now(), 0.0)
	miko.place(torch.pos + Vector2(0, 3) * world.px)
	await get_tree().process_frame
	var toward: Vector2 = (world.village.centre() - torch.pos).normalized()
	var sl := Slime.spawn(world, world._load_json("res://data/monsters.json").slime, false, v.position + toward * 3.0 * world.px, 1.0)
	sl.angry_until = INF
	sl.hit.unkillable = true   # (the test: still there once the torch is lit)
	Villager.lighting.erase(torch.key)
	print("Torch fight: before, hour ", snappedf(clock.hour(), 0.1), ", night ", v._night(), ", torch tended ", fires.tended(torch), ", can pay ", v._can_pay(torch), ", being lit ", Villager.lighting.has(torch.key), ", distance ", snappedf(torch.pos.distance_to(v.position) / world.px, 0.1), ", wood ", world.village.stored("Wood"))
	v._fight(sl.hit)
	var seen := []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		var st: String = Villager.State.keys()[v.state]
		if seen.is_empty() or seen[-1] != st:
			seen.append(st)
		if fires.lit(torch) and v.state == Villager.State.FIGHT:
			break
		await get_tree().process_frame
	print("Torch fight: ", v.person.name, " went ", seen, "; torch lit ", fires.lit(torch), "; slime still about ", is_instance_valid(sl) and sl.hit.alive())
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_lit.png")
