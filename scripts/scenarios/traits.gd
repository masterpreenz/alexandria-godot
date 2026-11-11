extends Scenario
## Traits and the unique Miyu: what everyone was given and what it does; then Miyu taken away and the rumor to find
## her run both ways (reached in time: she comes; left too long: she's lost).
## Run with --window=traits.


func run() -> void:
	var rm: Rumors = g.get_node("Rumors")
	var ch: Chronicle = g.get_node("Chronicle")
	print("Traits: ", Traits.all().size(), " in the file, ", Uniques.all().size(), " unique characters")
	for vl in Villager.all:
		var p: Dictionary = vl.person
		print("Traits: ", p.name, (" (unique: %s)" % p.unique) if p.has("unique") else "", " ", Traits.of(p), ": work x", snappedf(Traits.mul(p, "work"), 0.01), ", hunger x", snappedf(Traits.mul(p, "hunger"), 0.01),
			", carries ", vl._carry_most(), ", flees under ", snappedf(minf(0.8, Villager.FLEE_BELOW * Traits.mul(p, "flee")), 0.01), ", max HP ", p.maxHp)
	# Rolled many times: never two that are opposites, never Unique.
	var bad := 0
	var counts := {}
	for i in 400:
		var q := {"maxHp": 40.0, "hp": 40.0, "atk": 6.0}
		Traits.roll(q)
		for id in Traits.of(q):
			counts[id] = int(counts.get(id, 0)) + 1
			if id == "unique" or Traits.of(q).any(func(o): return (Traits.all()[id].opposite as Array).has(o)):
				bad += 1
	print("Traits: 400 rolls: ", counts.size(), " different traits came up, ", bad, " bad rolls (opposites together, or Unique); a newcomer's name can be Miyu ", not Uniques.name_taken("Miyu"))
	var jw: JobsWindow = g.get_node("Hud/JobsWindow")
	jw.visible = true
	jw._built_for = "-"
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_table.png")
	jw.visible = false
	# Miyu not here: the rumor to find her.
	for both in ["reached", "left"]:
		people.people = people.people.filter(func(p): return str(p.get("unique", "")) != "miyu")
		ch.events = []
		rm.heard = {}
		rm.offers = {}
		clock.hours = 24.0 * 3.0 + 9.0
		rm._clock = 9.0
		for i in 5:
			await get_tree().process_frame
		var teller: Villager = null
		for vl in Villager.all:
			if is_instance_valid(vl) and rm.offer_from(vl).get("id", "") == "find_miyu":
				teller = vl
		if teller == null:
			print("Traits: nobody has the rumor to tell: ", rm.offers)
			return
		var told := rm.hear("find_miyu", teller)
		var st: Dictionary = rm.heard["find_miyu"]
		var at := rm.place_of(st, rm.by_id["find_miyu"], 0)
		if both == "reached":
			print("Find Miyu: ", teller.person.name, " (", Traits.of(teller.person), ") says '", told.left(90), "...'; the place ", snappedf(at.distance_to(world.village.centre()) / world.px, 1.0), " units ", rm.direction(at))
			miko.place(at + Vector2(0.5, 0.3) * world.px)
		else:
			clock.hours += 24.0 * 6.5
		rm._clock = 9.0
		for i in 5:
			await get_tree().process_frame
		var here := Uniques.person(people, "miyu")
		print("Find Miyu (", both, "): the rumor ", st.state, "; Miyu in the village ", not here.is_empty(), (" with %s" % str(Traits.of(here))) if not here.is_empty() else "", ", lost ", Uniques.lost("miyu"), "; chronicle ", ch.events.map(func(e): return e.what))
		rm._clock = 9.0
		for i in 5:
			await get_tree().process_frame
		print("Find Miyu (", both, "): offered again ", rm.offers.has("find_miyu"), "; a second arrival ", Uniques.arrive(people, "miyu"))
