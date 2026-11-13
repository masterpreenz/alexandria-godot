extends Scenario
## Miyu joins Sera when she's brought her the spell book, not before: waking, she wants to come but stays; given the
## Water Spell Book, her scene ends with her in the party. Run with --window=miyujoin.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var ch := Chronicle.active
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	var trait_list: Array = miyu.person.get("traits", []).duplicate()
	trait_list.append("unique")
	miyu.person["traits"] = trait_list
	ch.events = ch.events.filter(func(e): return not (str(e.what).begins_with("party") or str(e.what).begins_with("scene:miyu") or str(e.what) in ["miyu_water", "book_given:miyu", "miyu_errand"]))
	Party.active.members.erase("miyu")
	if not ch.happened("miyu_home"):
		ch.record("miyu_home")
	var talk: Talk = Talk.active
	miko.place(miyu.position + Vector2(1.0, 0.6) * world.px)
	for i in 10:
		await get_tree().process_frame
	var wake := Scenes.for_speaker(miyu.person)
	talk.open(miyu)
	talk._play(wake, (wake.lines as Array).size())
	for i in 10:
		await get_tree().process_frame
	print("Miyu join: woke ('", wake.get("id", ""), "'), in the party ", Party.active.members.has("miyu"), ", would come if asked ", Party.willing(miyu.person))
	talk.close()
	ch.record("scene:miyu_magic")
	ch.record("miyu_errand")
	miko.bag.items[miko.bag.free_slot()] = "WaterTome"
	talk.open(miyu)
	for i in 5:
		await get_tree().process_frame
	var book := Companions.book_for(miyu.person, miko.bag)
	print("Miyu join: book offered '", book.get("offer", ""), "'")
	talk._give_book(book)
	for i in 5:
		await get_tree().process_frame
	# (on to the scene's end)
	var playing: Dictionary = Scenes.all().filter(func(s): return s.id == "miyu_water_book")[0]
	talk._play(playing, (playing.lines as Array).size())
	for i in 10:
		await get_tree().process_frame
	print("Miyu join: after the book, in the party ", Party.active.members.has("miyu"), ", knows ", Companions.stats_for(miyu.person).known_spells())
