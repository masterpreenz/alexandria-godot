extends Scenario
## Intimacy with Miyu: the day's first talk, her topics and what the answers do, gifts by her tastes (one a day),
## hearts, the milestones, and at 100 her asking for a book.
## Run with --window=intimacy.


func run() -> void:
	var talk: Talk = g.get_node("Hud/Talk")
	var rm: Rumors = g.get_node("Rumors")
	var ch: Chronicle = g.get_node("Chronicle")
	while Villager.all.is_empty():
		await get_tree().process_frame
	clock.hours = float(clock.day() - 1) * 24.0 + 10.0
	var miyu: Villager = null
	for vl in Villager.all:
		if vl.person.has("unique"):
			miyu = vl
	if miyu == null:
		# (this save's fourth villager is a newcomer each run: made Miyu for the test)
		miyu = Villager.all.filter(func(x): return int(x.person.get("look", -1)) == 2)[0]
		miyu.person["name"] = "Miyu"
		miyu.person["unique"] = "miyu"
		Traits.give(miyu.person, Uniques.all()["miyu"].traits)
	var p: Dictionary = miyu.person
	p.hunger = 90.0
	for k in ["intimacy", "talkedDay", "giftDay", "topics"]:
		p.erase(k)
	var other: Villager = Villager.all.filter(func(x): return not x.person.has("unique"))[0]
	print("Intimacy: ", p.name, " ", Intimacy.hearts(p), " ", Intimacy.of(p), "; ", other.person.name, " (not unique) hearts '", Intimacy.hearts(other.person), "'")
	var choices := func() -> Array:
		return talk._choices.get_children().filter(func(c): return not c.is_queued_for_deletion()).map(func(c): return c.text)
	miko.place(miyu.position + Vector2(0.8, 0.3) * world.px)
	talk.open(miyu)
	await get_tree().process_frame
	print("Intimacy: first talk of the day: ", Intimacy.of(p), "; she says '", talk._line.text, "'; choices ", choices.call())
	talk.close()
	talk.open(miyu)
	await get_tree().process_frame
	print("Intimacy: a second talk the same day: ", Intimacy.of(p))
	# Her first topic, the best answer.
	var topic := Intimacy.topic(p)
	talk._ask_topic(topic)
	await get_tree().process_frame
	print("Intimacy: topic '", topic.ask, "': replies ", choices.call())
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_topic.png")
	(talk._acts[0] as Callable).call()
	await get_tree().process_frame
	print("Intimacy: answered: ", Intimacy.of(p), ", she says '", talk._line.text, "'; next topic '", Intimacy.topic(p).get("ask", "none yet"), "'")
	# Gifts.
	for item in ["Candy", "Fish", "Wood", "Bread"]:
		miko.bag.counts[item] = 3
	talk._pick_gift()
	await get_tree().process_frame
	print("Intimacy: gift choices ", choices.call())
	var before := Intimacy.of(p)
	talk._give_gift("Candy")
	await get_tree().process_frame
	print("Intimacy: candy (", Intimacy.taste(p, "Candy"), "): ", before, " -> ", Intimacy.of(p), ", '", talk._line.text, "'; candy left ", miko.bag.count("Candy"))
	talk._pick_gift()
	await get_tree().process_frame
	print("Intimacy: another the same day: '", talk._line.text, "'")
	for item in ["Fish", "Wood"]:
		p.erase("giftDay")
		before = Intimacy.of(p)
		talk._give_gift(item)
		print("Intimacy: ", item, " (", Intimacy.taste(p, item), "): ", before, " -> ", Intimacy.of(p))
	talk.close()
	# Up through the milestones to 100.
	for at in [30.0, 55.0, 80.0, 100.0]:
		Intimacy.gain(p, at - Intimacy.of(p))
		print("Intimacy: at ", Intimacy.of(p), " ", Intimacy.hearts(p), ": greets '", Intimacy.greeting(p), "'; topic '", Intimacy.topic(p).get("ask", "none"), "'")
	print("Intimacy: chronicle ", ch.events.map(func(e): return e.what).filter(func(w): return str(w).begins_with("intimacy")))
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Intimacy: at 100, to tell: ", rm.offers, "; Miyu has the rumor ", rm.offer_from(miyu).get("title", "none"))
	talk.open(miyu)
	await get_tree().process_frame
	print("Intimacy: choices now ", choices.call())
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_full.png")
	talk.close()
	var again: Dictionary = JSON.parse_string(people.to_json())
	for q in again.people:
		if q.has("unique"):
			print("Intimacy: saved: intimacy ", q.get("intimacy"), ", topics ", q.get("topics"), ", talked day ", q.get("talkedDay"))
