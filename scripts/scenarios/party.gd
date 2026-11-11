extends Scenario
## The party: Miyu joins (the story's word, once she's awake), follows Sera across the map and catches up when far
## behind, fights a slime that comes at them, waits when told and follows again, chops a tree for Sera (into her bag),
## and goes home. Its faces under Sera's card. Saved and loaded.
## Run with --window=party.


func run() -> void:
	var pt: Party = g.get_node("Party")
	var ch: Chronicle = g.get_node("Chronicle")
	while Villager.all.size() < 2:
		await get_tree().process_frame
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day()) * 24.0 + 9.0
	var miyu: Villager = null
	for v in Villager.all:
		if str(v.person.get("unique", "")) == "miyu":
			miyu = v
	if miyu == null:
		# (this save's girl of her look, made Miyu for the test)
		for v in Villager.all:
			if int(v.person.get("look", -1)) == 2:
				miyu = v
		miyu.person.name = "Miyu"
		miyu.person["unique"] = "miyu"
		Traits.give(miyu.person, Uniques.all()["miyu"].traits)
	miyu.person.hunger = 90.0
	miyu.person.erase("restUntil")
	ch.record("party_join:miyu")
	pt._next = 0.0
	for i in 5:
		await get_tree().process_frame
	print("Party: members ", pt.members, "; Miyu ", Villager.State.keys()[miyu.state])
	# Follow across the village and on out.
	for i in 30:
		await get_tree().process_frame
	var start := miko.position
	for step in 6:
		miko.place(start + Vector2(step * 1.5, step * 0.4) * world.px)
		for i in 25:
			await get_tree().physics_frame
	print("Party: walked 9 units: Miyu ", snappedf(miyu.position.distance_to(miko.position) / world.px, 0.1), " units from Sera, ", Villager.State.keys()[miyu.state])
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_follow.png")
	# Far off: she's brought up.
	miko.place(world.floors.cell_centre(Vector2i(-200, 0)))
	for i in 20:
		await get_tree().physics_frame
	print("Party: Sera far off (a teleport): Miyu ", snappedf(miyu.position.distance_to(miko.position) / world.px, 0.1), " units away")
	# A slime at them.
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var sl := Slime.spawn(world, md.slime, false, miko.position + Vector2(3.0, 0.5) * world.px, 1.0)
	sl.angry_until = INF
	for i in 5:
		await get_tree().physics_frame
	print("Party: slime hostile ", sl.hostile(), ", at ", snappedf(sl.position.distance_to(miko.position) / world.px, 0.1), " units; Miyu's threat ", miyu._party_threat(), ", state ", Villager.State.keys()[miyu.state], ", low ", miyu._low())
	var fought := false
	for i in 200:
		await get_tree().physics_frame
		if miyu.state == Villager.State.FIGHT:
			fought = true
	print("Party: a slime: Miyu fought ", fought, ", the slime ", "gone" if not is_instance_valid(sl) or not sl.hit.alive() else "still there")
	if is_instance_valid(sl):
		sl.queue_free()
	# Wait, then follow.
	pt.wait_here(miyu.person, miyu.position)
	var waited := miyu.position
	miko.place(miko.position + Vector2(5, 0) * world.px)
	for i in 60:
		await get_tree().physics_frame
	print("Party: told to wait: moved ", snappedf(miyu.position.distance_to(waited) / world.px, 0.1), " units; '", miyu.activity(), "'")
	pt.follow(miyu.person)
	for i in 120:
		await get_tree().physics_frame
	print("Party: told to follow: ", snappedf(miyu.position.distance_to(miko.position) / world.px, 0.1), " units from Sera")
	# An errand: the nearest tree.
	var near: Gatherable = null
	for gt in Gatherable.all:
		if gt.axe and not gt.depleted() and (near == null or gt.foot.distance_to(miko.position) < near.foot.distance_to(miko.position)):
			near = gt
	miko.place(near.foot + Vector2(1.5, 0.6) * world.px)
	for i in 60:
		await get_tree().physics_frame
	var wood := miko.bag.count("Wood")
	print("Party: chop here: ", miyu.errand_gather())
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000 and miko.bag.count("Wood") == wood:
		await get_tree().physics_frame
	for i in 120:
		await get_tree().physics_frame
	print("Party: Sera's wood ", wood, " -> ", miko.bag.count("Wood"), "; Miyu now ", Villager.State.keys()[miyu.state])
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_chop.png")
	var saved := pt.to_json()
	pt.members = []
	pt.from_json(saved)
	print("Party: saved and loaded: ", pt.members)
	pt.leave("miyu")
	for i in 30:
		await get_tree().physics_frame
	print("Party: sent home: members ", pt.members, ", Miyu ", miyu.activity())
