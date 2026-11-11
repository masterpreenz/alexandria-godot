extends Scenario
## The first rumor, start to finish: someone has it to tell; heard; found; cleared; waited out; what
## comes of it; then the one it leads to. And the other way: left too long.
## Run with --window=rumors.


func run() -> void:
	var rm: Rumors = g.get_node("Rumors")
	var ch: Chronicle = g.get_node("Chronicle")
	var jw: RumorsWindow = g.get_node("Hud/RumorsWindow")
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 9.0
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Rumors: ", rm.defs.size(), " in the file; to tell now ", rm.offers)
	var teller: Villager = null
	for vl in Villager.all:
		if rm.has_offer(vl):
			teller = vl
	print("Rumors: ", teller.person.name, " has '", rm.offer_from(teller).title, "' to tell; emote ", teller._rumor_emote())
	var chat: Talk = g.get_node("Hud/Talk")
	miko.place(teller.position + Vector2(0.8, 0.3) * world.px)
	chat.open(teller)
	await get_tree().process_frame
	print("Rumors: talk's choices ", chat._choices.get_children().filter(func(c): return not c.is_queued_for_deletion()).map(func(c): return c.text))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_ask.png")
	chat._ask_rumor()
	await get_tree().process_frame
	print("Rumors: told '", chat._line.text, "'")
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_told.png")
	chat.close()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_tracker.png")
	var trk: RumorTracker = g.get_node("Hud/RumorTracker")
	print("Rumors: the tracker '", trk._title.text, "' / '", trk._note.text, "' / '", trk._way.text, "'")
	var st: Dictionary = rm.heard["forest_clearing"]
	var wood := rm.place_of(st, rm.by_id["forest_clearing"], 0)
	print("Rumors: heard ", rm.heard.keys(), "; the wood ", snappedf(wood.distance_to(world.village.centre()) / world.px, 0.1), " units ", rm.direction(wood), ", mist there ", world.mist.tier_at(wood), "; mark ", rm.marks().map(func(m): return [m.title, snappedf((m.at as Vector2).distance_to(wood) / world.px, 0.1), m.radius / world.px]))
	rm.set_notes("forest_clearing", "Bring a cleansing crystal. Boars about.")
	jw.open()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_journal.png")
	jw.close()
	var map: WorldMap = g.get_node("Hud/WorldMap")
	map.open()
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_map.png")
	map.close()
	# There.
	miko.place(wood + Vector2(0.5, 0.3) * world.px)
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	for i in 40:
		await get_tree().process_frame
	print("Rumors: the tracker there '", trk._way.text, "'")
	print("Rumors: at the wood: step ", st.step, " '", rm.lines("forest_clearing")[-1][0], "', cleared ", snappedf(rm.cleared_share(wood, 4.0), 0.01))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_wood.png")
	world.props.place(world.floors.cell_at(wood) + Vector2i(1, 1), "CleansingCrystal")
	for i in 300:
		await get_tree().process_frame
	print("Rumors: a crystal set: cleared ", snappedf(rm.cleared_share(wood, 4.0), 0.01), ", step ", st.step, " '", rm.lines("forest_clearing")[-1][0], "'")
	var holes := world.props_named("RabbitHole").size()
	var seeds := miko.bag.count("WheatSeed")
	clock.hours += 49.0
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Rumors: two days on: ", st.state, "; rabbit holes ", holes, " -> ", world.props_named("RabbitHole").size(), ", wheat seed ", seeds, " -> ", miko.bag.count("WheatSeed"), "; tracked ", rm.marks().size())
	clock.hours += 49.0
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Rumors: two more: to tell ", rm.offers)
	print("Rumors: the chronicle ", ch.events.map(func(e): return "%s (%s)" % [e.what, ch.date(float(e.h))]))
	# Saved and loaded.
	var saved_r := rm.to_json()
	var saved_c := ch.to_json()
	rm.heard = {}
	ch.events = []
	ch.from_json(saved_c)
	rm.from_json(saved_r)
	print("Rumors: saved and loaded: ", rm.heard.keys(), ", notes '", rm.heard["forest_clearing"].notes, "', events ", ch.events.size())
	# The other way: heard, and nothing done.
	rm.heard = {}
	rm.offers = {}
	ch.events = []
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	for vl in Villager.all:
		if rm.has_offer(vl):
			rm.hear("forest_clearing", vl)
	clock.hours += 24.0 * 12.5
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	rm._clock = 9.0
	for i in 5:
		await get_tree().process_frame
	print("Rumors: left 12 days: ", rm.heard["forest_clearing"].state, "; to tell ", rm.offers, "; chronicle ", ch.events.map(func(e): return e.what))
