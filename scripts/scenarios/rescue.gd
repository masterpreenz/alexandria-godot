extends Scenario
## Miyu's rescue, start to end: a game without her; the elder's rumor; the next village's monsters as Sera nears; Miyu
## in the street; carried home (slower); set down, asleep the day through; the elders' scene; the chronicle. Then the
## other way: a day gone by with nobody going: she's lost.
## Run with --window=rescue.


func run() -> void:
	var rm: Rumors = g.get_node("Rumors")
	var ch: Chronicle = g.get_node("Chronicle")
	var rs: Rescue = g.get_node("Rescue")
	while Villager.all.size() < 2:
		await get_tree().process_frame
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day()) * 24.0 + 8.0
	# No Miyu (an old save's is taken out); the elder here (made of whoever's first).
	people.people = people.people.filter(func(p): return str(p.get("unique", "")) != "miyu")
	for v in Villager.all.duplicate():
		if str(v.person.get("unique", "")) == "miyu":
			v.queue_free()
	await get_tree().process_frame
	var elder_v: Villager = Villager.all[0]
	elder_v.person.name = "Genzo"
	elder_v.person["unique"] = "elder"
	ch.events = []
	rm.heard = {}
	rm.offers = {}
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Rescue: to tell ", rm.offers)
	var told := rm.hear("find_miyu", elder_v)
	print("Rescue: the elder says '", told.left(80), "...'; deadline ", rm.by_id.find_miyu.expires)
	var start_speed := miko.stats.stat("moveSpeed")
	# Near the village: its monsters.
	var before := Creature.all.size()
	miko.place(world.floors.cell_centre(Vector2i(-250, 70)))
	for i in 10:
		await get_tree().process_frame
	print("Rescue: near the next village: monsters there ", Creature.all.size() - before)
	for c in Creature.all.duplicate():
		if world.floors.cell_at(c.position).x < -200:
			c.queue_free()
	# Reached.
	miko.place(world.floors.cell_centre(Vector2i(-250, 108)))
	rm._clock = 9.0
	for i in 10:
		await get_tree().process_frame
	print("Rescue: reached: step ", rm.heard.find_miyu.step, ", Miyu ", rs.state)
	miko.place(world.floors.cell_centre(Rescue.LIES_AT) + Vector2(0.6, 0.2) * world.px)
	for i in 20:
		await get_tree().process_frame
	print("Rescue: by her: '", rs.prompt.text, "'")
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_lying.png")
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	for i in 6:
		await get_tree().process_frame
	print("Rescue: E: ", rs.state, "; move speed ", start_speed, " -> ", miko.stats.stat("moveSpeed"))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_carry.png")
	# Days pass on the way (the deadline no longer runs once she's carried).
	clock.hours += 30.0
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Rescue: 30 hours carrying her: the rumor still ", rm.heard.find_miyu.state)
	miko.place(world.village.centre() + Vector2(1.0, 1.0) * world.px)
	for i in 10:
		await get_tree().process_frame
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	var miyu := Uniques.person(people, "miyu")
	print("Rescue: home: ", rs.state, ", Miyu in the village ", not miyu.is_empty(), ", sleeps till ", snappedf(float(miyu.get("restUntil", 0.0)) - clock.hours, 0.1), " h from now; speed back to ", miko.stats.stat("moveSpeed"), "; rumor ", rm.heard.find_miyu.state)
	# The elders' scene.
	var talk: Talk = g.get_node("Hud/Talk")
	miko.place(elder_v.position + Vector2(0.8, 0.3) * world.px)
	talk.open(elder_v)
	await get_tree().process_frame
	var said := [talk._name.text + ": " + talk._line.text.left(50)]
	for i in 12:
		if talk._acts.is_empty() or not talk.visible or talk._acts.size() > 1:
			break
		(talk._acts[0] as Callable).call()
		await get_tree().process_frame
		said.append(talk._name.text + ": " + talk._line.text.left(40))
	print("Rescue: the scene: ", said.size(), " lines: ", said.slice(0, 4), " ... ", said[-2])
	talk.close()
	print("Rescue: chronicle ", ch.events.map(func(e): return e.what))
	# The other way: nobody goes.
	people.people = people.people.filter(func(p): return str(p.get("unique", "")) != "miyu")
	ch.events = []
	rm.heard = {}
	rs.state = ""
	rs.monsters_out = false
	rm.hear("find_miyu", elder_v)
	clock.hours += 25.0
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Rescue: a day with nobody going: ", rm.heard.find_miyu.state, "; lost ", Uniques.lost("miyu"), "; can she come now ", Uniques.arrive(people, "miyu"))
