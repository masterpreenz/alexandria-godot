extends Scenario
## After the fight, the elder by the town banner: next to him, E is for talking to him (his scene waits), not the
## banner. Run with --window=eldertalk --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	Chronicle.active.record("village_warded")
	Chronicle.active.record("scene:messenger")   # (his news heard: skipped past here)
	while str(st._beats()[st.beat].id) != "aftermath":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	var elder: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "elder":
			elder = v
	for i in 200:   # (the camera's look over the village, skipped past: done, and she's free again)
		if not miko.locked:
			break
		await get_tree().process_frame
	miko.locked = false
	miko.place(elder.position + Vector2(0.7, 0.2) * world.px)
	# (coming near the village sets off the camera's look over it: she's held till it's done)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000 and (miko.locked or Time.get_ticks_msec() - t0 < 500):
		await get_tree().process_frame
	miko.place(elder.position + Vector2(0.7, 0.2) * world.px)
	for i in 10:
		await get_tree().process_frame
	var talk: Talk = g.get_node("Hud/Talk")
	var banner_near := miko.position.distance_to(world.village.centre()) < VillageDesk.BANNER_RANGE * world.px
	print("Elder talk: by the banner ", banner_near, "; talk prompt ", talk.prompt.visible, " '", talk.prompt.text, "'")
	print("Elder talk: distance ", snappedf(elder.position.distance_to(miko.position) / world.px, 0.01), " (reach ", Talk.RANGE, "), locked ", miko.locked, ", panel ", CharacterPanel.up(), ", building ", BuildMode.is_open())
	var spots := st._open_spots_near(world.props_named("TownBanner")[0], 2)
	print("Elder talk: spots found ", spots.map(func(p): return snappedf(p.distance_to(world.props_named("TownBanner")[0]) / world.px, 0.1)))
	var n := talk._nearest()
	print("Elder talk: nearest ", n.person.name if n != null else "none", ", his state ", Villager.State.keys()[elder.state], " visible ", elder.visible, " in bed ", elder.in_bed,
		"; scene waiting ", not Scenes.for_speaker(elder.person).is_empty(), "; other prompts ", WorldPrompts._labels.filter(func(l): return is_instance_valid(l) and l.visible and l.text != "").map(func(l): return l.text))
	print("Elder talk: choosing ", WorldPrompts.choosing(), ", picked '", WorldPrompts._picked.text if WorldPrompts._picked != null else "", "'")
	# (a real E press: goes to the picked row)
	var e := InputEventKey.new()
	e.keycode = KEY_E
	e.pressed = true
	Input.parse_input_event(e)
	for i in 3:
		await get_tree().process_frame
	print("Elder talk: E opens his talk ", talk.visible, " with ", talk._name.text, ": '", talk._line.text.left(40), "'; the banner's window open ", g.find_children("*", "BannerPanel", true, false).any(func(b): return b.visible))
	# Both in reach (him moved by the banner): a list of two, his talk picked first; Tab picks the banner.
	talk.close()
	for i in 5:
		await get_tree().process_frame
	var banner: Vector2 = world.props_named("TownBanner")[0]
	elder.position = banner + Vector2(0.9, 0.6) * world.px
	miko.place(banner + Vector2(0.4, 0.9) * world.px)
	for i in 10:
		elder.position = banner + Vector2(0.9, 0.6) * world.px
		await get_tree().process_frame
	print("Elder talk: both in reach: choosing ", WorldPrompts.choosing(), ", picked '", WorldPrompts._picked.text if WorldPrompts._picked != null else "", "'")
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_list.png")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	for i in 3:
		await get_tree().process_frame
	print("Elder talk: after Tab, picked '", WorldPrompts._picked.text if WorldPrompts._picked != null else "", "'")
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_tab.png")
