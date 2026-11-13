extends Scenario
## Half a day after Miyu wakes she talks of magic, and of the book she went to the next village to borrow; then her
## rumor sends Sera back there for what's left. In the overrun village: its two bookshelves (put into games that had
## the village already), a plain one with nothing on it, and the old woman's with the book of water magic.
## Run with --window=miyubook.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var ch := Chronicle.active
	var r := Rumors.active
	var miyu: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			miyu = v
	if miyu == null:
		# (the bundled save has no Miyu yet: someone stands in for her)
		miyu = Villager.all[1]
		miyu.person["unique"] = "miyu"
		miyu.person["name"] = "Miyu"
		var tr: Array = miyu.person.get("traits", []).duplicate()
		tr.append("unique")
		miyu.person["traits"] = tr
	ch.events = ch.events.filter(func(e): return not str(e.what) in ["scene:miyu_magic", "miyu_errand", "water_tome_found", "scene:miyu_wakes"])
	r.heard.erase("village_salvage")
	for e in ["miyu_home", "party:miyu"]:
		if not ch.happened(e):
			ch.record(e)
	ch.record("scene:miyu_wakes")
	print("Miyu book: just woken, her magic talk waiting '", Scenes.for_speaker(miyu.person).get("id", ""), "'")
	for e in ch.events:
		if e.what == "scene:miyu_wakes":
			e.h = float(e.h) - 13.0
	var scene := Scenes.for_speaker(miyu.person)
	print("Miyu book: half a day on, waiting '", scene.get("id", ""), "', lines ", (scene.get("lines", []) as Array).size())
	miko.place(miyu.position + Vector2(1.0, 0.6) * world.px)
	for i in 10:
		await get_tree().process_frame
	Talk.active.open(miyu)
	for i in 10:
		await get_tree().process_frame
	Talk.active._play(scene, 3)
	for i in 5:
		await get_tree().process_frame
	shot("talk")
	Talk.active._play(scene, (scene.lines as Array).size())
	Talk.active.close()
	for i in 90:
		await get_tree().process_frame
	print("Miyu book: errand told ", ch.happened("miyu_errand"), ", her rumor offered by ", r.offers.get("village_salvage", "-"))
	r.hear("village_salvage", miyu)
	# Up to the overrun village.
	miko.place(world.floors.cell_centre(Vector2i(-250, 110)))
	for i in 120:
		await get_tree().process_frame
	print("Miyu book: there, the rumor's step ", r.heard.village_salvage.get("step", ""))
	var shelves := []
	for nm in Salvage.SHELVES:
		for at in world.props_named(nm):
			if Wildlands.WEST_VILLAGE.has_point(world.floors.cell_at(at)):
				shelves.append(world.floors.cell_at(at) - Wildlands.WEST_VILLAGE.position)
	print("Miyu book: shelves in the village ", shelves)
	var sv: Salvage = get_tree().root.find_child("Salvage", true, false)
	var lo := Wildlands.WEST_VILLAGE.position
	for at in [Vector2i(2, 14), Salvage.BOOK_SHELF]:
		var spot := world.floors.cell_centre(lo + at)
		miko.place(spot + Vector2(0.5, 0.6) * world.px)
		for i in 10:
			await get_tree().process_frame
		print("Miyu book: by the shelf ", at, ": prompt '", sv.prompt.text, "' showing ", sv.prompt.visible)
		if at == Salvage.BOOK_SHELF:
			shot("shelf")
		sv._pressed = true
		for i in 10:
			await get_tree().process_frame
	for i in 90:
		await get_tree().process_frame
	print("Miyu book: book found ", ch.happened("water_tome_found"), ", in her bag ", miko.bag.items.has("WaterTome"), ", rumor done ", ch.happened("done:village_salvage"))
	shot("found")
