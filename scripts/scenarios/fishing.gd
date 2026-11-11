extends Scenario
## A dock by the river: where one may go; Miko's casts; a villager set to fish.
## Run with --window=fishing.


func run() -> void:
	var fz: Fishing = g.get_node("Fishing")
	# (by day throughout: the save may be at bedtime)
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 8.0
	var bm := BuildMode.active
	var v := world.village
	var dock_item := bm.item_for("Prop", "FishingDock")
	print("Fishing: a dock in the village's middle '", bm.why_not(dock_item, v.centre()), "'")
	# The dry cell nearest the village with water by it.
	var c0 := world.floors.cell_at(v.centre())
	var spot := Vector2i(1 << 20, 0)
	for r in range(1, 60):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r or spot.x < (1 << 20):
					continue
				var cc := c0 + Vector2i(dx, dy)
				var dock_try := world.floors.cell_centre(cc)
				if not bm.no_build(cc) and Fishing.water_near(world, dock_try) and bm.why_not(dock_item, dock_try) == "":
					spot = cc
		if spot.x < (1 << 20):
			break
	world.props.place(spot, "FishingDock")
	var dock_at := world.floors.cell_centre(spot)
	print("Fishing: dock placed ", spot - c0, " cells from the village's middle")
	miko.place(dock_at + Vector2(-1.0, 0.6) * world.px)
	miko.bag.items[miko.bag.free_slot()] = "FishingRod"
	miko.bag.counts["Bait"] = 10
	for i in 20:
		await get_tree().process_frame
	print("Fishing: prompt '", fz.prompt.text, "'")
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_dock.png")
	var fish0 := miko.bag.count("Fish")
	# One cast as played: E, the wait, the catch.
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	for i in 20:
		await get_tree().process_frame
	print("Fishing: E pressed: casting ", fz.casting, ", Miko held ", miko.locked, ", emote showing ", fz._emote != null and fz._emote.visible, ", pose ", miko.pose)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_cast.png")
	for i in 70:
		await get_tree().process_frame
	print("Fishing: the line out ", fz._line != null and fz._line.visible, ", float in the water ", fz._line != null and fz._line.landed, ", water there ", snappedf(world.water_depth(fz._float_at), 0.01), ", ", snappedf(fz._float_at.distance_to(dock_at) / world.px, 0.1), " from the dock, pose ", miko.pose)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_line.png")
	while fz.casting:
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_caught.png")
	print("Fishing: the cast in: fish ", miko.bag.count("Fish"), ", bait ", miko.bag.count("Bait"), ", Miko held ", miko.locked, ", fishing skill xp ", LifeSkills.xp[LifeSkills.Skill.FISHING])
	for cast in 5:
		fz._dock = dock_at
		fz.casting = true
		fz._cast_until = 0.0
		await get_tree().process_frame
		await get_tree().process_frame
	print("Fishing: 6 casts: fish ", fish0, " -> ", miko.bag.count("Fish"), ", bait left ", miko.bag.count("Bait"), ", a cast takes ", fz.cast_time(), " s")
	# A villager set to fish: not while the dock's in the mist; with a crystal clearing it, yes.
	print("Fishing: the dock on cleared ground ", Villager.safe_ground(world, dock_at), ", docks the villagers work ", fz.village_docks().size(), ", prompt '", fz.prompt.text.replace("
", " / "), "'")
	world.props.place(spot + Vector2i(3, 3), "CleansingCrystal")
	for i in 240:
		await get_tree().process_frame
	print("Fishing: a cleansing crystal by it: on cleared ground ", Villager.safe_ground(world, dock_at), ", docks the villagers work ", fz.village_docks().size())
	v.put_in_stash("Bait", 12)
	v.stash["Fish"] = 0
	var vl: Villager = Villager.all[0]
	for other in Villager.all:   # (the one with fishing drawn, if she's here)
		if not (other.s.get("fishDown", []) as Array).is_empty() and (Shots.arg("look") == "" or int(other.person.get("look", -1)) == int(Shots.arg("look"))):
			vl = other
	for other in Villager.all:   # (the dock's hers: one villager to a dock)
		Villager.only(other.person, [])
	Villager.only(vl.person, [Villager.Job.FISHING])
	vl.person.hunger = 100.0
	vl._stand(Villager.now(), 0.0)
	var seen := []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 200000:
		await get_tree().process_frame
		var what: String = Villager.State.keys()[vl.state]
		if seen.is_empty() or seen[-1] != what:
			seen.append(what)
			print("  ", what, " at ", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), " s, ", snappedf(vl.position.distance_to(dock_at) / world.px, 0.1), " from the dock, carrying ", vl.carrying)
		if v.stored("Fish") > 0:
			break
		if what == "FISH" and vl.carrying > 0 and not seen.has("shot"):
			seen.append("shot")
			miko.place(vl.position + Vector2(2.2, 0.3) * world.px)
			for i in 150:
				await get_tree().process_frame
			print("Fishing: ", vl.person.name, " (look ", vl.person.get("look", "?"), "): line out ", vl._fish_line != null and vl._fish_line.visible, ", float in the water ", vl._fish_line != null and vl._fish_line.landed)
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_villager.png")
	print("Fishing: the villager went ", seen, "; fish in storage ", v.stored("Fish"), ", bait left ", v.stored("Bait"))
